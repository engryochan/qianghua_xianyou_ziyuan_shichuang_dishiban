<#
  Register_Kernels_And_Runtime.ps1

  Two things that have to be done by hand on this machine, because the standard
  tooling silently does the wrong thing here:

  1) Jupyter kernels. `ipykernel install --user` writes into %APPDATA%, which the
     Claude desktop app's MSIX container redirects into
     ...\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\ -- invisible to a real
     Jupyter/Positron. And `--prefix` writes argv[0] as a bare "python", which
     resolves through PATH to the wrong interpreter. So kernel.json is written by
     hand, under C:\work\jupyter, with an absolute argv[0].

  2) The OpenMP runtime. This machine has vcruntime140/msvcp140/concrt140 but NOT
     vcomp140.dll, so any OpenMP-linked wheel fails with
     "Could not find module <dll> (or one of its dependencies)" even though the
     dll is right there. Since Python 3.8 the Windows DLL search no longer looks
     at PATH (LOAD_LIBRARY_SEARCH_DEFAULT_DIRS), so a .pth calling
     os.add_dll_directory is the mechanism that actually works.

  The JSON is built with ConvertTo-Json rather than string concatenation. Hand
  concatenation already produced a broken kernel.json once: the Windows path needs
  its backslashes escaped, and getting the quoting level wrong yields
  `json.decoder.JSONDecodeError: Invalid \escape` while `jupyter kernelspec list`
  still cheerfully lists the directory, so it looks registered when it is not.

  NOTE: this file must keep its UTF-8 BOM. Without one, Windows PowerShell 5.1
  decodes it as ANSI and every non-ASCII path inside is destroyed.
#>

$ErrorActionPreference = 'Stop'

$RUNTIME = 'C:\work\runtime'
$KERNELS = 'C:\work\jupyter\kernels'

$envs = [ordered]@{
  ds    = 'Python 3.13 (ds)'
  fin   = 'Python 3.13 (fin: openbb/pypfopt)'
  nlp   = 'Python 3.13 (nlp: flair, transformers<5)'
  mlops = 'Python 3.13 (mlops: evidently/nannyml/feast)'
  xai   = 'Python 3.13 (xai: dalex, plotly>=6)'
  rl    = 'Python 3.13 (rl: tianshou/gluonts)'
}

New-Item -ItemType Directory -Path $RUNTIME, $KERNELS -Force | Out-Null

# --- 1. OpenMP runtime, sourced from a wheel that already ships it -------------
$dst = Join-Path $RUNTIME 'vcomp140.dll'
if (-not (Test-Path $dst)) {
    $src = 'C:\work\envs\ds\Lib\site-packages\sklearn\.libs\vcomp140.dll'
    if (Test-Path $src) { Copy-Item $src $dst -Force; "placed vcomp140.dll in $RUNTIME" }
    else { Write-Warning "vcomp140.dll not found at $src -- ask IT for the VC++ Redistributable" }
} else { "vcomp140.dll already in $RUNTIME" }

# --- 2. per-env .pth + kernel.json --------------------------------------------
# The isdir() guard is not optional: .pth lines run at EVERY interpreter start,
# and add_dll_directory on a missing path raises and breaks the whole env.
$pth = 'import os; os.path.isdir(r"C:\work\runtime") and os.add_dll_directory(r"C:\work\runtime")'

$noBom = New-Object System.Text.UTF8Encoding($false)

foreach ($name in $envs.Keys) {
    $py = "C:\work\envs\$name\Scripts\python.exe"
    if (-not (Test-Path $py)) { Write-Warning "skip $name (no interpreter)"; continue }

    $sp = "C:\work\envs\$name\Lib\site-packages"
    [System.IO.File]::WriteAllText("$sp\zz_work_runtime_dlls.pth", $pth, $noBom)

    & "$env:USERPROFILE\.local\bin\uv.exe" pip install --python $py --quiet ipykernel | Out-Null

    $dir = Join-Path $KERNELS $name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    $spec = [ordered]@{
        argv         = @($py, '-m', 'ipykernel_launcher', '-f', '{connection_file}')
        display_name = $envs[$name]
        language     = 'python'
        metadata     = @{ debugger = $true }
    }
    # ConvertTo-Json escapes the backslashes in the Windows path for us.
    $json = $spec | ConvertTo-Json -Depth 5
    # data file -> NO BOM, or json.load rejects it
    [System.IO.File]::WriteAllText("$dir\kernel.json", $json, $noBom)

    # verify by PARSING it back with Python, not by trusting kernelspec list
    $probe = & $py -c "import json,sys; d=json.load(open(sys.argv[1], encoding='utf-8')); print('OK', d['argv'][0])" "$dir\kernel.json" 2>&1
    "{0,-6} {1}" -f $name, ($probe | Select-Object -Last 1)
}

$env:JUPYTER_DATA_DIR = 'C:\work\jupyter'
& 'C:\work\envs\ds\Scripts\python.exe' -m jupyter kernelspec list
