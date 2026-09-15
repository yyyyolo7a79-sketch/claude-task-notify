# =============================================================
# notify-complete.ps1 — Claude Code Stop Hook 入口（快速返回）
#
# 职责（按 Codex 弹窗规格适配 + 等待提醒扩展）：
#   1. 读取 stdin JSON，校验事件——四类：Stop（主回复结束）/
#      PreToolUse+AskUserQuestion（Claude 提问，等你回答）/
#      PermissionRequest（权限确认，等你批准）/
#      PostToolUse（AskUserQuestion 已作答 / 权限工具执行完成 → 写关闭标志）；其余忽略
#   2. 生成摘要（本地确定性处理，不调模型）
#   3. 2 秒去重（SHA-256 键 + state.json 原子替换）
#   4. 写临时 payload，Start-Process 派生独立 UI 进程（show-popup.ps1）
#   5. 500ms 内退出，绝不阻塞 Claude Code
#
# 输出：无 stdout（返回空 = 不干预 Claude 行为；PreToolUse/PermissionRequest
#       语义下"无决定" = 工具调用正常走权限流程，即不阻断也不放行）
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
# 用户配置（/notify_AskUserQuestion_persistence 命令维护；文件不存在 = 默认持久开启）
$CONFIG_FILE = Join-Path $PSScriptRoot 'notify-config.json'
$persistQuestion = $true
try {
    if (Test-Path $CONFIG_FILE) {
        $cfg = Get-Content -Raw $CONFIG_FILE -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $cfg.askUserQuestionPersistence) { $persistQuestion = [bool]$cfg.askUserQuestionPersistence }
    }
} catch { }

# =============================================================
# 辅助函数
# =============================================================

# 脱敏日志：只记时间/事件/会话前 8 位/结果/异常类型，禁止记录全文
# 第六轮审查修复：入口与 UI 进程共写同一 notify.log，原 Out-File -Append 无锁 +
#   各自删除超限文件 → 并发时丢日志。改为：命名 Mutex 串行化「检查→滚动→追加」，
#   滚动用 SetLength(0) 截断（不删除文件——避免另一进程已打开句柄失效）；
#   第八轮审查修复：超时直接放弃本条，不无锁写（AppendAllText 在持锁 ReadWrite
#   下会共享冲突；且不重试——入口最坏等待 = 去重锁 100ms + 日志锁 100ms ≈ 200ms，
#   保证 500ms 返回目标成立）。
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
        # 超时直接放弃本条（单次 WaitOne 100ms，不重试——最坏等待可控，见函数头注释）
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
            }
            # $got=false（超时）：放弃本条，不写
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

