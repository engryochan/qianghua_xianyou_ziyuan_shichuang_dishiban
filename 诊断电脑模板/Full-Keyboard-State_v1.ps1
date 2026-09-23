Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class FullKeyboardState {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    public static extern short GetKeyState(int vKey);
}
"@

$keys = [ordered]@{
    "A" = 0x41; "B" = 0x42; "C" = 0x43; "D" = 0x44
    "E" = 0x45; "F" = 0x46; "G" = 0x47; "H" = 0x48
    "I" = 0x49; "J" = 0x4A; "K" = 0x4B; "L" = 0x4C
    "M" = 0x4D; "N" = 0x4E; "O" = 0x4F; "P" = 0x50
    "Q" = 0x51; "R" = 0x52; "S" = 0x53; "T" = 0x54
    "U" = 0x55; "V" = 0x56; "W" = 0x57; "X" = 0x58
    "Y" = 0x59; "Z" = 0x5A

    "0" = 0x30; "1" = 0x31; "2" = 0x32; "3" = 0x33
    "4" = 0x34; "5" = 0x35; "6" = 0x36; "7" = 0x37
    "8" = 0x38; "9" = 0x39

    "Space" = 0x20
    "Enter" = 0x0D
    "Tab" = 0x09
    "Backspace" = 0x08
    "Escape" = 0x1B
    "Insert" = 0x2D
    "Delete" = 0x2E
    "Home" = 0x24
    "End" = 0x23
    "PageUp" = 0x21
    "PageDown" = 0x22
    "Left" = 0x25
    "Up" = 0x26
    "Right" = 0x27
    "Down" = 0x28

    "ShiftLeft" = 0xA0
    "ShiftRight" = 0xA1
    "CtrlLeft" = 0xA2
    "CtrlRight" = 0xA3
    "AltLeft" = 0xA4
    "AltRight" = 0xA5
    "WinLeft" = 0x5B
    "WinRight" = 0x5C

    "CapsLock" = 0x14
    "NumLock" = 0x90
    "ScrollLock" = 0x91
}

function Test-KeyDown {
    param([int]$VirtualKey)
    return (([FullKeyboardState]::GetAsyncKeyState($VirtualKey) -band 0x8000) -ne 0)
}

function Test-ToggleOn {
    param([int]$VirtualKey)
    return (([FullKeyboardState]::GetKeyState($VirtualKey) -band 1) -ne 0)
}

Write-Host "本程序只显示本机键位状态，不记录字符、文本、密码或网络地址。" -ForegroundColor Yellow
Write-Host "按 Ctrl+C 结束。" -ForegroundColor Yellow

while ($true) {
    $pressed = @()

    foreach ($item in $keys.GetEnumerator()) {
        if (Test-KeyDown $item.Value) {
            $pressed += $item.Key
        }
    }

    $caps = Test-ToggleOn 0x14
    $num = Test-ToggleOn 0x90
    $scroll = Test-ToggleOn 0x91

    Clear-Host

    [pscustomobject]@{
        Time = Get-Date -Format "HH:mm:ss.fff"
        PressedKeys = if ($pressed.Count) { $pressed -join ", " } else { "(none)" }
        CapsLock = $caps
        NumLock = $num
        ScrollLock = $scroll
    } | Format-List

    Start-Sleep -Milliseconds 100
}