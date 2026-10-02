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
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$InputPath,
    [string]$GroupBy,
    [string]$ValueColumn,
    [string]$PythonExe,
    [string]$WorkRoot=(Join-Path $env:LOCALAPPDATA 'DataWorkbench'),
    [ValidateRange(1,64)][int]$MemoryGB=8,
    [ValidateRange(1,64)][int]$Threads=6,
    [ValidateRange(1,1024)][int]$MaxTempGB=20,
    [string]$OutputDirectory=(Join-Path $PSScriptRoot ('reports\analysis-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)))
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$inputFile=Get-Item -LiteralPath $InputPath
if ($inputFile.PSIsContainer -or $inputFile.Extension -notin @('.csv','.parquet')) { throw 'InputPath must be one CSV or Parquet file.' }
if ($ValueColumn -and -not $GroupBy) { throw 'ValueColumn requires GroupBy.' }
if (-not $PythonExe) {
    foreach ($relative in @('python-env\Scripts\python.exe','python-extended\Scripts\python.exe','python-core\Scripts\python.exe')) {
        $candidate=Join-Path $WorkRoot $relative
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $PythonExe=$candidate; break }
    }
}
if (-not $PythonExe -or -not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) { throw 'Run Setup_DataStack_v2.ps1 -Apply first, or specify -PythonExe.' }
$os=Get-CimInstance Win32_OperatingSystem
$availableGB=[double]$os.FreePhysicalMemory/1MB
$effectiveMemory=[math]::Min($MemoryGB,[math]::Max(1,[math]::Floor($availableGB/2)))
if ($availableGB -lt 2) { throw 'Less than 2 GiB memory available; close unused applications first.' }
$cpu=Get-CimInstance Win32_Processor
$physicalCores=($cpu | Measure-Object -Property NumberOfCores -Sum).Sum
$effectiveThreads=[math]::Min($Threads,[math]::Max(1,$physicalCores))
$output=[IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw 'OutputDirectory already exists; use a new folder to avoid overwriting results.' }
$drive=New-Object IO.DriveInfo([IO.Path]::GetPathRoot($output))
if (-not $drive.IsReady -or $drive.AvailableFreeSpace -lt (($MaxTempGB+5)*1GB)) { throw 'Insufficient free disk space for MaxTempGB plus 5 GiB reserve; choose another output drive or lower MaxTempGB.' }
[void][IO.Directory]::CreateDirectory($output)
$scriptPath=Join-Path $output 'query.py'
$configPath=Join-Path $output 'query-config.json'
$config=[ordered]@{input=$inputFile.FullName;output=$output;group=$GroupBy;value=$ValueColumn;memory_gb=$effectiveMemory;threads=$effectiveThreads;max_temp_gb=$MaxTempGB}
$utf8=New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($configPath,($config|ConvertTo-Json),$utf8)
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
[IO.File]::WriteAllText($scriptPath,$python,$utf8)
Write-Host ('DuckDB buffer limit: {0} GB; threads: {1}; temporary disk limit: {2} GB' -f $effectiveMemory,$effectiveThreads,$MaxTempGB)
& $PythonExe -I $scriptPath $configPath
if ($LASTEXITCODE -ne 0) { throw "Analysis failed (exit $LASTEXITCODE). See $output" }
Write-Host ('完成：'+(Join-Path $output 'result.parquet'))
