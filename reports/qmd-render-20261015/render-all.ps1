$ErrorActionPreference = 'Stop'
$python = if ($env:RETICULATE_PYTHON) { $env:RETICULATE_PYTHON } else { 'C:/work/envs/ds/Scripts/python.exe' }
if (-not (Test-Path -LiteralPath $python)) { throw 'Set RETICULATE_PYTHON to an existing Python executable.' }
$env:PYTHONIOENCODING = 'utf-8'
& $python (Join-Path $PSScriptRoot 'render_all.py')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $python (Join-Path $PSScriptRoot 'verify.py')
exit $LASTEXITCODE
