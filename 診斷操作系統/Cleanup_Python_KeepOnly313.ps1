<#
.SYNOPSIS
    Keep ONLY Python 3.13.15; remove every other version
    (uv-managed 3.12 & 3.14, and the system-installed 3.14.7).

.SAFETY
    - Both analysis envs (C:\work\envs\ds and C:\work\projects\lab\.venv) have their
      pyvenv.cfg "home" pointing at the uv-managed cpython-3.13. So the uv 3.13 MUST
      stay. This script removes ONLY 3.12 and 3.14, and aborts up front unless it can
      confirm the survivor (uv 3.13 + the ds env at 3.13.15) is intact.
    - System Python 3.14.7 was installed by the python.org bundle installer (9
      components). It is removed via its bundle uninstaller in one shot, not by
      hand-deleting folders.

.USAGE
    Run in a NORMAL PowerShell (NOT inside the Claude app). A per-user uninstall may
    raise a UAC prompt; approve it.
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
        .\Cleanup_Python_KeepOnly313.ps1 -WhatIf     # dry run, shows plan only
        .\Cleanup_Python_KeepOnly313.ps1             # execute
#>
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
function Ok($t)  { Write-Host "  [OK]   $t" -ForegroundColor Green }
function Warn($t){ Write-Host "  [WARN] $t" -ForegroundColor Yellow }
function Bad($t) { Write-Host "  [STOP] $t" -ForegroundColor Red }

Write-Host "=== Pre-flight safety checks ===" -ForegroundColor Cyan

# 0) not running inside the Claude app sandbox
$probeName = "_probe_" + [guid]::NewGuid().ToString('N') + ".tmp"
$probe = Join-Path $env:APPDATA $probeName
[System.IO.File]::WriteAllText($probe, 'x')
$redir = $false
foreach ($p in (Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -EA SilentlyContinue)) {
    if ([System.IO.File]::Exists((Join-Path $p.FullName ('LocalCache/Roaming/' + $probeName)))) { $redir = $true }
}
if ([System.IO.File]::Exists($probe)) { [System.IO.File]::Delete($probe) }
if ($redir) { Bad 'Writes are sandbox-redirected. Run from a normal PowerShell. Aborting.'; exit 2 }
Ok 'Not sandboxed.'

# 0b) no process may hold the interpreters. A running python / uv / IDE keeps a
#     file handle open on the version being removed, and uv then fails the whole
#     uninstall with "failed to remove directory ...: os error 5" (access denied).
#     This is the actual cause of that error, not permissions. Catch it up front.
$busy = Get-Process python, python3, pythonw, uv, pip, pycharm64, rsession, rstudio, Positron -EA SilentlyContinue
if ($busy) {
    Bad ('These processes lock the interpreters (this is what causes "os error 5"). Close them, then re-run: ' +
         (($busy.Name | Sort-Object -Unique) -join ', '))
    exit 7
}
Ok 'No Python / uv / IDE processes running.'

# 1) locate uv
$uv = Join-Path $env:USERPROFILE '.local\bin\uv.exe'
if (-not (Test-Path $uv)) { $uv = (Get-Command uv -EA SilentlyContinue).Source }
if (-not $uv) { Bad 'uv not found. Aborting.'; exit 3 }
Ok "uv: $uv"

# 2) SURVIVOR GATE: confirm the keeper (uv 3.13 + ds env) exists, else abort
$dsPy  = 'C:\work\envs\ds\Scripts\python.exe'
$uv313 = Join-Path $env:APPDATA 'uv\python\cpython-3.13-windows-x86_64-none\python.exe'
if (-not (Test-Path $dsPy))  { Bad "ds env missing ($dsPy). Aborting to avoid data loss."; exit 4 }
if (-not (Test-Path $uv313)) { Bad "uv 3.13 base interpreter missing ($uv313). Aborting."; exit 5 }
$dsVer = & $dsPy -c "import sys;print(sys.version.split()[0])"
if ($dsVer -ne '3.13.15') { Bad "ds is not 3.13.15 (got $dsVer). Aborting."; exit 6 }
Ok "Survivor confirmed: uv 3.13.15 + ds env (3.13.15) are intact."

