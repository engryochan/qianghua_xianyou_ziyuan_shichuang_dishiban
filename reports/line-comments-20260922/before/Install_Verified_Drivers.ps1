#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Apply,[string]$Root)
$ErrorActionPreference='Stop'
if(-not $Root){$Root=Join-Path $PSScriptRoot '..\reports\2026-09-21\update-round2\drivers'}
$Root=[IO.Path]::GetFullPath($Root)
$candidates=Get-Content (Join-Path $Root 'compatible-plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$plan=@($candidates | Where-Object Decision -eq 'Eligible')
if($plan.Count -eq 0){throw 'No verified candidates'}
if(-not $Apply){$plan | Select-Object Inf,Version,Decision;return}
$run=Join-Path $Root ('installation-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
$null=New-Item -ItemType Directory -Path $run
$status=[ordered]@{Started=(Get-Date -Format o);State='Checking';RebootRequired=$false;Steps=@();Error=$null}
function Save-State {$status | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $run 'status.json') -Encoding UTF8}
Save-State
try {
  $admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if(-not $admin){throw 'Administrator credentials required; no drivers changed.'}
  if((Get-CimInstance Win32_BaseBoard).Product -ne 'PRIME H610M-R D4'){throw 'Motherboard mismatch'}
  if((Get-PSDrive C).Free -lt 8GB){throw 'Less than 8 GiB free; stop before backup'}
  $before=@(Get-CimInstance Win32_PnPSignedDriver)
  $beforeProblems=@(Get-PnpDevice -PresentOnly | Where-Object Status -ne 'OK' | Select-Object -ExpandProperty InstanceId)
  $before | Select-Object DeviceID,DeviceName,DriverVersion,DriverProviderName,InfName | Export-Csv (Join-Path $run 'before.csv') -NoTypeInformation -Encoding UTF8
  # Recheck all candidates and current versions BEFORE any changes.
  foreach($entry in $plan){
    if(-not $entry.Inf.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'INF outside reviewed directory'}
    if((Get-FileHash -LiteralPath $entry.Inf).Hash -ne $entry.SHA256){throw 'INF changed'}
    if((Get-FileHash -LiteralPath $entry.Catalog).Hash -ne $entry.CatalogSHA256){throw 'Catalog changed'}
    if((Get-AuthenticodeSignature -LiteralPath $entry.Catalog).Status -ne 'Valid'){throw 'Catalog signature invalid'}
    foreach($device in $entry.Devices){
      $current=$before | Where-Object DeviceID -eq $device.DeviceID | Select-Object -First 1
      if([string]$current.DriverVersion -ne [string]$device.Before){throw "Driver changed since plan: $($device.DeviceID). Re-diagnose."}
      if($current.DriverVersion -and [version]$entry.Version -lt [version]$current.DriverVersion){throw 'Lower version rejected'}
    }
  }
  $backup=Join-Path $run 'driver-backup'
  $null=New-Item -ItemType Directory -Path $backup
  & pnputil.exe /export-driver '*' $backup *> (Join-Path $run 'backup.log')
  if($LASTEXITCODE -ne 0){throw 'Driver export failed; no installation performed'}
  # Checkpoint is extra protection; exported drivers remain the driver rollback source.
  try {
    Import-Module Microsoft.PowerShell.Management -ErrorAction Stop
    $restoreDescription='Verified ASUS drivers '+(Get-Date -Format 'yyyyMMdd-HHmmss')
    Checkpoint-Computer -Description $restoreDescription -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    $points=@(Get-ComputerRestorePoint -ErrorAction Stop)
    $points | Select-Object SequenceNumber,Description,CreationTime | ConvertTo-Json | Set-Content (Join-Path $run 'restore-points.json') -Encoding UTF8
    $status.RestorePoint=if($points.Description -contains $restoreDescription){'New restore point verified'}else{'No new restore point; exported drivers available'}
  } catch {$status.RestorePoint='Unavailable: '+$_.Exception.Message}
  $status.State='Installing';Save-State
  foreach($entry in $plan){
    $name=Split-Path $entry.Inf -Leaf
    # PnP ranks applicability; never force a lower-ranked driver and never reboot here.
    & pnputil.exe /add-driver $entry.Inf /install *> (Join-Path $run ($name+'.log'))
    $code=$LASTEXITCODE
    $status.Steps+=@([pscustomobject]@{Inf=$name;Version=$entry.Version;ExitCode=$code})
    if($code -eq 3010){$status.RebootRequired=$true}
    Save-State
    if($code -notin @(0,3010)){throw "Installation stopped at $name, exit $code"}
    $newProblems=@(Get-PnpDevice -PresentOnly | Where-Object {$_.Status -ne 'OK' -and $_.InstanceId -notin $beforeProblems})
    if($newProblems.Count){throw ('New device problem; stop further updates: '+($newProblems.InstanceId -join ', '))}
  }
  $after=@(Get-CimInstance Win32_PnPSignedDriver)
  $after | Select-Object DeviceID,DeviceName,DriverVersion,DriverProviderName,InfName | Export-Csv (Join-Path $run 'after.csv') -NoTypeInformation -Encoding UTF8
  $problems=@(Get-PnpDevice -PresentOnly | Where-Object Status -ne 'OK' | Select-Object FriendlyName,Problem,InstanceId)
  ConvertTo-Json -InputObject $problems -Depth 4 | Set-Content (Join-Path $run 'problems-after.json') -Encoding UTF8
  $lower=@(foreach($old in $before){
    $new=$after | Where-Object DeviceID -eq $old.DeviceID | Select-Object -First 1
    if([string]$old.DriverVersion -eq [string]$new.DriverVersion){continue}
    if($old.DriverVersion -and $new.DriverVersion){
      $oldVersion=$null;$newVersion=$null
      if(-not [version]::TryParse([string]$old.DriverVersion,[ref]$oldVersion) -or -not [version]::TryParse([string]$new.DriverVersion,[ref]$newVersion)){
        throw ('Changed nonnumeric driver version requires review: '+$old.DeviceID)
      }
      if($newVersion -lt $oldVersion){$old.DeviceID}
    }
  })
  if($lower.Count){throw ('Lower installed version detected; retain backups and review: '+($lower -join ', '))}
  $status.State=if($problems.Count){'InstalledNeedsDeviceReview'}else{'InstalledDeviceChecksPassed'}
  $status.RemainingDeviceProblems=$problems.Count
} catch {$status.State='Stopped';$status.Error=$_.Exception.Message;throw}
finally{Save-State}