# 摘要：清洗代码块/HTML/实体/markdown/图片/URL，取首段，截断 $MAX_CHARS（默认 180）字
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
                # 第九轮修复：RoundtripKind 保留 "…Z" 的 UTC 语义——原 [DateTime]::Parse
                #   把带 Z 的 UTC 时间戳转换为本地时间（Kind=Local），与 UtcNow 相减
                #   得 -8h（中国时区）→ elapsed 恒负 → 去重永不生效
                $tsUtc = [DateTime]::Parse($st.ts, [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::RoundtripKind)
                $elapsed = ($now - $tsUtc).TotalMilliseconds
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

# 清理超过 10 分钟未被 UI 读取的旧 payload + 无人消费的旧关闭标志
function Clear-StalePayloads {
    try {
        Get-ChildItem "$DIR\payload-*.json" -ErrorAction SilentlyContinue | ForEach-Object {
            if ((Get-Date) - $_.LastWriteTime -gt [TimeSpan]::FromMinutes($PAYLOAD_TTL)) {
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
        Get-ChildItem "$DIR\close-*.flag" -ErrorAction SilentlyContinue | ForEach-Object {
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

# 过滤：仅四类事件——Stop（主回复结束）/
# PreToolUse+AskUserQuestion（提问，等你回答）/ PermissionRequest（等你批准）/
# PostToolUse（AskUserQuestion 已作答 / 权限工具执行完成 → 写关闭标志）
$evtName = [string]$data.hook_event_name
$isStop = ($evtName -eq "Stop")
$isQuestion = ($evtName -eq "PreToolUse" -and $data.tool_name -eq "AskUserQuestion")
# 注：AskUserQuestion 自身也会触发 PermissionRequest（工具级决策噪音）——跳过它，
#   该场景已由 question 弹窗覆盖；其余工具的权限请求保留
$isPermission = ($evtName -eq "PermissionRequest" -and $data.tool_name -ne "AskUserQuestion")
$isPostToolUse = ($evtName -eq "PostToolUse")   # matcher 层已限定工具范围（AskUserQuestion / Bash|Edit|Write|...）
if (-not ($isStop -or $isQuestion -or $isPermission -or $isPostToolUse)) {
    Write-NotifyLog ("SKIP event=" + $evtName + " tool=" + $data.tool_name + " sid=" + ($data.session_id -replace '(.{8}).*', '$1'))
    exit 0
}
if ($isStop -and $data.stop_hook_active) {
    # 防止 Stop Hook 自身触发导致的递归
    Write-NotifyLog ("SKIP stop_hook_active sid=" + ($data.session_id -replace '(.{8}).*', '$1'))
    exit 0
}

# PostToolUse 统一处理：写关闭标志让对应持久弹窗自动淡出
#   · AskUserQuestion 已作答 → 关闭提问弹窗
#   · 权限批准后工具执行完成 → 关闭权限弹窗（同一 tool_use_id）
#   （标志名含 tool_use_id，仅接受 ^[A-Za-z0-9_-]{1,64}$ 防路径注入）
if ($isPostToolUse) {
    try {
        $tuid = [string]$data.tool_use_id
        if ($tuid -match '^[A-Za-z0-9_-]{1,64}$') {
            if (-not (Test-Path $DIR)) { $null = New-Item -ItemType Directory -Force $DIR }
            Set-Content -Path (Join-Path $DIR ("close-" + $tuid + ".flag")) -Value "1" -Encoding UTF8
            Write-NotifyLog ("OK evt=tool-done tool=" + $data.tool_name + " sid=" + ($data.session_id -replace '(.{8}).*', '$1'))
        }
    } catch { }
    exit 0
}
# 内容获取 + 标题（按事件类型分支）
$hasBg = $false
$isNeedInfo = $false
$persist = $false      # 弹窗是否持久显示（等待类事件 + 配置开启）
$tuid = ""             # tool_use_id（供持久弹窗轮询关闭标志）
if ($isQuestion) {
    # 提问事件：正文显示第一个问题的文本（多问时标注数量）
    $qList = @($data.tool_input.questions)
    $rawText = ""
    if ($qList.Count -ge 1 -and $qList[0].question) { $rawText = [string]$qList[0].question }
    if ($qList.Count -gt 1) { $rawText = "（共 $($qList.Count) 个问题）" + $rawText }
    if (-not $rawText) { $rawText = "Claude 向你提出了问题，请回到窗口查看并选择。" }
    $emoji = "❓"; $titleText = "Claude 在等你回答"
    $persist = $persistQuestion
    if ([string]$data.tool_use_id -match '^[A-Za-z0-9_-]{1,64}$') { $tuid = [string]$data.tool_use_id }
} elseif ($isPermission) {
    # 权限确认事件：正文显示工具名 + 关键参数（command/file_path 等）
    $toolName = [string]$data.tool_name
    $detail = ""
    try {
        $ti = $data.tool_input
        if ($ti.command) { $detail = [string]$ti.command }
        elseif ($ti.file_path) { $detail = [string]$ti.file_path }
        elseif ($ti.pattern) { $detail = [string]$ti.pattern }
        elseif ($ti.url) { $detail = [string]$ti.url }
    } catch { }
    if ($detail) { $rawText = $toolName + " " + $detail } else { $rawText = $toolName }
    $emoji = "⏳"; $titleText = "Claude 在等你批准操作"
    $persist = $persistQuestion
    # 权限批准后，该工具的 PostToolUse 会带同一 tool_use_id → 写关闭标志自动关
    if ([string]$data.tool_use_id -match '^[A-Za-z0-9_-]{1,64}$') { $tuid = [string]$data.tool_use_id }
} else {
    # Stop 事件（原逻辑）：优先 last_assistant_message，缺失则读 transcript 兜底
    $rawText = $data.last_assistant_message
    if (-not $rawText -and $data.transcript_path) {
        $rawText = Get-LastAssistantFromTranscript -path $data.transcript_path
    }
    if (-not $rawText) { $rawText = "任务已完成，等待你的下一步操作。" }
    # 后台任务仍在运行时：不显示"任务完成"（避免误导），但也不跳过——
    # 后台任务结束后未必再次触发 Stop，跳过会导致永远没有通知。
    # 改为：标题显示"主回复完成"，并在日志标注 bg=1
    if ($data.background_tasks -and @($data.background_tasks).Count -gt 0) { $hasBg = $true }
    $isNeedInfo = Test-NeedInfo -t $rawText
    if ($isNeedInfo) {
        $emoji = "❓"; $titleText = "需要用户提供相关信息"
    } elseif ($hasBg) {
        $emoji = "⏳"; $titleText = "主回复完成，后台任务运行中"
    } else {
        $emoji = "✅"; $titleText = "任务完成"
    }
}

# 摘要 + 项目名
$bodyText = Get-Summary -t $rawText
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
        persist    = $persist
        toolUseId  = $tuid
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

# 清理旧 payload + 日志（dur 为入口实际耗时，验证 500ms 内返回；evt 标记事件类型）
Clear-StalePayloads
$evtTag = if ($isQuestion) { "question" } elseif ($isPermission) { "permission" } else { "stop" }
Write-NotifyLog ("OK adapter=wpf evt=" + $evtTag + " need_info=" + $isNeedInfo + " bg=" + $hasBg +
    " dur=" + $sw.ElapsedMilliseconds + "ms sid=" + ($data.session_id -replace '(.{8}).*', '$1'))

exit 0
