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
# 启用 PowerShell 高级脚本参数绑定及所列功能。
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
# 声明脚本或函数接受的参数及默认值。
param(
    # 声明参数 $Apply的类型、默认值或校验规则。
    [switch]$Apply,
    # 声明参数 $Profile的类型、默认值或校验规则。
    [ValidateSet('Core', 'Extended')][string]$Profile = 'Core',
    # 声明参数 $WorkRoot的类型、默认值或校验规则。
    [string]$WorkRoot = (Join-Path $env:LOCALAPPDATA 'DataWorkbench'),
    # 声明参数 $PythonExe的类型、默认值或校验规则。
    [string]$PythonExe,
    # 声明参数 $SetupR的类型、默认值或校验规则。
    [switch]$SetupR,
    # 声明参数 $CompatibilityPolars的类型、默认值或校验规则。
    [switch]$CompatibilityPolars,
    # 声明参数的类型、默认值或校验规则。
    [ValidateSet('Python.Python.3.13', 'Microsoft.PowerShell', 'Microsoft.VisualStudioCode', 'Posit.Quarto')]
    # 声明参数 $InstallTool的类型、默认值或校验规则。
    [string[]]$InstallTool = @(),
    # 声明参数 $CommandTimeoutSeconds的类型、默认值或校验规则。
    [ValidateRange(60, 7200)][int]$CommandTimeoutSeconds = 1800,
    # 声明参数 $PassThru的类型、默认值或校验规则。
    [switch]$PassThru
# 结束此处的代码块、参数列表或集合定义。
)

# 处理 Set-StrictMode 所指定的操作或当前表达式的后续部分。
Set-StrictMode -Version 2.0
# 设置本脚本遇到 PowerShell 错误时的处理方式。
$ErrorActionPreference = 'Stop'
# 计算本行表达式并设置 $script:LogPath，供后续步骤使用。
$script:LogPath = $null
# 计算本行表达式并设置 $script:NativeSequence，供后续步骤使用。
$script:NativeSequence = 0
# 计算本行表达式并设置 $script:NativeLogFolder，供后续步骤使用。
$script:NativeLogFolder = $null

