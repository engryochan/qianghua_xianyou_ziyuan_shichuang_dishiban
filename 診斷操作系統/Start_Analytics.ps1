#Requires -Version 5.1
<#
.SYNOPSIS
Start the verified analysis environment with session-only CPU settings.
.EXAMPLE
.\Start_Analytics.ps1 -Mode Jupyter
.EXAMPLE
.\Start_Analytics.ps1 -Mode LargeFile -InputPath C:\work\data\sales.csv -GroupBy category -ValueColumn amount
#>
# 启用 PowerShell 高级脚本参数绑定及所列功能。
[CmdletBinding()]
# 声明脚本或函数接受的参数及默认值。
param(
    # 声明参数 $Mode的类型、默认值或校验规则。
    [ValidateSet('Check','Jupyter','LargeFile')][string]$Mode='Check',
    # 声明参数 $PythonExe的类型、默认值或校验规则。
    [string]$PythonExe='C:\work\projects\lab\.venv\Scripts\python.exe',
    # 声明参数 $Project的类型、默认值或校验规则。
    [string]$Project='C:\work\projects\lab',
    # 声明参数 $Threads的类型、默认值或校验规则。
    [ValidateRange(1,64)][int]$Threads=6,
    # 声明参数 $MemoryGB的类型、默认值或校验规则。
    [ValidateRange(1,64)][int]$MemoryGB=6,
    # 声明参数 $InputPath的类型、默认值或校验规则。
    [string]$InputPath,
    # 声明参数 $GroupBy的类型、默认值或校验规则。
    [string]$GroupBy,
    # 声明参数 $ValueColumn的类型、默认值或校验规则。
    [string]$ValueColumn,
    # 声明参数 $OutputDirectory的类型、默认值或校验规则。
    [string]$OutputDirectory=(Join-Path $PSScriptRoot ('reports\run-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')))
# 结束此处的代码块、参数列表或集合定义。
)
# 设置本脚本遇到 PowerShell 错误时的处理方式。
$ErrorActionPreference='Stop'
# 检查本行条件；满足时执行对应分支。
if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) { throw "Missing interpreter: $PythonExe" }
# 计算本行表达式并设置 $saved，供后续步骤使用。
$saved=@{}
# 开始受异常处理保护的操作。
try {
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($name in @('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS','NUMEXPR_NUM_THREADS','POLARS_MAX_THREADS')) {
        # 读取指定作用域的环境变量，并保存到 $saved[$name]。
        $saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')
        # 写入指定作用域的环境变量。
        [Environment]::SetEnvironmentVariable($name,"$Threads",'Process')
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 根据指定值选择并执行对应分支。
    switch ($Mode) {
        # 提供当前表达式所需的文本、字段名称或列表元素。
        'Check' {
            # 组合父目录与子路径。
            & $PythonExe -I (Join-Path $PSScriptRoot 'DataStack_Smoke.py') --output $OutputDirectory
            # 检查本行条件；满足时执行对应分支。
            if ($LASTEXITCODE -ne 0) { throw 'Analysis smoke test failed.' }
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 提供当前表达式所需的文本、字段名称或列表元素。
        'Jupyter' {
            # 检查本行条件；满足时执行对应分支。
            if (-not (Test-Path -LiteralPath $Project -PathType Container)) { throw "Missing project: $Project" }
            # Keep Jupyter's authentication enabled and bind only to localhost.
            # 调用本行指定的程序或脚本，并传入列出的参数。
            & $PythonExe -I -m jupyterlab "--ServerApp.root_dir=$Project" --ServerApp.ip=127.0.0.1
            # 检查本行条件；满足时执行对应分支。
            if ($LASTEXITCODE -ne 0) { throw 'Jupyter exited with an error.' }
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 提供当前表达式所需的文本、字段名称或列表元素。
        'LargeFile' {
            # 检查本行条件；满足时执行对应分支。
            if (-not $InputPath) { throw 'LargeFile requires -InputPath.' }
            # 组合父目录与子路径。
            & (Join-Path $PSScriptRoot 'Analyze_LargeFile.ps1') -InputPath $InputPath -GroupBy $GroupBy -ValueColumn $ValueColumn -PythonExe $PythonExe -Threads $Threads -MemoryGB $MemoryGB -OutputDirectory $OutputDirectory
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束上一代码块并进入必定执行的资源清理。
} finally {
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
# 结束此处的代码块、参数列表或集合定义。
}
