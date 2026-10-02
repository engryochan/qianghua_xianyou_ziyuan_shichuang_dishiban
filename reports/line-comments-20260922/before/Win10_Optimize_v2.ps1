#Requires -Version 5.1
<#
.SYNOPSIS
  可預演、可還原的 Windows 資料分析工作站設定。預設僅顯示計畫。
.DESCRIPTION
  -Apply 才變更。每次變更前保存精確的原設定，逐步驗證並記錄。
  不自動重開機，不更改分頁檔、Defender、防火牆、DLP、服務或執行原則。
  高效能電源計畫是選項；不宣稱會提升每項工作負載的速度。
.EXAMPLE
  .\Win10_Optimize_v2.ps1 -EnableLongPaths
.EXAMPLE
  .\Win10_Optimize_v2.ps1 -Apply -EnableLongPaths -WhatIf
.EXAMPLE
  .\Win10_Optimize_v2.ps1 -Apply -EnableLongPaths
.EXAMPLE
  .\Win10_Optimize_v2.ps1 -Apply -RestoreFrom 'C:\reports\system\settings-20260920-120000.json'
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
param(
    [switch]$Apply,
    [switch]$EnableLongPaths,
    [ValidateSet('Keep','Balanced','HighPerformance')][string]$PowerPlan='Keep',
    [switch]$CreateRestorePoint,
    [string]$RestoreFrom,
    [string]$BackupDirectory=(Join-Path $PSScriptRoot 'reports\system')
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$key='HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
$name='LongPathsEnabled'
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$encoding=New-Object System.Text.UTF8Encoding($true)

function Read-LongPaths {
    $rk=Get-Item -LiteralPath $key
    $exists=@($rk.GetValueNames()) -contains $name
    if ($exists) {
        $kind=$rk.GetValueKind($name).ToString()
        if ($kind -ne 'DWord') { throw "Unexpected registry type $kind; inspect manually before changing." }
        $value=[int]$rk.GetValue($name)
        if ($value -notin @(0,1)) { throw 'Unexpected LongPathsEnabled value; inspect manually before changing.' }
        return [pscustomobject]@{Exists=$true;Kind=$kind;Value=$value}
    }
    return [pscustomobject]@{Exists=$false;Kind='DWord';Value=$null}
}
function Read-PowerPlan {
    $raw=& "$env:SystemRoot\System32\powercfg.exe" /getactivescheme 2>&1
    if ($LASTEXITCODE -ne 0) { throw "powercfg failed ($LASTEXITCODE): $raw" }
    $m=[regex]::Match(($raw -join ' '),'[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}')
    if (-not $m.Success) { throw 'Cannot parse active power plan GUID.' }
    return $m.Value.ToLowerInvariant()
}
function Set-PowerPlan([string]$Guid) {
    $validated=[guid]::Parse($Guid).ToString()
    & "$env:SystemRoot\System32\powercfg.exe" /setactive $validated | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "powercfg failed with exit code $LASTEXITCODE" }
    if ((Read-PowerPlan) -ne $validated) { throw 'Power plan verification failed.' }
}
function Save-Journal {
    # Write temporary file beside destination; never discard the prior journal on serialization failure.
    $text=$script:journal | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText(($script:journalPath+'.tmp'),$text,$encoding)
    Move-Item -LiteralPath ($script:journalPath+'.tmp') -Destination $script:journalPath -Force
}

if ($RestoreFrom) {
    if ($EnableLongPaths -or $PowerPlan -ne 'Keep' -or $CreateRestorePoint) { throw 'RestoreFrom cannot be combined with other actions.' }
    $snapshot=Get-Content -LiteralPath $RestoreFrom -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($snapshot.Schema -ne 'DataWorkbench.SystemSettings.v1' -or $snapshot.ComputerName -ne $env:COMPUTERNAME) {
        throw 'Unsupported snapshot or snapshot belongs to a different computer.'
    }
    foreach ($change in @($snapshot.Changes)) {
        if ($change.Name -notin @('LongPaths','PowerPlan')) { throw 'Snapshot contains an unsupported action.' }
        if ($change.Name -eq 'LongPaths') {
            if ($change.Before.Kind -ne 'DWord' -or $change.After.Kind -ne 'DWord' -or
                $change.Before.Exists -isnot [bool] -or $change.After.Value -ne 1 -or
                ($change.Before.Exists -and $change.Before.Value -notin @(0,1))) { throw 'Invalid LongPaths snapshot.' }
        } else {
            [void][guid]::Parse([string]$change.Before)
            [void][guid]::Parse([string]$change.After)
        }
    }
    if (-not $Apply) {
        Write-Host '僅顯示還原計畫；加 -Apply 才會還原。'
        $snapshot.Changes | Select-Object Name,Before,After,Status
        return
    }
    if (-not $admin -and -not $WhatIfPreference) { throw '請在系統管理員 PowerShell 執行還原。' }
    $restoreActions=@($snapshot.Changes)
    [array]::Reverse($restoreActions)
    foreach ($change in $restoreActions) {
        if ($change.Status -notin @('Applied','Pending','Failed')) { continue }
        if ($change.Name -eq 'LongPaths') {
            $current=Read-LongPaths
            if ($current.Exists -eq $change.Before.Exists -and $current.Value -eq $change.Before.Value) { Write-Host 'LongPaths 已是原設定。'; continue }
            if (-not $current.Exists -or $current.Value -ne $change.After.Value) { throw 'LongPaths changed since this run; refusing to overwrite a later setting.' }
            if ($PSCmdlet.ShouldProcess($key,'還原 LongPathsEnabled')) {
                if ($change.Before.Exists) {
                    New-ItemProperty -LiteralPath $key -Name $name -PropertyType DWord -Value ([int]$change.Before.Value) -Force | Out-Null
                } else { Remove-ItemProperty -LiteralPath $key -Name $name }
                $verified=Read-LongPaths
                if ($verified.Exists -ne $change.Before.Exists -or $verified.Value -ne $change.Before.Value) { throw 'LongPaths rollback verification failed.' }
                Write-Host 'LongPaths 已還原並驗證。'
            }
        } else {
            $current=Read-PowerPlan
            if ($current -eq $change.Before) { Write-Host '電源計畫已是原設定。'; continue }
            if ($current -ne $change.After) { throw 'Power plan changed since this run; refusing to overwrite a later setting.' }
            if ($PSCmdlet.ShouldProcess([string]$change.Before,'還原原電源計畫')) { Set-PowerPlan $change.Before; Write-Host '電源計畫已還原並驗證。' }
        }
    }
    return
}

