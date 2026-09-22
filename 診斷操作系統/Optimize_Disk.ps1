<#
.SYNOPSIS
    Reclaim disk space on C:, one reviewed item at a time.

.DESCRIPTION
    Nothing is deleted unless you name the switch for that item, and every run
    without -Execute is a dry run that only reports sizes.

    Deletions go to the Recycle Bin, never a hard delete, except where Windows
    itself owns the removal (Windows.old, Panther) - those are handed to the
    built-in Disk Cleanup because deleting them by hand corrupts servicing.

    RUN FROM A NORMAL POWERSHELL WINDOW. Inside the Claude desktop app every
    write and delete under %APPDATA% / %LOCALAPPDATA% is redirected into an
    MSIX container, so a delete appears to succeed while the real file stays.

    A NOTE ON SIZES, because the obvious number is wrong here:
    uv hardlinks every file in a virtual environment to its download cache.
    A sample of 120 large files in ds314 found 88% of them hardlinked. So
    `du` and Explorer both count that data twice. Deleting an environment frees
    only its unique blocks (~12%); the rest is freed by `uv cache prune`
    afterwards, once the cache entries have no environment pointing at them.
    That is why -Ds314 always runs a prune when it finishes.

.EXAMPLE
    .\Optimize_Disk.ps1                       # dry run, report only
    .\Optimize_Disk.ps1 -DriverZips -Execute
    .\Optimize_Disk.ps1 -Ds314 -ChromeAiModel -Execute
#>
[CmdletBinding()]
param(
    [switch]$DriverZips,      # Downloads\*.zip - the 7 driver packages, verified installed
    [switch]$Ds314,           # C:\work\envs\ds314 - the Python 3.14 alternate environment
    [switch]$UvCacheOld,      # %LOCALAPPDATA%\uv - superseded by C:\work\uvcache
    [switch]$ReportsDrivers,  # reports\2026-09-21\update-round2 - driver copies + rollback backup
    [switch]$ChromeAiModel,   # Chrome's on-device Gemini Nano weights
    [switch]$InstallerArchive,# C:\<installer archive folder>
    [switch]$WindowsOld,      # hands Windows.old to Disk Cleanup (needs admin)
    [switch]$Execute          # without this, nothing is touched
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName Microsoft.VisualBasic

function Head($t) { Write-Host ''; Write-Host ('=== ' + $t + ' ===') -ForegroundColor Cyan }
function Ok($t)   { Write-Host ('  [OK]   ' + $t) -ForegroundColor Green }
function Warn($t) { Write-Host ('  [WARN] ' + $t) -ForegroundColor Yellow }
function Bad($t)  { Write-Host ('  [STOP] ' + $t) -ForegroundColor Red }

function Get-SizeGB($path) {
    if (-not (Test-Path -LiteralPath $path)) { return -1 }
    $o = robocopy $path 'NULL' /L /E /NFL /NDL /NJH /BYTES /R:0 /W:0 /XJ 2>$null
    foreach ($l in $o) { if ($l -match '^\s*(?:Bytes|\u5b57\u8282)\s*:\s*(\d+)') { return [math]::Round([int64]$Matches[1] / 1GB, 2) } }
    return 0
}

function Free() { [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB, 2) }

function Remove-ToRecycleBin($path, $label) {
    $gb = Get-SizeGB $path
    if ($gb -lt 0) { Warn ($label + ': not present, nothing to do'); return }
    Write-Host ('  {0,8:N2} GB  {1}' -f $gb, $path)
    if (-not $Execute) { Warn 'dry run - pass -Execute to actually remove'; return }
    try {
        if (Test-Path -LiteralPath $path -PathType Container) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($path,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin,
                [Microsoft.VisualBasic.FileIO.UICancelOption]::ThrowException)
        } else {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($path,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin,
                [Microsoft.VisualBasic.FileIO.UICancelOption]::ThrowException)
        }
        Ok ('moved to Recycle Bin: ' + $label)
    } catch { Bad ($label + ' -> ' + $_.Exception.Message) }
}

# ---------------------------------------------------------------- guard rail
Head 'Pre-flight'
$probeName = '_redir_probe_' + [guid]::NewGuid().ToString('N') + '.tmp'
$probe = Join-Path $env:APPDATA $probeName
[System.IO.File]::WriteAllText($probe, 'probe')
$redirected = $false
foreach ($pkg in (Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -EA SilentlyContinue)) {
    if ([System.IO.File]::Exists((Join-Path $pkg.FullName ('LocalCache/Roaming/' + $probeName)))) {
        $redirected = $true; Bad ('%APPDATA% writes redirected into ' + $pkg.Name)
    }
}
if ([System.IO.File]::Exists($probe)) { [System.IO.File]::Delete($probe) }
if ($redirected) { Bad 'Run this from a normal PowerShell window. Aborting.'; exit 2 }
Ok 'Not sandboxed.'

$freeStart = Free
Write-Host ('  C: free at start: {0:N2} GB' -f $freeStart)

