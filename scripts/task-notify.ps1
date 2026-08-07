# =============================================================
# task-notify.ps1 — Claude Code 任务完成右下角弹窗（Stop hook 用）
#
# 功能：每次 Claude 停止响应时，右下角弹出 ChatGPT 风格反馈卡片：
#       ✅ 任务完成 / ❓ 需要用户提供相关信息（附回复摘要）
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

# 提取摘要：去 markdown 符号、压缩空白、截断 $MAX_CHARS 字
function Get-Summary {
    param([string]$t)
    if (-not $t) { return "" }
    $clean = $t -replace '`', '' -replace '\*\*?', '' -replace '^#+\s*', '' -replace '^\s*[-*+]\s*', ''
    $clean = $clean -replace '\s+', ' '
    $clean = $clean.Trim()
    if ($clean.Length -gt $MAX_CHARS) { $clean = $clean.Substring(0, $MAX_CHARS) + "…" }
    return $clean
}

# 按可用宽度折行：Label 只有 Text 含换行符时才显示多行
function Format-Body {
    param([string]$t, [int]$maxWidth, [System.Drawing.Font]$font)
    if (-not $t) { return "" }
    $result = ""
    $line = ""
    foreach ($ch in $t.ToCharArray()) {
        $test = $line + $ch
        $w = [System.Windows.Forms.TextRenderer]::MeasureText($test, $font).Width
        if ($w -gt $maxWidth -and $line) {
            $result += $line + "`n"
            $line = $ch
        } else {
            $line = $test
        }
    }
    $result += $line
    return $result
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
# WinForms 弹窗（零第三方依赖）
# =============================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 圆角 + Win32 API（SW_SHOWNA = 8：显示但不激活，不抢用户焦点）
# 注意：CreateRoundRectRgn 位于 gdi32.dll（wingdi.h），不是 user32.dll
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NotifyWin32 {
    [DllImport("gdi32.dll")]
    public static extern IntPtr CreateRoundRectRgn(int x1, int y1, int x2, int y2, int w, int h);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")]
    public static extern uint GetDpiForSystem();
}
"@

# DPI aware：PS 5.1 默认不做 DPI 感知，高分屏（125%/150% 缩放）下
# 文字会被位图拉伸导致模糊；声明后按系统 DPI 缩放窗体尺寸与字号
$null = [NotifyWin32]::SetProcessDPIAware()
$scale = [NotifyWin32]::GetDpiForSystem() / 96.0
# 尺寸基准值（100% DPI），经 HTML 调整器调优
$W = [int](380 * $scale)        # 卡片宽度
$H = [int](150 * $scale)        # 卡片高度
$MARGIN = [int](20 * $scale)
$PAD_X = [int](20 * $scale)     # 标题左边距
$PAD_TOP = [int](14 * $scale)   # 标题上边距
$BODY_TOP = [int](34 * $scale)  # 正文上边距
$BODY_H = [int](60 * $scale)    # 正文区域高度
$F_TITLE = 8 * $scale           # 标题字号 (pt)
$F_BODY = 7 * $scale            # 正文字号 (pt)
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
# 注意：PS 5.1 中 New-Object 类型名(逗号参数) 有解析坑，一律用 ::new
$form.Location = [System.Drawing.Point]::new($wa.Right - $W - $MARGIN, $wa.Bottom - $H - $MARGIN)
$form.Size = [System.Drawing.Size]::new($W, $H)
$form.BackColor = [System.Drawing.Color]::White   # 白色卡片 + 黑字，醒目
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.KeyPreview = $true
$form.Opacity = 0.0

# 圆角 16px
$rgn = [NotifyWin32]::CreateRoundRectRgn(0, 0, $W, $H, 16, 16)
$form.Region = [System.Drawing.Region]::FromHrgn($rgn)

# 标题（emoji + 文案）
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Location = [System.Drawing.Point]::new($PAD_X, $PAD_TOP)
$lblTitle.AutoSize = $true
$lblTitle.Text = "$emoji  $titleText"
$lblTitle.Font = [System.Drawing.Font]::new("Segoe UI", $F_TITLE, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::Black
$lblTitle.BackColor = $form.BackColor

# 正文摘要
$lblBody = New-Object System.Windows.Forms.Label
$lblBody.Location = [System.Drawing.Point]::new($PAD_X, $BODY_TOP)
$lblBody.Size = [System.Drawing.Size]::new($W - 2 * $PAD_X, $BODY_H)
$lblBody.Font = [System.Drawing.Font]::new("Segoe UI", $F_BODY)
$lblBody.Text = Format-Body -t $bodyText -maxWidth ($W - 2 * $PAD_X) -font $lblBody.Font
$lblBody.ForeColor = [System.Drawing.Color]::FromArgb(51, 51, 51)   # 深灰黑正文
$lblBody.BackColor = $form.BackColor

$form.Controls.Add($lblTitle) | Out-Null
$form.Controls.Add($lblBody) | Out-Null

# 白色卡片加浅灰边框，亮色背景下边缘更清晰
$form.Add_Paint({
    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(204, 204, 204))
    $_.Graphics.DrawRectangle($pen, 0, 0, $form.Width - 1, $form.Height - 1)
    $pen.Dispose()
})

# ---- 关闭逻辑：点击任意处 / Esc 立即关闭 ----
$clickHandler = {
    $script:timer.Stop()
    $form.Close()
}
$form.Add_MouseClick($clickHandler)
$lblTitle.Add_MouseClick($clickHandler)
$lblBody.Add_MouseClick($clickHandler)

$form.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $script:timer.Stop()
        $form.Close()
    }
})

# ---- 动画：淡入（~0.5s）→ 停留 5s → 淡出（~0.5s） ----
$script:phase = "in"
$script:holdTicks = 0

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 20
$timer.Add_Tick({
    if ($script:phase -eq "in") {
        $form.Opacity += 0.05
        if ($form.Opacity -ge 1.0) {
            $form.Opacity = 1.0
            $script:phase = "hold"
            $script:holdTicks = 0
        }
    } elseif ($script:phase -eq "hold") {
        $script:holdTicks++
        if ($script:holdTicks -ge 250) { $script:phase = "out" }   # 250 × 20ms = 5s
    } elseif ($script:phase -eq "out") {
        $form.Opacity -= 0.05
        if ($form.Opacity -le 0.0) {
            $timer.Stop()
            $form.Close()
        }
    }
})

# ---- 显示（不激活、不抢焦点）+ 消息循环 ----
# 注意：CreateHandle() 是 protected 方法，PS 无法调用；
#      用公开的 Handle 属性触发句柄创建（不显示窗口）
$form.Add_FormClosed({ [System.Windows.Forms.Application]::Exit() })
$null = $form.Handle
$null = [NotifyWin32]::ShowWindow($form.Handle, 8)   # SW_SHOWNA
$timer.Start()
[System.Windows.Forms.Application]::Run()

exit 0
