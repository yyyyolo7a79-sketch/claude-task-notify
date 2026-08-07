# =============================================================
# show-popup.ps1 — 弹窗 UI 进程（由 notify-complete.ps1 派生，独立运行）
#
# 职责：
#   1. 读取 payload 文件（-PayloadFile），读取后立即删除
#   2. WPF（DirectWrite）渲染右下角非模态卡片弹窗
#   3. hold 8 秒后淡出；点击卡片 / 右上角 ✕ 立即关闭（无 Esc——无焦点窗口收不到键盘）
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
# 第四轮审查修复：校验通过后统一使用规范化路径 $payloadPath（读取与删除一致）；
#   $DIR 也先 GetFullPath 再构造前缀（防环境变量含相对片段导致校验语义不一致）
$payloadPath = ""
if ($PayloadFile) {
    try {
        $dirFull = [IO.Path]::GetFullPath($DIR)
        $full = [IO.Path]::GetFullPath($PayloadFile)
        $prefix = $dirFull.TrimEnd('\') + '\'
        if ($full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFileName($full) -match '^payload-[0-9a-f]{32}\.json$') {
            $payloadPath = $full
        }
    } catch { }
}
if (-not $payloadPath) {
    Write-NotifyLog "UI payload-rejected"
    exit 1   # 校验不通过：不读取也不删除任何文件
}

try {
    $p = Get-Content -Raw $payloadPath -Encoding UTF8 | ConvertFrom-Json
    if ($p.emoji) { $emoji = $p.emoji }
    if ($p.title) { $titleText = $p.title }
    if ($p.body) { $bodyText = $p.body }
    if ($p.project) { $project = $p.project }
    Write-NotifyLog "UI payload-ok"
} catch {
    Write-NotifyLog "UI payload-invalid"
} finally {
    Remove-Item $payloadPath -Force -ErrorAction SilentlyContinue
}

# =============================================================
# WPF 渲染
# =============================================================
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

# Win32：WS_EX_NOACTIVATE（点击不抢焦点）+ SetWindowPos（物理像素定位）
# 第三轮审查修复：
#   - SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2)：进程默认 system-aware，
#     MDT_EFFECTIVE_DPI 会返回系统 DPI 而非目标屏 DPI；必须在创建任何窗口前声明
#   - SetLastError=true + 返回值检查 + DPI fallback（查询失败回退 96）
#   - 定位全程使用同一 HMONITOR（单次 GetCursorPos → MonitorFromPoint → GetMonitorInfo/GetDpiForMonitor）
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32Ext {
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr", SetLastError = true)]
    public static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr", SetLastError = true)]
    public static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool GetCursorPos(out POINT pt);
    [DllImport("user32.dll", SetLastError = true)] public static extern IntPtr MonitorFromPoint(POINT pt, uint dwFlags);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool GetMonitorInfo(IntPtr hMonitor, out MONITORINFO lpmi);
    [DllImport("shcore.dll", SetLastError = true)] public static extern int GetDpiForMonitor(IntPtr hMonitor, int dpiType, out uint dpiX, out uint dpiY);
    // 第五轮审查修复：Get/SetWindowLongPtr 精确失败判断——
    //   PS 5.1 层直接调 Marshal.SetLastWin32Error 会抛 RuntimeException（曾导致弹窗
    //   渲染失败），故清零+读取 last error 全部收进 C# 包装层（.NET Framework 层可用）。
    //   语义：返回 0 且 last error≠0 才是失败；返回 0 且 last error=0 是"成功但旧值恰为 0"
    [DllImport("kernel32.dll")] private static extern void SetLastError(uint dwErrCode);
    public static bool GetWindowLongPtrChecked(IntPtr hWnd, int nIndex, out IntPtr value) {
        SetLastError(0);
        value = GetWindowLongPtr64(hWnd, nIndex);
        return !(value == IntPtr.Zero && Marshal.GetLastWin32Error() != 0);
    }
    public static bool SetWindowLongPtrChecked(IntPtr hWnd, int nIndex, IntPtr dwNewLong) {
        SetLastError(0);
        IntPtr ret = SetWindowLongPtr64(hWnd, nIndex, dwNewLong);
        return !(ret == IntPtr.Zero && Marshal.GetLastWin32Error() != 0);
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int L; public int T; public int R; public int B; }
    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }
}
"@
# PER_MONITOR_AWARE_V2 = -4：必须在任何 WPF 窗口创建之前调用
# 第五轮审查修复：PMv2 失败 → 跳过自定义定位，保留 WPF 初始位置
#   （system-aware 下 GetDpiForMonitor 返回的是系统 DPI，按它换算的物理尺寸/坐标
#     在混合 DPI 副屏上会缩小或错位；WPF 初始位置由系统按主屏正确计算）
$pmv2Ok = $false
try {
    if ([Win32Ext]::SetProcessDpiAwarenessContext([IntPtr](-4))) {
        $pmv2Ok = $true
    } else {
        Write-NotifyLog "UI pmv2-failed-initial-pos"
    }
} catch {
    Write-NotifyLog "UI pmv2-error-initial-pos"
}
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
[System.Windows.Controls.Grid]::SetColumnSpan($tbBody, 3)   # 第三轮审查修复：正文跨全部三列，否则被压缩到标题列宽度
$grid.Children.Add($tbBody) | Out-Null

$win.Content = $border

