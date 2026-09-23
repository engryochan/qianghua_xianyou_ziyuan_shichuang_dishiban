# 定义采集参数及边界。
param([ValidateRange(1,600)][int]$DurationSeconds=30, [switch]$RecordKeyCodes, [string]$OutDir=(Join-Path $env:TEMP "KbdDiag"))
# 执行本地诊断或资源清理，不修改系统配置。
$ErrorActionPreference="Stop"
# 执行本地诊断或资源清理，不修改系统配置。
Add-Type -AssemblyName System.Windows.Forms
# Save as: Log-AllKeys-Async.ps1
# 无需管理员权限。
# 执行本地诊断或资源清理，不修改系统配置。
if (-not ("K" -as [type])) {
# 执行本地诊断或资源清理，不修改系统配置。
Add-Type @"
using System; // 声明或执行键盘诊断逻辑。
using System.Runtime.InteropServices; // 声明或执行键盘诊断逻辑。
public static class K { // 声明或执行键盘诊断逻辑。
    [DllImport("user32.dll")] // 声明或执行键盘诊断逻辑。
    public static extern short GetAsyncKeyState(int vKey); // 声明或执行键盘诊断逻辑。
} // 声明或执行键盘诊断逻辑。
"@
# 执行本地诊断或资源清理，不修改系统配置。
}


# 执行本地诊断或资源清理，不修改系统配置。
New-Item -Path $OutDir -ItemType Directory -Force | Out-Null
# 执行本地诊断或资源清理，不修改系统配置。
$logFile = Join-Path $OutDir ("keys_" + (Get-Date -Format "yyyyMMdd_HHmmss_fffffff") + ".csv")
# 执行本地诊断或资源清理，不修改系统配置。
"Timestamp,VirtualKey,KeyName,State" | Out-File -FilePath $logFile -Encoding UTF8

# Virtual-Key codes 1..254
# 执行本地诊断或资源清理，不修改系统配置。
$vkRange = if ($RecordKeyCodes) { 1..254 } else { @(0xA0,0xA1,0xA2,0xA3,0xA4,0xA5,0x5B,0x5C,0x14,0x90,0x91) }

# 执行本地诊断或资源清理，不修改系统配置。
Write-Host "按 Ctrl+C 停止。正在记录选定键位状态变化；轮询可能漏掉短按，不能证明事件来源到 $logFile" -ForegroundColor Yellow

# Maintain previous state to detect transitions
# 执行本地诊断或资源清理，不修改系统配置。
$prev = @{}
# 执行本地诊断或资源清理，不修改系统配置。
foreach ($v in $vkRange) { $prev[$v] = $false }

# 执行本地诊断或资源清理，不修改系统配置。
$watch=[Diagnostics.Stopwatch]::StartNew()
# 执行本地诊断或资源清理，不修改系统配置。
try {
# 执行本地诊断或资源清理，不修改系统配置。
    while ($watch.Elapsed.TotalSeconds -lt $DurationSeconds) {
# 执行本地诊断或资源清理，不修改系统配置。
        $ts = Get-Date -Format "o"
# 执行本地诊断或资源清理，不修改系统配置。
        foreach ($vk in $vkRange) {
# 执行本地诊断或资源清理，不修改系统配置。
            $state = ([K]::GetAsyncKeyState($vk) -band 0x8000) -ne 0
# 执行本地诊断或资源清理，不修改系统配置。
            if ($state -and -not $prev[$vk]) {
                # Key down transition
# 执行本地诊断或资源清理，不修改系统配置。
                $name = try { [System.Windows.Forms.Keys]$vk } catch { $vk }
# 执行本地诊断或资源清理，不修改系统配置。
                "$ts,$vk,$name,Down" | Out-File -FilePath $logFile -Append -Encoding UTF8
# 执行本地诊断或资源清理，不修改系统配置。
            } elseif (-not $state -and $prev[$vk]) {
                # Key up transition
# 执行本地诊断或资源清理，不修改系统配置。
                $name = try { [System.Windows.Forms.Keys]$vk } catch { $vk }
# 执行本地诊断或资源清理，不修改系统配置。
                "$ts,$vk,$name,Up" | Out-File -FilePath $logFile -Append -Encoding UTF8
# 执行本地诊断或资源清理，不修改系统配置。
            }
# 执行本地诊断或资源清理，不修改系统配置。
            $prev[$vk] = $state
# 执行本地诊断或资源清理，不修改系统配置。
        }
# 执行本地诊断或资源清理，不修改系统配置。
        Start-Sleep -Milliseconds 50
# 执行本地诊断或资源清理，不修改系统配置。
    }
# 执行本地诊断或资源清理，不修改系统配置。
} catch [System.Exception] {
# 执行本地诊断或资源清理，不修改系统配置。
    throw
# 执行本地诊断或资源清理，不修改系统配置。
}
