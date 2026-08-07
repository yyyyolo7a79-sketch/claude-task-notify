# =============================================================
# show-popup.ps1 — 弹窗 UI 进程（由 notify-complete.ps1 派生，独立运行）
#
# 职责：
#   1. 读取 payload 文件（-PayloadFile），读取后立即删除
#   2. WPF（DirectWrite）渲染右下角非模态卡片弹窗
#   3. 8 秒自动淡出；点击卡片 / 右上角 ✕ / Esc 立即关闭
#
# 不抢焦点：ShowActivated=false；不阻塞：独立进程管理 UI 生命周期
#
# 注意：UTF-8 with BOM 保存；必须以 -STA 启动（WPF 必需）
# =============================================================

param(
    [string]$PayloadFile
)

# ---- 编码 ----
try { [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# 脚本级总兜底：Add-Type/WPF 初始化等任何未捕获异常都记日志（不静默退出）
trap {
    try { Write-NotifyLog ("UI fatal: " + $_.Exception.GetType().Name) } catch { }
    exit 1
}

# =============================================================
# 常量（尺寸基准，WPF 单位 = DIP，等价 HTML CSS px）
# =============================================================
$DIR = "$env:TEMP\claude-code-notify"
$LOG_FILE = "$DIR\notify.log"
$LOG_MAX = 200KB

$W = 400        # 卡片宽度
$H = 200        # 卡片高度
$MARGIN = 20    # 距屏幕右下角边距
$PAD_X = 20     # 标题左边距
$PAD_TOP = 15   # 标题上边距
$BODY_TOP = 52  # 正文上边距（含项目名行，原 40 + 项目行 12）
$BODY_H = 80    # 正文区域高度
# 字号：WPF FontSize 单位是 DIP px，pt → px = × 4/3
$F_TITLE = 12 * 1.3333     # 标题（≈12pt）
$F_BODY = 10 * 1.3333      # 正文（≈10pt）
$SHADOW_PAD = 30           # 阴影边距（窗口比卡片大一圈，否则阴影被裁剪）
$DURATION_MS = 8000        # 显示时长 8 秒（规格 3.2）

# 脱敏日志（与入口共用）
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

# =============================================================
# 读取 payload（读取后立即删除，即使渲染失败）
# =============================================================
$emoji = "✅"; $titleText = "任务完成"; $bodyText = "任务已完成，等待你的下一步操作。"; $project = ""

# 审查修复：路径约束——只接受 %TEMP%\claude-code-notify\payload-<32hex>.json，
# 防止脚本被误调用时删除任意 JSON 文件
$payloadOk = $false
if ($PayloadFile) {
    try {
        $full = [IO.Path]::GetFullPath($PayloadFile)
        $prefix = $DIR.TrimEnd('\') + '\'
        if ($full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFileName($full) -match '^payload-[0-9a-f]{32}\.json$') {
            $payloadOk = $true
        }
    } catch { }
}
if (-not $payloadOk) {
    Write-NotifyLog "UI payload-rejected"
    exit 1   # 校验不通过：不读取也不删除任何文件
}

try {
    $p = Get-Content -Raw $PayloadFile -Encoding UTF8 | ConvertFrom-Json
    if ($p.emoji) { $emoji = $p.emoji }
    if ($p.title) { $titleText = $p.title }
    if ($p.body) { $bodyText = $p.body }
    if ($p.project) { $project = $p.project }
    Write-NotifyLog "UI payload-ok"
} catch {
    Write-NotifyLog "UI payload-invalid"
} finally {
    Remove-Item $PayloadFile -Force -ErrorAction SilentlyContinue
}

# =============================================================
# WPF 渲染
# =============================================================
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Windows.Forms   # 仅用 Screen/Cursor 做多显示器定位

# Win32：WS_EX_NOACTIVATE（点击不抢焦点）+ SetWindowPos（物理像素定位）
# 审查修复：Get/SetWindowLongPtr（64位）；GetDpiForMonitor 取目标屏 DPI（混合 DPI 正确）
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32Ext {
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")]
    public static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")]
    public static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT pt);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromPoint(POINT pt, uint dwFlags);
    [DllImport("shcore.dll")] public static extern int GetDpiForMonitor(IntPtr hMonitor, int dpiType, out uint dpiX, out uint dpiY);
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }
}
"@
$GWL_EXSTYLE = -20
$WS_EX_NOACTIVATE = 0x08000000
$WS_EX_TOOLWINDOW = 0x00000080
$SWP_NOSIZE = 0x0001
$SWP_NOZORDER = 0x0004
$SWP_NOACTIVATE = 0x0010
$SWP_FRAMECHANGED = 0x0020
$MDT_EFFECTIVE_DPI = 0
$MONITOR_DEFAULTTONEAREST = 2

$app = New-Object System.Windows.Application

$win = New-Object System.Windows.Window
$win.Width = $W + 2 * $SHADOW_PAD
$win.Height = $H + 2 * $SHADOW_PAD
$win.WindowStyle = [System.Windows.WindowStyle]::None
$win.AllowsTransparency = $true
$win.Background = [System.Windows.Media.Brushes]::Transparent
$win.Topmost = $true
$win.ShowInTaskbar = $false
$win.ShowActivated = $false          # 不激活，不抢焦点（WS_EX_NOACTIVATE 在 Show 后叠加）
$win.Opacity = 0.0
# 初始位置（Show 后会被 SetWindowPos 按鼠标所在屏幕精确覆盖）
$wa = [System.Windows.SystemParameters]::WorkArea
$win.Left = $wa.Right - $W - $MARGIN - $SHADOW_PAD
$win.Top = $wa.Bottom - $H - $MARGIN - $SHADOW_PAD

# 卡片 Border：白底、圆角、浅灰边框、阴影（内缩进窗口）
$border = New-Object System.Windows.Controls.Border
$border.Margin = [System.Windows.Thickness]::new($SHADOW_PAD)
$border.Background = [System.Windows.Media.Brushes]::White
$border.CornerRadius = [System.Windows.CornerRadius]::new(16)
$border.BorderBrush = [System.Windows.Media.Brushes]::LightGray
$border.BorderThickness = [System.Windows.Thickness]::new(1)
$shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
$shadow.BlurRadius = 24
$shadow.ShadowDepth = 6
$shadow.Direction = 270
$shadow.Opacity = 0.18
$shadow.Color = [System.Windows.Media.Colors]::Black
$border.Effect = $shadow

$grid = New-Object System.Windows.Controls.Grid
$border.Child = $grid

# 三列 Grid（审查修复）：标题(*) 可收缩省略 / 项目名(Auto) 截断 / ✕(Auto) 固定
$colTitle = New-Object System.Windows.Controls.ColumnDefinition
$colTitle.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
$colProject = New-Object System.Windows.Controls.ColumnDefinition
$colProject.Width = [System.Windows.GridLength]::Auto
$colClose = New-Object System.Windows.Controls.ColumnDefinition
$colClose.Width = [System.Windows.GridLength]::Auto
$grid.ColumnDefinitions.Add($colTitle) | Out-Null
$grid.ColumnDefinitions.Add($colProject) | Out-Null
$grid.ColumnDefinitions.Add($colClose) | Out-Null

# 标题（可收缩，长标题省略号）
$tbTitle = New-Object System.Windows.Controls.TextBlock
$tbTitle.Text = "$emoji  $titleText"
$tbTitle.FontSize = $F_TITLE
$tbTitle.FontWeight = [System.Windows.FontWeights]::Bold
$tbTitle.Foreground = [System.Windows.Media.Brushes]::Black
$tbTitle.Margin = [System.Windows.Thickness]::new($PAD_X, $PAD_TOP, 4, 0)
$tbTitle.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
$tbTitle.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
[System.Windows.Controls.Grid]::SetColumn($tbTitle, 0)
$grid.Children.Add($tbTitle) | Out-Null

# 项目名（Auto 列，MaxWidth 截断）
if ($project) {
    $tbProject = New-Object System.Windows.Controls.TextBlock
    $tbProject.Text = "· $project"
    $tbProject.FontSize = $F_BODY * 0.85
    $tbProject.Foreground = [System.Windows.Media.Brushes]::Gray
    $tbProject.Margin = [System.Windows.Thickness]::new(0, $PAD_TOP + 2, 8, 0)
    $tbProject.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
    $tbProject.MaxWidth = 140
    $tbProject.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    [System.Windows.Controls.Grid]::SetColumn($tbProject, 1)
    $grid.Children.Add($tbProject) | Out-Null
}

# 右上角 ✕ 关闭按钮（固定列，绝不重叠）
$btnClose = New-Object System.Windows.Controls.TextBlock
$btnClose.Text = "✕"
$btnClose.FontSize = $F_TITLE * 0.9
$btnClose.Foreground = [System.Windows.Media.Brushes]::Gray
$btnClose.Margin = [System.Windows.Thickness]::new(0, $PAD_TOP, $PAD_X, 0)
$btnClose.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
$btnClose.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
$btnClose.Cursor = [System.Windows.Input.Cursors]::Hand
$btnClose.Add_MouseLeftButtonDown({
    $script:animTimer.Stop()
    $win.Close()
})
[System.Windows.Controls.Grid]::SetColumn($btnClose, 2)
$grid.Children.Add($btnClose) | Out-Null

# 正文摘要（自动换行 + 超长省略）
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
$grid.Children.Add($tbBody) | Out-Null

$win.Content = $border

# ---- 关闭逻辑：点击卡片任意处 / Esc ----
$win.Add_MouseLeftButtonDown({
    $script:animTimer.Stop()
    $win.Close()
})
# ---- 动画：淡入 → 停留 8s → 淡出 ----
# 审查修复：hold 用真实时间戳（DispatcherTimer 不保证每 20ms 调度，
#   累计 tick 会把 8 秒拖成 15 秒——实测日志确认）
$script:phase = "in"
$script:holdStart = [DateTime]::UtcNow

$animTimer = New-Object System.Windows.Threading.DispatcherTimer
$animTimer.Interval = [TimeSpan]::FromMilliseconds(20)
$animTimer.Add_Tick({
    if ($script:phase -eq "in") {
        $win.Opacity += 0.05
        if ($win.Opacity -ge 1.0) {
            $win.Opacity = 1.0
            $script:phase = "hold"
            $script:holdStart = [DateTime]::UtcNow
        }
    } elseif ($script:phase -eq "hold") {
        if (([DateTime]::UtcNow - $script:holdStart).TotalMilliseconds -ge $DURATION_MS) {
            $script:phase = "out"
        }
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
try {
    $null = $win.Show()
    $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle

    # ① 叠加 WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW（Ptr API + 失败检查）
    $exOld = [Win32Ext]::GetWindowLongPtr64($hwnd, $GWL_EXSTYLE)
    $exNew = [IntPtr]($exOld.ToInt64() -bor $WS_EX_NOACTIVATE -bor $WS_EX_TOOLWINDOW)
    $null = [Win32Ext]::SetWindowLongPtr64($hwnd, $GWL_EXSTYLE, $exNew)
    # 用 SWP_FRAMECHANGED | SWP_NOACTIVATE 刷新扩展样式（不移动、不激活）
    $null = [Win32Ext]::SetWindowPos($hwnd, [IntPtr]::Zero, 0, 0, 0, 0,
        ($SWP_FRAMECHANGED -bor $SWP_NOACTIVATE -bor $SWP_NOSIZE -bor $SWP_NOZORDER))

    # ② 多显示器定位：鼠标所在屏幕（物理像素）
    # 目标屏 DPI 用 GetDpiForMonitor 获取（不能读当前窗口所在屏的 TransformToDevice——
    #   窗口仍在主屏时副屏 scale 会算错，混合 DPI 修复）
    $pt = New-Object Win32Ext+POINT
    $null = [Win32Ext]::GetCursorPos([ref]$pt)
    $hMon = [Win32Ext]::MonitorFromPoint($pt, $MONITOR_DEFAULTTONEAREST)
    $dpiX = 0; $dpiY = 0
    $null = [Win32Ext]::GetDpiForMonitor($hMon, $MDT_EFFECTIVE_DPI, [ref]$dpiX, [ref]$dpiY)
    $targetScale = $dpiX / 96.0
    $scr = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position)
    $wa2 = $scr.WorkingArea
    $winPhysW = [int](($W + 2 * $SHADOW_PAD) * $targetScale)
    $winPhysH = [int](($H + 2 * $SHADOW_PAD) * $targetScale)
    $marginPx = [int]($MARGIN * $targetScale)
    $x = $wa2.Right - $winPhysW - $marginPx
    $y = $wa2.Bottom - $winPhysH - $marginPx
    $null = [Win32Ext]::SetWindowPos($hwnd, [IntPtr]::Zero, $x, $y, $winPhysW, $winPhysH,
        ($SWP_NOACTIVATE -bor $SWP_NOZORDER))

    $animTimer.Start()
    $null = $app.Run()   # Run() 返回退出码，必须吞掉，保持 stdout 干净
    Write-NotifyLog "UI closed"
} catch {
    # 顶层兜底：任何 UI 初始化/渲染失败都不静默退出，记日志便于诊断
    Write-NotifyLog ("UI render-error: " + $_.Exception.GetType().Name)
    exit 1
}

exit 0
