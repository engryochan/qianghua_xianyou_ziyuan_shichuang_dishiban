#Requires -Version 5.1
<#
.SYNOPSIS
  Plan or build an isolated Windows data-analysis workbench. Default is read-only.
.DESCRIPTION
  Core: SQL/Parquet/Excel, scientific statistics, visualization and Jupyter.
  Extended adds CPU machine learning, SHAP, database clients, automation and quality tools.
  Packages are resolved from HTTPS PyPI as binary wheels. No global package upgrades,
  security exclusions, pagefile changes, reboot, PATH edits or elevation are performed.
  -SetupR uses a separate renv project and HTTPS CRAN binary packages.
  Re-run the same command to resume. Existing unmanaged environments are never adopted.
  requirements.freeze.txt records installed versions; it is NOT a hash-verified lockfile.
.EXAMPLE
  .\Setup_DataStack_v2.ps1 -Profile Extended -PassThru
.EXAMPLE
  .\Setup_DataStack_v2.ps1 -Apply -Profile Extended -WhatIf
.EXAMPLE
  .\Setup_DataStack_v2.ps1 -Apply -Profile Extended -SetupR
.EXAMPLE
  .\Setup_DataStack_v2.ps1 -Apply -InstallTool Python.Python.3.13 -PythonExe C:\Python313\python.exe
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [switch]$Apply,
    [ValidateSet('Core', 'Extended')][string]$Profile = 'Core',
    [string]$WorkRoot = (Join-Path $env:LOCALAPPDATA 'DataWorkbench'),
    [string]$PythonExe,
    [switch]$SetupR,
    [switch]$CompatibilityPolars,
    [ValidateSet('Python.Python.3.13', 'Microsoft.PowerShell', 'Microsoft.VisualStudioCode', 'Posit.Quarto')]
    [string[]]$InstallTool = @(),
    [ValidateRange(60, 7200)][int]$CommandTimeoutSeconds = 1800,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:LogPath = $null
$script:NativeSequence = 0
$script:NativeLogFolder = $null

