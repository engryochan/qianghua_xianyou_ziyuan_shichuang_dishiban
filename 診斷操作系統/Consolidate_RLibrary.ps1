<#
.SYNOPSIS
    Move user-installed R packages out of the base library
    (C:\Program Files\R\R-4.6.1\library) into the standard user library
    (%LOCALAPPDATA%\R\win-library\4.6), so they survive R minor-version upgrades.

.WHY
    ~257 user packages currently sit in the Program Files base library. When R
    upgrades its minor version, that directory is replaced wholesale and those
    packages would be wiped. The user library is the correct, upgrade-safe home.

    Base and Recommended packages (base, stats, MASS, Matrix, survival, ...) MUST
    stay in Program Files — moving them breaks R. This script identifies them by
    reading each package's DESCRIPTION `Priority:` field (not a hard-coded list),
    and never touches anything marked base or recommended.

.MUST
    - Run from an ELEVATED (Administrator) PowerShell — writing under Program Files
      needs it. Run from a NORMAL window (not inside the Claude app; its sandbox
      redirects %LOCALAPPDATA% writes).
    - Close R / RStudio / Positron first — packages in use cannot be moved.

.EXAMPLE
    .\Consolidate_RLibrary.ps1 -WhatIf     # dry run, shows what would move
    .\Consolidate_RLibrary.ps1             # do it
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Src = 'C:\Program Files\R\R-4.6.1\library',
    [string]$Dst = "$env:LOCALAPPDATA\R\win-library\4.6"
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
function Ok($t)  { Write-Host "  [OK]   $t" -ForegroundColor Green }
function Warn($t){ Write-Host "  [WARN] $t" -ForegroundColor Yellow }
function Bad($t) { Write-Host "  [STOP] $t" -ForegroundColor Red }

Write-Host "=== Pre-flight ===" -ForegroundColor Cyan

# 1) elevation
$admin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Bad 'Not elevated. Right-click PowerShell -> Run as administrator. Aborting.'; exit 2 }
Ok 'Running elevated.'

# 2) sandbox guard (never write user library from inside the Claude app)
$probeName = "_probe_$([guid]::NewGuid().ToString('N')).tmp"
$probe = Join-Path $env:APPDATA $probeName
[System.IO.File]::WriteAllText($probe, 'x')
$redirected = $false
foreach ($pkg in (Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -EA SilentlyContinue)) {
    if ([System.IO.File]::Exists((Join-Path $pkg.FullName ('LocalCache/Roaming/' + $probeName)))) { $redirected = $true }
}
if ([System.IO.File]::Exists($probe)) { [System.IO.File]::Delete($probe) }
if ($redirected) { Bad 'Writes are being sandbox-redirected. Run from a normal PowerShell, not the Claude app. Aborting.'; exit 3 }
Ok 'Not sandboxed.'

# 3) no R running
$busy = Get-Process R, Rgui, Rterm, Rscript, rstudio, rsession, Positron -EA SilentlyContinue
if ($busy) { Bad ('Close these first: ' + (($busy.Name | Sort-Object -Unique) -join ', ')); exit 4 }
Ok 'No R / RStudio / Positron running.'

if (-not (Test-Path $Src)) { Bad "Source not found: $Src"; exit 5 }
New-Item -ItemType Directory -Path $Dst -Force | Out-Null
Ok "Source: $Src"
Ok "Dest  : $Dst"

# --- classify: read each package's DESCRIPTION Priority ---
Write-Host "`n=== Classifying packages by DESCRIPTION Priority ===" -ForegroundColor Cyan
$base = New-Object System.Collections.Generic.List[string]
$user = New-Object System.Collections.Generic.List[string]
foreach ($d in Get-ChildItem $Src -Directory) {
    $desc = Join-Path $d.FullName 'DESCRIPTION'
    $prio = ''
    if (Test-Path $desc) {
        $m = Select-String -Path $desc -Pattern '^Priority:\s*(\S+)' -EA SilentlyContinue | Select-Object -First 1
        if ($m) { $prio = $m.Matches[0].Groups[1].Value.Trim().ToLower() }
    }
    if ($prio -in @('base','recommended')) { $base.Add($d.Name) } else { $user.Add($d.Name) }
}
Ok ("Base/Recommended (KEPT, never moved): {0}" -f $base.Count)
Ok ("User packages (to relocate)        : {0}" -f $user.Count)

# --- move / dedupe ---
Write-Host "`n=== Relocating ===" -ForegroundColor Cyan
$moved = 0; $dedup = 0; $fail = 0
foreach ($name in $user) {
    $s = Join-Path $Src $name
    $t = Join-Path $Dst $name
    try {
        if (Test-Path $t) {
            # win-library already has it (it wins by .libPaths order) -> drop the redundant PF copy
            if ($PSCmdlet.ShouldProcess($s, 'remove redundant (already in user library)')) {
                Remove-Item $s -Recurse -Force
            }
            $dedup++
        } else {
            if ($PSCmdlet.ShouldProcess($s, "move -> $t")) {
                Move-Item $s $t -Force
            }
            $moved++
        }
    } catch {
        Bad ("$name -> $($_.Exception.Message)")
        $fail++
    }
}
Ok ("Moved: {0}   Removed-as-redundant: {1}   Failed: {2}" -f $moved, $dedup, $fail)

if ($WhatIfPreference) { Write-Host "`n(dry run — nothing changed)" -ForegroundColor Yellow; return }

# --- verify ---
Write-Host "`n=== Verification ===" -ForegroundColor Cyan
$baseLeft = (Get-ChildItem $Src -Directory | Measure-Object).Count
$userNow  = (Get-ChildItem $Dst -Directory | Measure-Object).Count
Ok ("Program Files library now holds {0} packages (should equal base/recommended = {1})" -f $baseLeft, $base.Count)
Ok ("User library now holds {0} packages" -f $userNow)

$rscript = 'C:\Program Files\R\R-4.6.1\bin\x64\Rscript.exe'
if (Test-Path $rscript) {
    $code = @'
n <- nrow(installed.packages())
cat("R sees", n, "packages total\n")
for (p in c("extRemes","brms","grf","pROC","survival","MASS","data.table"))
  cat("  ", p, ":", if (requireNamespace(p, quietly=TRUE)) "loads" else "FAIL", "\n")
'@
    $tmp = Join-Path $env:TEMP 'rlib_verify.R'
    $code | Set-Content $tmp -Encoding UTF8
    & $rscript $tmp
    Remove-Item $tmp -Force -EA SilentlyContinue
}
Write-Host "`nDone. If any package showed FAIL, tell Claude before installing anything else." -ForegroundColor Cyan