# ---- 关闭逻辑：点击卡片任意处 / 右上角 ✕ 立即关闭（无 Esc——无焦点窗口收不到键盘事件）----
$win.Add_MouseLeftButtonDown({
    $script:animTimer.Stop()
    $win.Close()
})
# ---- 动画：淡入 → 停留 8s（hold）→ 淡出 ----
# 审查修复：hold 用 Stopwatch 单调时钟（DispatcherTimer 累计 tick 会把 8 秒拖成
#   15 秒；DateTime 受系统校时影响，Stopwatch 不受）
$script:phase = "in"
$script:holdSw = [System.Diagnostics.Stopwatch]::StartNew()

$animTimer = New-Object System.Windows.Threading.DispatcherTimer
$animTimer.Interval = [TimeSpan]::FromMilliseconds(20)
$animTimer.Add_Tick({
    if ($script:phase -eq "in") {
        $win.Opacity += 0.05
        if ($win.Opacity -ge 1.0) {
            $win.Opacity = 1.0
            $script:phase = "hold"
            $script:holdSw.Restart()
        }
    } elseif ($script:phase -eq "hold") {
        if ($script:holdSw.ElapsedMilliseconds -ge $DURATION_MS) {
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

    # ① 叠加 WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW
    # 第五轮审查修复：失败判断收进 C# 包装层——调用前 SetLastError(0)，调用后
    #   读 Marshal.GetLastWin32Error()（PS 5.1 层直接调会抛 RuntimeException，
    #   Add-Type 编译的 C# 层可用）。返回 0 + last error≠0 才是失败；
    #   返回 0 + last error=0 是"成功但旧值恰为 0"，不再误报
    $exOld = [IntPtr]::Zero
    if ([Win32Ext]::GetWindowLongPtrChecked($hwnd, $GWL_EXSTYLE, [ref]$exOld)) {
        $exNew = [IntPtr]($exOld.ToInt64() -bor $WS_EX_NOACTIVATE -bor $WS_EX_TOOLWINDOW)
        if (-not [Win32Ext]::SetWindowLongPtrChecked($hwnd, $GWL_EXSTYLE, $exNew)) {
            Write-NotifyLog "UI style-apply-failed"
        }
    } else {
        Write-NotifyLog "UI style-read-failed"
    }
    # 用 SWP_FRAMECHANGED | SWP_NOACTIVATE 刷新扩展样式（不移动、不激活）
    if (-not [Win32Ext]::SetWindowPos($hwnd, [IntPtr]::Zero, 0, 0, 0, 0,
        ($SWP_FRAMECHANGED -bor $SWP_NOACTIVATE -bor $SWP_NOSIZE -bor $SWP_NOZORDER))) {
        Write-NotifyLog "UI style-refresh-failed"
    }

    # ② 多显示器定位（第四轮+第五轮审查修复）：
    #    全链路失败检查——PMv2 失败 / GetCursorPos / MonitorFromPoint / GetMonitorInfo
    #    / GetDpiForMonitor 任一失败则跳过 SetWindowPos（保留 WPF 初始位置），
    #    绝不使用未初始化/回退数据计算坐标（否则窗口会被移出屏幕或错位）
    $posOk = $pmv2Ok
    $pt = New-Object Win32Ext+POINT
    if (-not [Win32Ext]::GetCursorPos([ref]$pt)) {
        $posOk = $false
        Write-NotifyLog "UI cursorpos-failed"
    }
    $hMon = [IntPtr]::Zero
    if ($posOk) {
        $hMon = [Win32Ext]::MonitorFromPoint($pt, $MONITOR_DEFAULTTONEAREST)
        if ($hMon -eq [IntPtr]::Zero) {
            $posOk = $false
            Write-NotifyLog "UI monitor-failed"
        }
    }
    $mi = New-Object Win32Ext+MONITORINFO
    if ($posOk) {
        $mi.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($mi)
        if (-not [Win32Ext]::GetMonitorInfo($hMon, [ref]$mi)) {
            $posOk = $false
            Write-NotifyLog "UI monitor-info-failed"
        }
    }
    $dpiX = 96; $dpiY = 96
    if ($posOk) {
        $hr = [Win32Ext]::GetDpiForMonitor($hMon, $MDT_EFFECTIVE_DPI, [ref]$dpiX, [ref]$dpiY)
        if ($hr -ne 0 -or $dpiX -le 0 -or $dpiY -le 0) {
            # DPI 查询失败：跳过 SetWindowPos，保留 WPF 初始位置
            #（按 96 计算的物理尺寸在 150% 屏上会缩小 1/3，错误定位比不定位更糟）
            $posOk = $false
            Write-NotifyLog "UI dpi-failed-initial-pos"
        }
    }
    if ($posOk) {
        $targetScale = $dpiX / 96.0
        $winPhysW = [int](($W + 2 * $SHADOW_PAD) * $targetScale)
        $winPhysH = [int](($H + 2 * $SHADOW_PAD) * $targetScale)
        $marginPx = [int]($MARGIN * $targetScale)
        $x = $mi.rcWork.R - $winPhysW - $marginPx
        $y = $mi.rcWork.B - $winPhysH - $marginPx
        if (-not [Win32Ext]::SetWindowPos($hwnd, [IntPtr]::Zero, $x, $y, $winPhysW, $winPhysH,
            ($SWP_NOACTIVATE -bor $SWP_NOZORDER))) {
            Write-NotifyLog "UI position-failed"
        }
    }

    $animTimer.Start()
    $null = $app.Run()   # Run() 返回退出码，必须吞掉，保持 stdout 干净
    Write-NotifyLog "UI closed"
} catch {
    # 顶层兜底：任何 UI 初始化/渲染失败都不静默退出，记日志便于诊断
    Write-NotifyLog ("UI render-error: " + $_.Exception.GetType().Name)
    exit 1
}

exit 0