# 定义 Write-RunLog，封装此函数内的操作。
function Write-RunLog([string]$Message) {
    # 向终端显示提示或结果。
    Write-Host $Message
    # 检查本行条件；满足时执行对应分支。
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value ((Get-Date -Format o) + ' ' + $Message) -Encoding UTF8 }
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 ConvertTo-NativeArgument，封装此函数内的操作。
function ConvertTo-NativeArgument([string]$Value) {
    # Windows CommandLineToArgvW quoting, including embedded quotes and final backslashes.
    # 返回本行结果并结束当前函数。
    return '"' + (($Value -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Invoke-Native，封装此函数内的操作。
function Invoke-Native {
    # 声明脚本或函数接受的参数及默认值。
    param([string]$File, [string[]]$Arguments, [int]$TimeoutSeconds = 60, [switch]$AllowFailure)
    # 创建指定类型的对象，并保存到 $si。
    $si = New-Object System.Diagnostics.ProcessStartInfo
    # 计算本行表达式并设置 $si.FileName，供后续步骤使用。
    $si.FileName = $File
    # 逐项处理管道传入的记录，并保存到 $si.Arguments。
    $si.Arguments = (@($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
    # 计算本行表达式并设置 $si.UseShellExecute，供后续步骤使用。
    $si.UseShellExecute = $false
    # 计算本行表达式并设置 $si.CreateNoWindow，供后续步骤使用。
    $si.CreateNoWindow = $true
    # 计算本行表达式并设置 $si.RedirectStandardOutput，供后续步骤使用。
    $si.RedirectStandardOutput = $true
    # 计算本行表达式并设置 $si.RedirectStandardError，供后续步骤使用。
    $si.RedirectStandardError = $true
    # 构造或计算 $si.EnvironmentVariables['PYTHON_MANAGER_AUTOMATIC_INSTALL']，保存本行指定的集合或索引结果。
    $si.EnvironmentVariables['PYTHON_MANAGER_AUTOMATIC_INSTALL'] = 'false'
    # 准备或执行 Python 套件管理操作，并保存到 $si.EnvironmentVariables['PIP_DISABLE_PIP_VERSION_CHECK']。
    $si.EnvironmentVariables['PIP_DISABLE_PIP_VERSION_CHECK'] = '1'
    # 构造或计算 $si.EnvironmentVariables['PYTHONIOENCODING']，保存本行指定的集合或索引结果。
    $si.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
    # Network indexes are explicit. Isolated pip ignores user configuration and env options.
    # 创建指定类型的对象，并保存到 $process。
    $process = New-Object System.Diagnostics.Process
    # 计算本行表达式并设置 $process.StartInfo，供后续步骤使用。
    $process.StartInfo = $si
    # 开始受异常处理保护的操作。
    try {
        # 检查本行条件；满足时执行对应分支。
        if (-not $process.Start()) { throw "Could not start $File" }
        # 构造或计算 $stdout，保存本行指定的集合或索引结果。
        $stdout = $process.StandardOutput.ReadToEndAsync()
        # 构造或计算 $stderr，保存本行指定的集合或索引结果。
        $stderr = $process.StandardError.ReadToEndAsync()
        # 等待子进程结束或到达指定时限，并保存到 $timedOut。
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        # 检查本行条件；满足时执行对应分支。
        if ($timedOut) {
            # Do not kill unrelated processes; package child processes may require manual inspection.
            # 开始受异常处理保护的操作。
            try { $process.Kill() } catch { }
            # 等待子进程结束或到达指定时限；将不需要的返回值丢弃。
            $null = $process.WaitForExit(5000)
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 构造或计算 $output，保存本行指定的集合或索引结果。
        $output = if ($stdout.Wait(5000)) { $stdout.Result } else { '[stdout still held by a child process]' }
        # 构造或计算 $errors，保存本行指定的集合或索引结果。
        $errors = if ($stderr.Wait(5000)) { $stderr.Result } else { '[stderr still held by a child process]' }
        # 将上一操作的退出状态记录到 $code。
        $code = if ($timedOut) { -1 } else { $process.ExitCode }
        # 检查本行条件；满足时执行对应分支。
        if ($script:LogPath) {
            # 处理 $script:NativeSequence++ 所指定的操作或当前表达式的后续部分。
            $script:NativeSequence++
            # 组合父目录与子路径，并保存到 $prefix。
            $prefix = Join-Path $script:NativeLogFolder ('{0:D3}' -f $script:NativeSequence)
            # 将内容写入目标文件。
            Set-Content -LiteralPath ($prefix + '.stdout.txt') -Value $output -Encoding UTF8
            # 将内容写入目标文件。
            Set-Content -LiteralPath ($prefix + '.stderr.txt') -Value $errors -Encoding UTF8
            # 处理 Write-RunLog 所指定的操作或当前表达式的后续部分。
            Write-RunLog ("Native exit={0}; timeout={1}; {2} {3}; output={4}" -f $code, $timedOut, $File, $si.Arguments, $prefix)
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 检查本行条件；满足时执行对应分支。
        if (($code -ne 0 -or $timedOut) -and -not $AllowFailure) {
            # 报告本行指定的错误并中止当前执行路径。
            throw ("Native command failed (exit {0}, timeout {1}): {2}`n{3}`n{4}" -f $code, $timedOut, $File, $output, $errors)
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 把本行列出的字段组成结构化记录。
        [pscustomobject]@{ ExitCode = $code; TimedOut = $timedOut; Output = $output; Error = $errors }
    # 结束上一代码块并进入必定执行的资源清理。
    } finally { $process.Dispose() }
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Find-Application，封装此函数内的操作。
function Find-Application([string]$Name) {
    # 查找当前环境可用的命令及其位置；选取记录中的指定字段或条目，并保存到 $command。
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    # 检查本行条件；满足时执行对应分支。
    if ($command) { $command.Source }
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Get-PythonInfo，封装此函数内的操作。
function Get-PythonInfo([string]$Path) {
    # 检查本行条件；满足时执行对应分支。
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    # 检查本行条件；满足时执行对应分支。
    if ($Path -match '\\Microsoft\\WindowsApps\\') { return }
    # 将结果序列化为 JSON 文本，并保存到 $code。
    $code = "import json,sys,struct,platform;print(json.dumps(dict(path=sys.executable,version=platform.python_version(),bits=struct.calcsize('P')*8,implementation=platform.python_implementation(),prefix=sys.prefix,base_prefix=sys.base_prefix)))"
    # 构造或计算 $result，保存本行指定的集合或索引结果。
    $result = Invoke-Native -File $Path -Arguments @('-I', '-c', $code) -AllowFailure
    # 检查本行条件；满足时执行对应分支。
    if ($result.ExitCode -eq 0) {
        # 开始受异常处理保护的操作。
        try { $result.Output.Trim() | ConvertFrom-Json } catch { }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Find-Python，封装此函数内的操作。
function Find-Python {
    # 创建指定类型的对象，并保存到 $candidates。
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    # 检查本行条件；满足时执行对应分支。
    if ($PythonExe) { $candidates.Add([IO.Path]::GetFullPath($PythonExe)) }
    # 当前述条件不成立时执行此分支。
    else {
        # 按本行的迭代范围或条件重复执行循环体。
        foreach ($name in @('python.exe', 'python3.exe')) {
            # 按本行的迭代范围或条件重复执行循环体。
            foreach ($cmd in @(Get-Command $name -All -CommandType Application -ErrorAction SilentlyContinue)) { $candidates.Add($cmd.Source) }
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 计算本行表达式并设置 $launcher，供后续步骤使用。
        $launcher = Find-Application 'py.exe'
        # 检查本行条件；满足时执行对应分支。
        if ($launcher) {
            # 构造或计算 $listed，保存本行指定的集合或索引结果。
            $listed = Invoke-Native -File $launcher -Arguments @('-0p') -AllowFailure
            # 按本行的迭代范围或条件重复执行循环体。
            foreach ($line in ($listed.Output -split "`r?`n")) {
                # 检查本行条件；满足时执行对应分支。
                if ($line -match '([A-Za-z]:\\.*?python(?:3)?\.exe)\s*$') { $candidates.Add($matches[1]) }
            # 结束此处的代码块、参数列表或集合定义。
            }
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 按本行的迭代范围或条件重复执行循环体。
        foreach ($key in @('HKCU:\Software\Python\PythonCore\*\InstallPath', 'HKLM:\Software\Python\PythonCore\*\InstallPath', 'HKLM:\Software\WOW6432Node\Python\PythonCore\*\InstallPath')) {
            # 按本行的迭代范围或条件重复执行循环体。
            foreach ($item in @(Get-Item -Path $key -ErrorAction SilentlyContinue)) {
                # 计算本行表达式并设置 $path，供后续步骤使用。
                $path = $item.GetValue('ExecutablePath')
                # 检查本行条件；满足时执行对应分支。
                if (-not $path) { $path = Join-Path $item.GetValue('') 'python.exe' }
                # 检查本行条件；满足时执行对应分支。
                if ($path) { $candidates.Add($path) }
            # 结束此处的代码块、参数列表或集合定义。
            }
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 按本行的迭代范围或条件重复执行循环体。
        foreach ($item in @(Get-ChildItem -Path "$env:LOCALAPPDATA\Programs\Python\Python*\python.exe" -ErrorAction SilentlyContinue)) { $candidates.Add($item.FullName) }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 选取记录中的指定字段或条目，并保存到 $found。
    $found = @(foreach ($candidate in @($candidates | Select-Object -Unique)) {
        # 计算本行表达式并设置 $info，供后续步骤使用。
        $info = Get-PythonInfo $candidate
        # 检查本行条件；满足时执行对应分支。
        if ($info -and $info.bits -eq 64 -and $info.implementation -eq 'CPython' -and [version]$info.version -ge [version]'3.11' -and [version]$info.version -lt [version]'3.15') { $info }
    # 结束此处的代码块、参数列表或集合定义。
    })
    # 选取记录中的指定字段或条目；按指定属性排序输入记录。
    $found | Sort-Object { [version]$_.version } -Descending | Select-Object -First 1
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Find-Rscript，封装此函数内的操作。
function Find-Rscript {
    # 计算本行表达式并设置 $path，供后续步骤使用。
    $path = Find-Application 'Rscript.exe'
    # 检查本行条件；满足时执行对应分支。
    if ($path) { return $path }
    # 枚举指定位置的文件、目录或注册表项。
    Get-ChildItem -Path "$env:ProgramFiles\R\R-*\bin\Rscript.exe", "$env:LOCALAPPDATA\Programs\R\R-*\bin\Rscript.exe" -ErrorAction SilentlyContinue |
        # 选取记录中的指定字段或条目；按指定属性排序输入记录。
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
# 结束此处的代码块、参数列表或集合定义。
}

# 检查本行条件；满足时执行对应分支。
if (-not [IO.Path]::IsPathRooted($WorkRoot)) { throw 'WorkRoot must be an absolute local path.' }
# 构造或计算 $WorkRoot，保存本行指定的集合或索引结果。
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot).TrimEnd('\')
# 检查本行条件；满足时执行对应分支。
if ($WorkRoot -match '^\\\\' -or $WorkRoot -eq [IO.Path]::GetPathRoot($WorkRoot).TrimEnd('\')) { throw 'Choose a local work folder, not a network share or drive root.' }
# 按本行的迭代范围或条件重复执行循环体。
foreach ($cloud in @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)) {
    # 检查本行条件；满足时执行对应分支。
    if ($cloud -and ($WorkRoot + '\').StartsWith(([IO.Path]::GetFullPath($cloud).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) {
        # 报告本行指定的错误并中止当前执行路径。
        throw 'Choose WorkRoot outside OneDrive so binary environments are not synchronized.'
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 构造或计算 $cs，保存本行指定的集合或索引结果。
$cs = $null; $disk = $null; $gpu = @(); $os = $null
# 开始受异常处理保护的操作。
try { $cs = Get-CimInstance Win32_ComputerSystem; $os = Get-CimInstance Win32_OperatingSystem; $gpu = @(Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion) } catch { Write-Warning "Hardware query incomplete: $($_.Exception.Message)" }
# 构造或计算 $drive，保存本行指定的集合或索引结果。
$drive = [IO.Path]::GetPathRoot($WorkRoot).TrimEnd('\')
# 开始受异常处理保护的操作。
try { $disk = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $drive) } catch { }
# 构造或计算 $core，保存本行指定的集合或索引结果。
$core = @('numpy', 'pandas', 'scipy', 'scikit-learn', 'statsmodels', 'polars', 'duckdb', 'pyarrow', 'matplotlib', 'seaborn', 'plotly', 'sqlalchemy', 'openpyxl', 'xlsxwriter', 'jupyterlab', 'ipykernel')
# 检查本行条件；满足时执行对应分支。
if ($CompatibilityPolars) { $core = @($core | Where-Object { $_ -ne 'polars' }) + @('polars[rtcompat]') }
# 构造或计算 $extended，保存本行指定的集合或索引结果。
$extended = @('xgboost', 'lightgbm', 'shap', 'pyodbc', 'psycopg[binary]', 'pymysql', 'streamlit', 'papermill', 'pywin32', 'joblib', 'pytest', 'ruff')
# 计算本行表达式并设置 $packages，供后续步骤使用。
$packages = $core
# 检查本行条件；满足时执行对应分支。
if ($Profile -eq 'Extended') { $packages += $extended }
# 组合父目录与子路径，并保存到 $environment。
$environment = Join-Path $WorkRoot 'python-env'
# 组合父目录与子路径，并保存到 $envPython。
$envPython = Join-Path $environment 'Scripts\python.exe'
# 组合父目录与子路径，并保存到 $marker。
$marker = Join-Path $environment '.datastack-managed'
# 计算本行表达式并设置 $python，供后续步骤使用。
$python = Find-Python
# 计算本行表达式并设置 $rscript，供后续步骤使用。
$rscript = Find-Rscript
# 构造或计算 $freeGB，保存本行指定的集合或索引结果。
$freeGB = if ($disk) { [math]::Round($disk.FreeSpace / 1GB, 2) } else { $null }
# 构造或计算 $ramGB，保存本行指定的集合或索引结果。
$ramGB = if ($cs) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 2) } else { $null }
# 构造或计算 $threads，保存本行指定的集合或索引结果。
$threads = if ($cs) { [math]::Max(1, [math]::Min(8, [int]$cs.NumberOfLogicalProcessors - 2)) } else { 2 }
# 构造或计算 $plan，保存本行指定的集合或索引结果。
$plan = [pscustomobject][ordered]@{
    # 计算本行表达式并设置 Mode，供后续步骤使用。
    Mode = $(if ($Apply -and -not $WhatIfPreference) { 'Apply' } else { 'Plan' })
    # 计算本行表达式并设置 WorkRoot，供后续步骤使用。
    WorkRoot = $WorkRoot; Profile = $Profile; Python = $python; Environment = $environment
    # 计算本行表达式并设置 Packages，供后续步骤使用。
    Packages = $packages; PackageIndex = 'https://pypi.org/simple'; BinaryWheelsOnly = $true
    # 构造或计算 RRequested，保存本行指定的集合或索引结果。
    RRequested = [bool]$SetupR; Rscript = $rscript; InstallTool = $InstallTool
    # 计算本行表达式并设置 RAMGB，供后续步骤使用。
    RAMGB = $ramGB; FreeDiskGB = $freeGB; SessionThreads = $threads; GPU = $gpu
    # 计算本行表达式并设置 Windows，供后续步骤使用。
    Windows = $(if ($os) { $os.Caption + ' build ' + $os.BuildNumber } else { 'Unknown' })
    # 准备或执行 Python 套件管理操作，并保存到 Changes。
    Changes = @('Create/resume one managed Python virtual environment', 'Install selected missing packages; no --upgrade', 'pip check + analytics smoke + version freeze')
    # 构造或计算 Limitations，保存本行指定的集合或索引结果。
    Limitations = @('Wheels determine runtime compatibility; failed resolution stops before package installation', 'GPU acceleration is not enabled automatically', 'Freeze records versions but does not contain artifact hashes')
# 结束此处的代码块、参数列表或集合定义。
}
# 把结果转换为文本；向终端显示提示或结果。
Write-Host ($plan | Format-List Mode, WorkRoot, Profile, Python, Environment, RAMGB, FreeDiskGB, SessionThreads, RRequested, Rscript, InstallTool | Out-String)
# 向终端显示提示或结果。
Write-Host ('Packages: ' + ($packages -join ', '))
# 检查本行条件；满足时执行对应分支。
if (-not $Apply) { Write-Host 'PLAN ONLY: add -Apply to execute; -Apply -WhatIf previews without writing files.'; if ($PassThru) { $plan }; return }
# 检查本行条件；满足时执行对应分支。
if (-not $PSCmdlet.ShouldProcess($WorkRoot, 'Create/resume selected isolated analytics environment and run validation')) { if ($PassThru) { $plan }; return }
# 检查本行条件；满足时执行对应分支。
if ($null -eq $freeGB) { throw 'Cannot verify free disk space; choose an accessible local fixed drive.' }
# 计算本行表达式并设置 $minSpace，供后续步骤使用。
$minSpace = if ($Profile -eq 'Extended') { 10 } else { 6 }
# 检查本行条件；满足时执行对应分支。
if ($freeGB -lt $minSpace) { throw "At least $minSpace GiB free disk space is required for this profile." }
# 检查本行条件；满足时执行对应分支。
if ($ramGB -and $ramGB -lt 4) { Write-Warning 'Less than 4 GiB RAM: use Core and small datasets.' }
# 按本行的迭代范围或条件重复执行循环体。
foreach ($support in @('DataStack_Smoke.py', 'DataStack_R_Bootstrap.R')) {
    # 检查本行条件；满足时执行对应分支。
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $support))) { throw "Keep $support beside this script." }
# 结束此处的代码块、参数列表或集合定义。
}
# 生成当前时间或格式化时间戳；组合父目录与子路径，并保存到 $run。
$run = Join-Path $WorkRoot ('logs\' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
# 创建指定目录、文件或配置项；将不需要的返回值丢弃。
$null = New-Item -ItemType Directory -Path $run -Force
# 组合父目录与子路径，并保存到 $script:LogPath。
$script:LogPath = Join-Path $run 'setup.log'
# 计算本行表达式并设置 $script:NativeLogFolder，供后续步骤使用。
$script:NativeLogFolder = $run
# 组合父目录与子路径；将内容写入目标文件；把对象序列化为 JSON。
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $run 'plan.json') -Encoding UTF8
# 生成当前时间或格式化时间戳，并保存到 $status。
$status = [ordered]@{ Status = 'Running'; Started = (Get-Date -Format o); Python = 'NotRun'; R = 'NotRequested'; LogDirectory = $run; Error = $null }
# 开始受异常处理保护的操作。
try {
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($tool in $InstallTool) {
        # 检查本行条件；满足时执行对应分支。
        if ($PSCmdlet.ShouldProcess($tool, 'Install exact WinGet ID with user scope and --no-upgrade; accept its license agreements')) {
            # 调用 WinGet 执行本行指定的软件管理操作，并保存到 $winget。
            $winget = Find-Application 'winget.exe'
            # 检查本行条件；满足时执行对应分支。
            if (-not $winget) { throw 'winget not found; install the selected tool manually from its official publisher.' }
            # 调用 WinGet 执行本行指定的软件管理操作；将不需要的返回值丢弃。
            $null = Invoke-Native -File $winget -Arguments @('show', '--id', $tool, '--exact', '--source', 'winget', '--accept-source-agreements', '--disable-interactivity') -TimeoutSeconds 120
            # 调用 WinGet 执行本行指定的软件管理操作；将不需要的返回值丢弃。
            $null = Invoke-Native -File $winget -Arguments @('install', '--id', $tool, '--exact', '--source', 'winget', '--scope', 'user', '--no-upgrade', '--silent', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity') -TimeoutSeconds $CommandTimeoutSeconds
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 检查本行条件；满足时执行对应分支。
    if (-not $python) { $python = Find-Python }
    # 检查本行条件；满足时执行对应分支。
    if (-not $python) { throw 'No compatible installed 64-bit CPython 3.11-3.14 found. Provide -PythonExe or explicitly select -InstallTool Python.Python.3.13.' }
    # 检查本行条件；满足时执行对应分支。
    if (Test-Path -LiteralPath $environment) {
        # 检查本行条件；满足时执行对应分支。
        if (-not (Test-Path -LiteralPath $marker)) { throw 'Existing python-env is unmanaged; select a different WorkRoot. Nothing inside it was changed.' }
        # 检查本行条件；满足时执行对应分支。
        if ((Get-Content -LiteralPath $marker -Raw).Trim() -ne 'DataStack-v2') { throw 'Unrecognized environment marker; stop for manual review.' }
    # 结束上一代码块并进入另一条件分支。
    } else {
        # 创建指定目录、文件或配置项；将不需要的返回值丢弃。
        $null = New-Item -ItemType Directory -Path $environment
        # 将内容写入目标文件。
        Set-Content -LiteralPath $marker -Value 'DataStack-v2' -Encoding ASCII
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 检查本行条件；满足时执行对应分支。
    if (-not (Test-Path -LiteralPath $envPython)) {
        # 处理 Invoke-Native 所指定的操作或当前表达式的后续部分；将不需要的返回值丢弃。
        $null = Invoke-Native -File $python.path -Arguments @('-I', '-m', 'venv', $environment) -TimeoutSeconds 180
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 计算本行表达式并设置 $activePython，供后续步骤使用。
    $activePython = Get-PythonInfo $envPython
    # 检查本行条件；满足时执行对应分支。
    if (-not $activePython -or $activePython.bits -ne 64 -or $activePython.prefix -eq $activePython.base_prefix) { throw 'Target Python is not a valid isolated 64-bit virtual environment.' }
    # 处理 Write-RunLog 所指定的操作或当前表达式的后续部分。
    Write-RunLog ("Using isolated Python {0}: {1}" -f $activePython.version, $activePython.path)
    # 准备或执行 Python 套件管理操作，并保存到 $before。
    $before = Invoke-Native -File $envPython -Arguments @('-I', '-m', 'pip', '--isolated', 'freeze', '--all')
    # 组合父目录与子路径；将内容写入目标文件。
    Set-Content -LiteralPath (Join-Path $run 'requirements.before.txt') -Value $before.Output -Encoding ASCII
    # 组合父目录与子路径，并保存到 $requirements。
    $requirements = Join-Path $run 'requirements.requested.txt'
    # 将内容写入目标文件。
    Set-Content -LiteralPath $requirements -Value $packages -Encoding ASCII
    # 准备或执行 Python 套件管理操作，并保存到 $common。
    $common = @('-I', '-m', 'pip', '--isolated', 'install', '--index-url', 'https://pypi.org/simple', '--only-binary=:all:', '--no-input', '--disable-pip-version-check', '--timeout', '60', '--retries', '2', '-r', $requirements)
    # 处理 Write-RunLog 所指定的操作或当前表达式的后续部分。
    Write-RunLog 'Resolving binary wheels first. This may download wheel metadata or files; package installation starts only after resolution succeeds.'
    # 组合父目录与子路径；准备或执行 Python 套件管理操作；将不需要的返回值丢弃。
    $null = Invoke-Native -File $envPython -Arguments ($common + @('--dry-run', '--report', (Join-Path $run 'pip-resolve.json'))) -TimeoutSeconds $CommandTimeoutSeconds
    # 组合父目录与子路径；准备或执行 Python 套件管理操作；将不需要的返回值丢弃。
    $null = Invoke-Native -File $envPython -Arguments ($common + @('--report', (Join-Path $run 'pip-install.json'))) -TimeoutSeconds $CommandTimeoutSeconds
    # 准备或执行 Python 套件管理操作；将不需要的返回值丢弃。
    $null = Invoke-Native -File $envPython -Arguments @('-I', '-m', 'pip', '--isolated', 'check') -TimeoutSeconds 120
    # 准备或执行 Python 套件管理操作，并保存到 $freeze。
    $freeze = Invoke-Native -File $envPython -Arguments @('-I', '-m', 'pip', '--isolated', 'freeze', '--all')
    # 组合父目录与子路径；将内容写入目标文件。
    Set-Content -LiteralPath (Join-Path $run 'requirements.freeze.txt') -Value $freeze.Output -Encoding ASCII
    # 组合父目录与子路径；将内容写入目标文件。
    Set-Content -LiteralPath (Join-Path $WorkRoot 'requirements.freeze.txt') -Value $freeze.Output -Encoding ASCII
    # 组合父目录与子路径，并保存到 $smokeArgs。
    $smokeArgs = @('-I', '-X', 'utf8', (Join-Path $PSScriptRoot 'DataStack_Smoke.py'), '--output', (Join-Path $run 'smoke'))
    # 检查本行条件；满足时执行对应分支。
    if ($Profile -eq 'Extended') { $smokeArgs += '--extended' }
    # 计算本行表达式并设置 $smoke，供后续步骤使用。
    $smoke = Invoke-Native -File $envPython -Arguments $smokeArgs -TimeoutSeconds 300
    # 处理 Write-RunLog 所指定的操作或当前表达式的后续部分。
    Write-RunLog $smoke.Output.Trim()
    # 计算本行表达式并设置 $status.Python，供后续步骤使用。
    $status.Python = 'Passed'
    # 计算本行表达式并设置 $escapedPython，供后续步骤使用。
    $escapedPython = $envPython.Replace("'", "''")
    # 计算本行表达式并设置 $launcher，供后续步骤使用。
    $launcher = "# Session-only thread limits. No machine/user variables are changed.`r`n" +
        # 提供当前表达式所需的文本、字段名称或列表元素。
        "`$env:OMP_NUM_THREADS='$threads'`r`n`$env:OPENBLAS_NUM_THREADS='$threads'`r`n`$env:MKL_NUM_THREADS='$threads'`r`n`$env:POLARS_MAX_THREADS='$threads'`r`n" +
        # 提供当前表达式所需的文本、字段名称或列表元素。
        "& '$escapedPython' -m jupyterlab --no-browser --ServerApp.ip=127.0.0.1`r`n"
    # 组合父目录与子路径；将内容写入目标文件。
    Set-Content -LiteralPath (Join-Path $WorkRoot 'Start-Jupyter.ps1') -Value $launcher -Encoding UTF8
    # 检查本行条件；满足时执行对应分支。
    if ($SetupR) {
        # 检查本行条件；满足时执行对应分支。
        if (-not $rscript) { throw 'Rscript was not found. Python passed; R was not installed or globally upgraded.' }
        # 计算本行表达式并设置 $status.R，供后续步骤使用。
        $status.R = 'Running'
        # 组合父目录与子路径，并保存到 $rResult。
        $rResult = Invoke-Native -File $rscript -Arguments @('--vanilla', (Join-Path $PSScriptRoot 'DataStack_R_Bootstrap.R'), $WorkRoot, $run) -TimeoutSeconds $CommandTimeoutSeconds
        # 处理 Write-RunLog 所指定的操作或当前表达式的后续部分。
        Write-RunLog $rResult.Output.Trim()
        # 计算本行表达式并设置 $status.R，供后续步骤使用。
        $status.R = 'Passed'
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 计算本行表达式并设置 $status.Status，供后续步骤使用。
    $status.Status = 'Passed'
    # 处理 Write-RunLog 所指定的操作或当前表达式的后续部分。
    Write-RunLog ('PASSED. Interpreter: ' + $envPython)
    # 组合父目录与子路径。
    Write-RunLog ('Launch Jupyter when needed: & ''' + (Join-Path $WorkRoot 'Start-Jupyter.ps1') + '''')
# 结束上一代码块并进入异常处理。
} catch {
    # 计算本行表达式并设置 $status.Status，供后续步骤使用。
    $status.Status = 'Failed'
    # 计算本行表达式并设置 $status.Error，供后续步骤使用。
    $status.Error = $_.Exception.Message
    # 处理 Write-RunLog 所指定的操作或当前表达式的后续部分。
    Write-RunLog ('FAILED: ' + $_.Exception.Message)
    # 报告本行指定的错误并中止当前执行路径。
    throw
# 结束上一代码块并进入必定执行的资源清理。
} finally {
    # 生成当前时间或格式化时间戳，并保存到 $status['Finished']。
    $status['Finished'] = Get-Date -Format o
    # 组合父目录与子路径；将内容写入目标文件；把对象序列化为 JSON。
    $status | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'status.json') -Encoding UTF8
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if ($PassThru) { [pscustomobject]$status }
