$ErrorActionPreference = 'Stop'
$out = $PSScriptRoot
$status = @()
function Probe($name, [scriptblock]$body) {
    try {
        $data = & $body
        ConvertTo-Json -InputObject $data -Depth 10 | Set-Content -LiteralPath (Join-Path $out ($name + '.json')) -Encoding utf8
        $script:status += [pscustomobject]@{Probe=$name;Success=$true;Error=$null}
    } catch {
        $script:status += [pscustomobject]@{Probe=$name;Success=$false;Error=$_.Exception.Message}
    }
}
Probe 'system' { Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,TotalPhysicalMemory,HypervisorPresent }
Probe 'os' { Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,OSArchitecture,InstallDate,LastBootUpTime,FreePhysicalMemory,TotalVisibleMemorySize }
Probe 'version' { Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' | Select-Object ProductName,DisplayVersion,CurrentBuild,UBR,EditionID,InstallationType }
Probe 'cpu' { Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed,VirtualizationFirmwareEnabled }
Probe 'memory' { Get-CimInstance Win32_PhysicalMemory | Select-Object Manufacturer,Capacity,Speed,ConfiguredClockSpeed,PartNumber,DeviceLocator }
Probe 'board' { Get-CimInstance Win32_BaseBoard | Select-Object Manufacturer,Product,Version }
Probe 'bios' { Get-CimInstance Win32_BIOS | Select-Object Manufacturer,SMBIOSBIOSVersion,ReleaseDate }
Probe 'gpu' { Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,DriverDate,VideoModeDescription,Status }
Probe 'disks' { Get-CimInstance Win32_DiskDrive | Select-Object Model,Size,InterfaceType,Status }
Probe 'volumes' { Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object DeviceID,FileSystem,Size,FreeSpace }
Probe 'disk-health' { Get-PhysicalDisk | Select-Object FriendlyName,MediaType,Size,HealthStatus,OperationalStatus }
Probe 'devices' { Get-PnpDevice -PresentOnly | Select-Object Class,FriendlyName,Status,Problem,InstanceId }
Probe 'drivers' { Get-CimInstance Win32_PnPSignedDriver | Select-Object DeviceName,DeviceClass,DriverVersion,DriverDate,DriverProviderName,InfName,IsSigned }
Probe 'network' { Get-NetAdapter | Select-Object Name,InterfaceDescription,Status,LinkSpeed,DriverInformation }
Probe 'network-profiles' { Get-NetConnectionProfile | Select-Object Name,InterfaceAlias,NetworkCategory,IPv4Connectivity,IPv6Connectivity }
Probe 'updates' { Get-HotFix | Select-Object HotFixID,Description,InstalledOn }
Probe 'licensing' { Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" | Select-Object Name,Description,LicenseStatus }
Probe 'antivirus' { Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct | Select-Object displayName,productState }
Probe 'defender' { Get-MpComputerStatus | Select-Object AMServiceEnabled,AntivirusEnabled,RealTimeProtectionEnabled,AntivirusSignatureLastUpdated }
Probe 'firewall' { Get-NetFirewallProfile | Select-Object Name,Enabled,DefaultInboundAction,DefaultOutboundAction }
Probe 'tpm' { $t = Get-Tpm -ErrorAction Stop; if ($null -eq $t.TpmPresent) { throw 'TPM state unavailable' }; $t | Select-Object TpmPresent,TpmReady,TpmEnabled,TpmActivated }
Probe 'secure-boot' { Confirm-SecureBootUEFI }
Probe 'bitlocker' { $v = Get-BitLockerVolume -ErrorAction Stop; if (-not $v) { throw 'No verified BitLocker volume information returned' }; $v | Select-Object MountPoint,VolumeStatus,ProtectionStatus,EncryptionMethod }
Probe 'services' { Get-Service | Select-Object Name,DisplayName,Status,StartType }
Probe 'software' { Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object DisplayName | Select-Object DisplayName,DisplayVersion,Publisher,InstallDate }
Probe 'recent-system-errors' { Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2;StartTime=(Get-Date).AddDays(-3)} -MaxEvents 80 | Select-Object TimeCreated,Id,ProviderName,Message }
Probe 'reboot' { [pscustomobject]@{CBS=Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending';WindowsUpdate=Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'} }
$status | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $out 'probe-status.json') -Encoding utf8
[pscustomobject]@{CollectedUtc=[DateTime]::UtcNow.ToString('o');UserFacingDate='2026-10-10';Mode='ReadOnly';IsAdministrator=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)} | ConvertTo-Json | Set-Content (Join-Path $out 'metadata.json') -Encoding utf8
$status | Format-Table -AutoSize
