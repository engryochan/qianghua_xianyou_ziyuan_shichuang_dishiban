#Requires -Version 5.1
<#
.SYNOPSIS
Start the verified analysis environment with session-only CPU settings.
.EXAMPLE
.\Start_Analytics.ps1 -Mode Jupyter
.EXAMPLE
.\Start_Analytics.ps1 -Mode LargeFile -InputPath C:\work\data\sales.csv -GroupBy category -ValueColumn amount
#>
[CmdletBinding()]
param(
    [ValidateSet('Check','Jupyter','LargeFile')][string]$Mode='Check',
    [string]$PythonExe='C:\work\projects\lab\.venv\Scripts\python.exe',
    [string]$Project='C:\work\projects\lab',
    [ValidateRange(1,64)][int]$Threads=6,
    [ValidateRange(1,64)][int]$MemoryGB=6,
    [string]$InputPath,
    [string]$GroupBy,
    [string]$ValueColumn,
    [string]$OutputDirectory=(Join-Path $PSScriptRoot ('reports\run-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')))
)
$ErrorActionPreference='Stop'
if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) { throw "Missing interpreter: $PythonExe" }
$saved=@{}
try {
    foreach ($name in @('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS','NUMEXPR_NUM_THREADS','POLARS_MAX_THREADS')) {
        $saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')
        [Environment]::SetEnvironmentVariable($name,"$Threads",'Process')
    }
    switch ($Mode) {
        'Check' {
            & $PythonExe -I (Join-Path $PSScriptRoot 'DataStack_Smoke.py') --output $OutputDirectory
            if ($LASTEXITCODE -ne 0) { throw 'Analysis smoke test failed.' }
        }
        'Jupyter' {
            if (-not (Test-Path -LiteralPath $Project -PathType Container)) { throw "Missing project: $Project" }
            # Keep Jupyter's authentication enabled and bind only to localhost.
            & $PythonExe -I -m jupyterlab "--ServerApp.root_dir=$Project" --ServerApp.ip=127.0.0.1
            if ($LASTEXITCODE -ne 0) { throw 'Jupyter exited with an error.' }
        }
        'LargeFile' {
            if (-not $InputPath) { throw 'LargeFile requires -InputPath.' }
            & (Join-Path $PSScriptRoot 'Analyze_LargeFile.ps1') -InputPath $InputPath -GroupBy $GroupBy -ValueColumn $ValueColumn -PythonExe $PythonExe -Threads $Threads -MemoryGB $MemoryGB -OutputDirectory $OutputDirectory
        }
    }
} finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
}
