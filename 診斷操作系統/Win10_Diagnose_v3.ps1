#Requires -Version 5.1
<#
.SYNOPSIS
Windows 10/11 與資料分析工具鏈的唯讀、離線盤點。
.DESCRIPTION
只寫入報告資料夾。不安裝/更新套件、不變更系統、不讀取金鑰、完整環境變數、Git 憑證或程式命令列。
各 CIM/PowerShell 探測在獨立 Windows PowerShell 5.1 子行程內執行，設有逾時。
缺少權限或工具時明確記錄 Unknown/Unavailable，不把失敗當成沒有問題。
Python/R 套件來自已發現直譯器；不遞迴搜尋整顆磁碟或執行使用者啟動設定。
隱私：報告仍含已安裝軟體與本機路徑，分享前請檢視。
.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Win10_Diagnose_v3.ps1 -OutputDirectory .\reports
#>
[CmdletBinding()]
param(
    [Alias('OutDir')][string]$OutputDirectory = (Join-Path $PSScriptRoot ('reports\diagnostics-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))),
    [ValidateRange(10,180)][int]$ProbeTimeoutSeconds = 35,
    [ValidateRange(1,24)][int]$MaxInterpreters = 8,
    [string[]]$AdditionalPythonPaths = @(),
    [string[]]$AdditionalRPaths = @(),
    [switch]$SkipPackages,
    [switch]$SkipEvents
)
$ErrorActionPreference = 'Stop'
$script:PowerShellExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $script:PowerShellExe)) { throw '此腳本需要 Windows PowerShell 5.1。' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$script:Status = New-Object System.Collections.Generic.List[object]
$script:Findings = New-Object System.Collections.Generic.List[object]
$script:Data = [ordered]@{}
$script:Utf8 = New-Object Text.UTF8Encoding($true)

function Write-JsonFile { param($Value,[string]$Name)
    [IO.File]::WriteAllText((Join-Path $OutputDirectory $Name), (ConvertTo-Json -InputObject $Value -Depth 16), $script:Utf8)
}
function Save-Data { param([string]$Name,$Value)
    $rows = @($Value | Where-Object { $null -ne $_ })
    $script:Data[$Name] = $rows
    Write-JsonFile -Value $rows -Name ($Name + '.json')
    if ($rows.Count -gt 0) { $rows | Export-Csv -LiteralPath (Join-Path $OutputDirectory ($Name + '.csv')) -NoTypeInformation -Encoding UTF8 }
}
function Add-Status { param([string]$Probe,[string]$State,[string]$Detail,[double]$Seconds=0)
    $script:Status.Add([pscustomobject]@{Probe=$Probe;Status=$State;Detail=$Detail;Seconds=[math]::Round($Seconds,2)})
}
function Add-Finding { param([string]$Level,[string]$Area,[string]$Message)
    $script:Findings.Add([pscustomobject]@{Level=$Level;Area=$Area;Message=$Message})
}
function ConvertTo-NativeArgument { param([AllowEmptyString()][string]$Value)
    # Windows CommandLineToArgvW quoting; never interpolate arguments into a shell.
    if ($Value -notmatch '[\s"]' -and $Value.Length -gt 0) { return $Value }
    return '"' + ([regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1')) + '"'
}
function Invoke-BoundedProcess {
    param([string]$FilePath,[string[]]$ArgumentList=@(),[int]$TimeoutSeconds=$ProbeTimeoutSeconds)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $process = New-Object Diagnostics.Process
    try {
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = $FilePath
        $info.Arguments = (($ArgumentList | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
        $info.UseShellExecute = $false; $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
        $info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
        $info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
        $info.WorkingDirectory = $OutputDirectory
        $info.EnvironmentVariables['PYTHONDONTWRITEBYTECODE'] = '1'
        $info.EnvironmentVariables['PYTHONUTF8'] = '1'
        $info.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
        $info.EnvironmentVariables['PIP_DISABLE_PIP_VERSION_CHECK'] = '1'
        $process.StartInfo = $info
        $null = $process.Start()
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            # Only the diagnostic child PID and descendants are terminated.
            $killer = New-Object Diagnostics.Process
            try {
                $killer.StartInfo = New-Object Diagnostics.ProcessStartInfo
                $killer.StartInfo.FileName = Join-Path $env:WINDIR 'System32\taskkill.exe'
                $killer.StartInfo.Arguments = '/PID ' + $process.Id + ' /T /F'
                $killer.StartInfo.UseShellExecute = $false; $killer.StartInfo.CreateNoWindow = $true
                $killer.StartInfo.RedirectStandardOutput = $true; $killer.StartInfo.RedirectStandardError = $true
                $null = $killer.Start(); $null = $killer.WaitForExit(5000)
                if (-not $process.HasExited) { $process.Kill() }
            } finally { $killer.Dispose() }
            return [pscustomobject]@{State='Timeout';ExitCode=$null;Stdout='';Stderr='已超過探測時限；不代表資料不存在。';Seconds=$watch.Elapsed.TotalSeconds}
        }
        if (-not $outTask.Wait(5000) -or -not $errTask.Wait(5000)) { throw '子行程輸出未能在時限內關閉。' }
        return [pscustomobject]@{State='Completed';ExitCode=$process.ExitCode;Stdout=$outTask.Result;Stderr=$errTask.Result;Seconds=$watch.Elapsed.TotalSeconds}
    } catch {
        return [pscustomobject]@{State='Unavailable';ExitCode=$null;Stdout='';Stderr=$_.Exception.Message;Seconds=$watch.Elapsed.TotalSeconds}
    } finally { $process.Dispose() }
}
function Invoke-Probe { param([string]$Name,[scriptblock]$Body,[int]$TimeoutSeconds=$ProbeTimeoutSeconds)
    Write-Host ('盤點：' + $Name)
    $code = @'
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
try {
  $items = @(& {
'@ + $Body.ToString() + @'

  })
  [pscustomobject]@{Success=$true;Data=$items;Error=$null} | ConvertTo-Json -Depth 14 -Compress
} catch {
  [pscustomobject]@{Success=$false;Data=@();Error=$_.Exception.Message} | ConvertTo-Json -Depth 5 -Compress
}
'@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    $result = Invoke-BoundedProcess $script:PowerShellExe @('-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',$encoded) $TimeoutSeconds
    if ($result.State -ne 'Completed') { Add-Status $Name $result.State $result.Stderr $result.Seconds; Save-Data $Name @(); return }
    try {
        $envelope = $result.Stdout.Trim() | ConvertFrom-Json
        if (-not $envelope.Success) { throw [string]$envelope.Error }
        Add-Status $Name 'OK' ('已讀取 ' + @($envelope.Data).Count + ' 筆；空清單只代表此探測沒有回傳項目。') $result.Seconds
        Save-Data $Name @($envelope.Data)
    } catch { Add-Status $Name 'Unavailable' $_.Exception.Message $result.Seconds; Save-Data $Name @() }
}
function Invoke-Tool { param([string]$Name,[string]$Path,[string[]]$Arguments)
    if (-not $Path) { Add-Status $Name 'Unavailable' '在 PATH 與限定的安裝位置未發現。'; return $null }
    if ([IO.Path]::GetExtension($Path) -in @('.cmd','.bat')) {
        $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json @{Path=$Path;Args=$Arguments} -Compress)))
        $cmd = '[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false); $p=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+$payload+''')) | ConvertFrom-Json; $a=@($p.Args); & $p.Path @a; exit $LASTEXITCODE'
        $result = Invoke-BoundedProcess $script:PowerShellExe @('-NoProfile','-NonInteractive','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd)))
    } else { $result = Invoke-BoundedProcess $Path $Arguments }
    $state = $result.State
    if ($state -eq 'Completed') { if ($result.ExitCode -eq 0) { $state='OK' } else { $state='Failed' } }
    $detail = 'ExitCode=' + $result.ExitCode
    if ($state -ne 'OK') { $detail += '; ' + ($result.Stderr -replace '[\r\n]+',' ') }
    if ($detail.Length -gt 700) { $detail = $detail.Substring(0,700) }
    Add-Status $Name $state $detail $result.Seconds
    return $result
}
function Find-Executables { param([string[]]$Names,[string[]]$Patterns=@())
    $candidates = @()
    foreach ($name in $Names) { $candidates += @(Get-Command $name -CommandType Application -All -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source) }
    foreach ($pattern in $Patterns) { if ($pattern) { $candidates += @(Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName) } }
    # AppExecutionAlias Python stubs can open the Store. Versioned real Store packages are found through registration instead.
    @($candidates | Where-Object { $_ -and $_ -notmatch '\\Microsoft\\WindowsApps\\(python[0-9.]*|py)\.exe$' } | Select-Object -Unique)
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Save-Data '00_metadata' ([pscustomobject]@{SchemaVersion='3.0';CollectedAt=(Get-Date).ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();IsAdministrator=$isAdmin;Mode='OfflineReadOnly';ProbeTimeoutSeconds=$ProbeTimeoutSeconds;MaxInterpreters=$MaxInterpreters;Scope='Machine software + current user; no other user hives, recursive disk scan, network update check, secrets or command arguments'})

Invoke-Probe '01_system' {
    $os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 15
    $cs=Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 15
    $cv=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [pscustomobject]@{Caption=$os.Caption;EditionID=$cv.EditionID;DisplayVersion=$cv.DisplayVersion;Build=($cv.CurrentBuild.ToString()+'.'+$cv.UBR);BuildNumber=$os.BuildNumber;Architecture=$os.OSArchitecture;ProductType=$os.ProductType;RAM_GB=[math]::Round($cs.TotalPhysicalMemory/1GB,2);FreeRAM_GB=[math]::Round($os.FreePhysicalMemory/1MB,2);UptimeDays=[math]::Round(((Get-Date)-$os.LastBootUpTime).TotalDays,2);LastBoot=$os.LastBootUpTime.ToString('o');AutomaticManagedPagefile=$cs.AutomaticManagedPagefile;Manufacturer=$cs.Manufacturer;Model=$cs.Model;HypervisorPresent=$cs.HypervisorPresent;PartOfDomain=$cs.PartOfDomain}
}
Invoke-Probe '02_cpu' { Get-CimInstance Win32_Processor -OperationTimeoutSec 15 | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed,AddressWidth,VirtualizationFirmwareEnabled,SecondLevelAddressTranslationExtensions,VMMonitorModeExtensions }
Invoke-Probe '03_memory' { Get-CimInstance Win32_PhysicalMemory -OperationTimeoutSec 15 | Select-Object Manufacturer,PartNumber,@{n='Capacity_GB';e={[math]::Round($_.Capacity/1GB,2)}},Speed,ConfiguredClockSpeed }
Invoke-Probe '04_gpu' { Get-CimInstance Win32_VideoController -OperationTimeoutSec 15 | Select-Object Name,DriverVersion,DriverDate,VideoProcessor,Status,AdapterRAM }
Invoke-Probe '05_bios' { Get-CimInstance Win32_BIOS -OperationTimeoutSec 15 | Select-Object Manufacturer,SMBIOSBIOSVersion,ReleaseDate }
Invoke-Probe '06_volumes' { Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -OperationTimeoutSec 15 | Select-Object DeviceID,FileSystem,@{n='Size_GB';e={[math]::Round($_.Size/1GB,2)}},@{n='Free_GB';e={[math]::Round($_.FreeSpace/1GB,2)}},@{n='Free_Percent';e={if ($_.Size) {[math]::Round(100*$_.FreeSpace/$_.Size,1)}}} }
Invoke-Probe '07_disks' { Get-PhysicalDisk | Select-Object FriendlyName,@{n='MediaType';e={$_.MediaType.ToString()}},@{n='BusType';e={$_.BusType.ToString()}},@{n='HealthStatus';e={$_.HealthStatus.ToString()}},@{n='OperationalStatus';e={$_.OperationalStatus -join ';'}},@{n='Size_GB';e={[math]::Round($_.Size/1GB,2)}} }
Invoke-Probe '08_pagefile' { Get-CimInstance Win32_PageFileUsage -OperationTimeoutSec 15 | Select-Object Name,AllocatedBaseSize,CurrentUsage,PeakUsage,TempPageFile }
Invoke-Probe '09_updates' { Get-CimInstance Win32_QuickFixEngineering -OperationTimeoutSec 15 | Select-Object HotFixID,Description,InstalledOn }
Invoke-Probe '10_reboot' {
    $rename=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    [pscustomobject]@{CBS=Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending';WindowsUpdate=Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired';PendingFileRename=[bool]$rename.PendingFileRenameOperations}
}
Invoke-Probe '11_software' {
    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if (Test-Path $root) {
            Get-ChildItem $root | ForEach-Object { $p=Get-ItemProperty $_.PSPath; if ($p.DisplayName) { [pscustomobject]@{Name=$p.DisplayName;Version=$p.DisplayVersion;Publisher=$p.Publisher;InstallDate=$p.InstallDate;InstallLocation=$p.InstallLocation;SystemComponent=[bool]$p.SystemComponent;Scope=if ($root -like 'HKCU*') {'CurrentUser'} else {'Machine'};RegistryView=if ($root -like '*WOW6432Node*') {'32bit'} else {'Native'}} } }
    }
}
Invoke-Probe '12_appx_current_user' { Get-AppxPackage | Select-Object Name,@{n='Version';e={$_.Version.ToString()}},@{n='Architecture';e={$_.Architecture.ToString()}},IsFramework,SignatureKind,Status }
Invoke-Probe '13_startup' { Get-CimInstance Win32_StartupCommand -OperationTimeoutSec 15 | Select-Object Name,Location }
Invoke-Probe '14_services' { Get-CimInstance Win32_Service -OperationTimeoutSec 15 | Select-Object Name,DisplayName,State,StartMode,DelayedAutoStart }
Invoke-Probe '15_scheduled_tasks' { Get-ScheduledTask | Select-Object TaskName,TaskPath,@{n='State';e={$_.State.ToString()}} }
Invoke-Probe '16_defender' { Get-MpComputerStatus | Select-Object AMRunningMode,AMServiceEnabled,AntivirusEnabled,RealTimeProtectionEnabled,BehaviorMonitorEnabled,IsTamperProtected,AntivirusSignatureVersion,AntivirusSignatureLastUpdated,AntivirusSignatureAge,QuickScanEndTime }
Invoke-Probe '17_antivirus' { Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntivirusProduct -OperationTimeoutSec 15 | Select-Object displayName,productState }
Invoke-Probe '18_firewall' { Get-NetFirewallProfile | Select-Object Name,@{n='Enabled';e={$_.Enabled.ToString()}},DefaultInboundAction,DefaultOutboundAction }
Invoke-Probe '19_secure_boot' { [pscustomobject]@{Enabled=Confirm-SecureBootUEFI} }
Invoke-Probe '20_tpm' { Get-Tpm | Select-Object TpmPresent,TpmReady,TpmEnabled,TpmActivated,ManufacturerVersion,AutoProvisioning }
Invoke-Probe '21_tpm_specification' { Get-CimInstance -Namespace 'root\CIMV2\Security\MicrosoftTpm' -ClassName Win32_Tpm -OperationTimeoutSec 15 | Select-Object SpecVersion,ManufacturerVersion,IsEnabled_InitialValue,IsActivated_InitialValue }
Invoke-Probe '22_bitlocker' { Get-BitLockerVolume | Select-Object MountPoint,@{n='VolumeStatus';e={$_.VolumeStatus.ToString()}},@{n='ProtectionStatus';e={$_.ProtectionStatus.ToString()}},EncryptionPercentage,EncryptionMethod }
Invoke-Probe '23_security_settings' {
    $uac=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $rdp=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    $nla=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
    [pscustomobject]@{UACEnabled=$uac.EnableLUA;ConsentPromptBehaviorAdmin=$uac.ConsentPromptBehaviorAdmin;RDPDenied=$rdp.fDenyTSConnections;RDPNetworkLevelAuthentication=$nla.UserAuthentication}
}
Invoke-Probe '24_device_guard' { Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -OperationTimeoutSec 15 | Select-Object VirtualizationBasedSecurityStatus,SecurityServicesConfigured,SecurityServicesRunning,AvailableSecurityProperties }
Invoke-Probe '25_optional_features' { Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -match 'Subsystem-Linux|VirtualMachinePlatform|Hyper-V|Containers|Sandbox|SMB1Protocol|NetFx3' } | Select-Object FeatureName,@{n='State';e={$_.State.ToString()}} }
Invoke-Probe '26_smb' { Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol,EnableSMB2Protocol,RequireSecuritySignature,EnableSecuritySignature }
Invoke-Probe '27_settings' {
    $fs=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    $cp=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage'
    [pscustomobject]@{LongPathsEnabled=$fs.LongPathsEnabled;ANSI_CodePage=$cp.ACP;OEM_CodePage=$cp.OEMCP;Culture=(Get-Culture).Name;SystemLocale=(Get-WinSystemLocale).Name;TimeZone=(Get-TimeZone).Id}
}
Invoke-Probe '28_execution_policy' { Get-ExecutionPolicy -List | Select-Object @{n='Scope';e={$_.Scope.ToString()}},@{n='ExecutionPolicy';e={$_.ExecutionPolicy.ToString()}} }
Invoke-Probe '29_odbc' { Get-OdbcDriver | Select-Object Name,Platform }
Invoke-Probe '30_windows_licensing' {
    # No product key/partial product key or activation identifier is exported.
    Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f'" -OperationTimeoutSec 15 | Where-Object { $_.LicenseStatus -ne 0 -or $_.Name -match 'ESU|Extended Security' } | Select-Object Name,Description,LicenseStatus,GracePeriodRemaining
}
Invoke-Probe '31_editor_extensions' {
    foreach ($root in @((Join-Path $env:USERPROFILE '.vscode\extensions'),(Join-Path $env:USERPROFILE '.vscode-insiders\extensions'),(Join-Path $env:USERPROFILE '.positron\extensions'))) {
        if (Test-Path -LiteralPath $root) { foreach ($dir in (Get-ChildItem -LiteralPath $root -Directory | Select-Object -First 400)) {
            $manifest=Join-Path $dir.FullName 'package.json'
            if (Test-Path -LiteralPath $manifest) { $m=Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json; [pscustomobject]@{EditorRoot=$root;Id=($m.publisher+'.'+$m.name);Version=$m.version} }
        } }
    }
}
if ($SkipEvents) { Add-Status '32_events' 'Skipped' '-SkipEvents' } else {
    Invoke-Probe '32_events' {
        try { $events=@(Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2;StartTime=(Get-Date).AddDays(-14)} -MaxEvents 300) }
        catch { if ($_.FullyQualifiedErrorId -match 'NoMatchingEventsFound') { $events=@() } else { throw } }
        $events | Group-Object ProviderName,Id | Select-Object Count,Name
    }
}

