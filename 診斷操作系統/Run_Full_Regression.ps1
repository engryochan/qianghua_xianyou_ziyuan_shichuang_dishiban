$ErrorActionPreference = 'Continue'
$repo = 'C:\Users\PPCCpcpc\Documents\GitHub\qianghua_xianyou_ziyuan_shichuang_dishiban'
$env:Path = "C:\work\tools\bin;C:\work\R\R-4.6.1\bin\x64;$env:USERPROFILE\.local\bin;$env:Path"
$env:RETICULATE_PYTHON = 'C:/work/envs/ds/Scripts/python.exe'
$env:JUPYTER_DATA_DIR  = 'C:\work\jupyter'
$fail = 0

"########## 1. Python core ##########"
& 'C:\work\envs\ds\Scripts\python.exe' "$repo\診斷操作系統\Accept_Python_Stack.py" 2>&1 | Select-String -Pattern '^(PASS|\w.*(PASS|FAIL))' | Select-Object -Last 17
if ($LASTEXITCODE -ne 0) { $fail++ }

"########## 2. R core ##########"
& 'C:\work\R\R-4.6.1\bin\x64\Rscript.exe' "$repo\診斷操作系統\Accept_R_Stack.R" 2>&1 | Select-String -Pattern 'PASS|FAIL' | Select-Object -Last 12
if ($LASTEXITCODE -ne 0) { $fail++ }

"########## 3. satellites: imports + constraint guards ##########"
foreach ($g in 'fin','nlp','mlops','xai','rl') {
  & "C:\work\envs\$g\Scripts\python.exe" "$repo\診斷操作系統\Accept_Satellites.py" $g 2>&1 | Where-Object { $_ -match '^(---|  )' }
  if ($LASTEXITCODE -ne 0) { $fail++ }
}

"########## 4. satellites: domain computation ##########"
foreach ($g in 'fin','nlp','mlops','xai','rl') {
  & "C:\work\envs\$g\Scripts\python.exe" "$repo\診斷操作系統\Accept_Satellites_Domain.py" $g 2>&1 | Where-Object { $_ -match '^(---|  )' }
  if ($LASTEXITCODE -ne 0) { $fail++ }
}

"########## 5. flair NER (real model) ##########"
& 'C:\work\envs\nlp\Scripts\python.exe' "$repo\診斷操作系統\Accept_Flair_NER.py" 2>&1 | Select-String -Pattern 'entities|RESULT'
if ($LASTEXITCODE -ne 0) { $fail++ }

"########## 6. CmdStan (compile + fit) ##########"
$env:RTOOLS45_HOME = 'C:\work\rtools45'
$env:Path = "C:\work\rtools45\usr\bin;$env:Path"
& 'C:\work\R\R-4.6.1\bin\x64\Rscript.exe' "$repo\診斷操作系統\Accept_CmdStan.R" 2>&1 | Select-String -Pattern 'posterior|rhat|RESULT'
if ($LASTEXITCODE -ne 0) { $fail++ }

"########## 7. Quarto render of the repo template ##########"
Copy-Item "$repo\templates\r-python-template.qmd" 'C:\work\projects\lab\regress.qmd' -Force
Set-Location 'C:\work\projects\lab'
& 'C:\work\tools\bin\quarto.cmd' render regress.qmd --to html 2>&1 | Select-String -Pattern 'Output created|Error'
if (Test-Path 'C:\work\projects\lab\regress.html') {
  (Select-String -Path 'C:\work\projects\lab\regress.html' -Pattern 'python 3\.13\.\d+ \| polars').Matches.Value | Select-Object -First 1
} else { "render FAILED"; $fail++ }

"########## 8. Jupyter kernels ##########"
# kernelspec list only enumerates DIRECTORIES: it shows a kernel whose JSON is
# malformed. So parse every kernel.json and probe its interpreter.
& 'C:\work\envs\ds\Scripts\python.exe' "$repo\診斷操作系統\Accept_Jupyter_Kernels.py" 2>&1 | Where-Object { $_ -match '^  ' }
if ($LASTEXITCODE -ne 0) { $fail++ }

"`n################ REGRESSION FAILURES: $fail ################"
