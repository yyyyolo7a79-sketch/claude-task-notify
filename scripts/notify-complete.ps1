# =============================================================
# notify-complete.ps1 — Claude Code Stop Hook 入口（快速返回）
#
# 职责（按 Codex 弹窗规格适配）：
#   1. 读取 stdin JSON，校验事件（仅 Stop 且 stop_hook_active=false）
#   2. 生成摘要（本地确定性处理，不调模型）
#   3. 2 秒去重（SHA-256 键 + state.json 原子替换）
#   4. 写临时 payload，Start-Process 派生独立 UI 进程（show-popup.ps1）
#   5. 500ms 内退出，绝不阻塞 Claude Code
#
# 输出：无 stdout（返回空 = 不干预 Claude 的停止行为）
#
# 注意：UTF-8 with BOM 保存；PowerShell 5.1 对无 BOM 文件按 ANSI 解释
# =============================================================

# ---- 编码：PS 5.1 必须强制 UTF-8，否则 stdin 中文乱码 ----
try { [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# =============================================================
# 常量
# =============================================================
$DIR = "$env:TEMP\claude-code-notify"
$STATE_FILE = "$DIR\state.json"
$LOG_FILE = "$DIR\notify.log"
$LOG_MAX = 200KB
$DEDUPE_MS = 2000      # 去重窗口
$PAYLOAD_TTL = 10      # payload 清理阈值（分钟）
$SHOW_POPUP = "C:\Users\PC\.claude\scripts\show-popup.ps1"

# =============================================================
# 辅助函数
# =============================================================

# 脱敏日志：只记时间/事件/会话前 8 位/结果/异常类型，禁止记录全文
function Write-NotifyLog {
    param([string]$msg)
    try {
        if (-not (Test-Path $DIR)) { $null = New-Item -ItemType Directory -Force $DIR }
        if ((Test-Path $LOG_FILE) -and (Get-Item $LOG_FILE).Length -gt $LOG_MAX) {
            Remove-Item $LOG_FILE -Force
        }
        ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg) |
            Out-File $LOG_FILE -Append -Encoding UTF8
    } catch { }
}

function Get-Sha256Hex {
    param([string]$s)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($s)
    $hash = [System.Security.Cryptography.SHA256]::Create()
    try {
        $h = $hash.ComputeHash($bytes)
        return (($h | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally { $hash.Dispose() }
}

# 从 transcript（JSONL）尾部取最后一条 assistant 文本（兜底）
function Get-LastAssistantFromTranscript {
    param([string]$path)
    try {
        if (-not (Test-Path -LiteralPath $path)) { return $null }
        $lines = @(Get-Content -LiteralPath $path -Tail 80 -Encoding UTF8 -ErrorAction Stop)
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            try {
                $obj = $lines[$i] | ConvertFrom-Json
                if ($obj.type -eq "assistant" -and $obj.message.role -eq "assistant") {
                    $texts = @($obj.message.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text })
                    if ($texts.Count -gt 0) { return ($texts -join "`n") }
                }
            } catch { }
        }
    } catch { }
    return $null
}

# 启发式判断：是否需要用户提供相关信息
function Test-NeedInfo {
    param([string]$t)
    if (-not $t) { return $false }
    $t = $t.Trim()
    if ($t -match "[?？]\s*$") { return $true }
    if ($t -match "请(你|您)?(提供|告诉|告知|确认|给出|补充|说明|检查|输入|发送|上传|分享|回复|告知)") { return $true }
    if ($t -match "需要你|需要您|麻烦你|请把|能否|你能不") { return $true }
    return $false
}

# 摘要：清洗代码块/HTML/实体/emoji/markdown/URL，取首段，截断 50 字
function Get-Summary {
    param([string]$t)
    if (-not $t) { return "" }
    $clean = [regex]::Replace($t, '```[\s\S]*?```', ' ')
    $clean = $clean -replace '`[^`]*`', ' '
    $clean = [regex]::Replace($clean, '<[^>]+>', ' ')
    $clean = $clean -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>' -replace '&quot;', '"'
    $clean = $clean -replace '&[a-zA-Z#0-9]{1,8};', ' '
    $clean = $clean -replace '\*\*?', '' -replace '^#+\s*', '' -replace '^\s*[-*+]\s*', ''
    $clean = [regex]::Replace($clean, '[\uD800-\uDBFF][\uDC00-\uDFFF]', '')
    $clean = $clean -replace 'https?://[^\s]+', ''      # 删 URL（B 级改进）
    $clean = $clean -replace '!\[[^\]]*\]\([^)]*\)', ''  # 删图片 Markdown
    $paras = @($clean -split '(\r?\n\s*){2,}' | Where-Object { $_.Trim() })
    if ($paras.Count -gt 0) { $clean = $paras[0] }
    $clean = $clean -replace '\s+', ' '
    $clean = $clean.Trim()
    if ($clean.Length -gt 50) { $clean = $clean.Substring(0, 50) + "…" }
    return $clean
}

# 2 秒去重：同一 (session, 回复) 在窗口内只通知一次；原子替换避免并发损坏
function Test-Dedupe {
    param([string]$key)
    $now = [DateTime]::UtcNow
    if (Test-Path $STATE_FILE) {
        try {
            $st = Get-Content -Raw $STATE_FILE -Encoding UTF8 | ConvertFrom-Json
            if ($st.key -eq $key -and ($now - [DateTime]::Parse($st.ts)).TotalMilliseconds -lt $DEDUPE_MS) {
                return $true
            }
        } catch { }
    }
    # 原子写：先写临时文件再 Move（避免并发写损坏）
    try {
        if (-not (Test-Path $DIR)) { $null = New-Item -ItemType Directory -Force $DIR }
        $tmp = "$STATE_FILE.tmp"
        @{ key = $key; ts = $now.ToString("o") } | ConvertTo-Json |
            Set-Content $tmp -Encoding UTF8
        Move-Item -Force $tmp $STATE_FILE
    } catch { }
    return $false
}

# 清理超过 10 分钟未被 UI 读取的旧 payload
function Clear-StalePayloads {
    try {
        Get-ChildItem "$DIR\payload-*.json" -ErrorAction SilentlyContinue | ForEach-Object {
            if ((Get-Date) - $_.LastWriteTime -gt [TimeSpan]::FromMinutes($PAYLOAD_TTL)) {
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    } catch { }
}

# =============================================================
# 主流程
# =============================================================
$stdinJson = ""
if ([Console]::IsInputRedirected) {
    try { $stdinJson = [Console]::In.ReadToEnd() } catch { }
}

if (-not $stdinJson) { exit 0 }

try {
    $data = $stdinJson | ConvertFrom-Json
} catch {
    Write-NotifyLog "ERR invalid-json"
    exit 0
}

# 过滤：仅主 Agent 的 Stop 事件
if ($data.hook_event_name -ne "Stop") {
    Write-NotifyLog ("SKIP event=" + $data.hook_event_name + " sid=" + ($data.session_id -replace '(.{8}).*', '$1'))
    exit 0
}
if ($data.stop_hook_active) {
    # 防止 Stop Hook 自身触发导致的递归
    Write-NotifyLog ("SKIP stop_hook_active sid=" + ($data.session_id -replace '(.{8}).*', '$1'))
    exit 0
}

# 内容获取：优先 last_assistant_message，缺失则读 transcript 兜底
$rawText = $data.last_assistant_message
if (-not $rawText -and $data.transcript_path) {
    $rawText = Get-LastAssistantFromTranscript -path $data.transcript_path
}
if (-not $rawText) { $rawText = "任务已完成，等待你的下一步操作。" }

# 摘要 + 类型 + 项目名
$bodyText = Get-Summary -t $rawText
$isNeedInfo = Test-NeedInfo -t $rawText
if ($isNeedInfo) {
    $emoji = "❓"; $titleText = "需要用户提供相关信息"
} else {
    $emoji = "✅"; $titleText = "任务完成"
}
$project = ""
if ($data.cwd) { $project = Split-Path $data.cwd -Leaf }

# 去重
$dedupeKey = Get-Sha256Hex -s ($data.session_id + "`n" + $rawText)
if (Test-Dedupe -key $dedupeKey) {
    Write-NotifyLog ("DEDUPE sid=" + ($data.session_id -replace '(.{8}).*', '$1'))
    exit 0
}

# 写 payload
$payloadFile = Join-Path $DIR ("payload-" + [Guid]::NewGuid().ToString("N") + ".json")
try {
    @{
        emoji      = $emoji
        title      = $titleText
        body       = $bodyText
        project    = $project
        sessionId  = $data.session_id
        createdAt  = (Get-Date -Format "o")
    } | ConvertTo-Json | Set-Content $payloadFile -Encoding UTF8
} catch {
    Write-NotifyLog "ERR payload-write"
    exit 0
}

# 派生独立 UI 进程（-STA 为 WPF 必需；Hidden 隐藏控制台窗口）
try {
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile", "-STA", "-WindowStyle", "Hidden",
        "-ExecutionPolicy", "Bypass",
        "-File", $SHOW_POPUP,
        "-PayloadFile", $payloadFile
    ) | Out-Null
} catch {
    Write-NotifyLog "ERR spawn-ui"
    exit 0
}

# 清理旧 payload + 日志
Clear-StalePayloads
Write-NotifyLog ("OK adapter=wpf need_info=" + $isNeedInfo + " sid=" + ($data.session_id -replace '(.{8}).*', '$1'))

exit 0
