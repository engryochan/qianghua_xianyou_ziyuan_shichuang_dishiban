#Requires -Version 5.1
<#
.SYNOPSIS
  把 Windows 10 強化成一台「可重現、跑得動大資料」的分析工作站。每一項都是獨立開關，全部支援 -WhatIf。
.DESCRIPTION
  這支腳本補的是 Win10_Optimize.ps1 沒做的事：Win10_Optimize.ps1 只「更新已安裝的東西」，
  這支則負責「把缺的東西補齊、把設定調對」。

  設計原則（與 v1 相同，不妥協）
    1. 先跑 Win10_Diagnose_v2.ps1，照 99_建議指令.txt 選開關；不帶開關時只顯示說明。
    2. 每一步都支援 -WhatIf 預演、-Confirm 逐項確認，全程寫入 log。
    3. 會改狀態的步驟先備份（R 套件清單、既有 .Rprofile、PATH、pagefile 設定）。
    4. 絕不碰遙測、服務、Defender 的開關，也絕不動企業管控代理（DLP / EDR / 透明加密）。
       那些只能由貴公司 IT 處理——自行停用既違規也解決不了問題。

  分兩次執行（權限不同）
    一般使用者： .\Setup_DataStack.ps1 -FixPath -ConfigureGit -SetupR -SetupPython -PrepareWorkspace
    系統管理員： .\Setup_DataStack.ps1 -EnableLongPaths -SetPageFile -AddDefenderExclusions
.EXAMPLE
  .\Setup_DataStack.ps1 -SetupR -WhatIf
.EXAMPLE
  .\Setup_DataStack.ps1 -InstallToolchain -InstallRtools -FixPath
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    # ---- 工具鏈 ----
    [switch]$InstallToolchain,      # winget：PowerShell 7 / DuckDB CLI / Quarto CLI（已安裝者自動略過）
    [switch]$InstallRtools,         # winget：Rtools（R 編譯工具鏈，沒有它就裝不了需編譯的套件）
    [switch]$InstallODBC,           # winget：PostgreSQL / MySQL ODBC 驅動（ID 未逐一查證，找不到會給官方下載連結）
    [switch]$UpdateApps,            # winget：升級已安裝的資料分析相關軟體

    # ---- 環境設定 ----
    [switch]$FixPath,               # 把 R / Quarto / Rtools 加入使用者 PATH，並把真 Python 排到 WindowsApps 之前
    [switch]$ConfigureGit,          # git 全域設定：longpaths / autocrlf / fscache / credential / 效能參數
    [switch]$PrepareWorkspace,      # 建立 C:\work 純 ASCII、未同步的工作區骨架
    [switch]$PowerPlanHigh,         # 切到高效能電源計畫

    # ---- 分析堆疊 ----
    [switch]$SetupR,                # 寫 .Rprofile（CRAN 鏡像 / Ncpus / 二進位優先）+ 用 pak 併發安裝 R 堆疊
    [switch]$SetupPython,           # 用 uv 建立鎖定版 Python 專案環境並安裝資料堆疊 + 註冊 Jupyter kernel
    [string]$PythonVersion = '3.13',# SetupPython 要用的 Python 版本（預設 3.13：wheel 覆蓋率與新版特性的平衡點）
    [string]$WorkRoot = 'C:\work',  # 工作區根目錄（純 ASCII、不在雲端同步範圍內）
    [ValidateSet('core', 'full')][string]$RProfile = 'full',   # R 套件組：core=最小可用；full=完整分析堆疊

    # ---- 需要系統管理員 ----
    [switch]$EnableLongPaths,       # 啟用 Windows 長路徑
    [switch]$SetPageFile,           # 把分頁檔固定為 0.5x ~ 1.0x 實體記憶體（避免大資料 OOM 被殺）
    [switch]$AddDefenderExclusions, # 對 R 套件庫 / venv / 工作區加 Defender 掃描排除（第三方代理仍須由 IT 處理）

    [switch]$All                    # = InstallToolchain InstallRtools FixPath ConfigureGit PrepareWorkspace SetupR SetupPython
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

if ($All) {
    $InstallToolchain = $true; $InstallRtools = $true; $FixPath = $true
    $ConfigureGit = $true; $PrepareWorkspace = $true; $SetupR = $true; $SetupPython = $true
}

