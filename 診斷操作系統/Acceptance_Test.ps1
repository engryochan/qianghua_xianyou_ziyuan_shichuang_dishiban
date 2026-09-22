#Requires -Version 5.1
<#
.SYNOPSIS
  竣工驗收：把宣稱過的每一項都實跑一遍，輸出可查證的數字。
.DESCRIPTION
  這支腳本不做任何變更，只驗證。每一項輸出 PASS / FAIL / SKIP 與實際量到的值。
  任何一項 FAIL 就以非零離開碼結束，可直接接進排程或 CI。

  設計原則：驗收標準是「跑出結果」，不是「有沒有裝」。
  所以這裡不查登錄檔版本號，而是真的去跑一段運算並比對輸出。
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Acceptance_Test.ps1
.EXAMPLE
  .\Acceptance_Test.ps1 -SkipRender   # 略過 quarto render（最耗時的一項）
#>
# 启用 PowerShell 高级脚本参数绑定及所列功能。
[CmdletBinding()]
# 声明脚本或函数接受的参数及默认值。
param(
    # 声明参数 $SkipRender的类型、默认值或校验规则。
    [switch]$SkipRender,
    # 預設不對 Comet 做無頭探測。加上這個開關才會實測，且只有在
    # Comet 沒有執行時才動手——驗收腳本不該在使用者背後關掉他的瀏覽器。
    # 声明参数 $IncludeCometProbe的类型、默认值或校验规则。
    [switch]$IncludeCometProbe,
    # 声明参数 $WorkRoot的类型、默认值或校验规则。
    [string]$WorkRoot = 'C:\work',
    # 声明参数 $Project的类型、默认值或校验规则。
    [string]$Project = 'C:\work\projects\lab'
# 结束此处的代码块、参数列表或集合定义。
)