$changes=New-Object System.Collections.Generic.List[object]
if ($EnableLongPaths) {
    $before=Read-LongPaths
    if ($before.Exists -and $before.Value -eq 1) { Write-Host '長路徑已啟用，無需變更。' }
    else { $changes.Add([pscustomobject]@{Name='LongPaths';Before=$before;After=[pscustomobject]@{Exists=$true;Kind='DWord';Value=1};Status='Planned';Error=$null}) }
}
if ($PowerPlan -ne 'Keep') {
    $before=Read-PowerPlan
    $target=if ($PowerPlan -eq 'Balanced') {'381b4222-f694-41f0-9685-ff5bb260df2e'} else {'8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'}
    $available=& "$env:SystemRoot\System32\powercfg.exe" /list 2>&1
    if ($LASTEXITCODE -ne 0 -or ($available -join ' ') -notmatch [regex]::Escape($target)) { throw 'Requested power plan does not exist on this device.' }
    if ($before -eq $target) { Write-Host '目前已使用指定的電源計畫。' }
    else { $changes.Add([pscustomobject]@{Name='PowerPlan';Before=$before;After=$target;Status='Planned';Error=$null}) }
}
if (-not $Apply) {
    Write-Host '預覽模式：沒有變更設定；加 -Apply 才會執行。'
    if (-not $EnableLongPaths -and $PowerPlan -eq 'Keep' -and -not $CreateRestorePoint) {
        Write-Host '建議依診斷選用 -EnableLongPaths。電源計畫與分頁檔先保留現況。'
    }
    $changes.ToArray() | Select-Object Name,Before,After,Status
    if ($CreateRestorePoint) { Write-Host '計畫：建立 Windows 系統還原點。' }
    return
}
if (-not $admin -and -not $WhatIfPreference) { throw '此部分需要系統管理員 PowerShell；未變更任何設定。資料分析套件安裝不需要管理員。' }
if ($WhatIfPreference) {
    foreach ($change in $changes) { [void]$PSCmdlet.ShouldProcess($change.Name,'保存原設定並套用新設定') }
    if ($CreateRestorePoint) { [void]$PSCmdlet.ShouldProcess('Windows','建立系統還原點') }
    return
}
if ($CreateRestorePoint -and $PSCmdlet.ShouldProcess('Windows','建立系統還原點')) {
    # Fail rather than claiming a backup exists when System Protection is disabled.
    Checkpoint-Computer -Description ('DataWorkbench '+(Get-Date -Format 'yyyyMMdd-HHmmss')) -RestorePointType MODIFY_SETTINGS
}
if ($changes.Count -eq 0) { Write-Host '沒有需要變更的設定。'; return }
$script:journalPath=$null
$script:journal=[ordered]@{Schema='DataWorkbench.SystemSettings.v1';ComputerName=$env:COMPUTERNAME;Created=(Get-Date).ToString('o');Changes=$changes.ToArray()}
foreach ($change in $changes) {
    if (-not $PSCmdlet.ShouldProcess($change.Name,'保存原設定、套用並驗證')) { continue }
    if (-not $script:journalPath) {
        $folder=[IO.Path]::GetFullPath($BackupDirectory)
        [void][IO.Directory]::CreateDirectory($folder)
        $script:journalPath=Join-Path $folder ('settings-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.json')
    }
    $change.Status='Pending'
    Save-Journal
    try {
        if ($change.Name -eq 'LongPaths') {
            New-ItemProperty -LiteralPath $key -Name $name -PropertyType DWord -Value 1 -Force | Out-Null
            if ((Read-LongPaths).Value -ne 1) { throw 'LongPaths verification failed.' }
        } else { Set-PowerPlan $change.After }
        $change.Status='Applied'
        Save-Journal
        Write-Host ($change.Name+'：已套用並驗證。')
    } catch {
        $change.Status='Failed'; $change.Error=$_.Exception.Message
        Save-Journal
        throw
    }
}
if ($script:journalPath) { Write-Host ('還原資料：'+$script:journalPath) }
Write-Host '完成。長路徑需要應用程式支援，部分程序須重新啟動或重新開機才會生效。'