Write-Host "`n=== Will remove (ONLY 3.12 and 3.14; never 3.13) ===" -ForegroundColor Cyan
Write-Host '  1) uv-managed Python 3.12'
Write-Host '  2) uv-managed Python 3.14'
Write-Host '  3) system-installed Python 3.14.7 (bundle, all 9 components)'

# 3) uninstall uv-managed 3.12 / 3.14
Write-Host "`n=== Removing uv-managed 3.12 / 3.14 ===" -ForegroundColor Cyan
if ($PSCmdlet.ShouldProcess('uv python 3.12 and 3.14', 'uninstall')) {
    & $uv python uninstall 3.12 3.14
    Ok 'Requested uv uninstall of 3.12 / 3.14.'
} else { Warn 'Dry run: skipped uv uninstall.' }

# 4) uninstall the system Python 3.14.7 bundle (discover uninstaller dynamically)
Write-Host "`n=== Removing system Python 3.14.7 ===" -ForegroundColor Cyan
$keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
$bundle = Get-ItemProperty $keys -EA SilentlyContinue |
    Where-Object { $_.DisplayName -eq 'Python 3.14.7 (64-bit)' -and $_.QuietUninstallString } |
    Select-Object -First 1
if (-not $bundle) {
    Warn 'System Python 3.14.7 bundle uninstall entry not found (already uninstalled).'
    # The bundle is gone but an empty leftover folder can remain. Remove it ONLY
    # if it holds no executables (i.e. it is a genuine orphaned shell, not a live install).
    $py314 = 'C:\Users\PPCCpcpc\AppData\Local\Programs\Python\Python314'
    if (Test-Path $py314) {
        $hasExe = Get-ChildItem $py314 -Recurse -Filter *.exe -EA SilentlyContinue | Select-Object -First 1
        if ($hasExe) {
            Warn "  $py314 still contains executables - NOT deleting. Inspect manually."
        } elseif ($PSCmdlet.ShouldProcess($py314, 'remove orphaned empty leftover folder')) {
            Remove-Item $py314 -Recurse -Force -EA SilentlyContinue
            Ok "  Removed orphaned empty leftover folder: $py314"
        }
    }
} else {
    Write-Host ('  uninstall string: ' + $bundle.QuietUninstallString)
    if ($PSCmdlet.ShouldProcess('system Python 3.14.7', 'uninstall /quiet')) {
        $q = $bundle.QuietUninstallString
        $exe = ($q -split '"')[1]
        $argline = $q.Substring($q.IndexOf('"', 1) + 1).Trim()
        Start-Process -FilePath $exe -ArgumentList $argline -Wait
        Ok 'Requested system Python 3.14.7 uninstall.'
    } else { Warn 'Dry run: skipped system 3.14 uninstall.' }
}

if ($WhatIfPreference) { Write-Host "`n(dry run complete - nothing changed)" -ForegroundColor Yellow; return }

# 5) verify
Write-Host "`n=== Verification ===" -ForegroundColor Cyan
Start-Sleep -Seconds 2
Write-Host '  uv Pythons remaining:'
& $uv python list --only-installed 2>$null | Select-String 'cpython-3' | ForEach-Object { '     ' + $_.Line.Trim() }
$sys314 = Test-Path 'C:\Users\PPCCpcpc\AppData\Local\Programs\Python\Python314\python.exe'
Ok ("system Python314 folder still present: $sys314   (expected False)")
$dsOk = (Test-Path $dsPy) -and ((& $dsPy -c "import sys;print(sys.version.split()[0])") -eq '3.13.15')
Ok ("ds env intact and 3.13.15: $dsOk")
if ($dsOk) {
    $n = & $dsPy -c "import importlib.metadata as m;print(len(list(m.distributions())))"
    Ok ("ds visible packages: $n   (expected ~744)")
}
Write-Host "`nDone. Success = ds intact True AND system314 False." -ForegroundColor Cyan
Write-Host "Reminder: if PyCharm still points at the removed 3.14, repoint it in the UI to" -ForegroundColor Yellow
Write-Host "  C:\work\envs\ds\Scripts\python.exe" -ForegroundColor Yellow
