# 定义采集参数及边界。
param([ValidateRange(1,600)][int]$DurationSeconds=30, [ValidateRange(20,2000)][int]$IntervalMilliseconds=100, [switch]$AllKeys)
# 执行本地诊断或资源清理，不修改系统配置。
$ErrorActionPreference="Stop"
# 执行本地诊断或资源清理，不修改系统配置。
if (-not ("FullKeyboardState" -as [type])) {
# 执行本地诊断或资源清理，不修改系统配置。
Add-Type @"
using System; // 声明或执行键盘诊断逻辑。
using System.Runtime.InteropServices; // 声明或执行键盘诊断逻辑。

public static class FullKeyboardState { // 声明或执行键盘诊断逻辑。
    [DllImport("user32.dll")] // 声明或执行键盘诊断逻辑。
    public static extern short GetAsyncKeyState(int vKey); // 声明或执行键盘诊断逻辑。

    [DllImport("user32.dll")] // 声明或执行键盘诊断逻辑。
    public static extern short GetKeyState(int vKey); // 声明或执行键盘诊断逻辑。
} // 声明或执行键盘诊断逻辑。
"@
# 执行本地诊断或资源清理，不修改系统配置。
}

# 执行本地诊断或资源清理，不修改系统配置。
$keys = [ordered]@{
# 执行本地诊断或资源清理，不修改系统配置。
    "A" = 0x41; "B" = 0x42; "C" = 0x43; "D" = 0x44
# 执行本地诊断或资源清理，不修改系统配置。
    "E" = 0x45; "F" = 0x46; "G" = 0x47; "H" = 0x48
# 执行本地诊断或资源清理，不修改系统配置。
    "I" = 0x49; "J" = 0x4A; "K" = 0x4B; "L" = 0x4C
# 执行本地诊断或资源清理，不修改系统配置。
    "M" = 0x4D; "N" = 0x4E; "O" = 0x4F; "P" = 0x50
# 执行本地诊断或资源清理，不修改系统配置。
    "Q" = 0x51; "R" = 0x52; "S" = 0x53; "T" = 0x54
# 执行本地诊断或资源清理，不修改系统配置。
    "U" = 0x55; "V" = 0x56; "W" = 0x57; "X" = 0x58
# 执行本地诊断或资源清理，不修改系统配置。
    "Y" = 0x59; "Z" = 0x5A

# 执行本地诊断或资源清理，不修改系统配置。
    "0" = 0x30; "1" = 0x31; "2" = 0x32; "3" = 0x33
# 执行本地诊断或资源清理，不修改系统配置。
    "4" = 0x34; "5" = 0x35; "6" = 0x36; "7" = 0x37
# 执行本地诊断或资源清理，不修改系统配置。
    "8" = 0x38; "9" = 0x39

# 执行本地诊断或资源清理，不修改系统配置。
    "Space" = 0x20
# 执行本地诊断或资源清理，不修改系统配置。
    "Enter" = 0x0D
# 执行本地诊断或资源清理，不修改系统配置。
    "Tab" = 0x09
# 执行本地诊断或资源清理，不修改系统配置。
    "Backspace" = 0x08
# 执行本地诊断或资源清理，不修改系统配置。
    "Escape" = 0x1B
# 执行本地诊断或资源清理，不修改系统配置。
    "Insert" = 0x2D
# 执行本地诊断或资源清理，不修改系统配置。
    "Delete" = 0x2E
# 执行本地诊断或资源清理，不修改系统配置。
    "Home" = 0x24
# 执行本地诊断或资源清理，不修改系统配置。
    "End" = 0x23
# 执行本地诊断或资源清理，不修改系统配置。
    "PageUp" = 0x21
# 执行本地诊断或资源清理，不修改系统配置。
    "PageDown" = 0x22
# 执行本地诊断或资源清理，不修改系统配置。
    "Left" = 0x25
# 执行本地诊断或资源清理，不修改系统配置。
    "Up" = 0x26
# 执行本地诊断或资源清理，不修改系统配置。
    "Right" = 0x27
# 执行本地诊断或资源清理，不修改系统配置。
    "Down" = 0x28

# 执行本地诊断或资源清理，不修改系统配置。
    "ShiftLeft" = 0xA0
# 执行本地诊断或资源清理，不修改系统配置。
    "ShiftRight" = 0xA1
# 执行本地诊断或资源清理，不修改系统配置。
    "CtrlLeft" = 0xA2
# 执行本地诊断或资源清理，不修改系统配置。
    "CtrlRight" = 0xA3
# 执行本地诊断或资源清理，不修改系统配置。
    "AltLeft" = 0xA4
# 执行本地诊断或资源清理，不修改系统配置。
    "AltRight" = 0xA5
# 执行本地诊断或资源清理，不修改系统配置。
    "WinLeft" = 0x5B
# 执行本地诊断或资源清理，不修改系统配置。
    "WinRight" = 0x5C

# 执行本地诊断或资源清理，不修改系统配置。
    "CapsLock" = 0x14
# 执行本地诊断或资源清理，不修改系统配置。
    "NumLock" = 0x90
# 执行本地诊断或资源清理，不修改系统配置。
    "ScrollLock" = 0x91
# 执行本地诊断或资源清理，不修改系统配置。
}