$power=Invoke-Tool '33_power_plan' (Join-Path $env:WINDIR 'System32\powercfg.exe') @('/getactivescheme')
Save-Data '33_power_plan' $(if ($power -and $power.ExitCode -eq 0) { [pscustomobject]@{ActiveScheme=$power.Stdout.Trim()} })
$runtimeDefinitions = @(
    @{Name='Python';Commands=@('python.exe','python3.exe');Patterns=@("$env:LOCALAPPDATA\Programs\Python\Python*\python.exe","$env:ProgramFiles\Python*\python.exe","$env:USERPROFILE\miniconda3\python.exe","$env:USERPROFILE\anaconda3\python.exe","$env:USERPROFILE\miniforge3\python.exe","$env:LOCALAPPDATA\uv\python\*\python.exe","$env:APPDATA\uv\python\*\python.exe")},
    @{Name='Rscript';Commands=@('Rscript.exe');Patterns=@("$env:ProgramFiles\R\R-*\bin\Rscript.exe","$env:LOCALAPPDATA\Programs\R\R-*\bin\Rscript.exe","$env:ProgramFiles\R\R-*\bin\x64\Rscript.exe")},
    @{Name='uv';Commands=@('uv.exe');Patterns=@("$env:USERPROFILE\.local\bin\uv.exe","$env:LOCALAPPDATA\Microsoft\WinGet\Links\uv.exe")},
    @{Name='Git';Commands=@('git.exe');Patterns=@("$env:ProgramFiles\Git\cmd\git.exe","$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")},
    @{Name='Quarto';Commands=@('quarto.exe','quarto.cmd');Patterns=@("$env:ProgramFiles\Quarto\bin\quarto.exe","$env:ProgramFiles\Quarto\bin\quarto.cmd","$env:LOCALAPPDATA\Programs\Quarto\bin\quarto.cmd")},
    @{Name='Pandoc';Commands=@('pandoc.exe');Patterns=@("$env:LOCALAPPDATA\Pandoc\pandoc.exe","$env:ProgramFiles\Pandoc\pandoc.exe")},
    @{Name='PowerShell7';Commands=@('pwsh.exe');Patterns=@("$env:ProgramFiles\PowerShell\7\pwsh.exe")},
    @{Name='Node';Commands=@('node.exe');Patterns=@("$env:ProgramFiles\nodejs\node.exe")},
    @{Name='Java';Commands=@('java.exe');Patterns=@("$env:ProgramFiles\Eclipse Adoptium\*\bin\java.exe","$env:ProgramFiles\Java\*\bin\java.exe")},
    @{Name='DuckDB';Commands=@('duckdb.exe');Patterns=@("$env:USERPROFILE\.duckdb\cli\latest\duckdb.exe")},
    @{Name='PostgreSQL';Commands=@('psql.exe');Patterns=@("$env:ProgramFiles\PostgreSQL\*\bin\psql.exe")},
    @{Name='Docker';Commands=@('docker.exe');Patterns=@("$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe")},
    @{Name='Julia';Commands=@('julia.exe');Patterns=@("$env:LOCALAPPDATA\Programs\Julia*\bin\julia.exe")},
    @{Name='Winget';Commands=@('winget.exe');Patterns=@()},
    @{Name='RtoolsCompiler';Commands=@('gcc.exe');Patterns=@('C:\rtools*\x86_64-w64-mingw32.static.posix\bin\gcc.exe','C:\rtools*\mingw64\bin\gcc.exe')}
)
Invoke-Probe '34_registered_interpreters' {
    foreach ($base in @('HKCU:\SOFTWARE\Python\PythonCore','HKLM:\SOFTWARE\Python\PythonCore','HKLM:\SOFTWARE\WOW6432Node\Python\PythonCore')) {
        if (Test-Path $base) { foreach ($version in (Get-ChildItem $base)) { $key=Join-Path $version.PSPath 'InstallPath'; if (Test-Path $key) { $p=Get-ItemProperty $key; $path=$p.ExecutablePath; if (-not $path) { $path=Join-Path $p.'(default)' 'python.exe' }; [pscustomobject]@{Runtime='Python';Path=$path} } } }
    }
    foreach ($base in @('HKCU:\SOFTWARE\R-core\R','HKLM:\SOFTWARE\R-core\R','HKLM:\SOFTWARE\WOW6432Node\R-core\R')) {
        if (Test-Path $base) { foreach ($key in @((Get-Item $base)) + @(Get-ChildItem $base)) { $p=Get-ItemProperty $key.PSPath; if ($p.InstallPath) { [pscustomobject]@{Runtime='Rscript';Path=(Join-Path $p.InstallPath 'bin\Rscript.exe')} } }
    }
}
$runtimeRows=New-Object System.Collections.Generic.List[object]
$pythonPaths=@(); $rPaths=@()
foreach ($definition in $runtimeDefinitions) {
    $patterns=@($definition.Patterns)
    if ($definition.Name -eq 'Python') { $patterns += $AdditionalPythonPaths; $patterns += @($script:Data['34_registered_interpreters'] | Where-Object {$_.Runtime -eq 'Python'} | Select-Object -ExpandProperty Path) }
    if ($definition.Name -eq 'Rscript') { $patterns += $AdditionalRPaths; $patterns += @($script:Data['34_registered_interpreters'] | Where-Object {$_.Runtime -eq 'Rscript'} | Select-Object -ExpandProperty Path) }
    $paths=@(Find-Executables $definition.Commands $patterns)
    if ($paths.Count -gt $MaxInterpreters) { Add-Status ('Discovery/'+$definition.Name) 'Partial' ('發現 '+$paths.Count+' 個；限制只探測前 '+$MaxInterpreters+' 個。') }
    $paths=@($paths | Select-Object -First $MaxInterpreters)
    if ($paths.Count -eq 0) { Add-Status ('Runtime/'+$definition.Name) 'Unavailable' '限定的安裝位置未發現；可能是可攜版或另一使用者安裝。'; $runtimeRows.Add([pscustomobject]@{Tool=$definition.Name;Found=$false;Path=$null;Version=$null;Status='Unavailable'}); continue }
    foreach ($path in $paths) {
        $arguments=@('--version'); if ($definition.Name -eq 'Java') { $arguments=@('-version') }
        if ($definition.Name -eq 'Python') { $arguments=@('-I','-S','-B','--version'); $pythonPaths += $path }
        if ($definition.Name -eq 'Rscript') { $rPaths += $path }
        $result=Invoke-Tool ('Runtime/'+$definition.Name) $path $arguments
        $version=''; if ($result) { $version=(($result.Stdout+' '+$result.Stderr).Trim() -split '\r?\n')[0] }
        $runtimeRows.Add([pscustomobject]@{Tool=$definition.Name;Found=$true;Path=$path;Version=$version;Status=if ($result.ExitCode -eq 0) {'OK'} else {$result.State}})
    }
}
Save-Data '35_runtimes' $runtimeRows.ToArray()

# Metadata-only Python inventory: -I -S -B avoids user site startup files, .pth execution and bytecode writes.
$pythonCode=@'
import sys, sysconfig, os, json, site
from importlib import metadata
exe_dir=os.path.dirname(sys.executable)
venv_root=os.path.dirname(exe_dir) if os.path.basename(exe_dir).lower()=="scripts" else exe_dir
is_venv=os.path.isfile(os.path.join(venv_root,"pyvenv.cfg"))
paths=[os.path.join(venv_root,"Lib","site-packages")]
include_system=not is_venv
if is_venv:
    with open(os.path.join(venv_root,"pyvenv.cfg"),encoding="utf-8") as f:
        include_system="include-system-site-packages = true" in f.read().lower()
if include_system:
    paths.extend([sysconfig.get_paths().get("purelib",""),sysconfig.get_paths().get("platlib","")])
    user=site.getusersitepackages()
    paths.extend(user if isinstance(user,list) else [user])
paths=list(dict.fromkeys(p for p in paths if p and os.path.isdir(p)))
rows=[]
for path in paths:
    for dist in metadata.distributions(path=[path]):
        rows.append({"Name":dist.metadata.get("Name","?"),"Version":dist.version,"Library":path})
print(json.dumps({"Executable":sys.executable,"Version":sys.version.split()[0],"Libraries":paths,"IsVirtualEnvironment":is_venv,"Packages":sorted(rows,key=lambda p:p["Name"].lower()),"Scope":"Static distribution metadata; .pth/editable paths and runtime import behavior not executed"},ensure_ascii=True))
'@
$pythonFile=Join-Path $OutputDirectory '_probe_python.py'
[IO.File]::WriteAllText($pythonFile,$pythonCode,(New-Object Text.UTF8Encoding($false)))
$pythonEnvs=New-Object System.Collections.Generic.List[object]
$pythonPackages=New-Object System.Collections.Generic.List[object]
if ($SkipPackages) { Add-Status 'PythonPackages' 'Skipped' '-SkipPackages' } elseif ($pythonPaths.Count -eq 0) { Add-Status 'PythonPackages' 'Unavailable' '未找到可用 Python。' } else {
    foreach ($path in $pythonPaths) {
        $result=Invoke-Tool ('PythonPackages/'+$path) $path @('-I','-S','-B',$pythonFile)
        if ($result.ExitCode -eq 0) {
            try {
                $parsed=$result.Stdout | ConvertFrom-Json
                $pythonEnvs.Add([pscustomobject]@{Executable=$parsed.Executable;Version=$parsed.Version;Libraries=$parsed.Libraries -join ';';IsVirtualEnvironment=$parsed.IsVirtualEnvironment;PackageCount=@($parsed.Packages).Count;Scope=$parsed.Scope})
                foreach ($pkg in $parsed.Packages) { $pythonPackages.Add([pscustomobject]@{Interpreter=$path;Name=$pkg.Name;Version=$pkg.Version;Library=$pkg.Library}) }
            } catch { Add-Status ('PythonPackagesParse/'+$path) 'Failed' $_.Exception.Message }
        }
    }
}
Save-Data '36_python_environments' $pythonEnvs.ToArray()
Save-Data '37_python_packages' $pythonPackages.ToArray()
$rCode=@'
args <- commandArgs(trailingOnly=TRUE)
ip <- installed.packages(noCache=TRUE)
write.csv(data.frame(Package=ip[,"Package"], Version=ip[,"Version"], Built=ip[,"Built"], Library=ip[,"LibPath"]),args[1],row.names=FALSE,fileEncoding="UTF-8")
write.csv(data.frame(Version=R.version.string, RHome=R.home(), Library=.libPaths(), Writable=file.access(.libPaths(),2)==0),args[2],row.names=FALSE,fileEncoding="UTF-8")
'@
$rFile=Join-Path $OutputDirectory '_probe_r.R'
[IO.File]::WriteAllText($rFile,$rCode,(New-Object Text.UTF8Encoding($false)))
$rEnvs=New-Object System.Collections.Generic.List[object]; $rPackages=New-Object System.Collections.Generic.List[object]
if ($SkipPackages) { Add-Status 'RPackages' 'Skipped' '-SkipPackages' } elseif ($rPaths.Count -eq 0) { Add-Status 'RPackages' 'Unavailable' '未找到 Rscript。' } else {
    $index=0
    foreach ($path in $rPaths) {
        $index++; $pkgFile=Join-Path $OutputDirectory ('_r_packages_'+$index+'.csv'); $envFile=Join-Path $OutputDirectory ('_r_environment_'+$index+'.csv')
        $result=Invoke-Tool ('RPackages/'+$path) $path @('--vanilla',$rFile,$pkgFile,$envFile)
        if ($result.ExitCode -eq 0 -and (Test-Path -LiteralPath $pkgFile) -and (Test-Path -LiteralPath $envFile)) {
            foreach ($row in (Import-Csv -LiteralPath $envFile -Encoding UTF8)) { $rEnvs.Add([pscustomobject]@{Interpreter=$path;Version=$row.Version;Library=$row.Library;Writable=$row.Writable;Scope='--vanilla; no project .Rprofile/.Renviron executed'}) }
            foreach ($row in (Import-Csv -LiteralPath $pkgFile -Encoding UTF8)) { $rPackages.Add([pscustomobject]@{Interpreter=$path;Name=$row.Package;Version=$row.Version;Built=$row.Built;Library=$row.Library}) }
        }
    }
}
Save-Data '38_r_environments' $rEnvs.ToArray()
Save-Data '39_r_packages' $rPackages.ToArray()

$system=@($script:Data['01_system'] | Select-Object -First 1)
if ($system.Count) {
    if ($system[0].Caption -match 'Windows 10') { Add-Finding '注意' '作業系統' 'Windows 10 一般通道已於 2025-10-14 結束支援；LTSC/IoT/ESU 有不同期限。請依實際 Edition、ESU 授權與 Microsoft 公告確認。啟用狀態不等同最新修補或 ESU 已可用。' }
    if (-not $system[0].AutomaticManagedPagefile) { Add-Finding '注意' '記憶體' '分頁檔不是由 Windows 自動管理；應依 commit peak、當機傾印與可用磁碟評估，避免套用固定 RAM 倍數。' }
}
foreach ($v in $script:Data['06_volumes']) { if ($v.Free_Percent -lt 15) { Add-Finding '注意' '磁碟' ($v.DeviceID+' 剩餘 '+$v.Free_Percent+'%；處理大型資料需預留 spill 與套件快取空間。') } }
foreach ($d in $script:Data['07_disks']) { if ($d.HealthStatus -ne 'Healthy') { Add-Finding '警告' '磁碟' ($d.FriendlyName+' 健康狀態：'+$d.HealthStatus+'；請進一步確認並備份。') } }
foreach ($f in $script:Data['18_firewall']) { if ($f.Enabled -eq 'False') { Add-Finding '警告' '安全性' ($f.Name+' 防火牆設定檔停用。') } }
foreach ($d in $script:Data['16_defender']) { if (-not $d.RealTimeProtectionEnabled) { Add-Finding '注意' '安全性' 'Defender 即時保護未啟用；須结合安全中心防毒產品確認保護狀態，不能單憑此判定缺少防毒。' } }
foreach ($r in $script:Data['10_reboot']) { if ($r.CBS -or $r.WindowsUpdate -or $r.PendingFileRename) { Add-Finding '注意' '重啟' '偵測到待重啟標記；PendingFileRename 單獨出現未必代表 Windows 更新需要重啟。' } }
foreach ($s in $script:Data['27_settings']) { if ($s.LongPathsEnabled -ne 1) { Add-Finding '建議' '路徑' 'LongPathsEnabled 未啟用。啟用可改善支援 longPathAware 的程式；並非所有舊程式都能突破長路徑限制。' } }
Add-Finding '說明' 'GPU' 'GPU 名稱/驅動僅供盤點；CUDA、PyTorch 支援與 Windows 11 CPU/TPM/Secure Boot/WDDM 資格須依廠商當前要求另外核實。'
Add-Finding '說明' '套件' '未安装選用分析套件不等於故障。依工作負載建立獨立 Python/R 專案環境與鎖檔；不建議全域一次升級所有套件。'
Add-Finding '說明' '範圍' '本次不連網檢查可升級版本；Windows 更新清單不代表完整更新歷史。未搜尋其他使用者、所有可攜程式、每個專案環境、Conda/WSL 容器內部。'
Save-Data '90_findings' $script:Findings.ToArray()
Save-Data '91_probe_status' $script:Status.ToArray()
Write-JsonFile ([pscustomobject]$script:Data) 'inventory.json'
$summary=New-Object Text.StringBuilder
[void]$summary.AppendLine('# Windows 資料分析工作站診斷 v3')
[void]$summary.AppendLine('')
[void]$summary.AppendLine('時間：'+(Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz')+'；系統管理員：'+$isAdmin+'。所有探測離線唯讀，僅寫入本報告資料夾。')
[void]$summary.AppendLine('')
if ($system.Count) { [void]$summary.AppendLine('系統：'+$system[0].Caption+' '+$system[0].DisplayVersion+' / '+$system[0].EditionID+' / Build '+$system[0].Build+'；RAM '+$system[0].RAM_GB+' GB，當下可用 '+$system[0].FreeRAM_GB+' GB。') }
[void]$summary.AppendLine('')
[void]$summary.AppendLine('桌面軟體登錄筆數：'+@($script:Data['11_software']).Count+'；目前使用者 Appx：'+@($script:Data['12_appx_current_user']).Count+'；Python 已盤點環境：'+$pythonEnvs.Count+'；R 套件筆數（含不同直譯器）：'+$rPackages.Count+'。')
[void]$summary.AppendLine('')
foreach ($finding in $script:Findings) { [void]$summary.AppendLine('- **'+$finding.Level+' / '+$finding.Area+'**：'+$finding.Message) }
[void]$summary.AppendLine('')
[void]$summary.AppendLine('## 工具鏈')
[void]$summary.AppendLine('')
[void]$summary.AppendLine('| 工具 | 發現 | 版本 |')
[void]$summary.AppendLine('|---|---|---|')
foreach ($runtime in $runtimeRows) { [void]$summary.AppendLine('| '+$runtime.Tool+' | '+$runtime.Found+' | '+($runtime.Version -replace '\|','\|')+' |') }
[void]$summary.AppendLine('')
[void]$summary.AppendLine('## 未完成或不可用的探測')
[void]$summary.AppendLine('')
$incomplete=@($script:Status | Where-Object {$_.Status -ne 'OK'})
if ($incomplete.Count -eq 0) { [void]$summary.AppendLine('本次所有已安排探測均完成。') }
foreach ($status in $incomplete) { [void]$summary.AppendLine('- '+$status.Probe+'：'+$status.Status+' — '+$status.Detail) }
[void]$summary.AppendLine('')
[void]$summary.AppendLine('完整資料：inventory.json；逐項 CSV/JSON；91_probe_status.csv 保存每項結果與耗時。空資料不等於健康，先查探測狀態。探測用 _probe_* 檔案保留以便稽核。報告含軟體與本機路徑，分享前請檢視。')
[IO.File]::WriteAllText((Join-Path $OutputDirectory '00_summary.md'),$summary.ToString(),$script:Utf8)
Write-Host ('診斷完成：'+(Join-Path $OutputDirectory '00_summary.md'))