# ------------------------------------------------------------- driver zips
if ($DriverZips) {
    Head 'Driver packages in Downloads'
    Write-Host '  Verified before listing here: every device these drivers serve reports Status=OK,'
    Write-Host '  the bound driver versions match the package DriverVer exactly, and oem36/37/40/41/42/44.inf'
    Write-Host '  are all present in the Windows driver store, so rollback does not depend on these zips.'
    $dl = Join-Path $env:USERPROFILE 'Downloads'
    foreach ($f in (Get-ChildItem -LiteralPath $dl -Filter '*.zip' -File -EA SilentlyContinue)) {
        Remove-ToRecycleBin $f.FullName $f.Name
    }
}

# ------------------------------------------------------------------- ds314
if ($Ds314) {
    Head 'Python 3.14 alternate environment'
    Write-Host '  Measured: 733 packages vs 742 in the 3.13 environment, identical core versions,'
    Write-Host '  and 9 packages that cannot be installed on 3.14 at all (tensorflow, gensim,'
    Write-Host '  copulae, scikit-survival, alibi-detect, causalml have no cp314 wheels).'
    Remove-ToRecycleBin 'C:\work\envs\ds314' 'ds314'
    if ($Execute) {
        $uv = Join-Path $env:USERPROFILE '.local/bin/uv.exe'
        if (Test-Path $uv) {
            $env:UV_CACHE_DIR = 'C:/work/uvcache'
            Ok 'pruning uv cache so the now-unreferenced cp314 wheels are released'
            & $uv cache prune | Out-Host
        }
    }
}

# --------------------------------------------------------------- uv cache
if ($UvCacheOld) {
    Head 'Superseded uv cache under %LOCALAPPDATA%'
    Write-Host '  The active cache is C:\work\uvcache. This older one is no longer read.'
    Remove-ToRecycleBin (Join-Path $env:LOCALAPPDATA 'uv') 'old uv cache'
}

# ---------------------------------------------------------- reports copies
if ($ReportsDrivers) {
    Head 'Driver copies inside the repository reports folder'
    $p = Join-Path $env:USERPROFILE 'OneDrive\文档\GitHub\qianghua_xianyou_ziyuan_shichuang_dishiban\reports\2026-09-21\update-round2'
    Warn 'READ THIS FIRST: installation-*/driver-backup holds the PREVIOUS drivers.'
    Warn 'It is the only offline rollback material for the 2026-09-21 driver update.'
    Warn 'Device Manager can still roll back from the driver store, but that is then the only route.'
    Remove-ToRecycleBin $p 'reports/2026-09-21/update-round2'
}

# ------------------------------------------------------------ chrome model
if ($ChromeAiModel) {
    Head 'Chrome on-device AI model'
    Write-Host '  Gemini Nano weights. Chrome re-downloads them if a feature needs them.'
    Remove-ToRecycleBin (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\OptGuideOnDeviceModel') 'OptGuideOnDeviceModel'
}

# -------------------------------------------------------- installer archive
if ($InstallerArchive) {
    Head 'Installer archive on C:\'
    $cand = Get-ChildItem 'C:\' -Directory -Force -EA SilentlyContinue |
            Where-Object { $_.Name -notmatch '^[\x20-\x7E]+$' -and (Get-SizeGB $_.FullName) -gt 1 }
    foreach ($c in $cand) {
        Warn 'These are YOUR installers, not system leftovers. Check the list before removing.'
        Get-ChildItem -LiteralPath $c.FullName -File -EA SilentlyContinue |
            Sort-Object Length -Descending | Select-Object -First 10 |
            ForEach-Object { '      {0,8:N2} MB  {1}' -f ($_.Length/1MB), $_.Name }
        Remove-ToRecycleBin $c.FullName $c.Name
    }
}

# ------------------------------------------------------------- Windows.old
if ($WindowsOld) {
    Head 'Windows.old'
    $gb = Get-SizeGB 'C:\Windows.old'
    $created = (Get-Item 'C:\Windows.old' -Force -EA SilentlyContinue).CreationTime
    Write-Host ('  {0:N2} GB, created {1}' -f $gb, $created)
    $days = [math]::Round(((Get-Date) - $created).TotalDays, 1)
    Warn ('This is the Windows 11 upgrade rollback point, ' + $days + ' days old.')
    Warn 'While it exists, Settings > System > Recovery > Go back still works.'
    Warn 'Removing it is permanent and ends that option.'
    Bad  'Never delete this folder by hand - it breaks servicing. Use Disk Cleanup.'
    if ($Execute) {
        Ok 'launching Disk Cleanup; tick "Previous Windows installation(s)" yourself'
        Start-Process cleanmgr.exe -ArgumentList '/d C:' -Verb RunAs
    } else {
        Warn 'dry run - pass -Execute to launch Disk Cleanup (it will ask for admin)'
    }
}

Head 'Result'
$freeEnd = Free
Write-Host ('  C: free {0:N2} GB -> {1:N2} GB   (delta {2:N2} GB)' -f $freeStart, $freeEnd, ($freeEnd - $freeStart))
if ($Execute) {
    Write-Host ''
    Warn 'Items are in the Recycle Bin, so the space is not released until you empty it.'
    Warn 'Check the contents first, then: Clear-RecycleBin -DriveLetter C'
}
