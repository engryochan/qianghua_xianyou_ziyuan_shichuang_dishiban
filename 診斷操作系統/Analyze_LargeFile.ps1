#Requires -Version 5.1
<#
.SYNOPSIS
  用隔離環境的 DuckDB 處理 CSV/Parquet；控制記憶體與磁碟暫存。
.EXAMPLE
  .\Analyze_LargeFile.ps1 -InputPath 'D:\data\events.parquet'
.EXAMPLE
  .\Analyze_LargeFile.ps1 -InputPath 'D:\data\events.csv' -GroupBy 'category' -ValueColumn 'amount'
.DESCRIPTION
  未指定 GroupBy 時輸出列數。指定 GroupBy 時輸出完整分組結果 Parquet。
  ValueColumn 使用 DOUBLE，適合探索分析而非精確會計；另列無法轉數值的筆數。
  CSV 使用自動偵測分隔符且全部欄位先當文字；沒有跳過格式錯誤的列。
  不將整張表載入 pandas；記憶體限制是 DuckDB buffer limit，不是整個程序硬上限。
#>
# 启用 PowerShell 高级脚本参数绑定及所列功能。
[CmdletBinding()]
# 声明脚本或函数接受的参数及默认值。
param(
    # 声明参数 $InputPath的类型、默认值或校验规则。
    [Parameter(Mandatory=$true)][string]$InputPath,
    # 声明参数 $GroupBy的类型、默认值或校验规则。
    [string]$GroupBy,
    # 声明参数 $ValueColumn的类型、默认值或校验规则。
    [string]$ValueColumn,
    # 声明参数 $PythonExe的类型、默认值或校验规则。
    [string]$PythonExe,
    # 声明参数 $WorkRoot的类型、默认值或校验规则。
    [string]$WorkRoot=(Join-Path $env:LOCALAPPDATA 'DataWorkbench'),
    # 声明参数 $MemoryGB的类型、默认值或校验规则。
    [ValidateRange(1,64)][int]$MemoryGB=8,
    # 声明参数 $Threads的类型、默认值或校验规则。
    [ValidateRange(1,64)][int]$Threads=6,
    # 声明参数 $MaxTempGB的类型、默认值或校验规则。
    [ValidateRange(1,1024)][int]$MaxTempGB=20,
    # 声明参数 $OutputDirectory的类型、默认值或校验规则。
    [string]$OutputDirectory=(Join-Path $PSScriptRoot ('reports\analysis-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)))
# 结束此处的代码块、参数列表或集合定义。
)
# 处理 Set-StrictMode 所指定的操作或当前表达式的后续部分。
Set-StrictMode -Version 2.0
# 设置本脚本遇到 PowerShell 错误时的处理方式。
$ErrorActionPreference='Stop'
# 计算本行表达式并设置 $inputFile，供后续步骤使用。
$inputFile=Get-Item -LiteralPath $InputPath
# 检查本行条件；满足时执行对应分支。
if ($inputFile.PSIsContainer -or $inputFile.Extension -notin @('.csv','.parquet')) { throw 'InputPath must be one CSV or Parquet file.' }
# 检查本行条件；满足时执行对应分支。
if ($ValueColumn -and -not $GroupBy) { throw 'ValueColumn requires GroupBy.' }
# 检查本行条件；满足时执行对应分支。
if (-not $PythonExe) {
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($relative in @('python-env\Scripts\python.exe','python-extended\Scripts\python.exe','python-core\Scripts\python.exe')) {
        # 组合父目录与子路径，并保存到 $candidate。
        $candidate=Join-Path $WorkRoot $relative
        # 检查本行条件；满足时执行对应分支。
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $PythonExe=$candidate; break }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if (-not $PythonExe -or -not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) { throw 'Run Setup_DataStack_v2.ps1 -Apply first, or specify -PythonExe.' }
# 查询 Windows 管理接口中的设备或系统信息，并保存到 $os。
$os=Get-CimInstance Win32_OperatingSystem
# 构造或计算 $availableGB，保存本行指定的集合或索引结果。
$availableGB=[double]$os.FreePhysicalMemory/1MB
# 构造或计算 $effectiveMemory，保存本行指定的集合或索引结果。
$effectiveMemory=[math]::Min($MemoryGB,[math]::Max(1,[math]::Floor($availableGB/2)))
# 检查本行条件；满足时执行对应分支。
if ($availableGB -lt 2) { throw 'Less than 2 GiB memory available; close unused applications first.' }
# 查询 Windows 管理接口中的设备或系统信息，并保存到 $cpu。
$cpu=Get-CimInstance Win32_Processor
# 计算本行表达式并设置 $physicalCores，供后续步骤使用。
$physicalCores=($cpu | Measure-Object -Property NumberOfCores -Sum).Sum
# 构造或计算 $effectiveThreads，保存本行指定的集合或索引结果。
$effectiveThreads=[math]::Min($Threads,[math]::Max(1,$physicalCores))
# 构造或计算 $output，保存本行指定的集合或索引结果。
$output=[IO.Path]::GetFullPath($OutputDirectory)
# 检查本行条件；满足时执行对应分支。
if (Test-Path -LiteralPath $output) { throw 'OutputDirectory already exists; use a new folder to avoid overwriting results.' }
# 创建指定类型的对象，并保存到 $drive。
$drive=New-Object IO.DriveInfo([IO.Path]::GetPathRoot($output))
# 检查本行条件；满足时执行对应分支。
if (-not $drive.IsReady -or $drive.AvailableFreeSpace -lt (($MaxTempGB+5)*1GB)) { throw 'Insufficient free disk space for MaxTempGB plus 5 GiB reserve; choose another output drive or lower MaxTempGB.' }
# 继续当前表达式，补充参数、类型转换或结果处理。
[void][IO.Directory]::CreateDirectory($output)
# 组合父目录与子路径，并保存到 $scriptPath。
$scriptPath=Join-Path $output 'query.py'
# 组合父目录与子路径，并保存到 $configPath。
$configPath=Join-Path $output 'query-config.json'
# 构造或计算 $config，保存本行指定的集合或索引结果。
$config=[ordered]@{input=$inputFile.FullName;output=$output;group=$GroupBy;value=$ValueColumn;memory_gb=$effectiveMemory;threads=$effectiveThreads;max_temp_gb=$MaxTempGB}
# 创建指定类型的对象，并保存到 $utf8。
$utf8=New-Object Text.UTF8Encoding($false)
# 把对象序列化为 JSON；将文本写入指定文件。
[IO.File]::WriteAllText($configPath,($config|ConvertTo-Json),$utf8)
# 原文块第 1 行：计算本行表达式并设置 $python，供后续步骤使用。
# 原文块第 2 行：导入 json, pathlib, sys, time，供后续代码调用。
# 原文块第 3 行：导入 duckdb，供后续代码调用。
# 原文块第 4 行：读取目标文本文件，并保存到 config。
# 原文块第 5 行：构造或计算 out，保存本行指定的集合或索引结果。
# 原文块第 6 行：构造或计算 source，保存本行指定的集合或索引结果。
# 原文块第 7 行：计算本行表达式并设置 scratch，供后续步骤使用。
# 原文块第 8 行：创建输出目录。
# 原文块第 9 行：计算本行表达式并设置 started，供后续步骤使用。
# 原文块第 10 行：定义 ident，封装此函数内的操作。
# 原文块第 11 行：返回本行结果并结束当前函数。
# 原文块第 12 行：定义 literal，封装此函数内的操作。
# 原文块第 13 行：返回本行结果并结束当前函数。
# 原文块第 14 行：开始受异常处理保护的操作。
# 原文块第 15 行：进入上下文管理器，确保结束时自动释放相应资源。
# 原文块第 16 行：提供当前表达式所需的文本、字段名称或列表元素。
# 原文块第 17 行：提供当前表达式所需的文本、字段名称或列表元素。
# 原文块第 18 行：提供当前表达式所需的文本、字段名称或列表元素。
# 原文块第 19 行：提供当前表达式所需的文本、字段名称或列表元素。
# 原文块第 20 行：处理 if 所指定的操作或当前表达式的后续部分。
# 原文块第 21 行：读取 Parquet 数据，并保存到 relation。
# 原文块第 22 行：当前述条件不成立时执行此分支。
# 原文块第 23 行：计算本行表达式并设置 relation，供后续步骤使用。
# 原文块第 24 行：调用 relation.create_view，使用本行列出的输入完成对应操作。
# 原文块第 25 行：按本行的迭代范围或条件重复执行循环体。
# 原文块第 26 行：处理 if 所指定的操作或当前表达式的后续部分。
# 原文块第 27 行：报告本行指定的错误并中止当前执行路径。
# 原文块第 28 行：处理 if 所指定的操作或当前表达式的后续部分。
# 原文块第 29 行：构造或计算 group，保存本行指定的集合或索引结果。
# 原文块第 30 行：计算本行表达式并设置 fields，供后续步骤使用。
# 原文块第 31 行：处理 if 所指定的操作或当前表达式的后续部分。
# 原文块第 32 行：构造或计算 value，保存本行指定的集合或索引结果。
# 原文块第 33 行：计算本行表达式并设置 fields，供后续步骤使用。
# 原文块第 34 行：计算本行表达式并设置 fields，供后续步骤使用。
# 原文块第 35 行：计算本行表达式并设置 sql，供后续步骤使用。
# 原文块第 36 行：当前述条件不成立时执行此分支。
# 原文块第 37 行：计算本行表达式并设置 sql，供后续步骤使用。
# 原文块第 38 行：计算本行表达式并设置 target，供后续步骤使用。
# 原文块第 39 行：执行对象提供的命令或查询。
# 原文块第 40 行：读取 Parquet 数据；执行对象提供的命令或查询，并保存到 count。
# 原文块第 41 行：计算本行表达式并设置 report，供后续步骤使用。
# 原文块第 42 行：提供当前表达式所需的文本、字段名称或列表元素。
# 原文块第 43 行：提供当前表达式所需的文本、字段名称或列表元素。
# 原文块第 44 行：将文本写入目标文件；将结果序列化为 JSON 文本。
# 原文块第 45 行：输出本行的状态信息或计算结果。
# 原文块第 46 行：捕获并处理前述操作抛出的异常。
# 原文块第 47 行：将文本写入目标文件；将结果序列化为 JSON 文本。
# 原文块第 48 行：报告本行指定的错误并中止当前执行路径。
# 原文块第 49 行：提供当前表达式所需的文本、字段名称或列表元素。
$python=@'
import json, pathlib, sys, time
import duckdb
config = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
out = pathlib.Path(config["output"])
source = pathlib.Path(config["input"])
scratch = out / "scratch"
scratch.mkdir()
started = time.perf_counter()
def ident(value):
    return '"' + value.replace('"', '""') + '"'
def literal(value):
    return "'" + str(value).replace("'", "''") + "'"
try:
    with duckdb.connect(config={"memory_limit": f'{config["memory_gb"]}GB',
                               "threads": str(config["threads"]),
                               "temp_directory": str(scratch),
                               "max_temp_directory_size": f'{config["max_temp_gb"]}GB',
                               "preserve_insertion_order": "false"}) as con:
        if source.suffix.lower() == ".parquet":
            relation = con.read_parquet(str(source))
        else:
            relation = con.read_csv(str(source), all_varchar=True, ignore_errors=False)
        relation.create_view("source_data")
        for col in (config["group"], config["value"]):
            if col and col not in relation.columns:
                raise ValueError(f"Column not found: {col}")
        if config["group"]:
            group = ident(config["group"])
            fields = f'{group} AS group_value, COUNT(*) AS row_count'
            if config["value"]:
                value = ident(config["value"])
                fields += f', SUM(TRY_CAST({value} AS DOUBLE)) AS numeric_sum'
                fields += f', COUNT(*) FILTER (WHERE {value} IS NOT NULL AND TRY_CAST({value} AS DOUBLE) IS NULL) AS invalid_numeric_count'
            sql = f'SELECT {fields} FROM source_data GROUP BY {group}'
        else:
            sql = 'SELECT COUNT(*) AS row_count FROM source_data'
        target = out / "result.parquet"
        con.execute(f'COPY ({sql}) TO {literal(target)} (FORMAT PARQUET, COMPRESSION ZSTD)')
        count = con.execute('SELECT COUNT(*) FROM read_parquet(?)', [str(target)]).fetchone()[0]
    report = {"status": "passed", "elapsed_seconds": round(time.perf_counter()-started, 3),
              "result_rows": count, "result": str(target), "config": config,
              "duckdb": duckdb.__version__, "sql": sql}
    (out / "analysis-result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=True))
except Exception as exc:
    (out / "analysis-error.json").write_text(json.dumps({"status":"failed", "error":str(exc)}), encoding="utf-8")
    raise
'@
# 将文本写入指定文件。
[IO.File]::WriteAllText($scriptPath,$python,$utf8)
# 向终端显示提示或结果。
Write-Host ('DuckDB buffer limit: {0} GB; threads: {1}; temporary disk limit: {2} GB' -f $effectiveMemory,$effectiveThreads,$MaxTempGB)
# 调用本行指定的程序或脚本，并传入列出的参数。
& $PythonExe -I $scriptPath $configPath
# 检查本行条件；满足时执行对应分支。
if ($LASTEXITCODE -ne 0) { throw "Analysis failed (exit $LASTEXITCODE). See $output" }
# 组合父目录与子路径；向终端显示提示或结果。
Write-Host ('完成：'+(Join-Path $output 'result.parquet'))
