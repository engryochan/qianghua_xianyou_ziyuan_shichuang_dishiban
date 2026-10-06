$env:Path = "$env:USERPROFILE\.local\bin;$env:Path"
$env:UV_PYTHON_INSTALL_DIR = 'C:\work\pythons'

# One satellite per mutually-incompatible group. These 16 packages cannot coexist
# with the core set (see reports/2026-10-06 for each pair's proof), so they get
# their own environments. uv hardlinks from its cache, so the marginal disk cost
# of an extra env is small.
$groups = [ordered]@{
  'fin'   = @('openbb','openbb-platform-api','pyportfolioopt','s3fs')      # tight pin webs
  'nlp'   = @('flair','transformer-smaller-training-vocab')                # needs transformers<5
  'mlops' = @('evidently','nannyml','feast')                               # needs plotly<6
  'xai'   = @('dalex')                                                     # needs plotly>=6
  'rl'    = @('tianshou','gluonts','gevent')                               # toolz<1 / cffi>=2.1.1
}

foreach($g in $groups.Keys){
  $venv = "C:\work\envs\$g"
  "=== $(Get-Date -Format s) [$g] $($groups[$g] -join ', ') ==="
  uv venv --python 3.13 $venv 2>&1 | Select-Object -Last 1
  uv pip install --python "$venv\Scripts\python.exe" @($groups[$g]) 2>&1 | Select-Object -Last 4
  "[$g] uv exit=$LASTEXITCODE"
}
"=== $(Get-Date -Format s) satellites done ==="
