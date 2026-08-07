# =============================================================
# task-notify.ps1 — Claude Code 任务完成右下角弹窗（Stop hook 用）
#
# 功能：每次 Claude 停止响应时，右下角弹出 ChatGPT 风格反馈卡片：
#       ✅ 任务完成 / ❓ 需要用户提供相关信息（附回复摘要）
#
# 渲染：WPF（DirectWrite 渲染，与浏览器同源，文字清晰不发糊）
#       ⚠️ 必须以 STA 线程启动（settings.json 中 command 已带 -STA）
#
# 输入（二选一）：
#   1. stdin JSON — Stop hook 负载（含 last_assistant_message 字段）
#   2. 手动测试参数 — -Title / -Message / -Type
#
# 输出：无 stdout（返回空 = 不干预 Claude 的停止行为）
#
# 注意：脚本必须以 UTF-8 with BOM 保存（PowerShell 5.1 对无 BOM 的
#       UTF-8 按 ANSI/GBK 解释，中文字符串会乱码）。
# =============================================================

param(
    [string]$Title,
    [string]$Message,
    [ValidateSet("done", "need_info")]
    [string]$Type
)

# ---- 编码：PS 5.1 必须强制 UTF-8，否则 stdin 中文乱码 ----
try { [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# =============================================================
# 辅助函数
# =============================================================

# 从 transcript（JSONL）尾部取最后一条 assistant 文本 —— 仅当
# stdin 缺失 last_assistant_message 时的兜底方案
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

# 启发式判断：这条回复是否需要用户提供相关信息
# （以问号结尾 / 出现请求词 → need_info）
function Test-NeedInfo {
    param([string]$t)
    if (-not $t) { return $false }
    $t = $t.Trim()
    if ($t -match "[?？]\s*$") { return $true }
    if ($t -match "请(你|您)?(提供|告诉|告知|确认|给出|补充|说明|检查|输入|发送|上传|分享|回复|告知)") { return $true }
    if ($t -match "需要你|需要您|麻烦你|请把|能否|你能不") { return $true }
    return $false
}

# 摘要截断长度（字）——必须在 Get-Summary 调用前定义，否则其值为 $null
# 导致 Substring(0, $null) = 空串，正文只剩省略号（历史 bug 根因）
$MAX_CHARS = 50

# 提取摘要：清洗代码块/HTML/emoji/markdown，取首段自然语言，截断 $MAX_CHARS 字
function Get-Summary {
    param([string]$t)
    if (-not $t) { return "" }
    # 去代码块（```...```）与行内代码（`...`）
    $clean = [regex]::Replace($t, '```[\s\S]*?```', ' ')
    $clean = $clean -replace '`[^`]*`', ' '
    # 去 HTML 标签；常见实体转回原文，残留实体清除
    $clean = [regex]::Replace($clean, '<[^>]+>', ' ')
    $clean = $clean -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>' -replace '&quot;', '"'
    $clean = $clean -replace '&[a-zA-Z#0-9]{1,8};', ' '
    # 去 markdown 符号
    $clean = $clean -replace '\*\*?', '' -replace '^#+\s*', '' -replace '^\s*[-*+]\s*', ''
    # 去 emoji（补充平面代理对，避免渲染方块）
    $clean = [regex]::Replace($clean, '[\uD800-\uDBFF][\uDC00-\uDFFF]', '')
    # 取首段（按空行分段）
    $paras = @($clean -split '(\r?\n\s*){2,}' | Where-Object { $_.Trim() })
    if ($paras.Count -gt 0) { $clean = $paras[0] }
    $clean = $clean -replace '\s+', ' '
    $clean = $clean.Trim()
    if ($clean.Length -gt $MAX_CHARS) { $clean = $clean.Substring(0, $MAX_CHARS) + "…" }
    return $clean
}

# =============================================================
# 数据获取
# =============================================================
$rawText = $null
$isNeedInfo = $false

$stdinJson = ""
if ([Console]::IsInputRedirected) {
    # hook 模式：stdin 有重定向（Stop hook 负载）
    try { $stdinJson = [Console]::In.ReadToEnd() } catch { }
}

if ($stdinJson) {
    try {
        $data = $stdinJson | ConvertFrom-Json
        if ($null -ne $data.hook_event_name -or $null -ne $data.last_assistant_message) {
            $rawText = $data.last_assistant_message
            if (-not $rawText -and $data.transcript_path) {
                # 兜底：读 transcript 尾部最后一条 assistant 消息
                $rawText = Get-LastAssistantFromTranscript -path $data.transcript_path
            }
        }
    } catch { }
} elseif ($Title -and $Message) {
    # 手动测试模式：直接用参数
    $rawText = $Message
    $isNeedInfo = ($Type -eq "need_info")
}

if (-not $rawText) {
    # 最终兜底：什么都拿不到时显示通用文案
    $rawText = "Claude 已完成响应"
}

# ---- 类型判断 + 文案 ----
if (-not $isNeedInfo) { $isNeedInfo = Test-NeedInfo -t $rawText }
if ($isNeedInfo) {
    $emoji = "❓"
    $titleText = "需要用户提供相关信息"
} else {
    $emoji = "✅"
    $titleText = "任务完成"
}
$bodyText = Get-Summary -t $rawText

# =============================================================
# WPF 弹窗（DirectWrite 渲染，文字清晰；单位 = CSS px/pt，与
# HTML 调整器预览天然一致，无需手动 DPI 换算）
# =============================================================
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

# 尺寸基准值（WPF 单位 = DIP，等价 HTML CSS px）
$W = 400        # 卡片宽度
$H = 200        # 卡片高度
$MARGIN = 20    # 距屏幕右下角边距
$PAD_X = 20     # 标题左边距
$PAD_TOP = 15   # 标题上边距
$BODY_TOP = 40  # 正文上边距
$BODY_H = 80    # 正文区域高度
# 字号：WPF FontSize 单位是 DIP px，pt → px = × 4/3（与 HTML 的 pt 语义一致）
$F_TITLE = 12 * 1.3333     # 标题字号（≈12pt）
$F_BODY = 10 * 1.3333      # 正文字号（≈10pt）
# 阴影边距：DropShadowEffect 画在卡片外，窗口必须比卡片大一圈，
# 否则阴影被窗口边界裁剪不可见
$SHADOW_PAD = 30

$app = New-Object System.Windows.Application

$win = New-Object System.Windows.Window
$win.Width = $W + 2 * $SHADOW_PAD
$win.Height = $H + 2 * $SHADOW_PAD
$win.WindowStyle = [System.Windows.WindowStyle]::None
$win.AllowsTransparency = $true          # 支持圆角
$win.Background = [System.Windows.Media.Brushes]::Transparent
$win.Topmost = $true
$win.ShowInTaskbar = $false
$win.ShowActivated = $false              # 显示但不激活，不抢用户焦点
$win.Opacity = 0.0
# 定位右下角（按卡片实际位置算，卡片内缩阴影边距）
$wa = [System.Windows.SystemParameters]::WorkArea
$win.Left = $wa.Right - $W - $MARGIN - $SHADOW_PAD
$win.Top = $wa.Bottom - $H - $MARGIN - $SHADOW_PAD

# 卡片 Border：白底、圆角 16、浅灰边框、阴影（内缩进窗口，阴影可见）
$border = New-Object System.Windows.Controls.Border
$border.Margin = [System.Windows.Thickness]::new($SHADOW_PAD)
$border.Background = [System.Windows.Media.Brushes]::White
$border.CornerRadius = [System.Windows.CornerRadius]::new(16)
$border.BorderBrush = [System.Windows.Media.Brushes]::LightGray
$border.BorderThickness = [System.Windows.Thickness]::new(1)
$shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
$shadow.BlurRadius = 24
$shadow.ShadowDepth = 6                  # 向下偏移，贴近 HTML 的 box-shadow
$shadow.Direction = 270
$shadow.Opacity = 0.18
$shadow.Color = [System.Windows.Media.Colors]::Black
$border.Effect = $shadow

# 布局 Grid
$grid = New-Object System.Windows.Controls.Grid
$border.Child = $grid

# 标题 TextBlock（emoji + 文案，粗体黑）
$tbTitle = New-Object System.Windows.Controls.TextBlock
$tbTitle.Text = "$emoji  $titleText"
$tbTitle.FontSize = $F_TITLE
$tbTitle.FontWeight = [System.Windows.FontWeights]::Bold
$tbTitle.Foreground = [System.Windows.Media.Brushes]::Black
$tbTitle.Margin = [System.Windows.Thickness]::new($PAD_X, $PAD_TOP, 0, 0)
$tbTitle.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
$tbTitle.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left

# 正文 TextBlock（自动换行 + 超长省略，DirectWrite 渲染）
$tbBody = New-Object System.Windows.Controls.TextBlock
$tbBody.Text = $bodyText
$tbBody.FontSize = $F_BODY
$tbBody.Foreground = [System.Windows.Media.Brushes]::Black
$tbBody.Margin = [System.Windows.Thickness]::new($PAD_X, $BODY_TOP, $PAD_X, 0)
$tbBody.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
$tbBody.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
$tbBody.TextWrapping = [System.Windows.TextWrapping]::Wrap
$tbBody.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
$tbBody.MaxHeight = $BODY_H

$grid.Children.Add($tbTitle) | Out-Null
$grid.Children.Add($tbBody) | Out-Null
$win.Content = $border

# ---- 关闭逻辑：点击任意处 / Esc 立即关闭 ----
$win.Add_MouseLeftButtonDown({
    $script:animTimer.Stop()
    $win.Close()
})
$win.Add_KeyDown({
    if ($_.Key -eq [System.Windows.Input.Key]::Escape) {
        $script:animTimer.Stop()
        $win.Close()
    }
})

# ---- 动画：淡入（~0.5s）→ 停留 5s → 淡出（~0.5s） ----
$script:phase = "in"
$script:holdTicks = 0

$animTimer = New-Object System.Windows.Threading.DispatcherTimer
$animTimer.Interval = [TimeSpan]::FromMilliseconds(20)
$animTimer.Add_Tick({
    if ($script:phase -eq "in") {
        $win.Opacity += 0.05
        if ($win.Opacity -ge 1.0) {
            $win.Opacity = 1.0
            $script:phase = "hold"
            $script:holdTicks = 0
        }
    } elseif ($script:phase -eq "hold") {
        $script:holdTicks++
        if ($script:holdTicks -ge 250) { $script:phase = "out" }   # 250 × 20ms = 5s
    } elseif ($script:phase -eq "out") {
        $win.Opacity -= 0.05
        if ($win.Opacity -le 0.0) {
            $animTimer.Stop()
            $win.Close()
        }
    }
})

# ---- 显示 + 消息循环 ----
$win.Add_Closed({ $app.Shutdown() })
$null = $win.Show()
$animTimer.Start()
$null = $app.Run()   # 注意：Run() 返回退出码，必须吞掉，保持 stdout 干净（hook 会解析）

exit 0
