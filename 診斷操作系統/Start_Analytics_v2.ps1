<#
  Start_Analytics.ps1 — entry point for the verified analytics environment.

  Everything this sets is SESSION-SCOPED on purpose. Persistent user env vars are
  also set (see reports/2026-10-06), but this script is the thing that always
  works, including from inside the Claude desktop app whose MSIX container
  redirects %APPDATA% / %LOCALAPPDATA% writes away from the real profile.

  Nothing here lives under AppData. That is deliberate:
    * Writes to %LOCALAPPDATA% from the Claude app land in
      ...\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Local\ and are invisible to a
      normal R / Python / Jupyter session. Proven by probe on 2026-10-06.
    * uv's own minor-version Python link could not even be traversed under
      %APPDATA%; moving the install dir to C:\work fixed it outright.

  Usage:
      . C:\work\Start_Analytics.ps1                  # analysis
      . C:\work\Start_Analytics.ps1 -WithToolchain   # + compile R/Stan from source
#>

param([switch]$WithToolchain)

$ErrorActionPreference = 'Stop'

$DS_PY  = 'C:\work\envs\ds\Scripts\python.exe'
$R_BIN  = 'C:\work\R\R-4.6.1\bin\x64'
$QUARTO = 'C:\work\tools\bin'
$UV_BIN = Join-Path $env:USERPROFILE '.local\bin'

foreach ($p in @($R_BIN, $QUARTO, $UV_BIN)) {
    if ($env:Path -notlike "*$p*") { $env:Path = "$p;$env:Path" }
}

# reticulate honours RETICULATE_PYTHON ONLY. QUARTO_PYTHON is ignored; without
# this it silently downloads a clean CPython and every package looks missing.
$env:RETICULATE_PYTHON     = 'C:/work/envs/ds/Scripts/python.exe'
$env:UV_PYTHON_INSTALL_DIR = 'C:\work\pythons'
$env:UV_CACHE_DIR          = 'C:\work\uv-cache'
$env:JUPYTER_DATA_DIR      = 'C:\work\jupyter'

# Deliberately NOT set: OMP_NUM_THREADS, TZ, R_LIBS_USER.
# Thread and timezone settings change RESULTS, not just install behaviour, so the
# same script would compute different things on different machines. Set them per
# analysis if an analysis actually needs them.

Write-Host 'analytics environment ready' -ForegroundColor Green
Write-Host ("  python  : " + (& $DS_PY -c "import sys;print(sys.version.split()[0])"))
Write-Host ("  R       : " + (& "$R_BIN\Rscript.exe" -e "cat(R.version.string)" 2>$null))
Write-Host ("  quarto  : " + (& "$QUARTO\quarto.cmd" --version))
Write-Host ("  uv      : " + (& "$UV_BIN\uv.exe" --version))

if ($WithToolchain) {
    # rtools45\usr\bin holds make.exe, which R CMD SHLIB needs on PATH -- but it
    # also holds sh / find / sort, which shadow the Windows built-ins. So it goes
    # on PATH ONLY for this session, and only when explicitly asked for.
    # The registry key alone is NOT enough: R 4.5/4.6 Makeconf reads RTOOLS45_HOME.
    $env:RTOOLS45_HOME = 'C:\work\rtools45'
    $env:Path = "C:\work\rtools45\usr\bin;$env:Path"
    $env:CMDSTAN = 'C:/work/cmdstan/cmdstan-2.40.0'
    Write-Host '  toolchain ON (session only):' -ForegroundColor Yellow
    # gcc lives in x86_64-w64-mingw32.static.posixin, NOT usrin -- and it does
    # not need to be on PATH at all: R's Makeconf finds it via RTOOLS45_HOME.
    # Only make.exe (in usrin) has to be reachable. Report gcc by absolute path.
    $gccExe = 'C:\worktools45_64-w64-mingw32.static.posixin\gcc.exe'
    Write-Host ("    gcc     : " + (& $gccExe --version | Select-Object -First 1))
    Write-Host ("    make    : " + (Get-Command make).Source)
    Write-Host ("    cmdstan : " + $env:CMDSTAN)
    Write-Host '    NOTE: rtools45\usr\bin is now ahead of Windows sh/find/sort in THIS session.'
} else {
    Write-Host '  toolchain OFF. Use -WithToolchain to compile R/Stan from source.'
    Write-Host '  (rtools45\usr\bin shadows the built-in sh/find/sort, so it is opt-in.)'
}
