# Save as: Log-AllKeys-Async.ps1
# Run as Administrator
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class K {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);
}
"@

$OutDir = "C:\Forensic\KeyLogs"
New-Item -Path $OutDir -ItemType Directory -Force | Out-Null
$logFile = Join-Path $OutDir ("keys_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".csv")
"Timestamp,VirtualKey,KeyName,State" | Out-File -FilePath $logFile -Encoding UTF8

# Virtual-Key codes 1..254
$vkRange = 1..254

Write-Host "按 Ctrl+C 停止。正在记录所有按键事件到 $logFile" -ForegroundColor Yellow

# Maintain previous state to detect transitions
$prev = @{}
foreach ($v in $vkRange) { $prev[$v] = $false }

try {
    while ($true) {
        $ts = Get-Date -Format "o"
        foreach ($vk in $vkRange) {
            $state = ([K]::GetAsyncKeyState($vk) -band 0x8000) -ne 0
            if ($state -and -not $prev[$vk]) {
                # Key down transition
                $name = try { [System.Windows.Forms.Keys]$vk } catch { $vk }
                "$ts,$vk,$name,Down" | Out-File -FilePath $logFile -Append -Encoding UTF8
            } elseif (-not $state -and $prev[$vk]) {
                # Key up transition
                $name = try { [System.Windows.Forms.Keys]$vk } catch { $vk }
                "$ts,$vk,$name,Up" | Out-File -FilePath $logFile -Append -Encoding UTF8
            }
            $prev[$vk] = $state
        }
        Start-Sleep -Milliseconds 50
    }
} catch [System.Exception] {
    Write-Host "记录中断: $($_.Exception.Message)" -ForegroundColor Red
}