$anySwitch = $InstallToolchain -or $InstallRtools -or $InstallODBC -or $UpdateApps -or $FixPath -or $ConfigureGit -or
$PrepareWorkspace -or $PowerPlanHigh -or $SetupR -or $SetupPython -or $EnableLongPaths -or $SetPageFile -or $AddDefenderExclusions
if (-not $anySwitch) {
    Get-Help $MyInvocation.MyCommand.Path -Full | Out-String -Width 200 | Write-Host
    Write-Host '未指定任何開關，未執行任何動作。請先跑 Win10_Diagnose_v2.ps1，再照 99_建議指令.txt 選開關。' -ForegroundColor Yellow
    return
}

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$log = Join-Path $env:USERPROFILE ('Setup_DataStack_' + $ts + '.log')
try { Start-Transcript -Path $log -WhatIf:$false | Out-Null } catch { }

# ---------------------------------------------------------------- 共用函式
function Step { param([string]$T) Write-Host ''; Write-Host ('>>> ' + $T) -ForegroundColor Cyan }
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Assert-Admin {
    param([string]$What)
    if (-not (Test-Admin)) { Write-Warning ($What + ' 需要系統管理員權限，已略過。'); return $false }
    return $true
}
function Find-Exe {
    param([string]$Name, [string[]]$Fallbacks = @())
    $c = Get-Command $Name -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
    if ($c) { return $c.Source }
    foreach ($pat in $Fallbacks) {
        $hit = Get-ChildItem -Path $pat -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}
function Find-Rscript {
    return (Find-Exe 'Rscript' @("$env:ProgramFiles\R\R-*\bin\x64\Rscript.exe", "$env:LOCALAPPDATA\Programs\R\R-*\bin\x64\Rscript.exe"))
}

$script:WingetExe = Find-Exe 'winget'

# winget 安裝：先確認 ID 真的存在、且尚未安裝，再動手。找不到就給官方下載連結，不硬幹。
function Install-WingetId {
    param([string]$Id, [string]$Why, [string]$ManualUrl)
    if (-not $script:WingetExe) { Write-Warning ('找不到 winget，無法安裝 ' + $Id + '。手動下載：' + $ManualUrl); return }
    $listed = & $script:WingetExe list --id $Id --exact --accept-source-agreements 2>$null | Out-String
    if ($listed -match [regex]::Escape($Id)) { Write-Host ('  已安裝，略過：' + $Id); return }
    $shown = & $script:WingetExe show --id $Id --exact --accept-source-agreements 2>$null | Out-String
    if ($shown -notmatch [regex]::Escape($Id)) {
        Write-Warning ('  winget 沒有這個套件 ID：' + $Id + '（ID 可能已更名）。請手動下載：' + $ManualUrl)
        return
    }
    if ($PSCmdlet.ShouldProcess($Id, 'winget install  # ' + $Why)) {
        & $script:WingetExe install --id $Id --exact --silent --accept-source-agreements --accept-package-agreements
        Write-Host ('  ' + $Id + ' -> ExitCode ' + $LASTEXITCODE)
    }
}

# 使用者 PATH 前置插入（讀原始未展開值，避免把 %VAR% 寫死）
function Add-UserPathEntry {
    param([string]$Entry, [switch]$Prepend)
    if (-not $Entry) { return $false }
    $raw = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($null -eq $raw) { $raw = '' }
    $parts = @($raw -split ';' | Where-Object { $_ -and $_.Trim() })
    $norm = $Entry.TrimEnd('\')
    foreach ($p in $parts) { if ($p.TrimEnd('\') -ieq $norm) { Write-Host ('  已在 PATH：' + $Entry); return $false } }
    if ($Prepend) { $new = @($Entry) + $parts } else { $new = $parts + @($Entry) }
    $joined = ($new -join ';')
    if ($PSCmdlet.ShouldProcess('使用者 PATH', '加入 ' + $Entry)) {
        [Environment]::SetEnvironmentVariable('Path', $joined, 'User')
        Write-Host ('  已加入 PATH：' + $Entry)
        return $true
    }
    return $false
}

$isAdmin = Test-Admin
Write-Host ('系統管理員身分：' + $isAdmin + '    預演模式(-WhatIf)：' + [bool]$WhatIfPreference)
Write-Host ('記錄檔：' + $log)

# ================================================================= 1. 工具鏈
if ($InstallToolchain) {
    Step '安裝核心工具鏈（PowerShell 7 / DuckDB CLI / Quarto CLI）'
    Install-WingetId -Id 'Microsoft.PowerShell' -Why 'ForEach-Object -Parallel、正確的 UTF-8 與 JSON 處理' -ManualUrl 'https://github.com/PowerShell/PowerShell/releases'
    Install-WingetId -Id 'DuckDB.cli' -Why '直接對 Parquet/CSV 下 SQL，不必整份讀進記憶體' -ManualUrl 'https://duckdb.org/docs/installation/'
    Install-WingetId -Id 'Posit.Quarto' -Why '命令列 quarto render，讓報表能進排程與 CI' -ManualUrl 'https://quarto.org/docs/get-started/'
    Write-Host '提醒：RStudio / Positron 內建自己的 quarto 與 pandoc；這裡裝的是「命令列版」，兩者不衝突。'
}

if ($InstallRtools) {
    Step '安裝 Rtools（R 的 C/C++/Fortran 編譯工具鏈）'
    Install-WingetId -Id 'RProject.Rtools' -Why '沒有它就無法安裝需編譯的套件，也無法用 Rcpp 自行加速' -ManualUrl 'https://cran.r-project.org/bin/windows/Rtools/'
    Write-Host '安裝後請重開 PowerShell，並用 -FixPath 把 Rtools 的 usr\bin 加進 PATH。'
}

if ($InstallODBC) {
    Step '安裝資料庫 ODBC 驅動'
    Write-Host '注意：以下 winget ID 未逐一查證，不存在時會直接給官方下載連結。' -ForegroundColor Yellow
    Install-WingetId -Id 'PostgreSQL.psqlODBC' -Why 'R odbc / Python pyodbc 連 PostgreSQL' -ManualUrl 'https://www.postgresql.org/ftp/odbc/versions/msi/'
    Install-WingetId -Id 'Oracle.MySQLConnectorODBC' -Why 'StarRocks / Doris / MySQL 都走 MySQL 協定' -ManualUrl 'https://dev.mysql.com/downloads/connector/odbc/'
    Write-Host 'ClickHouse ODBC 沒有官方 winget 套件，請見 https://github.com/ClickHouse/clickhouse-odbc/releases'
}

if ($UpdateApps) {
    Step '升級已安裝的資料分析相關軟體'
    $ids = @('RProject.R', 'RProject.Rtools', 'Posit.RStudio', 'Posit.Positron', 'Posit.Quarto',
        'Git.Git', 'Microsoft.PowerShell', 'DuckDB.cli', 'Python.Launcher')
    foreach ($id in $ids) {
        if (-not $script:WingetExe) { break }
        $listed = & $script:WingetExe list --id $id --exact --accept-source-agreements 2>$null | Out-String
        if ($listed -notmatch [regex]::Escape($id)) { Write-Host ('  未安裝，略過：' + $id); continue }
        if ($PSCmdlet.ShouldProcess($id, 'winget upgrade')) {
            & $script:WingetExe upgrade --id $id --exact --silent --accept-source-agreements --accept-package-agreements
            Write-Host ('  ' + $id + ' -> ExitCode ' + $LASTEXITCODE + '（無更新時也可能非 0）')
        }
    }
    Write-Host 'R 的次版本升級（例如 4.6 -> 4.7）會換一個新的套件庫，升級後請重跑 -SetupR。'
}

# ================================================================= 2. PATH
if ($FixPath) {
    Step '修正使用者 PATH'
    $backup = Join-Path $env:USERPROFILE ('PATH_user_backup_' + $ts + '.txt')
    Set-Content -Path $backup -Value ([Environment]::GetEnvironmentVariable('Path', 'User')) -Encoding UTF8 -WhatIf:$false
    Write-Host ('  已備份使用者 PATH：' + $backup + '（還原：把內容寫回使用者環境變數 Path）')

    # R
    $rbin = Get-ChildItem "$env:ProgramFiles\R\R-*\bin\x64" -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($rbin) { [void](Add-UserPathEntry -Entry $rbin.FullName) } else { Write-Host '  找不到 R 的 bin\x64。' }

    # Rtools
    $rtools = Get-ChildItem 'C:\rtools*\usr\bin', "$env:ProgramFiles\Rtools*\usr\bin" -Directory -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($rtools) { [void](Add-UserPathEntry -Entry $rtools.FullName) }

    # Quarto
    $q = Get-Item "$env:LOCALAPPDATA\Programs\Quarto\bin", "$env:ProgramFiles\Quarto\bin" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($q) { [void](Add-UserPathEntry -Entry $q.FullName) }

    # 真 Python 要排在 WindowsApps 前面，否則 python 會被 Store 別名攔截
    $realPy = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*" -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($realPy) {
        [void](Add-UserPathEntry -Entry $realPy.FullName -Prepend)
        [void](Add-UserPathEntry -Entry (Join-Path $realPy.FullName 'Scripts') -Prepend)
        Write-Host '  另外請到「設定 > 應用程式 > 應用程式執行別名」把 python.exe / python3.exe 關掉，'
        Write-Host '  否則 Store 別名仍可能在某些情境下攔截。這一步無法安全地用腳本代做。'
    }
    Write-Host '  PATH 變更要「重開 PowerShell / IDE」才會生效。'
}

# ================================================================= 3. Git
if ($ConfigureGit) {
    Step '設定 Git 全域參數'
    $git = Find-Exe 'git' @("$env:ProgramFiles\Git\cmd\git.exe")
    if (-not $git) {
        Write-Warning '找不到 git，已略過。'
    } else {
        $backup = Join-Path $env:USERPROFILE ('gitconfig_backup_' + $ts + '.txt')
        (& $git config --global --list) | Set-Content -Path $backup -Encoding UTF8 -WhatIf:$false
        Write-Host ('  已備份 git 全域設定：' + $backup)
        $cfg = [ordered]@{
            'core.longpaths'      = 'true'    # 配合 -EnableLongPaths，避免深層路徑 checkout 失敗
            'core.autocrlf'       = 'input'   # 工作區保持 LF，避免 Linux/容器端腳本換行錯誤
            'core.fscache'        = 'true'    # Windows 檔案系統快取，大 repo 狀態查詢明顯變快
            'core.preloadindex'   = 'true'
            'credential.helper'   = 'manager'
            'init.defaultBranch'  = 'main'
            'pull.rebase'         = 'false'
            'fetch.prune'         = 'true'
            'diff.renames'        = 'true'
        }
        foreach ($k in $cfg.Keys) {
            if ($PSCmdlet.ShouldProcess('git --global', $k + ' = ' + $cfg[$k])) {
                & $git config --global $k $cfg[$k]
                Write-Host ('  ' + $k + ' = ' + $cfg[$k])
            }
        }
        Write-Host '  提醒：core.autocrlf=input 只影響「之後」的 checkout；既有檔案要用 git add --renormalize . 重整。'
    }
}

# ================================================================= 4. 工作區
if ($PrepareWorkspace) {
    Step ('建立工作區骨架：' + $WorkRoot)
    $dirs = @('', 'projects', 'data', 'data\raw', 'data\parquet', 'data\quarantine', 'envs', 'tmp', 'rlibs', 'cache')
    foreach ($d in $dirs) {
        $p = if ($d) { Join-Path $WorkRoot $d } else { $WorkRoot }
        if (Test-Path -LiteralPath $p) { continue }
        if ($PSCmdlet.ShouldProcess($p, '建立資料夾')) { $null = New-Item -ItemType Directory -Path $p -Force }
    }
    $readme = @"
這個工作區刻意放在 $WorkRoot：
  * 純 ASCII 路徑  —— 避免 R 編譯、Python C 擴充、LaTeX 在中文路徑上出錯。
  * 不在 OneDrive 之下 —— 同步用戶端會鎖住 .git、renv/library、.venv、*.parquet，
    輕則變慢，重則 repo 或環境毀損。文件與最終報告才放雲端。

  projects/         程式碼與 Git repo
  data/raw/         原始資料，唯讀，永不就地修改
  data/parquet/     轉成 Parquet 的分析用資料（DuckDB / Arrow 直接查）
  data/quarantine/  品質檢查沒過的資料
  envs/             Python 虛擬環境（uv 管理）
  rlibs/            R 套件庫（若要脫離使用者設定檔時使用）
  tmp/              大型中間檔、DuckDB spill
  cache/            套件下載快取

搬移既有專案（先關掉 IDE 與 OneDrive 同步）：
  robocopy "<舊路徑>" "$WorkRoot\projects\<專案名>" /E /MOVE
"@
    $rp = Join-Path $WorkRoot 'README.txt'
    if ($PSCmdlet.ShouldProcess($rp, '寫入說明檔')) { Set-Content -Path $rp -Value $readme -Encoding UTF8 }
    Write-Host ''
    Write-Host '  這一步只建立骨架，不會自動搬你的專案——搬移要在 IDE 關閉、OneDrive 暫停同步時手動做。' -ForegroundColor Yellow
    Write-Host ('  例如： robocopy "' + (Get-Location).Path + '" "' + $WorkRoot + '\projects\' + (Split-Path (Get-Location).Path -Leaf) + '" /E /MOVE')
}

if ($PowerPlanHigh) {
    Step '切換電源計畫：高效能'
    if ($PSCmdlet.ShouldProcess('電源計畫', 'powercfg /setactive SCHEME_MIN')) {
        & powercfg.exe /setactive SCHEME_MIN
        if ($LASTEXITCODE -ne 0) { Write-Warning '切換失敗：此裝置可能沒有「高效能」計畫。' }
        & powercfg.exe /getactivescheme
    }
}

# ================================================================= 5. R 堆疊
if ($SetupR) {
    Step ('建立 R 分析堆疊（套件組：' + $RProfile + '）')
    $rs = Find-Rscript
    if (-not $rs) {
        Write-Warning '找不到 Rscript，已略過。請先安裝 R。'
    } elseif (Test-Admin) {
        Write-Warning '目前是系統管理員身分：套件可能被寫進系統套件庫，造成日後一般使用者無法更新。請改用一般使用者身分執行本步驟。'
    } else {
        $bk = Join-Path $env:USERPROFILE ('R_packages_backup_' + $ts + '.csv')
        $rFile = Join-Path $env:TEMP ('setup_r_' + $ts + '.R')
        $rCode = @'
options(warn = 1)
bk <- Sys.getenv("SETUP_BACKUP")
grp <- Sys.getenv("SETUP_GROUP")

## 0. 先備份現有套件清單（還原用）
ip <- installed.packages()
write.csv(data.frame(Package = ip[, "Package"], Version = ip[, "Version"],
                     LibPath = ip[, "LibPath"], stringsAsFactors = FALSE),
          bk, row.names = FALSE, fileEncoding = "UTF-8")
cat("backup:", bk, "\n")

## 1. 確保有可寫入的個人套件庫
lib <- Sys.getenv("R_LIBS_USER")
if (!nzchar(lib)) lib <- file.path(path.expand("~"), "R", "win-library",
                                   paste(R.version$major, strsplit(R.version$minor, ".", fixed = TRUE)[[1]][1], sep = "."))
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(lib, .libPaths()))
cat("target library:", lib, " writable=", file.access(lib, 2) == 0, "\n", sep = "")

## 2. 寫 .Rprofile：CRAN 鏡像、多核心安裝、二進位優先
prof <- file.path(path.expand("~"), ".Rprofile")
if (file.exists(prof)) {
  file.copy(prof, paste0(prof, ".bak_", format(Sys.time(), "%Y%m%d_%H%M%S")))
  cat("existing .Rprofile backed up\n")
}
ncpu <- max(1L, parallel::detectCores() - 2L)
lines <- c(
  '# --- managed by Setup_DataStack.ps1 -------------------------------------',
  'local({',
  '  r <- getOption("repos")',
  '  r["CRAN"] <- "https://cloud.r-project.org"',
  '  # 想要 Windows 預編譯二進位更即時，可改用 Posit Public Package Manager：',
  '  # r["CRAN"] <- "https://packagemanager.posit.co/cran/latest"',
  '  options(repos = r)',
  '})',
  sprintf('options(Ncpus = %d)                 # 併發安裝，安裝數百個套件時差別很大', ncpu),
  'options(install.packages.check.source = "no")  # 有二進位就別去編譯原始碼',
  'options(timeout = 600)                        # 大套件下載不要中途斷線',
  '',
  '# 刻意「不」在這裡設定會影響分析結果或執行緒數的選項',
  '# （例如 warnPartialMatchArgs / OMP_NUM_THREADS / TZ / 語系）。',
  '# 理由：.Rprofile 是這台機器獨有的。凡是會改變程式行為的設定放在這裡，',
  '# 同一份腳本在同事機器或 CI 上就會跑出不同結果，而且極難追查。',
  '# 上面這幾行只影響「套件怎麼裝」，不影響「程式怎麼跑」——這是安全的分界線。',
  '# 要控制執行緒請在腳本內明示：data.table::setDTthreads()、arrow::set_cpu_count()。',
  '# 要鎖定套件版本請用 renv::init()，不要靠全域套件庫。',
  '# --- end managed block ---------------------------------------------------'
)
writeLines(lines, prof, useBytes = TRUE)
cat("wrote .Rprofile:", prof, "\n")
options(repos = c(CRAN = "https://cloud.r-project.org"), Ncpus = ncpu,
        install.packages.check.source = "no", timeout = 600)

## 3. pak：官方預編譯版，不需要 Rtools 就能裝，之後靠它併發解依賴
if (!requireNamespace("pak", quietly = TRUE)) {
  install.packages("pak", lib = lib,
                   repos = sprintf("https://r-lib.github.io/p/pak/stable/%s/%s/%s",
                                   .Platform$pkgType, R.Version()$os, R.Version()$arch))
}
has_pak <- requireNamespace("pak", quietly = TRUE)
cat("pak available:", has_pak, "\n")

core <- c("renv", "here", "conflicted", "sessioninfo",
          "data.table", "tidyverse", "janitor", "lubridate",
          "arrow", "duckdb", "DBI", "RSQLite", "odbc", "dbplyr",
          "ggplot2", "scales", "knitr", "rmarkdown", "quarto")
full <- c(core,
          "dtplyr", "collapse", "stringi", "fst", "qs", "vroom",
          "RPostgres", "RMariaDB", "pool",
          "xts", "zoo", "tsibble", "fable", "forecast", "TTR", "quantmod",
          "PerformanceAnalytics", "rugarch",
          "tidymodels", "xgboost", "lightgbm", "ranger", "glmnet",
          "survival", "survminer", "grf", "depmixS4",
          "DALEX", "iml", "fastshap", "vip", "pdp",
          "gt", "gtsummary", "flextable", "officer",
          "plotly", "ggiraph", "patchwork", "ggrepel",
          "future", "furrr", "parallelly", "Rcpp", "bench", "profvis",
          "shiny", "bslib", "shinyWidgets", "shinyjs", "DT", "reactable",
          "targets", "testthat", "lintr", "styler", "logger", "reticulate")
want <- if (identical(grp, "core")) core else full
todo <- setdiff(want, rownames(installed.packages()))
cat("to install:", length(todo), "\n")
if (length(todo)) {
  if (has_pak) {
    pak::pkg_install(todo, lib = lib, ask = FALSE)
  } else {
    install.packages(todo, lib = lib, Ncpus = ncpu)
  }
}

## 4. 結算：哪些真的裝起來了、哪些沒有
inst <- rownames(installed.packages())
ok <- intersect(want, inst); bad <- setdiff(want, inst)
cat("installed ok:", length(ok), "/", length(want), "\n")
if (length(bad)) {
  cat("STILL MISSING:", paste(bad, collapse = ", "), "\n")
  cat("多半是需要編譯（請先裝 Rtools）或需要系統相依套件。逐一 install.packages() 看錯誤訊息。\n")
}
cat("BLAS:", extSoftVersion()[["BLAS"]], "\n")
'@
        if ($PSCmdlet.ShouldProcess('R 個人套件庫', '寫入 .Rprofile 並安裝 ' + $RProfile + ' 套件組（備份：' + $bk + '）')) {
            Set-Content -Path $rFile -Value $rCode -Encoding ASCII -WhatIf:$false
            $env:SETUP_BACKUP = $bk
            $env:SETUP_GROUP = $RProfile
            & $rs $rFile
            Remove-Item $rFile -Force -ErrorAction SilentlyContinue
            Write-Host ''
            Write-Host '  下載量大（full 組約數百 MB），第一次可能要 20-60 分鐘，視網路與防毒掃描而定。'
            Write-Host '  需要「可重現」的專案，請在該專案目錄另外跑 renv::init()，不要靠全域套件庫。' -ForegroundColor Yellow
        }
    }
}

# ================================================================= 6. Python 堆疊
if ($SetupPython) {
    Step ('建立 Python 分析環境（uv + Python ' + $PythonVersion + '）')
    $uv = Find-Exe 'uv' @("$env:USERPROFILE\.local\bin\uv.exe")
    if (-not $uv) {
        Write-Warning '找不到 uv。安裝方式： winget install --id astral-sh.uv   或   https://docs.astral.sh/uv/'
    } else {
        $envDir = Join-Path $WorkRoot 'envs\ds'
        $pkgs = @(
            'pandas', 'polars', 'numpy', 'pyarrow', 'duckdb',
            'sqlalchemy', 'pymysql', 'psycopg[binary]', 'pyodbc',
            'scikit-learn', 'scipy', 'statsmodels', 'xgboost', 'lightgbm',
            'shap', 'lifelines',
            'matplotlib', 'seaborn', 'plotly', 'great-tables',
            'jupyterlab', 'ipykernel', 'papermill',
            'ruff', 'pytest'
        )
        if ($PSCmdlet.ShouldProcess($envDir, 'uv venv + 安裝 ' + $pkgs.Count + ' 個套件')) {
            $null = New-Item -ItemType Directory -Path (Split-Path $envDir -Parent) -Force
            & $uv python install $PythonVersion
            & $uv venv --python $PythonVersion $envDir
            $venvPy = Join-Path $envDir 'Scripts\python.exe'
            if (Test-Path $venvPy) {
                & $uv pip install --python $venvPy @pkgs
                Write-Host ''
                Write-Host '  鎖定版本（可重現的關鍵）：'
                $req = Join-Path $envDir 'requirements.lock.txt'
                & $uv pip freeze --python $venvPy | Set-Content -Path $req -Encoding UTF8
                Write-Host ('  已寫出 ' + $req + '（重建環境： uv pip install --python <新venv> -r ' + $req + '）')
                Write-Host ''
                Write-Host '  註冊 Jupyter kernel：'
                & $venvPy -m ipykernel install --user --name ds --display-name ('Python ' + $PythonVersion + ' (ds)')
                Write-Host ''
                Write-Host ('  在 Positron / VS Code 選直譯器時指向：' + $venvPy) -ForegroundColor Green
                Write-Host ('  R 端要用 reticulate 時：Sys.setenv(RETICULATE_PYTHON = "' + $venvPy + '")')
            } else {
                Write-Warning ('建立虛擬環境失敗：找不到 ' + $venvPy)
            }
        }
        Write-Host ''
        Write-Host '  為什麼不用全域 pip install：全域環境一旦混入互相衝突的版本，就得整台重裝。' -ForegroundColor Yellow
        Write-Host '  正式專案請用 uv init / uv add，讓 pyproject.toml + uv.lock 進版控。' -ForegroundColor Yellow
    }
}

# ================================================================= 7. 需要系統管理員
if ($EnableLongPaths) {
    Step '啟用 Windows 長路徑'
    if (Assert-Admin '啟用長路徑') {
        $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
        $cur = $null
        try { $cur = (Get-ItemProperty -Path $k -Name LongPathsEnabled -ErrorAction Stop).LongPathsEnabled } catch { }
        if ($cur -eq 1) { Write-Host '  已是啟用狀態。' }
        elseif ($PSCmdlet.ShouldProcess($k, 'LongPathsEnabled = 1')) {
            New-ItemProperty -Path $k -Name LongPathsEnabled -Value 1 -PropertyType DWord -Force | Out-Null
            Write-Host '  已啟用（需重新開機；應用程式本身也要支援才有效）。'
        }
    }
}

if ($SetPageFile) {
    Step '固定分頁檔大小（避免大資料運算被系統直接終止）'
    if (Assert-Admin '設定分頁檔') {
        $ramMB = [int]((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)
        $initMB = [int]($ramMB * 0.5)
        $maxMB = [int]($ramMB * 1.0)
        $free = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1MB
        Write-Host ('  實體記憶體 ' + $ramMB + ' MB；預計設定 C:\pagefile.sys 初始 ' + $initMB + ' MB / 最大 ' + $maxMB + ' MB')
        if ($free -lt ($maxMB + 20480)) {
            Write-Warning ('  C: 剩餘空間僅 ' + [int]$free + ' MB，設定 ' + $maxMB + ' MB 分頁檔後會過於吃緊，已略過。請先清出空間。')
        } elseif ($PSCmdlet.ShouldProcess('C:\pagefile.sys', "初始 $initMB MB / 最大 $maxMB MB")) {
            $bk = Join-Path $env:USERPROFILE ('pagefile_backup_' + $ts + '.txt')
            (Get-WmiObject Win32_PageFileSetting | Out-String) | Set-Content -Path $bk -Encoding UTF8 -WhatIf:$false
            Add-Content -Path $bk -Value ('AutomaticManagedPagefile=' + (Get-WmiObject Win32_ComputerSystem).AutomaticManagedPagefile) -WhatIf:$false
            Write-Host ('  已備份原設定：' + $bk)
            $csw = Get-WmiObject Win32_ComputerSystem -EnableAllPrivileges
            if ($csw.AutomaticManagedPagefile) { $csw.AutomaticManagedPagefile = $false; [void]$csw.Put() }
            $pfs = Get-WmiObject Win32_PageFileSetting | Where-Object { $_.Name -like 'C:*' }
            if ($pfs) {
                $pfs.InitialSize = $initMB; $pfs.MaximumSize = $maxMB; [void]$pfs.Put()
            } else {
                $null = Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{ Name = 'C:\pagefile.sys'; InitialSize = $initMB; MaximumSize = $maxMB }
            }
            Write-Host '  已設定，需重新開機生效。還原方式：系統內容 > 進階 > 效能 > 虛擬記憶體 > 自動管理。'
        }
    }
}

if ($AddDefenderExclusions) {
    Step '對開發目錄加入 Microsoft Defender 掃描排除'
    if (Assert-Admin '設定 Defender 排除') {
        $paths = @()
        $paths += $WorkRoot
        $rlib = [Environment]::GetEnvironmentVariable('R_LIBS_USER', 'User')
        if (-not $rlib) { $rlib = Join-Path $env:LOCALAPPDATA 'R\win-library' }
        $paths += [Environment]::ExpandEnvironmentVariables($rlib)
        $paths += (Join-Path $env:LOCALAPPDATA 'R')
        $paths += (Join-Path $env:USERPROFILE '.cache\uv')
        $paths += (Join-Path $env:LOCALAPPDATA 'uv')
        $paths = @($paths | Where-Object { $_ } | Select-Object -Unique)

        Write-Host '  排除掃描 = 用一點安全性換取安裝與讀寫速度。只排「你自己的程式碼與套件庫」，' -ForegroundColor Yellow
        Write-Host '  絕不要排除 Downloads、桌面或整顆 C:。若公司政策不允許，請直接跳過這一步。' -ForegroundColor Yellow
        foreach ($p in $paths) {
            if (-not (Test-Path -LiteralPath $p)) { Write-Host ('  路徑不存在，略過：' + $p); continue }
            if ($PSCmdlet.ShouldProcess($p, 'Add-MpPreference -ExclusionPath')) {
                try { Add-MpPreference -ExclusionPath $p -ErrorAction Stop; Write-Host ('  已排除：' + $p) }
                catch { Write-Warning ('  失敗（可能被群組原則鎖定）：' + $_.Exception.Message) }
            }
        }
        Write-Host ''
        Write-Host '  重要：這只對 Microsoft Defender 有效。機器上的第三方防毒與透明加密／DLP 用戶端' -ForegroundColor Yellow
        Write-Host '  不受這裡影響，必須由貴公司 IT 在他們的管理主控台加白名單。' -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host '完成。建議流程：重新開機 -> 重跑 Win10_Diagnose_v2.ps1 -> 比對 00_摘要.txt 的發現數量。' -ForegroundColor Green
Write-Host ('記錄檔：' + $log)
try { Stop-Transcript | Out-Null } catch { }
