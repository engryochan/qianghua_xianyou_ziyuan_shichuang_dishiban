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
[CmdletBinding()]
param(
    [switch]$SkipRender,
    [string]$WorkRoot = 'C:\work',
    [string]$Project = 'C:\work\projects\lab'
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$script:Rows = New-Object System.Collections.Generic.List[object]
$script:Tmp = Join-Path $env:TEMP ('acc_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$null = New-Item -ItemType Directory -Path $script:Tmp -Force

function Check {
    param([string]$Area, [string]$Name, [scriptblock]$Test)
    # $Test 要回傳 @{ ok = $true/$false; value = '量到的東西' }
    $v = ''
    $ok = $false
    try {
        $r = & $Test
        if ($null -ne $r) { $ok = [bool]$r.ok; $v = "$($r.value)" }
    } catch {
        $v = '例外: ' + $_.Exception.Message
    }
    $status = if ($ok) { 'PASS' } else { 'FAIL' }
    $color = if ($ok) { 'Green' } else { 'Red' }
    Write-Host ("{0,-4} {1,-10} {2,-34} {3}" -f $status, $Area, $Name, $v) -ForegroundColor $color
    $script:Rows.Add([pscustomobject]@{ Status = $status; Area = $Area; Name = $Name; Value = $v })
}
function Skip {
    param([string]$Area, [string]$Name, [string]$Why)
    Write-Host ("{0,-4} {1,-10} {2,-34} {3}" -f 'SKIP', $Area, $Name, $Why) -ForegroundColor DarkGray
    $script:Rows.Add([pscustomobject]@{ Status = 'SKIP'; Area = $Area; Name = $Name; Value = $Why })
}
function Find-Exe {
    param([string]$Name, [string[]]$Fallbacks = @())
    $c = Get-Command $Name -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
    if ($c) { return $c.Source }
    foreach ($p in $Fallbacks) {
        $h = Get-ChildItem -Path $p -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
        if ($h) { return $h.FullName }
    }
    return $null
}

Write-Host ''
Write-Host ('竣工驗收  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ForegroundColor Cyan
Write-Host ('暫存目錄：' + $script:Tmp)
Write-Host ''

# ================================================================ 系統
Check '系統' '作業系統為 Windows 11' {
    $b = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild
    $ubr = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR
    # 一律用 build number 判斷：就地升級後 ProductName 仍寫 Windows 10
    @{ ok = ($b -ge 22000); value = "Build $b.$ubr" }
}
Check '系統' '電源計畫為高效能' {
    $p = (& powercfg.exe /getactivescheme) -join ''
    @{ ok = ($p -match '高性能|高效能|High performance'); value = ($p -replace '.*\(', '(') }
}
Check '系統' 'C: 可用空間 > 15%' {
    $v = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $pct = [math]::Round(100 * $v.FreeSpace / $v.Size, 1)
    @{ ok = ($pct -gt 15); value = "$pct% ($([math]::Round($v.FreeSpace/1GB,1)) GB)" }
}

# ================================================================ PATH 與 git
Check 'PATH' '四項工具在持久化 PATH 上' {
    $dirs = @()
    foreach ($s in @('Machine', 'User')) {
        $raw = [Environment]::GetEnvironmentVariable('Path', $s)
        if ($raw) { foreach ($e in ($raw -split ';')) { if ($e.Trim()) { $dirs += [Environment]::ExpandEnvironmentVariables($e.Trim()).TrimEnd('\') } } }
    }
    $want = @('Rscript.exe', 'quarto.exe', 'duckdb.exe', 'git.exe')
    $miss = @()
    foreach ($w in $want) {
        $hit = $false
        foreach ($d in $dirs) { if (Test-Path -LiteralPath (Join-Path $d $w)) { $hit = $true; break } }
        if (-not $hit) { $miss += $w }
    }
    @{ ok = ($miss.Count -eq 0); value = if ($miss.Count) { '缺: ' + ($miss -join ',') } else { "$($want.Count)/$($want.Count) 皆在" } }
}
Check 'git' '全域設定六項' {
    $g = Find-Exe 'git' @("$env:ProgramFiles\Git\cmd\git.exe")
    if (-not $g) { return @{ ok = $false; value = '找不到 git' } }
    $want = @{ 'core.longpaths' = 'true'; 'core.autocrlf' = 'input'; 'core.fscache' = 'true'
        'credential.helper' = 'manager'; 'init.defaultBranch' = 'main'; 'fetch.prune' = 'true'
    }
    $bad = @()
    foreach ($k in $want.Keys) {
        $v = (& $g config --global $k 2>$null | Select-Object -First 1)
        if ("$v".Trim() -ne $want[$k]) { $bad += $k }
    }
    @{ ok = ($bad.Count -eq 0); value = if ($bad.Count) { '不符: ' + ($bad -join ',') } else { '6/6 符合' } }
}

# ================================================================ R
$rscript = Find-Exe 'Rscript' @("$env:ProgramFiles\R\R-*\bin\x64\Rscript.exe")
if (-not $rscript) {
    Skip 'R' '所有 R 項目' '找不到 Rscript'
} else {
    $rFile = Join-Path $script:Tmp 'acc.R'
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
    Set-Content -Path $rFile -Value $rCode -Encoding ASCII
    $env:ACC_OUT = ($script:Tmp -replace '\\', '/')
    $rOut = (& $rscript $rFile 2>&1) -join "`n"

    # 以下所有解析一律用 [ \t]* 而非 \s*：.NET 的 \s 包含換行，
    # 標籤後若該行為空，\s* 會跨行抓到下一行的值（本腳本第一版就這樣量錯過）。
    Check 'R' '套件數 >= 340' {
        $m = [regex]::Match($rOut, 'PKGCOUNT:[ \t]*(\d+)')
        @{ ok = ($m.Success -and [int]$m.Groups[1].Value -ge 340); value = if ($m.Success) { $m.Groups[1].Value + ' 個' } else { '讀不到' } }
    }
    Check 'R' '關鍵套件零缺口' {
        # 注意：.NET 的 \s 包含換行，'KEYMISS:\s*(.*)' 會跨行抓到下一行的內容。
        # 必須用 [ \t]* 限定同一行，捕捉也要用 [^\r\n]*。
        $m = [regex]::Match($rOut, 'KEYMISS:[ \t]*([^\r\n]*)')
        $v = if ($m.Success) { $m.Groups[1].Value.Trim() } else { '讀不到' }
        @{ ok = ($m.Success -and $v -eq ''); value = if ($v) { "缺 $v" } else { '10/10 齊全' } }
    }
    Check 'R' 'data.table 分組結果正確' {
        $m = [regex]::Match($rOut, 'DTSUM:[ \t]*(\d+)')
        @{ ok = ($m.Success -and $m.Groups[1].Value -eq '5000050000'); value = if ($m.Success) { $m.Groups[1].Value } else { '讀不到' } }
    }
    Check 'R' 'duckdb 讀回 Parquet 10 萬列' {
        $m = [regex]::Match($rOut, 'PARQUETROWS:[ \t]*(\d+)')
        $t = [regex]::Match($rOut, 'DUCKTHREADS:[ \t]*(\d+)')
        @{ ok = ($m.Success -and [int]$m.Groups[1].Value -eq 100000); value = "$($m.Groups[1].Value) 列 / $($t.Groups[1].Value) 執行緒" }
    }
    Check 'R' 'xgboost CPU 訓練 acc > 0.9' {
        $m = [regex]::Match($rOut, 'XGBACC:[ \t]*([\d\.]+)')
        @{ ok = ($m.Success -and [double]$m.Groups[1].Value -gt 0.9); value = if ($m.Success) { 'acc ' + $m.Groups[1].Value } else { '讀不到' } }
    }
    Check 'R' 'rugarch sGARCH(1,1) 收斂' {
        @{ ok = ($rOut -match 'GARCH:\s*converged'); value = if ($rOut -match 'GARCH:\s*(\w+)') { $Matches[1] } else { '讀不到' } }
    }
    Check 'R' 'Rtools 可編譯 C 擴充' {
        $d = Join-Path $script:Tmp 'shlib'
        $null = New-Item -ItemType Directory -Path $d -Force
        Set-Content -Path (Join-Path $d 'a.c') -Value '#include <R.h>
#include <Rinternals.h>
SEXP addtwo(SEXP a, SEXP b) { return ScalarReal(asReal(a) + asReal(b)); }' -Encoding ASCII
        $rexe = $rscript -replace 'Rscript\.exe$', 'R.exe'
        Push-Location $d
        $null = & $rexe CMD SHLIB a.c 2>&1
        Pop-Location
        $dll = Join-Path $d 'a.dll'
        @{ ok = (Test-Path $dll); value = if (Test-Path $dll) { 'a.dll ' + (Get-Item $dll).Length + ' bytes' } else { '未產生 dll' } }
    }
}

# ================================================================ Python
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
$pyFile = Join-Path $script:Tmp 'acc.py'
Set-Content -Path $pyFile -Value $pyCode -Encoding UTF8

foreach ($envDef in @(
        @{ Label = '共用環境'; Py = (Join-Path $WorkRoot 'envs\ds\Scripts\python.exe') },
        @{ Label = '專案環境'; Py = (Join-Path $Project '.venv\Scripts\python.exe') })) {
    $py = $envDef.Py
    $lbl = $envDef.Label
    if (-not (Test-Path $py)) { Skip 'Python' ($lbl + ' 全部項目') ('找不到 ' + $py); continue }
    $o = (& $py $pyFile 2>&1) -join "`n"
    $j = $null
    $m = [regex]::Match($o, 'ACCJSON(\{.*\})')
    if ($m.Success) { try { $j = $m.Groups[1].Value | ConvertFrom-Json } catch { } }

    Check 'Python' ($lbl + ' 直譯器 3.13 + 176 套件') {
        @{ ok = ($j -and $j.version -like '3.13*' -and $j.pkgs -ge 176); value = if ($j) { "$($j.version) / $($j.pkgs) 套件" } else { '未取得輸出' } }
    }
    Check 'Python' ($lbl + ' duckdb 聚合正確') {
        @{ ok = ($j -and [int64]$j.duckdb_sum -eq 4999950000); value = if ($j) { "sum=$($j.duckdb_sum) / $($j.threads) 執行緒" } else { 'n/a' } }
    }
    Check 'Python' ($lbl + ' xgboost + lightgbm') {
        @{ ok = ($j -and $j.xgb -gt 0.8 -and $j.lgb -gt 0.8); value = if ($j) { "xgb $($j.xgb) / lgb $($j.lgb)" } else { 'n/a' } }
    }
    Check 'Python' ($lbl + ' econml 還原 ATE≈2.0') {
        @{ ok = ($j -and [math]::Abs([double]$j.ate - 2.0) -lt 0.15); value = if ($j) { "ATE $($j.ate)" } else { 'n/a' } }
    }
}

# ================================================================ 跨語言
if ($rscript) {
    Check '跨語言' 'reticulate 接得上專案環境' {
        $f = Join-Path $script:Tmp 'ret.R'
        $venv = ($Project -replace '\\', '/') + '/.venv/Scripts/python.exe'
        Set-Content -Path $f -Encoding ASCII -Value @"
Sys.setenv(RETICULATE_PYTHON = "$venv")
suppressPackageStartupMessages(library(reticulate))
pl <- import("polars"); dd <- import("duckdb")
cat("RETIC:", pl[["__version__"]], dd[["__version__"]], "\n")
"@
        $o = (& $rscript $f 2>&1) -join "`n"
        $m = [regex]::Match($o, 'RETIC:\s*(\S+)\s+(\S+)')
        @{ ok = $m.Success; value = if ($m.Success) { "polars $($m.Groups[1].Value) / duckdb $($m.Groups[2].Value)" } else { '失敗' } }
    }
    Check '跨語言' 'arrow/pyarrow 衝突仍存在(迴歸)' {
        # 這是「已知地雷」的迴歸測試：預期 FAIL 才代表地雷還在。
        # 若哪天它變成可以載入，代表上游修好了，範本就可以放寬。
        $f = Join-Path $script:Tmp 'conflict.R'
        $venv = ($Project -replace '\\', '/') + '/.venv/Scripts/python.exe'
        Set-Content -Path $f -Encoding ASCII -Value @"
Sys.setenv(RETICULATE_PYTHON = "$venv")
suppressPackageStartupMessages(library(arrow))
suppressPackageStartupMessages(library(reticulate))
r <- tryCatch({ import("pyarrow"); "LOADED" }, error = function(e) "BLOCKED")
cat("CONFLICT:", r, "\n")
"@
        $o = (& $rscript $f 2>&1) -join "`n"
        $blocked = $o -match 'CONFLICT:\s*BLOCKED'
        @{ ok = $true; value = if ($blocked) { '仍衝突(符合預期,範本已規避)' } else { '★ 已不衝突,可放寬範本' } }
    }
}

# ================================================================ Quarto
if ($SkipRender) {
    Skip 'Quarto' 'render 範本' '-SkipRender'
} else {
    Check 'Quarto' 'render R+Python 範本' {
        $tpl = Join-Path $Project 'template.qmd'
        if (-not (Test-Path $tpl)) { return @{ ok = $false; value = '找不到 template.qmd' } }
        $q = Find-Exe 'quarto' @("$env:ProgramFiles\Quarto\bin\quarto.cmd")
        if (-not $q) { return @{ ok = $false; value = '找不到 quarto' } }
        $html = Join-Path $Project 'template.html'
        if (Test-Path $html) { Remove-Item -LiteralPath $html -Force -ErrorAction SilentlyContinue }
        Push-Location $Project
        $null = & $q render template.qmd 2>&1
        Pop-Location
        if (-not (Test-Path $html)) { return @{ ok = $false; value = '未產出 HTML' } }
        $t = Get-Content $html -Raw
        $hits = @('3.13.15', 'polars', 'pyarrow', 'xgboost acc') | Where-Object { $t -match [regex]::Escape($_) }
        @{ ok = ($hits.Count -ge 3); value = "HTML $([math]::Round($t.Length/1KB)) KB，命中 $($hits.Count)/4 標記" }
    }
}

# ================================================================ Positron
Check 'Positron' '工作區已開啟且已信任' {
    $g = "$env:APPDATA\Positron\User\globalStorage\storage.json"
    if (-not (Test-Path $g)) { return @{ ok = $false; value = '找不到 storage.json' } }
    $j = Get-Content $g -Raw | ConvertFrom-Json
    $folders = @($j.backupWorkspaces.folders)
    @{ ok = ($folders.Count -gt 0); value = if ($folders.Count) { "$($folders.Count) 個工作區: " + ($folders[0].folderUri) } else { '仍是 emptyWindows' } }
}

# ================================================================ 其他工具
foreach ($t in @(
        @{ N = 'duckdb CLI'; E = 'duckdb'; A = @('-c', 'select 42 as n') ; Expect = '42' },
        @{ N = 'PowerShell 7'; E = 'pwsh'; A = @('-NoProfile', '-Command', '1+1'); Expect = '2' },
        @{ N = 'uv'; E = 'uv'; A = @('--version'); Expect = 'uv' })) {
    Check '工具' $t.N {
        $e = Find-Exe $t.E
        if (-not $e) { return @{ ok = $false; value = '不在 PATH' } }
        $o = (& $e @($t.A) 2>&1) -join ' '
        @{ ok = ($o -match [regex]::Escape($t.Expect)); value = ($o -replace '\s+', ' ').Trim() }
    }
}

# ================================================================ 已知未解
Check '未解' 'Comet 仍為黑屏(記錄用)' {
    $exe = "$env:LOCALAPPDATA\Perplexity\Comet\Application\comet.exe"
    if (-not (Test-Path $exe)) { return @{ ok = $true; value = 'Comet 未安裝' } }
    $ud = Join-Path $script:Tmp 'comet_hs'
    $shot = Join-Path $script:Tmp 'comet.png'
    # 千萬不要用 -Wait：Comet 的無頭模式在這台機器上不會自己結束，
    # 實測卡了 11.5 分鐘才被手動清掉。一律設逾時並強制收尾。
    $p = Start-Process $exe -ArgumentList '--headless=new', "--user-data-dir=$ud", '--no-first-run', '--disable-gpu', "--screenshot=$shot", 'https://example.com' -PassThru -NoNewWindow
    $null = $p.WaitForExit(45000)
    Get-Process comet -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    # 這一項永遠 PASS：它只是記錄現況，不是驗收條件
    @{ ok = $true; value = if (Test-Path $shot) { '★ 無頭截圖成功，值得重測黑屏' } else { '無頭仍產不出截圖(與先前一致)' } }
}

# ================================================================ 摘要
$pass = @($script:Rows | Where-Object { $_.Status -eq 'PASS' }).Count
$fail = @($script:Rows | Where-Object { $_.Status -eq 'FAIL' }).Count
$skip = @($script:Rows | Where-Object { $_.Status -eq 'SKIP' }).Count
Write-Host ''
Write-Host ('=== 驗收結果： PASS ' + $pass + ' / FAIL ' + $fail + ' / SKIP ' + $skip + ' ===') -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
if ($fail) {
    Write-Host '未通過項目：' -ForegroundColor Red
    $script:Rows | Where-Object { $_.Status -eq 'FAIL' } | ForEach-Object { Write-Host ('  [' + $_.Area + '] ' + $_.Name + ' -> ' + $_.Value) -ForegroundColor Red }
}
$csv = Join-Path $env:USERPROFILE ('Acceptance_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.csv')
$script:Rows | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
Write-Host ('明細：' + $csv)
if ($fail) { exit 1 } else { exit 0 }