function Write-RunLog([string]$Message) {
    Write-Host $Message
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value ((Get-Date -Format o) + ' ' + $Message) -Encoding UTF8 }
}
function ConvertTo-NativeArgument([string]$Value) {
    # Windows CommandLineToArgvW quoting, including embedded quotes and final backslashes.
    return '"' + (($Value -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}
function Invoke-Native {
    param([string]$File, [string[]]$Arguments, [int]$TimeoutSeconds = 60, [switch]$AllowFailure)
    $si = New-Object System.Diagnostics.ProcessStartInfo
    $si.FileName = $File
    $si.Arguments = (@($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
    $si.UseShellExecute = $false
    $si.CreateNoWindow = $true
    $si.RedirectStandardOutput = $true
    $si.RedirectStandardError = $true
    $si.EnvironmentVariables['PYTHON_MANAGER_AUTOMATIC_INSTALL'] = 'false'
    $si.EnvironmentVariables['PIP_DISABLE_PIP_VERSION_CHECK'] = '1'
    $si.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
    # Network indexes are explicit. Isolated pip ignores user configuration and env options.
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $si
    try {
        if (-not $process.Start()) { throw "Could not start $File" }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            # Do not kill unrelated processes; package child processes may require manual inspection.
            try { $process.Kill() } catch { }
            $null = $process.WaitForExit(5000)
        }
        $output = if ($stdout.Wait(5000)) { $stdout.Result } else { '[stdout still held by a child process]' }
        $errors = if ($stderr.Wait(5000)) { $stderr.Result } else { '[stderr still held by a child process]' }
        $code = if ($timedOut) { -1 } else { $process.ExitCode }
        if ($script:LogPath) {
            $script:NativeSequence++
            $prefix = Join-Path $script:NativeLogFolder ('{0:D3}' -f $script:NativeSequence)
            Set-Content -LiteralPath ($prefix + '.stdout.txt') -Value $output -Encoding UTF8
            Set-Content -LiteralPath ($prefix + '.stderr.txt') -Value $errors -Encoding UTF8
            Write-RunLog ("Native exit={0}; timeout={1}; {2} {3}; output={4}" -f $code, $timedOut, $File, $si.Arguments, $prefix)
        }
        if (($code -ne 0 -or $timedOut) -and -not $AllowFailure) {
            throw ("Native command failed (exit {0}, timeout {1}): {2}`n{3}`n{4}" -f $code, $timedOut, $File, $output, $errors)
        }
        [pscustomobject]@{ ExitCode = $code; TimedOut = $timedOut; Output = $output; Error = $errors }
    } finally { $process.Dispose() }
}
function Find-Application([string]$Name) {
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $command.Source }
}
function Get-PythonInfo([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    if ($Path -match '\\Microsoft\\WindowsApps\\') { return }
    $code = "import json,sys,struct,platform;print(json.dumps(dict(path=sys.executable,version=platform.python_version(),bits=struct.calcsize('P')*8,implementation=platform.python_implementation(),prefix=sys.prefix,base_prefix=sys.base_prefix)))"
    $result = Invoke-Native -File $Path -Arguments @('-I', '-c', $code) -AllowFailure
    if ($result.ExitCode -eq 0) {
        try { $result.Output.Trim() | ConvertFrom-Json } catch { }
    }
}
function Find-Python {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    if ($PythonExe) { $candidates.Add([IO.Path]::GetFullPath($PythonExe)) }
    else {
        foreach ($name in @('python.exe', 'python3.exe')) {
            foreach ($cmd in @(Get-Command $name -All -CommandType Application -ErrorAction SilentlyContinue)) { $candidates.Add($cmd.Source) }
        }
        $launcher = Find-Application 'py.exe'
        if ($launcher) {
            $listed = Invoke-Native -File $launcher -Arguments @('-0p') -AllowFailure
            foreach ($line in ($listed.Output -split "`r?`n")) {
                if ($line -match '([A-Za-z]:\\.*?python(?:3)?\.exe)\s*$') { $candidates.Add($matches[1]) }
            }
        }
        foreach ($key in @('HKCU:\Software\Python\PythonCore\*\InstallPath', 'HKLM:\Software\Python\PythonCore\*\InstallPath', 'HKLM:\Software\WOW6432Node\Python\PythonCore\*\InstallPath')) {
            foreach ($item in @(Get-Item -Path $key -ErrorAction SilentlyContinue)) {
                $path = $item.GetValue('ExecutablePath')
                if (-not $path) { $path = Join-Path $item.GetValue('') 'python.exe' }
                if ($path) { $candidates.Add($path) }
            }
        }
        foreach ($item in @(Get-ChildItem -Path "$env:LOCALAPPDATA\Programs\Python\Python*\python.exe" -ErrorAction SilentlyContinue)) { $candidates.Add($item.FullName) }
    }
    $found = @(foreach ($candidate in @($candidates | Select-Object -Unique)) {
        $info = Get-PythonInfo $candidate
        if ($info -and $info.bits -eq 64 -and $info.implementation -eq 'CPython' -and [version]$info.version -ge [version]'3.11' -and [version]$info.version -lt [version]'3.15') { $info }
    })
    $found | Sort-Object { [version]$_.version } -Descending | Select-Object -First 1
}
function Find-Rscript {
    $path = Find-Application 'Rscript.exe'
    if ($path) { return $path }
    Get-ChildItem -Path "$env:ProgramFiles\R\R-*\bin\Rscript.exe", "$env:LOCALAPPDATA\Programs\R\R-*\bin\Rscript.exe" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}

if (-not [IO.Path]::IsPathRooted($WorkRoot)) { throw 'WorkRoot must be an absolute local path.' }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot).TrimEnd('\')
if ($WorkRoot -match '^\\\\' -or $WorkRoot -eq [IO.Path]::GetPathRoot($WorkRoot).TrimEnd('\')) { throw 'Choose a local work folder, not a network share or drive root.' }
foreach ($cloud in @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)) {
    if ($cloud -and ($WorkRoot + '\').StartsWith(([IO.Path]::GetFullPath($cloud).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Choose WorkRoot outside OneDrive so binary environments are not synchronized.'
    }
}
$cs = $null; $disk = $null; $gpu = @(); $os = $null
try { $cs = Get-CimInstance Win32_ComputerSystem; $os = Get-CimInstance Win32_OperatingSystem; $gpu = @(Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion) } catch { Write-Warning "Hardware query incomplete: $($_.Exception.Message)" }
$drive = [IO.Path]::GetPathRoot($WorkRoot).TrimEnd('\')
try { $disk = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $drive) } catch { }
$core = @('numpy', 'pandas', 'scipy', 'scikit-learn', 'statsmodels', 'polars', 'duckdb', 'pyarrow', 'matplotlib', 'seaborn', 'plotly', 'sqlalchemy', 'openpyxl', 'xlsxwriter', 'jupyterlab', 'ipykernel')
if ($CompatibilityPolars) { $core = @($core | Where-Object { $_ -ne 'polars' }) + @('polars[rtcompat]') }
$extended = @('xgboost', 'lightgbm', 'shap', 'pyodbc', 'psycopg[binary]', 'pymysql', 'streamlit', 'papermill', 'pywin32', 'joblib', 'pytest', 'ruff')
$packages = $core
if ($Profile -eq 'Extended') { $packages += $extended }
$environment = Join-Path $WorkRoot 'python-env'
$envPython = Join-Path $environment 'Scripts\python.exe'
$marker = Join-Path $environment '.datastack-managed'
$python = Find-Python
$rscript = Find-Rscript
$freeGB = if ($disk) { [math]::Round($disk.FreeSpace / 1GB, 2) } else { $null }
$ramGB = if ($cs) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 2) } else { $null }
$threads = if ($cs) { [math]::Max(1, [math]::Min(8, [int]$cs.NumberOfLogicalProcessors - 2)) } else { 2 }
$plan = [pscustomobject][ordered]@{
    Mode = $(if ($Apply -and -not $WhatIfPreference) { 'Apply' } else { 'Plan' })
    WorkRoot = $WorkRoot; Profile = $Profile; Python = $python; Environment = $environment
    Packages = $packages; PackageIndex = 'https://pypi.org/simple'; BinaryWheelsOnly = $true
    RRequested = [bool]$SetupR; Rscript = $rscript; InstallTool = $InstallTool
    RAMGB = $ramGB; FreeDiskGB = $freeGB; SessionThreads = $threads; GPU = $gpu
    Windows = $(if ($os) { $os.Caption + ' build ' + $os.BuildNumber } else { 'Unknown' })
    Changes = @('Create/resume one managed Python virtual environment', 'Install selected missing packages; no --upgrade', 'pip check + analytics smoke + version freeze')
    Limitations = @('Wheels determine runtime compatibility; failed resolution stops before package installation', 'GPU acceleration is not enabled automatically', 'Freeze records versions but does not contain artifact hashes')
}
Write-Host ($plan | Format-List Mode, WorkRoot, Profile, Python, Environment, RAMGB, FreeDiskGB, SessionThreads, RRequested, Rscript, InstallTool | Out-String)
Write-Host ('Packages: ' + ($packages -join ', '))
if (-not $Apply) { Write-Host 'PLAN ONLY: add -Apply to execute; -Apply -WhatIf previews without writing files.'; if ($PassThru) { $plan }; return }
if (-not $PSCmdlet.ShouldProcess($WorkRoot, 'Create/resume selected isolated analytics environment and run validation')) { if ($PassThru) { $plan }; return }
if ($null -eq $freeGB) { throw 'Cannot verify free disk space; choose an accessible local fixed drive.' }
$minSpace = if ($Profile -eq 'Extended') { 10 } else { 6 }
if ($freeGB -lt $minSpace) { throw "At least $minSpace GiB free disk space is required for this profile." }
if ($ramGB -and $ramGB -lt 4) { Write-Warning 'Less than 4 GiB RAM: use Core and small datasets.' }
foreach ($support in @('DataStack_Smoke.py', 'DataStack_R_Bootstrap.R')) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $support))) { throw "Keep $support beside this script." }
}
$run = Join-Path $WorkRoot ('logs\' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
$null = New-Item -ItemType Directory -Path $run -Force
$script:LogPath = Join-Path $run 'setup.log'
$script:NativeLogFolder = $run
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $run 'plan.json') -Encoding UTF8
$status = [ordered]@{ Status = 'Running'; Started = (Get-Date -Format o); Python = 'NotRun'; R = 'NotRequested'; LogDirectory = $run; Error = $null }
try {
    foreach ($tool in $InstallTool) {
        if ($PSCmdlet.ShouldProcess($tool, 'Install exact WinGet ID with user scope and --no-upgrade; accept its license agreements')) {
            $winget = Find-Application 'winget.exe'
            if (-not $winget) { throw 'winget not found; install the selected tool manually from its official publisher.' }
            $null = Invoke-Native -File $winget -Arguments @('show', '--id', $tool, '--exact', '--source', 'winget', '--accept-source-agreements', '--disable-interactivity') -TimeoutSeconds 120
            $null = Invoke-Native -File $winget -Arguments @('install', '--id', $tool, '--exact', '--source', 'winget', '--scope', 'user', '--no-upgrade', '--silent', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity') -TimeoutSeconds $CommandTimeoutSeconds
        }
    }
    if (-not $python) { $python = Find-Python }
    if (-not $python) { throw 'No compatible installed 64-bit CPython 3.11-3.14 found. Provide -PythonExe or explicitly select -InstallTool Python.Python.3.13.' }
    if (Test-Path -LiteralPath $environment) {
        if (-not (Test-Path -LiteralPath $marker)) { throw 'Existing python-env is unmanaged; select a different WorkRoot. Nothing inside it was changed.' }
        if ((Get-Content -LiteralPath $marker -Raw).Trim() -ne 'DataStack-v2') { throw 'Unrecognized environment marker; stop for manual review.' }
    } else {
        $null = New-Item -ItemType Directory -Path $environment
        Set-Content -LiteralPath $marker -Value 'DataStack-v2' -Encoding ASCII
    }
    if (-not (Test-Path -LiteralPath $envPython)) {
        $null = Invoke-Native -File $python.path -Arguments @('-I', '-m', 'venv', $environment) -TimeoutSeconds 180
    }
    $activePython = Get-PythonInfo $envPython
    if (-not $activePython -or $activePython.bits -ne 64 -or $activePython.prefix -eq $activePython.base_prefix) { throw 'Target Python is not a valid isolated 64-bit virtual environment.' }
    Write-RunLog ("Using isolated Python {0}: {1}" -f $activePython.version, $activePython.path)
    $before = Invoke-Native -File $envPython -Arguments @('-I', '-m', 'pip', '--isolated', 'freeze', '--all')
    Set-Content -LiteralPath (Join-Path $run 'requirements.before.txt') -Value $before.Output -Encoding ASCII
    $requirements = Join-Path $run 'requirements.requested.txt'
    Set-Content -LiteralPath $requirements -Value $packages -Encoding ASCII
    $common = @('-I', '-m', 'pip', '--isolated', 'install', '--index-url', 'https://pypi.org/simple', '--only-binary=:all:', '--no-input', '--disable-pip-version-check', '--timeout', '60', '--retries', '2', '-r', $requirements)
    Write-RunLog 'Resolving binary wheels first. This may download wheel metadata or files; package installation starts only after resolution succeeds.'
    $null = Invoke-Native -File $envPython -Arguments ($common + @('--dry-run', '--report', (Join-Path $run 'pip-resolve.json'))) -TimeoutSeconds $CommandTimeoutSeconds
    $null = Invoke-Native -File $envPython -Arguments ($common + @('--report', (Join-Path $run 'pip-install.json'))) -TimeoutSeconds $CommandTimeoutSeconds
    $null = Invoke-Native -File $envPython -Arguments @('-I', '-m', 'pip', '--isolated', 'check') -TimeoutSeconds 120
    $freeze = Invoke-Native -File $envPython -Arguments @('-I', '-m', 'pip', '--isolated', 'freeze', '--all')
    Set-Content -LiteralPath (Join-Path $run 'requirements.freeze.txt') -Value $freeze.Output -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $WorkRoot 'requirements.freeze.txt') -Value $freeze.Output -Encoding ASCII
    $smokeArgs = @('-I', '-X', 'utf8', (Join-Path $PSScriptRoot 'DataStack_Smoke.py'), '--output', (Join-Path $run 'smoke'))
    if ($Profile -eq 'Extended') { $smokeArgs += '--extended' }
    $smoke = Invoke-Native -File $envPython -Arguments $smokeArgs -TimeoutSeconds 300
    Write-RunLog $smoke.Output.Trim()
    $status.Python = 'Passed'
    $escapedPython = $envPython.Replace("'", "''")
    $launcher = "# Session-only thread limits. No machine/user variables are changed.`r`n" +
        "`$env:OMP_NUM_THREADS='$threads'`r`n`$env:OPENBLAS_NUM_THREADS='$threads'`r`n`$env:MKL_NUM_THREADS='$threads'`r`n`$env:POLARS_MAX_THREADS='$threads'`r`n" +
        "& '$escapedPython' -m jupyterlab --no-browser --ServerApp.ip=127.0.0.1`r`n"
    Set-Content -LiteralPath (Join-Path $WorkRoot 'Start-Jupyter.ps1') -Value $launcher -Encoding UTF8
    if ($SetupR) {
        if (-not $rscript) { throw 'Rscript was not found. Python passed; R was not installed or globally upgraded.' }
        $status.R = 'Running'
        $rResult = Invoke-Native -File $rscript -Arguments @('--vanilla', (Join-Path $PSScriptRoot 'DataStack_R_Bootstrap.R'), $WorkRoot, $run) -TimeoutSeconds $CommandTimeoutSeconds
        Write-RunLog $rResult.Output.Trim()
        $status.R = 'Passed'
    }
    $status.Status = 'Passed'
    Write-RunLog ('PASSED. Interpreter: ' + $envPython)
    Write-RunLog ('Launch Jupyter when needed: & ''' + (Join-Path $WorkRoot 'Start-Jupyter.ps1') + '''')
} catch {
    $status.Status = 'Failed'
    $status.Error = $_.Exception.Message
    Write-RunLog ('FAILED: ' + $_.Exception.Message)
    throw
} finally {
    $status['Finished'] = Get-Date -Format o
    $status | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'status.json') -Encoding UTF8
}
if ($PassThru) { [pscustomobject]$status }