# 执行本地诊断或资源清理，不修改系统配置。
function Test-KeyDown {
# 定义采集参数及边界。
    param([int]$VirtualKey)
# 执行本地诊断或资源清理，不修改系统配置。
    return (([FullKeyboardState]::GetAsyncKeyState($VirtualKey) -band 0x8000) -ne 0)
# 执行本地诊断或资源清理，不修改系统配置。
}

# 执行本地诊断或资源清理，不修改系统配置。
function Test-ToggleOn {
# 定义采集参数及边界。
    param([int]$VirtualKey)
# 执行本地诊断或资源清理，不修改系统配置。
    return (([FullKeyboardState]::GetKeyState($VirtualKey) -band 1) -ne 0)
# 执行本地诊断或资源清理，不修改系统配置。
}

# 执行本地诊断或资源清理，不修改系统配置。
Write-Host "本程序只显示本机键位状态，默认仅显示修饰键；-AllKeys 会显示所有键位，请勿输入敏感内容。" -ForegroundColor Yellow
# 执行本地诊断或资源清理，不修改系统配置。
Write-Host "按 Ctrl+C 结束。" -ForegroundColor Yellow

# 执行本地诊断或资源清理，不修改系统配置。
$watch = [Diagnostics.Stopwatch]::StartNew()
# 执行本地诊断或资源清理，不修改系统配置。
while ($watch.Elapsed.TotalSeconds -lt $DurationSeconds) {
# 执行本地诊断或资源清理，不修改系统配置。
    $pressed = @()

# 执行本地诊断或资源清理，不修改系统配置。
    foreach ($item in $keys.GetEnumerator()) {
# 执行本地诊断或资源清理，不修改系统配置。
        if (($AllKeys -or $item.Value -in 0xA0,0xA1,0xA2,0xA3,0xA4,0xA5,0x5B,0x5C,0x14,0x90,0x91) -and (Test-KeyDown $item.Value)) {
# 执行本地诊断或资源清理，不修改系统配置。
            $pressed += $item.Key
# 执行本地诊断或资源清理，不修改系统配置。
        }
# 执行本地诊断或资源清理，不修改系统配置。
    }

# 执行本地诊断或资源清理，不修改系统配置。
    $caps = Test-ToggleOn 0x14
# 执行本地诊断或资源清理，不修改系统配置。
    $num = Test-ToggleOn 0x90
# 执行本地诊断或资源清理，不修改系统配置。
    $scroll = Test-ToggleOn 0x91

    # 保留终端输出便于核验，不清空其他诊断内容。

# 执行本地诊断或资源清理，不修改系统配置。
    [pscustomobject]@{
# 执行本地诊断或资源清理，不修改系统配置。
        Time = Get-Date -Format "HH:mm:ss.fff"
# 执行本地诊断或资源清理，不修改系统配置。
        PressedKeys = if ($pressed.Count) { $pressed -join ", " } else { "(none)" }
# 执行本地诊断或资源清理，不修改系统配置。
        CapsLock = $caps
# 执行本地诊断或资源清理，不修改系统配置。
        NumLock = $num
# 执行本地诊断或资源清理，不修改系统配置。
        ScrollLock = $scroll
# 执行本地诊断或资源清理，不修改系统配置。
    } | Format-List

# 执行本地诊断或资源清理，不修改系统配置。
    Start-Sleep -Milliseconds $IntervalMilliseconds
# 执行本地诊断或资源清理，不修改系统配置。
}