# 处理 Set-StrictMode 所指定的操作或当前表达式的后续部分。
Set-StrictMode -Off
# 设置本脚本遇到 PowerShell 错误时的处理方式。
$ErrorActionPreference = 'Continue'
# 开始受异常处理保护的操作。
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# 创建指定类型的对象，并保存到 $script:Rows。
$script:Rows = New-Object System.Collections.Generic.List[object]
# 生成当前时间或格式化时间戳；组合父目录与子路径，并保存到 $script:Tmp。
$script:Tmp = Join-Path $env:TEMP ('acc_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
# 创建指定目录、文件或配置项；将不需要的返回值丢弃。
$null = New-Item -ItemType Directory -Path $script:Tmp -Force

# 定义 Check，封装此函数内的操作。
function Check {
    # 声明脚本或函数接受的参数及默认值。
    param([string]$Area, [string]$Name, [scriptblock]$Test)
    # $Test 要回傳 @{ ok = $true/$false; value = '量到的東西' }
    # 计算本行表达式并设置 $v，供后续步骤使用。
    $v = ''
    # 计算本行表达式并设置 $ok，供后续步骤使用。
    $ok = $false
    # 开始受异常处理保护的操作。
    try {
        # 计算本行表达式并设置 $r，供后续步骤使用。
        $r = & $Test
        # 检查本行条件；满足时执行对应分支。
        if ($null -ne $r) { $ok = [bool]$r.ok; $v = "$($r.value)" }
    # 结束上一代码块并进入异常处理。
    } catch {
        # 计算本行表达式并设置 $v，供后续步骤使用。
        $v = '例外: ' + $_.Exception.Message
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 计算本行表达式并设置 $status，供后续步骤使用。
    $status = if ($ok) { 'PASS' } else { 'FAIL' }
    # 计算本行表达式并设置 $color，供后续步骤使用。
    $color = if ($ok) { 'Green' } else { 'Red' }
    # 向终端显示提示或结果。
    Write-Host ("{0,-4} {1,-10} {2,-34} {3}" -f $status, $Area, $Name, $v) -ForegroundColor $color
    # 调用 $script:Rows.Add，使用本行列出的输入完成对应操作。
    $script:Rows.Add([pscustomobject]@{ Status = $status; Area = $Area; Name = $Name; Value = $v })
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Skip，封装此函数内的操作。
function Skip {
    # 声明脚本或函数接受的参数及默认值。
    param([string]$Area, [string]$Name, [string]$Why)
    # 向终端显示提示或结果。
    Write-Host ("{0,-4} {1,-10} {2,-34} {3}" -f 'SKIP', $Area, $Name, $Why) -ForegroundColor DarkGray
    # 调用 $script:Rows.Add，使用本行列出的输入完成对应操作。
    $script:Rows.Add([pscustomobject]@{ Status = 'SKIP'; Area = $Area; Name = $Name; Value = $Why })
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Find-Exe，封装此函数内的操作。
function Find-Exe {
    # 声明脚本或函数接受的参数及默认值。
    param([string]$Name, [string[]]$Fallbacks = @())
    # 查找当前环境可用的命令及其位置；选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $c。
    $c = Get-Command $Name -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
    # 检查本行条件；满足时执行对应分支。
    if ($c) { return $c.Source }
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($p in $Fallbacks) {
        # 枚举指定位置的文件、目录或注册表项；选取记录中的指定字段或条目；按指定属性排序输入记录，并保存到 $h。
        $h = Get-ChildItem -Path $p -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
        # 检查本行条件；满足时执行对应分支。
        if ($h) { return $h.FullName }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 返回本行结果并结束当前函数。
    return $null
# 结束此处的代码块、参数列表或集合定义。
}

# 向终端显示提示或结果。
Write-Host ''
# 生成当前时间或格式化时间戳；向终端显示提示或结果。
Write-Host ('竣工驗收  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ForegroundColor Cyan
# 向终端显示提示或结果。
Write-Host ('暫存目錄：' + $script:Tmp)
# 向终端显示提示或结果。
Write-Host ''

# ================================================================ 系統
# 处理 Check 所指定的操作或当前表达式的后续部分。
Check '系統' '作業系統為 Windows 11' {
    # 读取注册表或对象的属性，并保存到 $b。
    $b = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild
    # 读取注册表或对象的属性，并保存到 $ubr。
    $ubr = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR
    # 一律用 build number 判斷：就地升級後 ProductName 仍寫 Windows 10
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ ok = ($b -ge 22000); value = "Build $b.$ubr" }
# 结束此处的代码块、参数列表或集合定义。
}
# 处理 Check 所指定的操作或当前表达式的后续部分。
Check '系統' '電源計畫為高效能' {
    # 调用 Windows 电源配置工具，并保存到 $p。
    $p = (& powercfg.exe /getactivescheme) -join ''
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ ok = ($p -match '高性能|高效能|High performance'); value = ($p -replace '.*\(', '(') }
# 结束此处的代码块、参数列表或集合定义。
}
# 处理 Check 所指定的操作或当前表达式的后续部分。
Check '系統' 'C: 可用空間 > 15%' {
    # 查询 Windows 管理接口中的设备或系统信息，并保存到 $v。
    $v = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    # 构造或计算 $pct，保存本行指定的集合或索引结果。
    $pct = [math]::Round(100 * $v.FreeSpace / $v.Size, 1)
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ ok = ($pct -gt 15); value = "$pct% ($([math]::Round($v.FreeSpace/1GB,1)) GB)" }
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================ PATH 與 git
# 处理 Check 所指定的操作或当前表达式的后续部分。
Check 'PATH' '四項工具在持久化 PATH 上' {
    # 构造或计算 $dirs，保存本行指定的集合或索引结果。
    $dirs = @()
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($s in @('Machine', 'User')) {
        # 读取指定作用域的环境变量，并保存到 $raw。
        $raw = [Environment]::GetEnvironmentVariable('Path', $s)
        # 检查本行条件；满足时执行对应分支。
        if ($raw) { foreach ($e in ($raw -split ';')) { if ($e.Trim()) { $dirs += [Environment]::ExpandEnvironmentVariables($e.Trim()).TrimEnd('\') } } }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 构造或计算 $want，保存本行指定的集合或索引结果。
    $want = @('Rscript.exe', 'quarto.exe', 'duckdb.exe', 'git.exe')
    # 构造或计算 $miss，保存本行指定的集合或索引结果。
    $miss = @()
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($w in $want) {
        # 计算本行表达式并设置 $hit，供后续步骤使用。
        $hit = $false
        # 按本行的迭代范围或条件重复执行循环体。
        foreach ($d in $dirs) { if (Test-Path -LiteralPath (Join-Path $d $w)) { $hit = $true; break } }
        # 检查本行条件；满足时执行对应分支。
        if (-not $hit) { $miss += $w }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ ok = ($miss.Count -eq 0); value = if ($miss.Count) { '缺: ' + ($miss -join ',') } else { "$($want.Count)/$($want.Count) 皆在" } }
# 结束此处的代码块、参数列表或集合定义。
}
# 处理 Check 所指定的操作或当前表达式的后续部分。
Check 'git' '全域設定六項' {
    # 构造或计算 $g，保存本行指定的集合或索引结果。
    $g = Find-Exe 'git' @("$env:ProgramFiles\Git\cmd\git.exe")
    # 检查本行条件；满足时执行对应分支。
    if (-not $g) { return @{ ok = $false; value = '找不到 git' } }
    # 计算本行表达式并设置 $want，供后续步骤使用。
    $want = @{ 'core.longpaths' = 'true'; 'core.autocrlf' = 'input'; 'core.fscache' = 'true'
        # 提供当前表达式所需的文本、字段名称或列表元素。
        'credential.helper' = 'manager'; 'init.defaultBranch' = 'main'; 'fetch.prune' = 'true'
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 构造或计算 $bad，保存本行指定的集合或索引结果。
    $bad = @()
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($k in $want.Keys) {
        # 选取记录中的指定字段或条目，并保存到 $v。
        $v = (& $g config --global $k 2>$null | Select-Object -First 1)
        # 检查本行条件；满足时执行对应分支。
        if ("$v".Trim() -ne $want[$k]) { $bad += $k }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ ok = ($bad.Count -eq 0); value = if ($bad.Count) { '不符: ' + ($bad -join ',') } else { '6/6 符合' } }
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================ R
# 构造或计算 $rscript，保存本行指定的集合或索引结果。
$rscript = Find-Exe 'Rscript' @("$env:ProgramFiles\R\R-*\bin\x64\Rscript.exe")
# 检查本行条件；满足时执行对应分支。
if (-not $rscript) {
    # 处理 Skip 所指定的操作或当前表达式的后续部分。
    Skip 'R' '所有 R 項目' '找不到 Rscript'
# 结束上一代码块并进入另一条件分支。
} else {
    # 组合父目录与子路径，并保存到 $rFile。
    $rFile = Join-Path $script:Tmp 'acc.R'
    # 原文块第 1 行：计算本行表达式并设置 $rCode，供后续步骤使用。
    # 原文块第 2 行：读取 R 进程的环境变量，并保存到 out。
    # 原文块第 3 行：读取 R 套件安装清单，并保存到 ip。
    # 原文块第 4 行：输出本行的状态信息或计算结果。
    # 原文块第 5 行：构造或计算 key，保存本行指定的集合或索引结果。
    # 原文块第 6 行：输出本行的状态信息或计算结果。
    # 原文块第 7 行：加载指定 R 套件。
    # 原文块第 8 行：限制 data.table 使用的线程数量。
    # 原文块第 9 行：构造或计算 dt，保存本行指定的集合或索引结果。
    # 原文块第 10 行：构造或计算 r，保存本行指定的集合或索引结果。
    # 原文块第 11 行：输出本行的状态信息或计算结果。
    # 原文块第 12 行：加载指定 R 套件。
    # 原文块第 13 行：计算本行表达式并设置 pq，供后续步骤使用。
    # 原文块第 14 行：建立数据库连接，并保存到 con。
    # 原文块第 15 行：执行指定 SQL 语句。
    # 原文块第 16 行：执行 SQL 查询并取得结果；读取 Parquet 数据，并保存到 n。
    # 原文块第 19 行：输出本行的状态信息或计算结果。
    # 原文块第 20 行：输出本行的状态信息或计算结果。
    # 原文块第 21 行：关闭数据库连接并释放资源。
    # 原文块第 22 行：固定 R 随机种子以便重复验证。
    # 原文块第 23 行：计算本行表达式并设置 y，供后续步骤使用。
    # 原文块第 24 行：构造 XGBoost 使用的数据矩阵，并保存到 dm。
    # 原文块第 25 行：训练 XGBoost 模型，并保存到 fit。
    # 原文块第 26 行：计算本行表达式并设置 data，供后续步骤使用。
    # 原文块第 27 行：输出本行的状态信息或计算结果。
    # 原文块第 28 行：加载指定 R 套件。
    # 原文块第 29 行：构造或计算 rr，保存本行指定的集合或索引结果。
    # 原文块第 30 行：构造或计算 sp，保存本行指定的集合或索引结果。
    # 原文块第 31 行：构造或计算 mean.model，保存本行指定的集合或索引结果。
    # 原文块第 32 行：计算本行表达式并设置 gf，供后续步骤使用。
    # 原文块第 33 行：输出本行的状态信息或计算结果。
    # 原文块第 34 行：提供当前表达式所需的文本、字段名称或列表元素。
    $rCode = @'
out <- Sys.getenv("ACC_OUT")
ip <- rownames(installed.packages())
cat("PKGCOUNT:", length(ip), "\n")
key <- c("data.table","duckdb","DBI","xgboost","rugarch","tidymodels","reticulate","targets","renv","grf")
cat("KEYMISS:", paste(setdiff(key, ip), collapse=","), "\n")
suppressPackageStartupMessages(library(data.table))
setDTthreads(10)
dt <- data.table(g = rep(c("a","b"), each = 5e4), v = 1:1e5)
r <- dt[, .(s = sum(as.numeric(v))), by = g]
cat("DTSUM:", format(sum(r$s), scientific = FALSE), "\n")
suppressPackageStartupMessages({library(duckdb); library(DBI)})
pq <- gsub("\\\\","/", file.path(out, "acc.parquet"))
con <- dbConnect(duckdb()); duckdb_register(con, "dt", dt)
dbExecute(con, sprintf("copy dt to '%s' (format parquet)", pq))
n <- dbGetQuery(con, sprintf("select count(*) n from read_parquet('%s')", pq))$n
# 一定要關掉科學記號：cat() 預設會把 100000 印成 1e+05，
# 解析端的 (\d+) 只會抓到開頭的 1，量出來的數字是錯的。
cat("PARQUETROWS:", format(n, scientific = FALSE), "\n")
cat("DUCKTHREADS:", dbGetQuery(con, "select current_setting('threads') t")$t, "\n")
dbDisconnect(con, shutdown = TRUE)
set.seed(1); X <- matrix(rnorm(20000*20), 20000, 20)
y <- as.integer(X %*% rnorm(20) + rnorm(20000) > 0)
dm <- xgboost::xgb.DMatrix(data = X, label = y, nthread = 10)
fit <- xgboost::xgb.train(params = list(objective="binary:logistic", tree_method="hist", nthread=10),
                          data = dm, nrounds = 60, verbose = 0)
cat("XGBACC:", round(mean((predict(fit, dm) > 0.5) == y), 4), "\n")
suppressPackageStartupMessages(library(rugarch))
rr <- as.numeric(scale(diff(log(cumprod(1 + rnorm(2000, 0, 0.01))))))
sp <- ugarchspec(variance.model=list(model="sGARCH", garchOrder=c(1,1)),
                 mean.model=list(armaOrder=c(0,0), include.mean=FALSE))
gf <- tryCatch(ugarchfit(sp, rr, solver="hybrid"), error=function(e) NULL)
cat("GARCH:", if (!is.null(gf) && gf@fit$convergence == 0) "converged" else "FAILED", "\n")
'@
    # 将内容写入目标文件。
    Set-Content -Path $rFile -Value $rCode -Encoding ASCII
    # 计算本行表达式并设置 $env:ACC_OUT，供后续步骤使用。
    $env:ACC_OUT = ($script:Tmp -replace '\\', '/')
    # 计算本行表达式并设置 $rOut，供后续步骤使用。
    $rOut = (& $rscript $rFile 2>&1) -join "`n"

    # 以下所有解析一律用 [ \t]* 而非 \s*：.NET 的 \s 包含換行，
    # 標籤後若該行為空，\s* 會跨行抓到下一行的值（本腳本第一版就這樣量錯過）。
    # 处理 Check 所指定的操作或当前表达式的后续部分。
    Check 'R' '套件數 >= 340' {
        # 构造或计算 $m，保存本行指定的集合或索引结果。
        $m = [regex]::Match($rOut, 'PKGCOUNT:[ \t]*(\d+)')
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ ok = ($m.Success -and [int]$m.Groups[1].Value -ge 340); value = if ($m.Success) { $m.Groups[1].Value + ' 個' } else { '讀不到' } }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 处理 Check 所指定的操作或当前表达式的后续部分。
    Check 'R' '關鍵套件零缺口' {
        # 注意：.NET 的 \s 包含換行，'KEYMISS:\s*(.*)' 會跨行抓到下一行的內容。
        # 必須用 [ \t]* 限定同一行，捕捉也要用 [^\r\n]*。
        # 构造或计算 $m，保存本行指定的集合或索引结果。
        $m = [regex]::Match($rOut, 'KEYMISS:[ \t]*([^\r\n]*)')
        # 构造或计算 $v，保存本行指定的集合或索引结果。
        $v = if ($m.Success) { $m.Groups[1].Value.Trim() } else { '讀不到' }
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ ok = ($m.Success -and $v -eq ''); value = if ($v) { "缺 $v" } else { '10/10 齊全' } }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 处理 Check 所指定的操作或当前表达式的后续部分。
    Check 'R' 'data.table 分組結果正確' {
        # 构造或计算 $m，保存本行指定的集合或索引结果。
        $m = [regex]::Match($rOut, 'DTSUM:[ \t]*(\d+)')
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ ok = ($m.Success -and $m.Groups[1].Value -eq '5000050000'); value = if ($m.Success) { $m.Groups[1].Value } else { '讀不到' } }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 处理 Check 所指定的操作或当前表达式的后续部分。
    Check 'R' 'duckdb 讀回 Parquet 10 萬列' {
        # 构造或计算 $m，保存本行指定的集合或索引结果。
        $m = [regex]::Match($rOut, 'PARQUETROWS:[ \t]*(\d+)')
        # 构造或计算 $t，保存本行指定的集合或索引结果。
        $t = [regex]::Match($rOut, 'DUCKTHREADS:[ \t]*(\d+)')
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ ok = ($m.Success -and [int]$m.Groups[1].Value -eq 100000); value = "$($m.Groups[1].Value) 列 / $($t.Groups[1].Value) 執行緒" }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 处理 Check 所指定的操作或当前表达式的后续部分。
    Check 'R' 'xgboost CPU 訓練 acc > 0.9' {
        # 构造或计算 $m，保存本行指定的集合或索引结果。
        $m = [regex]::Match($rOut, 'XGBACC:[ \t]*([\d\.]+)')
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ ok = ($m.Success -and [double]$m.Groups[1].Value -gt 0.9); value = if ($m.Success) { 'acc ' + $m.Groups[1].Value } else { '讀不到' } }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 处理 Check 所指定的操作或当前表达式的后续部分。
    Check 'R' 'rugarch sGARCH(1,1) 收斂' {
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ ok = ($rOut -match 'GARCH:\s*converged'); value = if ($rOut -match 'GARCH:\s*(\w+)') { $Matches[1] } else { '讀不到' } }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 处理 Check 所指定的操作或当前表达式的后续部分。
    Check 'R' 'Rtools 可編譯 C 擴充' {
        # 组合父目录与子路径，并保存到 $d。
        $d = Join-Path $script:Tmp 'shlib'
        # 创建指定目录、文件或配置项；将不需要的返回值丢弃。
        $null = New-Item -ItemType Directory -Path $d -Force
        # 原文块第 1 行：组合父目录与子路径；将内容写入目标文件。
        # 原文块第 3 行：处理 SEXP 所指定的操作或当前表达式的后续部分。
        Set-Content -Path (Join-Path $d 'a.c') -Value '#include <R.h>
#include <Rinternals.h>
SEXP addtwo(SEXP a, SEXP b) { return ScalarReal(asReal(a) + asReal(b)); }' -Encoding ASCII
        # 计算本行表达式并设置 $rexe，供后续步骤使用。
        $rexe = $rscript -replace 'Rscript\.exe$', 'R.exe'
        # 处理 Push-Location 所指定的操作或当前表达式的后续部分。
        Push-Location $d
        # 调用本行指定的程序或脚本，并传入列出的参数；将不需要的返回值丢弃。
        $null = & $rexe CMD SHLIB a.c 2>&1
        # 处理 Pop-Location 所指定的操作或当前表达式的后续部分。
        Pop-Location
        # 组合父目录与子路径，并保存到 $dll。
        $dll = Join-Path $d 'a.dll'
        # 检查目标路径是否存在。
        @{ ok = (Test-Path $dll); value = if (Test-Path $dll) { 'a.dll ' + (Get-Item $dll).Length + ' bytes' } else { '未產生 dll' } }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================ Python
# 原文块第 1 行：计算本行表达式并设置 $pyCode，供后续步骤使用。
# 原文块第 2 行：导入 json, sys, importlib.metadata as md，供后续代码调用。
# 原文块第 3 行：导入 polars as pl, duckdb, pyarrow, numpy, pandas，供后续代码调用。
# 原文块第 4 行：导入 sklearn.datasets 中的 make_classification，供后续代码调用。
# 原文块第 5 行：导入 sklearn.model_selection 中的 train_test_split，供后续代码调用。
# 原文块第 6 行：导入 xgboost as xgb, lightgbm as lgb，供后续代码调用。
# 原文块第 7 行：导入 econml, shap, lifelines，供后续代码调用。
# 原文块第 8 行：导入 econml.dml 中的 LinearDML，供后续代码调用。
# 原文块第 9 行：导入 numpy as np，供后续代码调用。
# 原文块第 10 行：计算本行表达式并设置 res，供后续步骤使用。
# 原文块第 11 行：构造或计算 res["version"]，保存本行指定的集合或索引结果。
# 原文块第 12 行：构造或计算 res["pkgs"]，保存本行指定的集合或索引结果。
# 原文块第 13 行：构造或计算 df，保存本行指定的集合或索引结果。
# 原文块第 14 行：构造或计算 res["duckdb_sum"]，保存本行指定的集合或索引结果。
# 原文块第 17 行：构造或计算 res["threads"]，保存本行指定的集合或索引结果。
# 原文块第 18 行：生成固定随机种子的分类样本，分别保存特征矩阵 X 与标签 y。
# 原文块第 19 行：按固定随机种子划分训练集与测试集，分别保存特征和标签。
# 原文块第 20 行：配置 CPU 直方图算法、树数量与线程数，准备 XGBoost 分类验收。
# 原文块第 21 行：配置 LightGBM 分类器的树数量与 CPU 线程数。
# 原文块第 22 行：创建固定种子的随机数生成器，并保存到 rng。
# 原文块第 23 行：构造或计算 n，保存本行指定的集合或索引结果。
# 原文块第 28 行：使用给定数据拟合模型，并保存到 res["ate"]。
# 原文块第 29 行：输出本行的状态信息或计算结果。
# 原文块第 30 行：提供当前表达式所需的文本、字段名称或列表元素。
$pyCode = @'
import json, sys, importlib.metadata as md
import polars as pl, duckdb, pyarrow, numpy, pandas
from sklearn.datasets import make_classification
from sklearn.model_selection import train_test_split
import xgboost as xgb, lightgbm as lgb
import econml, shap, lifelines
from econml.dml import LinearDML
import numpy as np
res = {}
res["version"] = sys.version.split()[0]
res["pkgs"] = len([d.name for d in md.distributions() if d.name])
df = pl.DataFrame({"g": ["a","b"]*50000, "v": range(100000)})
res["duckdb_sum"] = duckdb.sql("select sum(v) from df").fetchone()[0]
# 這段程式是寫進 .py 檔再執行的，可以正常使用引號。
# （PowerShell 吃掉引號的問題只發生在 python -c 這種直接傳參數的情況。）
res["threads"] = duckdb.sql("select current_setting('threads')").fetchone()[0]
X, y = make_classification(n_samples=20000, n_features=20, random_state=0)
Xtr, Xte, ytr, yte = train_test_split(X, y, random_state=0)
res["xgb"] = round(xgb.XGBClassifier(tree_method="hist", n_estimators=60, n_jobs=10).fit(Xtr,ytr).score(Xte,yte), 4)
res["lgb"] = round(lgb.LGBMClassifier(n_estimators=60, n_jobs=10, verbose=-1).fit(Xtr,ytr).score(Xte,yte), 4)
rng = np.random.default_rng(0)
n=3000; Xc=rng.normal(size=(n,3)); T=rng.binomial(1,0.5,n); Y=2.0*T+Xc[:,0]+rng.normal(size=n)
# random_state 一定要鎖。LinearDML 內部交叉擬合有隨機性：不鎖種子時實測
# 連跑五次得到 2.0307 / 1.8229 / 2.0295 / 2.03 / 2.0312，會隨機踩線變成假紅字。
# 鎖 random_state=0 後連跑三次都是 2.0294。
# 驗收測試必須是確定性的——會飄的測試比沒有測試更糟，它會讓人去修沒壞的東西。
res["ate"] = round(float(LinearDML(discrete_treatment=True, random_state=0).fit(Y,T,X=Xc).ate(Xc)), 3)
print("ACCJSON" + json.dumps(res))
'@
# 组合父目录与子路径，并保存到 $pyFile。
$pyFile = Join-Path $script:Tmp 'acc.py'
# 将内容写入目标文件。
Set-Content -Path $pyFile -Value $pyCode -Encoding UTF8

# 按本行的迭代范围或条件重复执行循环体。
foreach ($envDef in @(
        # 组合父目录与子路径。
        @{ Label = '共用環境'; Py = (Join-Path $WorkRoot 'envs\ds\Scripts\python.exe') },
        # 组合父目录与子路径。
        @{ Label = '專案環境'; Py = (Join-Path $Project '.venv\Scripts\python.exe') })) {
    # 计算本行表达式并设置 $py，供后续步骤使用。
    $py = $envDef.Py
    # 计算本行表达式并设置 $lbl，供后续步骤使用。
    $lbl = $envDef.Label
    # 检查本行条件；满足时执行对应分支。
    if (-not (Test-Path $py)) { Skip 'Python' ($lbl + ' 全部項目') ('找不到 ' + $py); continue }
    # 计算本行表达式并设置 $o，供后续步骤使用。
    $o = (& $py $pyFile 2>&1) -join "`n"
    # 计算本行表达式并设置 $j，供后续步骤使用。
    $j = $null
    # 构造或计算 $m，保存本行指定的集合或索引结果。
    $m = [regex]::Match($o, 'ACCJSON(\{.*\})')
    # 检查本行条件；满足时执行对应分支。
    if ($m.Success) { try { $j = $m.Groups[1].Value | ConvertFrom-Json } catch { } }

    # 176 是「下限」不是「應等於」：後續工作補過 openpyxl 等套件，現為 182。
    # 標題寫成 >= 才不會讓人誤以為多出來的套件是異常。
    # 处理 Check 所指定的操作或当前表达式的后续部分。
    Check 'Python' ($lbl + ' 直譯器 3.13 + 套件數 >= 176') {
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ ok = ($j -and $j.version -like '3.13*' -and $j.pkgs -ge 176); value = if ($j) { "$($j.version) / $($j.pkgs) 套件" } else { '未取得輸出' } }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 处理 Check 所指定的操作或当前表达式的后续部分。
    Check 'Python' ($lbl + ' duckdb 聚合正確') {
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ ok = ($j -and [int64]$j.duckdb_sum -eq 4999950000); value = if ($j) { "sum=$($j.duckdb_sum) / $($j.threads) 執行緒" } else { 'n/a' } }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 处理 Check 所指定的操作或当前表达式的后续部分。
    Check 'Python' ($lbl + ' xgboost + lightgbm') {
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ ok = ($j -and $j.xgb -gt 0.8 -and $j.lgb -gt 0.8); value = if ($j) { "xgb $($j.xgb) / lgb $($j.lgb)" } else { 'n/a' } }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 处理 Check 所指定的操作或当前表达式的后续部分。
    Check 'Python' ($lbl + ' econml 還原 ATE≈2.0') {
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ ok = ($j -and [math]::Abs([double]$j.ate - 2.0) -lt 0.15); value = if ($j) { "ATE $($j.ate)" } else { 'n/a' } }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================ 跨語言
# 检查本行条件；满足时执行对应分支。
if ($rscript) {
    # 处理 Check 所指定的操作或当前表达式的后续部分。
    Check '跨語言' 'reticulate 接得上專案環境' {
        # 组合父目录与子路径，并保存到 $f。
        $f = Join-Path $script:Tmp 'ret.R'
        # 计算本行表达式并设置 $venv，供后续步骤使用。
        $venv = ($Project -replace '\\', '/') + '/.venv/Scripts/python.exe'
        # 原文块第 1 行：将内容写入目标文件。
        # 原文块第 2 行：设置当前 R 进程的环境变量。
        # 原文块第 3 行：加载指定 R 套件。
        # 原文块第 4 行：计算本行表达式并设置 pl，供后续步骤使用。
        # 原文块第 5 行：输出本行的状态信息或计算结果。
        # 原文块第 6 行：提供当前表达式所需的文本、字段名称或列表元素。
        Set-Content -Path $f -Encoding ASCII -Value @"
Sys.setenv(RETICULATE_PYTHON = "$venv")
suppressPackageStartupMessages(library(reticulate))
pl <- import("polars"); dd <- import("duckdb")
cat("RETIC:", pl[["__version__"]], dd[["__version__"]], "\n")
"@
        # 计算本行表达式并设置 $o，供后续步骤使用。
        $o = (& $rscript $f 2>&1) -join "`n"
        # 构造或计算 $m，保存本行指定的集合或索引结果。
        $m = [regex]::Match($o, 'RETIC:\s*(\S+)\s+(\S+)')
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ ok = $m.Success; value = if ($m.Success) { "polars $($m.Groups[1].Value) / duckdb $($m.Groups[2].Value)" } else { '失敗' } }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 处理 Check 所指定的操作或当前表达式的后续部分。
    Check '跨語言' 'arrow/pyarrow 衝突仍存在(迴歸)' {
        # 這是「已知地雷」的迴歸測試：預期 FAIL 才代表地雷還在。
        # 若哪天它變成可以載入，代表上游修好了，範本就可以放寬。
        # 组合父目录与子路径，并保存到 $f。
        $f = Join-Path $script:Tmp 'conflict.R'
        # 计算本行表达式并设置 $venv，供后续步骤使用。
        $venv = ($Project -replace '\\', '/') + '/.venv/Scripts/python.exe'
        # 原文块第 1 行：将内容写入目标文件。
        # 原文块第 2 行：设置当前 R 进程的环境变量。
        # 原文块第 3 行：加载指定 R 套件。
        # 原文块第 4 行：加载指定 R 套件。
        # 原文块第 5 行：计算本行表达式并设置 r，供后续步骤使用。
        # 原文块第 6 行：输出本行的状态信息或计算结果。
        # 原文块第 7 行：提供当前表达式所需的文本、字段名称或列表元素。
        Set-Content -Path $f -Encoding ASCII -Value @"
Sys.setenv(RETICULATE_PYTHON = "$venv")
suppressPackageStartupMessages(library(arrow))
suppressPackageStartupMessages(library(reticulate))
r <- tryCatch({ import("pyarrow"); "LOADED" }, error = function(e) "BLOCKED")
cat("CONFLICT:", r, "\n")
"@
        # 计算本行表达式并设置 $o，供后续步骤使用。
        $o = (& $rscript $f 2>&1) -join "`n"
        # 计算本行表达式并设置 $blocked，供后续步骤使用。
        $blocked = $o -match 'CONFLICT:\s*BLOCKED'
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ ok = $true; value = if ($blocked) { '仍衝突(符合預期,範本已規避)' } else { '★ 已不衝突,可放寬範本' } }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================ Quarto
# 检查本行条件；满足时执行对应分支。
if ($SkipRender) {
    # 处理 Skip 所指定的操作或当前表达式的后续部分。
    Skip 'Quarto' 'render 範本' '-SkipRender'
# 结束上一代码块并进入另一条件分支。
} else {
    # 处理 Check 所指定的操作或当前表达式的后续部分。
    Check 'Quarto' 'render R+Python 範本' {
        # 组合父目录与子路径，并保存到 $tpl。
        $tpl = Join-Path $Project 'template.qmd'
        # 检查本行条件；满足时执行对应分支。
        if (-not (Test-Path $tpl)) { return @{ ok = $false; value = '找不到 template.qmd' } }
        # 构造或计算 $q，保存本行指定的集合或索引结果。
        $q = Find-Exe 'quarto' @("$env:ProgramFiles\Quarto\bin\quarto.cmd")
        # 检查本行条件；满足时执行对应分支。
        if (-not $q) { return @{ ok = $false; value = '找不到 quarto' } }
        # 组合父目录与子路径，并保存到 $html。
        $html = Join-Path $Project 'template.html'
        # 检查本行条件；满足时执行对应分支。
        if (Test-Path $html) { Remove-Item -LiteralPath $html -Force -ErrorAction SilentlyContinue }
        # 处理 Push-Location 所指定的操作或当前表达式的后续部分。
        Push-Location $Project
        # 调用本行指定的程序或脚本，并传入列出的参数；将不需要的返回值丢弃。
        $null = & $q render template.qmd 2>&1
        # 处理 Pop-Location 所指定的操作或当前表达式的后续部分。
        Pop-Location
        # 检查本行条件；满足时执行对应分支。
        if (-not (Test-Path $html)) { return @{ ok = $false; value = '未產出 HTML' } }
        # 读取文件内容供后续处理，并保存到 $t。
        $t = Get-Content $html -Raw
        # 按条件筛选输入记录，并保存到 $hits。
        $hits = @('3.13.15', 'polars', 'pyarrow', 'xgboost acc') | Where-Object { $t -match [regex]::Escape($_) }
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ ok = ($hits.Count -ge 3); value = "HTML $([math]::Round($t.Length/1KB)) KB，命中 $($hits.Count)/4 標記" }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================ Positron
# 处理 Check 所指定的操作或当前表达式的后续部分。
Check 'Positron' '工作區已開啟且已信任' {
    # 计算本行表达式并设置 $g，供后续步骤使用。
    $g = "$env:APPDATA\Positron\User\globalStorage\storage.json"
    # 检查本行条件；满足时执行对应分支。
    if (-not (Test-Path $g)) { return @{ ok = $false; value = '找不到 storage.json' } }
    # 读取文件内容供后续处理；把 JSON 文本解析为对象，并保存到 $j。
    $j = Get-Content $g -Raw | ConvertFrom-Json
    # 构造或计算 $folders，保存本行指定的集合或索引结果。
    $folders = @($j.backupWorkspaces.folders)
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ ok = ($folders.Count -gt 0); value = if ($folders.Count) { "$($folders.Count) 個工作區: " + ($folders[0].folderUri) } else { '仍是 emptyWindows' } }
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================ 其他工具
# 按本行的迭代范围或条件重复执行循环体。
foreach ($t in @(
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ N = 'duckdb CLI'; E = 'duckdb'; A = @('-c', 'select 42 as n') ; Expect = '42' },
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ N = 'PowerShell 7'; E = 'pwsh'; A = @('-NoProfile', '-Command', '1+1'); Expect = '2' },
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ N = 'uv'; E = 'uv'; A = @('--version'); Expect = 'uv' })) {
    # 处理 Check 所指定的操作或当前表达式的后续部分。
    Check '工具' $t.N {
        # 计算本行表达式并设置 $e，供后续步骤使用。
        $e = Find-Exe $t.E
        # 检查本行条件；满足时执行对应分支。
        if (-not $e) { return @{ ok = $false; value = '不在 PATH' } }
        # 构造或计算 $o，保存本行指定的集合或索引结果。
        $o = (& $e @($t.A) 2>&1) -join ' '
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ ok = ($o -match [regex]::Escape($t.Expect)); value = ($o -replace '\s+', ' ').Trim() }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================ 已知未解
# 這一項預設「只觀察、不動手」。
#
# 舊版缺陷（由另一工作階段指出，屬實）：它會執行
#   Get-Process comet | Stop-Process -Force
# 無差別終止所有 comet 行程——包含使用者當下正在用的視窗。
# 一支「驗收」腳本不該在使用者背後關掉他的瀏覽器。
#
# 現在預設只讀取安裝與執行狀態；要真的做無頭探測，得明確加
# -IncludeCometProbe，而且只有在 comet 沒有執行時才會動手，
# 事後也只終止自己啟動的那一個行程樹。
# 检查本行条件；满足时执行对应分支。
if (-not $IncludeCometProbe) {
    # 处理 Check 所指定的操作或当前表达式的后续部分。
    Check '未解' 'Comet 現況(唯讀觀察)' {
        # 计算本行表达式并设置 $exe，供后续步骤使用。
        $exe = "$env:LOCALAPPDATA\Perplexity\Comet\Application\comet.exe"
        # 检查本行条件；满足时执行对应分支。
        if (-not (Test-Path $exe)) { return @{ ok = $true; value = 'Comet 未安裝' } }
        # 读取正在运行的进程信息，并保存到 $running。
        $running = @(Get-Process comet -ErrorAction SilentlyContinue)
        # 计算本行表达式并设置 $v，供后续步骤使用。
        $v = (Get-Item $exe).VersionInfo.FileVersion
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ ok = $true; value = "已安裝 $v，目前 $($running.Count) 個行程（未探測，加 -IncludeCometProbe 才會實測）" }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束上一代码块并进入另一条件分支。
} else {
    # 处理 Check 所指定的操作或当前表达式的后续部分。
    Check '未解' 'Comet 無頭渲染探測' {
        # 计算本行表达式并设置 $exe，供后续步骤使用。
        $exe = "$env:LOCALAPPDATA\Perplexity\Comet\Application\comet.exe"
        # 检查本行条件；满足时执行对应分支。
        if (-not (Test-Path $exe)) { return @{ ok = $true; value = 'Comet 未安裝' } }
        # 检查本行条件；满足时执行对应分支。
        if (@(Get-Process comet -ErrorAction SilentlyContinue).Count -gt 0) {
            # 返回本行结果并结束当前函数。
            return @{ ok = $true; value = '略過：Comet 正在執行中，不打斷使用者' }
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 组合父目录与子路径，并保存到 $ud。
        $ud = Join-Path $script:Tmp 'comet_hs'
        # 组合父目录与子路径，并保存到 $shot。
        $shot = Join-Path $script:Tmp 'comet.png'
        # 不可用 -Wait：Comet 的無頭模式在本機不會自己結束，實測卡過 11.5 分鐘。
        # 使用指定程序和参数启动子进程，并保存到 $p。
        $p = Start-Process $exe -ArgumentList '--headless=new', "--user-data-dir=$ud", '--no-first-run', '--disable-gpu', "--screenshot=$shot", 'https://example.com' -PassThru -NoNewWindow
        # 等待子进程结束或到达指定时限；将不需要的返回值丢弃。
        $null = $p.WaitForExit(45000)
        # 只收拾自己啟動的那一棵行程樹，不碰其他 comet 行程
        # 检查本行条件；满足时执行对应分支。
        if (-not $p.HasExited) {
            # 丢弃不需要显示的输出。
            & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 這一項永遠 PASS：它是現況記錄，不是驗收條件
        # 检查目标路径是否存在。
        @{ ok = $true; value = if (Test-Path $shot) { '★ 無頭截圖成功，值得重測黑屏' } else { '無頭仍產不出截圖(與先前一致)' } }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================ 摘要
# 按条件筛选输入记录，并保存到 $pass。
$pass = @($script:Rows | Where-Object { $_.Status -eq 'PASS' }).Count
# 按条件筛选输入记录，并保存到 $fail。
$fail = @($script:Rows | Where-Object { $_.Status -eq 'FAIL' }).Count
# 按条件筛选输入记录，并保存到 $skip。
$skip = @($script:Rows | Where-Object { $_.Status -eq 'SKIP' }).Count
# 向终端显示提示或结果。
Write-Host ''
# 向终端显示提示或结果。
Write-Host ('=== 驗收結果： PASS ' + $pass + ' / FAIL ' + $fail + ' / SKIP ' + $skip + ' ===') -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
# 检查本行条件；满足时执行对应分支。
if ($fail) {
    # 向终端显示提示或结果。
    Write-Host '未通過項目：' -ForegroundColor Red
    # 按条件筛选输入记录；逐项处理管道传入的记录；向终端显示提示或结果。
    $script:Rows | Where-Object { $_.Status -eq 'FAIL' } | ForEach-Object { Write-Host ('  [' + $_.Area + '] ' + $_.Name + ' -> ' + $_.Value) -ForegroundColor Red }
# 结束此处的代码块、参数列表或集合定义。
}
# 生成当前时间或格式化时间戳；组合父目录与子路径，并保存到 $csv。
$csv = Join-Path $env:USERPROFILE ('Acceptance_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.csv')
# 将记录导出为 CSV 文件。
$script:Rows | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
# 向终端显示提示或结果。
Write-Host ('明細：' + $csv)
# 检查本行条件；满足时执行对应分支。
if ($fail) { exit 1 } else { exit 0 }
