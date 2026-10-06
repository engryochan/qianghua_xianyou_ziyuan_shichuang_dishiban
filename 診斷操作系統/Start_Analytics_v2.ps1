<#
  Start_Analytics.ps1 — entry point for the verified analytics environment.

  Everything this sets is SESSION-SCOPED on purpose. Persistent user env vars are
  also set (see the report), but this script is the thing that always works,
  including from inside the Claude desktop app whose MSIX container redirects
  %APPDATA% / %LOCALAPPDATA% writes away from the real profile.

  Nothing here lives under AppData. That is deliberate:
    * Writes to %LOCALAPPDATA% from the Claude app land in
      ...\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Local\ and are invisible to a
      normal R / Python / Jupyter session. Proven by probe on 2026-10-06.
    * uv's own minor-version Python link could not even be traversed under
      %APPDATA%; moving the install dir to C:\work fixed it outright.

  Usage:   . C:\work\Start_Analytics.ps1        (dot-source to keep the changes)
#>

$ErrorActionPreference = 'Stop'

$DS_PY    = 'C:\work\envs\ds\Scripts\python.exe'
$R_BIN    = 'C:\work\R\R-4.6.1\bin\x64'
$QUARTO   = 'C:\work\tools\bin'
$UV_BIN   = Join-Path $env:USERPROFILE '.local\bin'

foreach ($p in @($R_BIN, $QUARTO, $UV_BIN)) {
    if ($env:Path -notlike "*$p*") { $env:Path = "$p;$env:Path" }
}

# reticulate honours RETICULATE_PYTHON ONLY. QUARTO_PYTHON is ignored; without
# this it silently downloads a clean CPython and every package looks missing.
$env:RETICULATE_PYTHON    = 'C:/work/envs/ds/Scripts/python.exe'
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
Write-Host '  Rtools is intentionally absent from PATH: rtools\usr\bin shadows the'
Write-Host '  built-in sh / find / sort. R locates it via HKLM\SOFTWARE\R-core\Rtools.'
