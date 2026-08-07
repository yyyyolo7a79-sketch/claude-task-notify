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
$MAX_CHARS = 180       # 摘要截断长度（字；与弹窗参数调整器的 MAX_CHARS 滑块对应）
# 可移植路径：UI 脚本与入口同目录（$PSScriptRoot），解释器用绝对路径（防 PATH 劫持）
$SHOW_POPUP = Join-Path $PSScriptRoot 'show-popup.ps1'
$PS_EXE = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

# =============================================================
# 辅助函数
# =============================================================

# 脱敏日志：只记时间/事件/会话前 8 位/结果/异常类型，禁止记录全文
# 第六轮审查修复：入口与 UI 进程共写同一 notify.log，原 Out-File -Append 无锁 +
#   各自删除超限文件 → 并发时丢日志。改为：命名 Mutex 串行化「检查→滚动→追加」，
#   滚动用 SetLength(0) 截断（不删除文件——避免另一进程已打开句柄失效）；
#   超时 fail-open 直接追加（单次写，不阻塞）。
function Write-NotifyLog {
    param([string]$msg)
    try {
        if (-not (Test-Path $DIR)) { $null = New-Item -ItemType Directory -Force $DIR }
        $line = ("[{0}] {1}`r`n" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg)
        $mutex = New-Object System.Threading.Mutex($false, 'Local\ClaudeCodeNotifyLog')
        $got = $false
        try {
            $got = $mutex.WaitOne(100)
        } catch [System.Threading.AbandonedMutexException] {
            $got = $true    # Abandoned：锁已取得，稍后必须释放
        } catch { }
        try {
            if ($got) {
                $fs = [IO.File]::Open($LOG_FILE, [IO.FileMode]::OpenOrCreate,
                    [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
                try {
                    if ($fs.Length -gt $LOG_MAX) { $fs.SetLength(0) }
                    # ⚠️ Open() 后文件指针在 0，必须 Seek 到末尾再写（否则从开头覆盖历史日志）
                    $null = $fs.Seek(0, [IO.SeekOrigin]::End)
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
                    $fs.Write($bytes, 0, $bytes.Length)
                } finally { $fs.Close() }
            } else {
                [System.IO.File]::AppendAllText($LOG_FILE, $line)   # fail-open：单次追加
            }
        } finally {
            if ($got) { try { $mutex.ReleaseMutex() } catch { } }
            $mutex.Dispose()
        }
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
# 第四轮审查修复：
#   ① skill 收尾标记：先删代码块（块内标记不生效），然后只检查**最后一个非空
#      文本行**是否为行首收尾标记——较早的示例/说明行不覆盖后续真实请求
#   ② 排除礼貌性追问（"需要我…吗？"），避免可选优化询问误判为阻塞性请求
#   ③ 兜底启发式只分析最后一段（完成句常以"请检查结果"收尾，全文搜索会误判）；
#      请求词只保留明确请求句式
function Test-NeedInfo {
    param([string]$t)
    if (-not $t) { return $false }
    # ① skill 收尾标记：删代码块 → 取最后一个非空行 → 判断是否为行首标记
    $cleanT = [regex]::Replace($t, '```[\s\S]*?```', ' ')
    $lastLine = ($cleanT -split '\r?\n' | Where-Object { $_.Trim() } | Select-Object -Last 1)
    if ($lastLine) {
        if ($lastLine -match '^\s*❓\s*需要你提供') { return $true }
        if ($lastLine -match '^\s*✅\s*已完成') { return $false }
    }
    # ② 礼貌性追问排除："需要我继续优化吗？" → 不算阻塞性请求
    if ($t -match "需要我[^\r\n]{0,20}[吗么][?？]?\s*$") { return $false }
    # ③ 兜底启发式（只分析最后一段）
    $paras = @($t -split '(\r?\n\s*){1,}' | Where-Object { $_.Trim() })
    if ($paras.Count -gt 0) { $t = $paras[$paras.Count - 1] }
    $t = $t.Trim()
    if ($t -match "[?？]\s*$") { return $true }
    if ($t -match "请(你|您)?(提供|告诉我|告知|确认|补充|输入|上传|发送|给我)") { return $true }
    if ($t -match "需要你|需要您|麻烦你|请把|能否|你能不") { return $true }
    return $false
}

# 摘要：清洗代码块/HTML/实体/markdown/图片/URL，取首段，截断 50 字
# 顺序要点：图片先删（否则 URL 删除后残留 "![x]("）；标题/列表正则带 (?m) multiline；
#           不再删 emoji（WPF DirectWrite 渲染正常，且 surrogate 正则误删所有非 BMP 字符）
function Get-Summary {
    param([string]$t)
    if (-not $t) { return "" }
    $clean = [regex]::Replace($t, '```[\s\S]*?```', ' ')
    $clean = $clean -replace '`[^`]*`', ' '
    $clean = [regex]::Replace($clean, '!\[[^\]]*\]\([^)]*\)', ' ')   # 图片先删
    $clean = [regex]::Replace($clean, '<[^>]+>', ' ')
    $clean = $clean -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>' -replace '&quot;', '"'
    $clean = $clean -replace '&[a-zA-Z#0-9]{1,8};', ' '
    $clean = [regex]::Replace($clean, '(?m)^#+\s*', '')              # multiline 标题
    $clean = [regex]::Replace($clean, '(?m)^\s*[-*+]\s*', '')        # multiline 列表
    # 审查修复：普通 Markdown 链接先替换为链接文字（否则 URL 删除后残留 "[报告]("）
    $clean = [regex]::Replace($clean, '\[([^\]]*)\]\((https?://[^)\s]+)\)', '$1')
    $clean = $clean -replace 'https?://[^\s]+', ''                   # URL 后删
    $paras = @($clean -split '(\r?\n\s*){2,}' | Where-Object { $_.Trim() })
    if ($paras.Count -gt 0) { $clean = $paras[0] }
    $clean = $clean -replace '\s+', ' '
    $clean = $clean.Trim()
    if ($clean.Length -gt $MAX_CHARS) { $clean = $clean.Substring(0, $MAX_CHARS) + "…" }
    return $clean
}

# 2 秒去重：同一 (session, 回复) 在窗口内只通知一次
# 第三轮审查修复：
#   - 读-判-写整体包在命名 Mutex 内串行化
#   - 超时 100ms（不阻塞 500ms 目标）；未取得锁 → fail-open 直接返回（重复弹一次
#     无害），绝不无锁读写 state.json
#   - AbandonedMutexException = 已取得锁（上一持有者崩溃），必须释放
#   - 取得锁后才计算时间戳（等待期间可能超窗）
function Test-Dedupe {
    param([string]$key)
    $mutex = New-Object System.Threading.Mutex($false, 'Local\ClaudeCodeNotifyDedupe')
    $got = $false
    try {
        $got = $mutex.WaitOne(100)
    } catch [System.Threading.AbandonedMutexException] {
        $got = $true    # Abandoned：锁已取得，稍后必须释放
    } catch { }
    if (-not $got) {
        # fail-open：不去重（重复弹一次无害），不访问 state.json；
        # 第四轮审查修复：记录超时，便于线上区分"正常 fail-open"与"去重故障"
        Write-NotifyLog "DEDUPE mutex-timeout"
        $mutex.Dispose()
        return $false
    }
    try {
        $now = [DateTime]::UtcNow
        if (Test-Path $STATE_FILE) {
            try {
                $st = Get-Content -Raw $STATE_FILE -Encoding UTF8 | ConvertFrom-Json
                $elapsed = ($now - [DateTime]::Parse($st.ts)).TotalMilliseconds
                # 第四轮审查修复：elapsed >= 0 防御时钟回拨/未来时间戳导致的异常抑制
                if ($st.key -eq $key -and $elapsed -ge 0 -and $elapsed -lt $DEDUPE_MS) {
                    return $true
                }
            } catch { }
        }
        # 原子写：先写 GUID 临时文件再 Move（避免并发写损坏）
        try {
            if (-not (Test-Path $DIR)) { $null = New-Item -ItemType Directory -Force $DIR }
            $tmp = "$STATE_FILE.tmp-" + [Guid]::NewGuid().ToString("N")
            @{ key = $key; ts = $now.ToString("o") } | ConvertTo-Json |
                Set-Content $tmp -Encoding UTF8
            Move-Item -Force $tmp $STATE_FILE
        } catch { }
        return $false
    } finally {
        try { $mutex.ReleaseMutex() } catch { }
        $mutex.Dispose()
    }
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
$sw = [System.Diagnostics.Stopwatch]::StartNew()   # 入口耗时（审查建议：毫秒级验证 500ms）

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
# 后台任务仍在运行时：不显示"任务完成"（避免误导），但也不跳过——
# 后台任务结束后未必再次触发 Stop，跳过会导致永远没有通知。
# 改为：标题显示"主回复完成"，并在日志标注 bg=1
$hasBg = $false
if ($data.background_tasks -and @($data.background_tasks).Count -gt 0) { $hasBg = $true }

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
} elseif ($hasBg) {
    $emoji = "⏳"; $titleText = "主回复完成，后台任务运行中"
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
        background = $hasBg
        sessionId  = $data.session_id
        createdAt  = (Get-Date -Format "o")
    } | ConvertTo-Json | Set-Content $payloadFile -Encoding UTF8
} catch {
    Write-NotifyLog "ERR payload-write"
    exit 0
}

# 派生独立 UI 进程（-STA 为 WPF 必需；Hidden 隐藏控制台窗口）
# 注意：PS 5.1 的 Start-Process -ArgumentList 数组会拼接为字符串且不含空格引号，
#       因此用字符串形式并手动为路径加引号（路径固定、无用户输入，无注入面）
try {
    Start-Process -FilePath $PS_EXE -ArgumentList (
        '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $SHOW_POPUP +
        '" -PayloadFile "' + $payloadFile + '"'
    ) -WindowStyle Hidden | Out-Null
} catch {
    Write-NotifyLog "ERR spawn-ui"
    # 派生失败立即清理 payload，避免残留
    Remove-Item $payloadFile -Force -ErrorAction SilentlyContinue
    exit 0
}

# 清理旧 payload + 日志（dur 为入口实际耗时，验证 500ms 内返回）
Clear-StalePayloads
Write-NotifyLog ("OK adapter=wpf need_info=" + $isNeedInfo + " bg=" + $hasBg +
    " dur=" + $sw.ElapsedMilliseconds + "ms sid=" + ($data.session_id -replace '(.{8}).*', '$1'))

exit 0
