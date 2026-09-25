<#
.SYNOPSIS
    Recall R user packages back to the C:\work hub:
    move win-library\4.6  ->  C:\work\Rlib, and restore R_LIBS in ~/.Renviron.

.WHY
    C:\work is the central analysis hub (Python env, uv cache, projects all live there).
    This returns the R user library to C:\work\Rlib as well, which is the repo's
    original intended home (per CLAUDE.md). Base/Recommended packages stay in the R
    install's own library (Program Files) and are never touched.

.SAFETY
    - Only moves the user library (win-library\4.6). The 29 base/recommended packages
      in C:\Program Files\R\R-4.6.1\library are NOT touched.
    - Aborts unless it can confirm the R install and win-library exist.
    - Restores R_LIBS=C:/work/Rlib in ~/.Renviron so R sees the packages at the new
      location and installs new ones there.

.USAGE
    Run in a NORMAL PowerShell (NOT the Claude app). Close R / RStudio / Positron first.
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
        .\Recall_RLibrary_ToHub.ps1 -WhatIf     # dry run
        .\Recall_RLibrary_ToHub.ps1             # execute
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Src = "$env:LOCALAPPDATA\R\win-library\4.6",
    [string]$Dst = 'C:\work\Rlib'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
function Ok($t)  { Write-Host "  [OK]   $t" -ForegroundColor Green }
function Warn($t){ Write-Host "  [WARN] $t" -ForegroundColor Yellow }
function Bad($t) { Write-Host "  [STOP] $t" -ForegroundColor Red }

Write-Host "=== Pre-flight ===" -ForegroundColor Cyan

# sandbox guard
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

# R not running
$busy = Get-Process R, Rgui, Rterm, Rscript, rstudio, rsession, Positron -EA SilentlyContinue
if ($busy) { Bad ('Close these first: ' + (($busy.Name | Sort-Object -Unique) -join ', ')); exit 3 }
Ok 'No R / RStudio / Positron running.'

if (-not (Test-Path $Src)) { Bad "Source not found: $Src (nothing to recall)."; exit 4 }
$rscript = 'C:\Program Files\R\R-4.6.1\bin\x64\Rscript.exe'
if (-not (Test-Path $rscript)) { Bad 'Rscript not found. Aborting.'; exit 5 }
New-Item -ItemType Directory -Path $Dst -Force | Out-Null
$srcN = (Get-ChildItem $Src -Directory | Measure-Object).Count
Ok "Source win-library: $srcN packages  ->  Dest $Dst"

# --- move / dedupe ---
Write-Host "`n=== Recalling packages to hub ===" -ForegroundColor Cyan
$moved = 0; $dedup = 0; $fail = 0
foreach ($d in Get-ChildItem $Src -Directory) {
    $s = $d.FullName; $t = Join-Path $Dst $d.Name
    try {
        if (Test-Path $t) {
            if ($PSCmdlet.ShouldProcess($s, 'remove redundant (already in hub)')) { Remove-Item $s -Recurse -Force }
            $dedup++
        } else {
            if ($PSCmdlet.ShouldProcess($s, "move -> $t")) { Move-Item $s $t -Force }
            $moved++
        }
    } catch { Bad ("$($d.Name) -> $($_.Exception.Message)"); $fail++ }
}
Ok ("Moved: $moved   Removed-as-redundant: $dedup   Failed: $fail")

# --- restore R_LIBS in ~/.Renviron ---
Write-Host "`n=== Restoring R_LIBS in ~/.Renviron ===" -ForegroundColor Cyan
$renv = Join-Path $env:USERPROFILE '.Renviron'
if ($PSCmdlet.ShouldProcess($renv, 'set R_LIBS=C:/work/Rlib')) {
    $lines = if (Test-Path $renv) { Get-Content $renv | Where-Object { $_ -notmatch '^\s*R_LIBS\s*=' } } else { @() }
    $lines += 'R_LIBS=C:/work/Rlib'
    Set-Content -LiteralPath $renv -Value $lines -Encoding UTF8
    Ok 'R_LIBS=C:/work/Rlib written (existing R_LIBS lines replaced).'
} else { Warn 'Dry run: skipped .Renviron edit.' }

if ($WhatIfPreference) { Write-Host "`n(dry run complete - nothing changed)" -ForegroundColor Yellow; return }

# --- verify ---
Write-Host "`n=== Verification ===" -ForegroundColor Cyan
$hubN = (Get-ChildItem $Dst -Directory | Measure-Object).Count
$leftN = (Get-ChildItem $Src -Directory -EA SilentlyContinue | Measure-Object).Count
Ok "C:\work\Rlib now holds: $hubN packages"
Ok "win-library leftover  : $leftN packages (expected ~0)"
$code = @'
cat("R_LIBS =", Sys.getenv("R_LIBS"), "\n")
cat(".libPaths[1] =", .libPaths()[1], "\n")
cat("total visible =", nrow(installed.packages()), "\n")
for (p in c("extRemes","brms","grf","pROC","survival","data.table"))
  cat("  ", p, ":", if (requireNamespace(p, quietly=TRUE)) "loads" else "FAIL", "\n")
'@
$tmp = Join-Path $env:TEMP 'recall_verify.R'
[System.IO.File]::WriteAllText($tmp, $code)   # UTF-8 no BOM, Rscript-safe
& $rscript $tmp
Remove-Item $tmp -Force -EA SilentlyContinue
Write-Host "`nDone. R packages recalled to the C:\work hub." -ForegroundColor Cyan
