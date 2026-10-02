$ErrorActionPreference='Continue'
$dest=$PSScriptRoot
$state=[ordered]@{
 Time=(Get-Date -Format o)
 OS=Get-CimInstance Win32_OperatingSystem | Select-Object Caption,BuildNumber,LastBootUpTime,FreePhysicalMemory
 PageFileAuto=(Get-CimInstance Win32_ComputerSystem).AutomaticManagedPagefile
 PageFile=Get-CimInstance Win32_PageFileUsage | Select-Object Name,AllocatedBaseSize,CurrentUsage,PeakUsage
 FreeGiB=(Get-PSDrive C).Free/1GB
 Problems=@(Get-PnpDevice -PresentOnly | Where-Object Status -ne 'OK' | Select-Object FriendlyName,Problem,InstanceId)
 Network=Get-NetAdapter -Physical | Select-Object Name,InterfaceDescription,Status,LinkSpeed,DriverVersion
 SecurityServices=Get-Service | Where-Object {$_.Name -match 'WinDefend|AVP|klnagent|edgeupdate'} | Select-Object Name,Status,StartType
 Firewalls=Get-NetFirewallProfile | Select-Object Name,Enabled
 PowerPlan=(& powercfg /getactivescheme | Out-String).Trim()
 LongPaths=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem').LongPathsEnabled
 RebootCBS=Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
 RebootWU=Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
}
$state | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $dest 'system-after.json') -Encoding UTF8
Get-CimInstance Win32_PnPSignedDriver | Select-Object DeviceID,DeviceName,DriverVersion,InfName | Export-Csv (Join-Path $dest 'drivers-after.csv') -NoTypeInformation -Encoding UTF8
$state | ConvertTo-Json -Depth 6
