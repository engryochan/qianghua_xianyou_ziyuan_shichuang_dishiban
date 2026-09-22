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
# 启用 PowerShell 高级脚本参数绑定及所列功能。
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
# 声明脚本或函数接受的参数及默认值。
param(
    # ---- 工具鏈 ----
    [switch]$InstallToolchain,      # winget：PowerShell 7 / DuckDB CLI / Quarto CLI（已安裝者自動略過）
    [switch]$InstallRtools,         # winget：Rtools（R 編譯工具鏈，沒有它就裝不了需編譯的套件）
    [switch]$InstallODBC,           # winget：PostgreSQL / MySQL ODBC 驅動（ID 未逐一查證，找不到會給官方下載連結）
    [switch]$UpdateApps,            # winget：升級已安裝的資料分析相關軟體

    # ---- 環境設定 ----
    [switch]$FixPath,               # 把 R / Quarto 加入使用者 PATH，並把真 Python 排到 WindowsApps 之前
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
# 结束此处的代码块、参数列表或集合定义。
)

# 处理 Set-StrictMode 所指定的操作或当前表达式的后续部分。
Set-StrictMode -Off
# 设置本脚本遇到 PowerShell 错误时的处理方式。
$ErrorActionPreference = 'Continue'
# 开始受异常处理保护的操作。
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# 检查本行条件；满足时执行对应分支。
if ($All) {
    # 计算本行表达式并设置 $InstallToolchain，供后续步骤使用。
    $InstallToolchain = $true; $InstallRtools = $true; $FixPath = $true
    # 计算本行表达式并设置 $ConfigureGit，供后续步骤使用。
    $ConfigureGit = $true; $PrepareWorkspace = $true; $SetupR = $true; $SetupPython = $true
# 结束此处的代码块、参数列表或集合定义。
}

# 计算本行表达式并设置 $anySwitch，供后续步骤使用。
$anySwitch = $InstallToolchain -or $InstallRtools -or $InstallODBC -or $UpdateApps -or $FixPath -or $ConfigureGit -or
# 处理 $PrepareWorkspace 所指定的操作或当前表达式的后续部分。
$PrepareWorkspace -or $PowerPlanHigh -or $SetupR -or $SetupPython -or $EnableLongPaths -or $SetPageFile -or $AddDefenderExclusions
# 检查本行条件；满足时执行对应分支。
if (-not $anySwitch) {
    # 把结果转换为文本；向终端显示提示或结果。
    Get-Help $MyInvocation.MyCommand.Path -Full | Out-String -Width 200 | Write-Host
    # 向终端显示提示或结果。
    Write-Host '未指定任何開關，未執行任何動作。請先跑 Win10_Diagnose_v2.ps1，再照 99_建議指令.txt 選開關。' -ForegroundColor Yellow
    # 返回本行结果并结束当前函数。
    return
# 结束此处的代码块、参数列表或集合定义。
}

# 生成当前时间或格式化时间戳，并保存到 $ts。
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
# 组合父目录与子路径，并保存到 $log。
$log = Join-Path $env:USERPROFILE ('Setup_DataStack_' + $ts + '.log')
# 开始受异常处理保护的操作。
try { Start-Transcript -Path $log -WhatIf:$false | Out-Null } catch { }

# ---------------------------------------------------------------- 共用函式
# 定义 Step，封装此函数内的操作。
function Step { param([string]$T) Write-Host ''; Write-Host ('>>> ' + $T) -ForegroundColor Cyan }
# 定义 Test-Admin，封装此函数内的操作。
function Test-Admin {
    # 构造或计算 $id，保存本行指定的集合或索引结果。
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    # 返回本行结果并结束当前函数。
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Assert-Admin，封装此函数内的操作。
function Assert-Admin {
    # 声明脚本或函数接受的参数及默认值。
    param([string]$What)
    # 检查本行条件；满足时执行对应分支。
    if (-not (Test-Admin)) { Write-Warning ($What + ' 需要系統管理員權限，已略過。'); return $false }
    # 返回本行结果并结束当前函数。
    return $true
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
    foreach ($pat in $Fallbacks) {
        # 枚举指定位置的文件、目录或注册表项；选取记录中的指定字段或条目；按指定属性排序输入记录，并保存到 $hit。
        $hit = Get-ChildItem -Path $pat -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
        # 检查本行条件；满足时执行对应分支。
        if ($hit) { return $hit.FullName }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 返回本行结果并结束当前函数。
    return $null
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Find-Rscript，封装此函数内的操作。
function Find-Rscript {
    # 返回本行结果并结束当前函数。
    return (Find-Exe 'Rscript' @("$env:ProgramFiles\R\R-*\bin\x64\Rscript.exe", "$env:LOCALAPPDATA\Programs\R\R-*\bin\x64\Rscript.exe"))
# 结束此处的代码块、参数列表或集合定义。
}

# 调用 WinGet 执行本行指定的软件管理操作，并保存到 $script:WingetExe。
$script:WingetExe = Find-Exe 'winget'

# winget 安裝：先確認 ID 真的存在、且尚未安裝，再動手。找不到就給官方下載連結，不硬幹。
# 定义 Install-WingetId，封装此函数内的操作。
function Install-WingetId {
    # 声明脚本或函数接受的参数及默认值。
    param([string]$Id, [string]$Why, [string]$ManualUrl)
    # 检查本行条件；满足时执行对应分支。
    if (-not $script:WingetExe) { Write-Warning ('找不到 winget，無法安裝 ' + $Id + '。手動下載：' + $ManualUrl); return }
    # 把结果转换为文本；调用 WinGet 执行本行指定的软件管理操作，并保存到 $listed。
    $listed = & $script:WingetExe list --id $Id --exact --accept-source-agreements 2>$null | Out-String
    # 检查本行条件；满足时执行对应分支。
    if ($listed -match [regex]::Escape($Id)) { Write-Host ('  已安裝，略過：' + $Id); return }
    # 把结果转换为文本；调用 WinGet 执行本行指定的软件管理操作，并保存到 $shown。
    $shown = & $script:WingetExe show --id $Id --exact --accept-source-agreements 2>$null | Out-String
    # 检查本行条件；满足时执行对应分支。
    if ($shown -notmatch [regex]::Escape($Id)) {
        # 显示警告信息；调用 WinGet 执行本行指定的软件管理操作。
        Write-Warning ('  winget 沒有這個套件 ID：' + $Id + '（ID 可能已更名）。請手動下載：' + $ManualUrl)
        # 返回本行结果并结束当前函数。
        return
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 检查本行条件；满足时执行对应分支。
    if ($PSCmdlet.ShouldProcess($Id, 'winget install  # ' + $Why)) {
        # 调用 WinGet 执行本行指定的软件管理操作。
        & $script:WingetExe install --id $Id --exact --silent --accept-source-agreements --accept-package-agreements
        # 向终端显示提示或结果。
        Write-Host ('  ' + $Id + ' -> ExitCode ' + $LASTEXITCODE)
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# 使用者 PATH 前置插入（讀原始未展開值，避免把 %VAR% 寫死）
# 定义 Add-UserPathEntry，封装此函数内的操作。
function Add-UserPathEntry {
    # 声明脚本或函数接受的参数及默认值。
    param([string]$Entry, [switch]$Prepend)
    # 检查本行条件；满足时执行对应分支。
    if (-not $Entry) { return $false }
    # 读取指定作用域的环境变量，并保存到 $raw。
    $raw = [Environment]::GetEnvironmentVariable('Path', 'User')
    # 检查本行条件；满足时执行对应分支。
    if ($null -eq $raw) { $raw = '' }
    # 按条件筛选输入记录，并保存到 $parts。
    $parts = @($raw -split ';' | Where-Object { $_ -and $_.Trim() })
    # 计算本行表达式并设置 $norm，供后续步骤使用。
    $norm = $Entry.TrimEnd('\')
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($p in $parts) { if ($p.TrimEnd('\') -ieq $norm) { Write-Host ('  已在 PATH：' + $Entry); return $false } }
    # 检查本行条件；满足时执行对应分支。
    if ($Prepend) { $new = @($Entry) + $parts } else { $new = $parts + @($Entry) }
    # 计算本行表达式并设置 $joined，供后续步骤使用。
    $joined = ($new -join ';')
    # 检查本行条件；满足时执行对应分支。
    if ($PSCmdlet.ShouldProcess('使用者 PATH', '加入 ' + $Entry)) {
        # 写入指定作用域的环境变量。
        [Environment]::SetEnvironmentVariable('Path', $joined, 'User')
        # 向终端显示提示或结果。
        Write-Host ('  已加入 PATH：' + $Entry)
        # 返回本行结果并结束当前函数。
        return $true
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 返回本行结果并结束当前函数。
    return $false
# 结束此处的代码块、参数列表或集合定义。
}

# 计算本行表达式并设置 $isAdmin，供后续步骤使用。
$isAdmin = Test-Admin
# 向终端显示提示或结果。
Write-Host ('系統管理員身分：' + $isAdmin + '    預演模式(-WhatIf)：' + [bool]$WhatIfPreference)
# 向终端显示提示或结果。
Write-Host ('記錄檔：' + $log)

# ================================================================= 1. 工具鏈
# 检查本行条件；满足时执行对应分支。
if ($InstallToolchain) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '安裝核心工具鏈（PowerShell 7 / DuckDB CLI / Quarto CLI）'
    # 逐项处理管道传入的记录；调用 WinGet 执行本行指定的软件管理操作。
    Install-WingetId -Id 'Microsoft.PowerShell' -Why 'ForEach-Object -Parallel、正確的 UTF-8 與 JSON 處理' -ManualUrl 'https://github.com/PowerShell/PowerShell/releases'
    # 调用 WinGet 执行本行指定的软件管理操作。
    Install-WingetId -Id 'DuckDB.cli' -Why '直接對 Parquet/CSV 下 SQL，不必整份讀進記憶體' -ManualUrl 'https://duckdb.org/docs/installation/'
    # 调用 WinGet 执行本行指定的软件管理操作。
    Install-WingetId -Id 'Posit.Quarto' -Why '命令列 quarto render，讓報表能進排程與 CI' -ManualUrl 'https://quarto.org/docs/get-started/'
    # 向终端显示提示或结果。
    Write-Host '提醒：RStudio / Positron 內建自己的 quarto 與 pandoc；這裡裝的是「命令列版」，兩者不衝突。'
# 结束此处的代码块、参数列表或集合定义。
}

# 检查本行条件；满足时执行对应分支。
if ($InstallRtools) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '安裝 Rtools（R 的 C/C++/Fortran 編譯工具鏈）'
    # 调用 WinGet 执行本行指定的软件管理操作。
    Install-WingetId -Id 'RProject.Rtools' -Why '沒有它就無法安裝需編譯的套件，也無法用 Rcpp 自行加速' -ManualUrl 'https://cran.r-project.org/bin/windows/Rtools/'
    # 向终端显示提示或结果。
    Write-Host '安裝後不需要改 PATH：R 透過登錄機碼 HKLM\SOFTWARE\R-core\Rtools 尋找工具鏈。'
    # 向终端显示提示或结果。
    Write-Host 'Rtools 的版本號不必然等於 R 的次版本——R 4.6 用的就是 Rtools45，CRAN 沒有 rtools46。'
    # 向终端显示提示或结果。
    Write-Host '要確認能不能編譯，用實測而非版本號： R CMD SHLIB 一支小 C 檔。'
# 结束此处的代码块、参数列表或集合定义。
}

# 检查本行条件；满足时执行对应分支。
if ($InstallODBC) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '安裝資料庫 ODBC 驅動'
    # 向终端显示提示或结果；调用 WinGet 执行本行指定的软件管理操作。
    Write-Host '注意：以下 winget ID 未逐一查證，不存在時會直接給官方下載連結。' -ForegroundColor Yellow
    # 调用 WinGet 执行本行指定的软件管理操作。
    Install-WingetId -Id 'PostgreSQL.psqlODBC' -Why 'R odbc / Python pyodbc 連 PostgreSQL' -ManualUrl 'https://www.postgresql.org/ftp/odbc/versions/msi/'
    # 调用 WinGet 执行本行指定的软件管理操作。
    Install-WingetId -Id 'Oracle.MySQLConnectorODBC' -Why 'StarRocks / Doris / MySQL 都走 MySQL 協定' -ManualUrl 'https://dev.mysql.com/downloads/connector/odbc/'
    # 向终端显示提示或结果；调用 WinGet 执行本行指定的软件管理操作。
    Write-Host 'ClickHouse ODBC 沒有官方 winget 套件，請見 https://github.com/ClickHouse/clickhouse-odbc/releases'
# 结束此处的代码块、参数列表或集合定义。
}

# 检查本行条件；满足时执行对应分支。
if ($UpdateApps) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '升級已安裝的資料分析相關軟體'
    # 构造或计算 $ids，保存本行指定的集合或索引结果。
    $ids = @('RProject.R', 'RProject.Rtools', 'Posit.RStudio', 'Posit.Positron', 'Posit.Quarto',
        # 提供当前表达式所需的文本、字段名称或列表元素。
        'Git.Git', 'Microsoft.PowerShell', 'DuckDB.cli', 'Python.Launcher')
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($id in $ids) {
        # 检查本行条件；满足时执行对应分支。
        if (-not $script:WingetExe) { break }
        # 把结果转换为文本；调用 WinGet 执行本行指定的软件管理操作，并保存到 $listed。
        $listed = & $script:WingetExe list --id $id --exact --accept-source-agreements 2>$null | Out-String
        # 检查本行条件；满足时执行对应分支。
        if ($listed -notmatch [regex]::Escape($id)) { Write-Host ('  未安裝，略過：' + $id); continue }
        # 检查本行条件；满足时执行对应分支。
        if ($PSCmdlet.ShouldProcess($id, 'winget upgrade')) {
            # 调用 WinGet 执行本行指定的软件管理操作。
            & $script:WingetExe upgrade --id $id --exact --silent --accept-source-agreements --accept-package-agreements
            # 向终端显示提示或结果。
            Write-Host ('  ' + $id + ' -> ExitCode ' + $LASTEXITCODE + '（無更新時也可能非 0）')
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 向终端显示提示或结果。
    Write-Host 'R 的次版本升級（例如 4.6 -> 4.7）會換一個新的套件庫，升級後請重跑 -SetupR。'
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================= 2. PATH
# 检查本行条件；满足时执行对应分支。
if ($FixPath) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '修正使用者 PATH'
    # 组合父目录与子路径，并保存到 $backup。
    $backup = Join-Path $env:USERPROFILE ('PATH_user_backup_' + $ts + '.txt')
    # 将内容写入目标文件；读取指定作用域的环境变量。
    Set-Content -Path $backup -Value ([Environment]::GetEnvironmentVariable('Path', 'User')) -Encoding UTF8 -WhatIf:$false
    # 向终端显示提示或结果。
    Write-Host ('  已備份使用者 PATH：' + $backup + '（還原：把內容寫回使用者環境變數 Path）')

    # R
    # 枚举指定位置的文件、目录或注册表项，并保存到 $rbin。
    $rbin = Get-ChildItem "$env:ProgramFiles\R\R-*\bin\x64" -Directory -ErrorAction SilentlyContinue |
        # 选取记录中的指定字段或条目；按指定属性排序输入记录。
        Sort-Object Name -Descending | Select-Object -First 1
    # 检查本行条件；满足时执行对应分支。
    if ($rbin) { [void](Add-UserPathEntry -Entry $rbin.FullName) } else { Write-Host '  找不到 R 的 bin\x64。' }

    # Rtools 刻意「不」加進 PATH。
    # 理由一：R 是透過登錄機碼 HKLM\SOFTWARE\R-core\Rtools 找工具鏈的，加 PATH 沒有必要——
    #         本機已實測 R CMD SHLIB 在 PATH 沒有 Rtools 的情況下編譯成功。
    # 理由二：rtools\usr\bin 是 msys2 工具集，內含 sh.exe / find.exe / sort.exe，
    #         一旦排進 PATH 會蓋掉同名的 Windows 內建指令，讓其他腳本出現極難追查的怪異行為。
    # 读取注册表或对象的属性，并保存到 $rtReg。
    $rtReg = @(Get-ItemProperty 'HKLM:\SOFTWARE\R-core\Rtools\*', 'HKCU:\SOFTWARE\R-core\Rtools\*' -ErrorAction SilentlyContinue |
            # 检查目标路径是否存在；按条件筛选输入记录。
            Where-Object { $_.InstallPath -and (Test-Path -LiteralPath $_.InstallPath) })
    # 检查本行条件；满足时执行对应分支。
    if ($rtReg.Count -gt 0) {
        # 逐项处理管道传入的记录；向终端显示提示或结果。
        Write-Host ('  Rtools 已註冊，不加入 PATH（R 靠登錄機碼尋找）：' + (($rtReg | ForEach-Object { $_.InstallPath }) -join '; '))
    # 结束此处的代码块、参数列表或集合定义。
    }

    # Quarto
    # 选取记录中的指定字段或条目，并保存到 $q。
    $q = Get-Item "$env:LOCALAPPDATA\Programs\Quarto\bin", "$env:ProgramFiles\Quarto\bin" -ErrorAction SilentlyContinue | Select-Object -First 1
    # 检查本行条件；满足时执行对应分支。
    if ($q) { [void](Add-UserPathEntry -Entry $q.FullName) }

    # 真 Python 要排在 WindowsApps 前面，否則 python 會被 Store 別名攔截
    # 枚举指定位置的文件、目录或注册表项，并保存到 $realPy。
    $realPy = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*" -Directory -ErrorAction SilentlyContinue |
        # 选取记录中的指定字段或条目；按指定属性排序输入记录。
        Sort-Object Name -Descending | Select-Object -First 1
    # 检查本行条件；满足时执行对应分支。
    if ($realPy) {
        # 继续当前表达式，补充参数、类型转换或结果处理。
        [void](Add-UserPathEntry -Entry $realPy.FullName -Prepend)
        # 组合父目录与子路径。
        [void](Add-UserPathEntry -Entry (Join-Path $realPy.FullName 'Scripts') -Prepend)
        # 向终端显示提示或结果。
        Write-Host '  另外請到「設定 > 應用程式 > 應用程式執行別名」把 python.exe / python3.exe 關掉，'
        # 向终端显示提示或结果。
        Write-Host '  否則 Store 別名仍可能在某些情境下攔截。這一步無法安全地用腳本代做。'
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 向终端显示提示或结果。
    Write-Host '  PATH 變更要「重開 PowerShell / IDE」才會生效。'
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================= 3. Git
# 检查本行条件；满足时执行对应分支。
if ($ConfigureGit) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '設定 Git 全域參數'
    # 构造或计算 $git，保存本行指定的集合或索引结果。
    $git = Find-Exe 'git' @("$env:ProgramFiles\Git\cmd\git.exe")
    # 检查本行条件；满足时执行对应分支。
    if (-not $git) {
        # 显示警告信息。
        Write-Warning '找不到 git，已略過。'
    # 结束上一代码块并进入另一条件分支。
    } else {
        # 组合父目录与子路径，并保存到 $backup。
        $backup = Join-Path $env:USERPROFILE ('gitconfig_backup_' + $ts + '.txt')
        # 将内容写入目标文件。
        (& $git config --global --list) | Set-Content -Path $backup -Encoding UTF8 -WhatIf:$false
        # 向终端显示提示或结果。
        Write-Host ('  已備份 git 全域設定：' + $backup)
        # 构造或计算 $cfg，保存本行指定的集合或索引结果。
        $cfg = [ordered]@{
            'core.longpaths'      = 'true'    # 配合 -EnableLongPaths，避免深層路徑 checkout 失敗
            'core.autocrlf'       = 'input'   # 工作區保持 LF，避免 Linux/容器端腳本換行錯誤
            'core.fscache'        = 'true'    # Windows 檔案系統快取，大 repo 狀態查詢明顯變快
            # 提供当前表达式所需的文本、字段名称或列表元素。
            'core.preloadindex'   = 'true'
            # 提供当前表达式所需的文本、字段名称或列表元素。
            'credential.helper'   = 'manager'
            # 提供当前表达式所需的文本、字段名称或列表元素。
            'init.defaultBranch'  = 'main'
            # 提供当前表达式所需的文本、字段名称或列表元素。
            'pull.rebase'         = 'false'
            # 提供当前表达式所需的文本、字段名称或列表元素。
            'fetch.prune'         = 'true'
            # 提供当前表达式所需的文本、字段名称或列表元素。
            'diff.renames'        = 'true'
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 按本行的迭代范围或条件重复执行循环体。
        foreach ($k in $cfg.Keys) {
            # 检查本行条件；满足时执行对应分支。
            if ($PSCmdlet.ShouldProcess('git --global', $k + ' = ' + $cfg[$k])) {
                # 调用本行指定的程序或脚本，并传入列出的参数。
                & $git config --global $k $cfg[$k]
                # 向终端显示提示或结果。
                Write-Host ('  ' + $k + ' = ' + $cfg[$k])
            # 结束此处的代码块、参数列表或集合定义。
            }
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 向终端显示提示或结果。
        Write-Host '  提醒：core.autocrlf=input 只影響「之後」的 checkout；既有檔案要用 git add --renormalize . 重整。'
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================= 4. 工作區
# 检查本行条件；满足时执行对应分支。
if ($PrepareWorkspace) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step ('建立工作區骨架：' + $WorkRoot)
    # 构造或计算 $dirs，保存本行指定的集合或索引结果。
    $dirs = @('', 'projects', 'data', 'data\raw', 'data\parquet', 'data\quarantine', 'envs', 'tmp', 'rlibs', 'cache')
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($d in $dirs) {
        # 组合父目录与子路径，并保存到 $p。
        $p = if ($d) { Join-Path $WorkRoot $d } else { $WorkRoot }
        # 检查本行条件；满足时执行对应分支。
        if (Test-Path -LiteralPath $p) { continue }
        # 检查本行条件；满足时执行对应分支。
        if ($PSCmdlet.ShouldProcess($p, '建立資料夾')) { $null = New-Item -ItemType Directory -Path $p -Force }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 原文块第 1 行：计算本行表达式并设置 $readme，供后续步骤使用。
    # 原文块第 2 行：处理 這個工作區刻意放在 所指定的操作或当前表达式的后续部分。
    # 原文块第 3 行：处理 * 所指定的操作或当前表达式的后续部分。
    # 原文块第 4 行：处理 * 所指定的操作或当前表达式的后续部分。
    # 原文块第 5 行：处理 輕則變慢，重則 所指定的操作或当前表达式的后续部分。
    # 原文块第 7 行：处理 projects/ 所指定的操作或当前表达式的后续部分。
    # 原文块第 8 行：处理 data/raw/ 所指定的操作或当前表达式的后续部分。
    # 原文块第 9 行：处理 data/parquet/ 所指定的操作或当前表达式的后续部分。
    # 原文块第 10 行：处理 data/quarantine/ 所指定的操作或当前表达式的后续部分。
    # 原文块第 11 行：处理 envs/ 所指定的操作或当前表达式的后续部分。
    # 原文块第 12 行：处理 rlibs/ 所指定的操作或当前表达式的后续部分。
    # 原文块第 13 行：处理 tmp/ 所指定的操作或当前表达式的后续部分。
    # 原文块第 14 行：处理 cache/ 所指定的操作或当前表达式的后续部分。
    # 原文块第 16 行：处理 搬移既有專案（先關掉 所指定的操作或当前表达式的后续部分。
    # 原文块第 17 行：处理 robocopy 所指定的操作或当前表达式的后续部分。
    # 原文块第 18 行：提供当前表达式所需的文本、字段名称或列表元素。
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
    # 组合父目录与子路径，并保存到 $rp。
    $rp = Join-Path $WorkRoot 'README.txt'
    # 检查本行条件；满足时执行对应分支。
    if ($PSCmdlet.ShouldProcess($rp, '寫入說明檔')) { Set-Content -Path $rp -Value $readme -Encoding UTF8 }
    # 向终端显示提示或结果。
    Write-Host ''
    # 向终端显示提示或结果。
    Write-Host '  這一步只建立骨架，不會自動搬你的專案——搬移要在 IDE 關閉、OneDrive 暫停同步時手動做。' -ForegroundColor Yellow
    # 提取路径中的指定部分；向终端显示提示或结果。
    Write-Host ('  例如： robocopy "' + (Get-Location).Path + '" "' + $WorkRoot + '\projects\' + (Split-Path (Get-Location).Path -Leaf) + '" /E /MOVE')
# 结束此处的代码块、参数列表或集合定义。
}

# 检查本行条件；满足时执行对应分支。
if ($PowerPlanHigh) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '切換電源計畫：高效能'
    # 检查本行条件；满足时执行对应分支。
    if ($PSCmdlet.ShouldProcess('電源計畫', 'powercfg /setactive SCHEME_MIN')) {
        # 调用 Windows 电源配置工具。
        & powercfg.exe /setactive SCHEME_MIN
        # 检查本行条件；满足时执行对应分支。
        if ($LASTEXITCODE -ne 0) { Write-Warning '切換失敗：此裝置可能沒有「高效能」計畫。' }
        # 调用 Windows 电源配置工具。
        & powercfg.exe /getactivescheme
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================= 5. R 堆疊
# 检查本行条件；满足时执行对应分支。
if ($SetupR) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step ('建立 R 分析堆疊（套件組：' + $RProfile + '）')
    # 计算本行表达式并设置 $rs，供后续步骤使用。
    $rs = Find-Rscript
    # 检查本行条件；满足时执行对应分支。
    if (-not $rs) {
        # 显示警告信息。
        Write-Warning '找不到 Rscript，已略過。請先安裝 R。'
    # 结束上一代码块并进入另一条件分支。
    } elseif (Test-Admin) {
        # 显示警告信息。
        Write-Warning '目前是系統管理員身分：套件可能被寫進系統套件庫，造成日後一般使用者無法更新。請改用一般使用者身分執行本步驟。'
    # 结束上一代码块并进入另一条件分支。
    } else {
        # 组合父目录与子路径，并保存到 $bk。
        $bk = Join-Path $env:USERPROFILE ('R_packages_backup_' + $ts + '.csv')
        # 组合父目录与子路径，并保存到 $rFile。
        $rFile = Join-Path $env:TEMP ('setup_r_' + $ts + '.R')
        # 原文块第 1 行：计算本行表达式并设置 $rCode，供后续步骤使用。
        # 原文块第 2 行：调用 options，使用本行列出的输入完成对应操作。
        # 原文块第 3 行：读取 R 进程的环境变量，并保存到 bk。
        # 原文块第 4 行：读取 R 进程的环境变量，并保存到 grp。
        # 原文块第 7 行：读取 R 套件安装清单，并保存到 ip。
        # 原文块第 8 行：将表格写入 CSV 文件。
        # 原文块第 9 行：构造或计算 LibPath，保存本行指定的集合或索引结果。
        # 原文块第 10 行：处理 bk, 所指定的操作或当前表达式的后续部分。
        # 原文块第 11 行：输出本行的状态信息或计算结果。
        # 原文块第 14 行：读取 R 进程的环境变量，并保存到 lib。
        # 原文块第 15 行：检查本行条件；满足时执行对应分支。
        # 原文块第 16 行：调用 paste，使用本行列出的输入完成对应操作。
        # 原文块第 17 行：调用 dir.create，使用本行列出的输入完成对应操作。
        # 原文块第 18 行：调用 .libPaths，使用本行列出的输入完成对应操作。
        # 原文块第 19 行：输出本行的状态信息或计算结果。
        # 原文块第 22 行：计算本行表达式并设置 prof，供后续步骤使用。
        # 原文块第 23 行：检查本行条件；满足时执行对应分支。
        # 原文块第 24 行：调用 file.copy，使用本行列出的输入完成对应操作。
        # 原文块第 25 行：输出本行的状态信息或计算结果。
        # 原文块第 26 行：结束此处的代码块、参数列表或集合定义。
        # 原文块第 27 行：计算本行表达式并设置 ncpu，供后续步骤使用。
        # 原文块第 28 行：构造或计算 lines，保存本行指定的集合或索引结果。
        # 原文块第 29 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 30 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 31 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 32 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 33 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 34 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 35 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 36 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 37 行：调用 sprintf，使用本行列出的输入完成对应操作。
        # 原文块第 38 行：安装本行指定的 R 套件。
        # 原文块第 39 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 40 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 41 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 42 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 43 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 44 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 45 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 46 行：限制 data.table 使用的线程数量。
        # 原文块第 47 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 48 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 49 行：结束此处的代码块、参数列表或集合定义。
        # 原文块第 50 行：输出一行文本；将文本逐行写入目标文件。
        # 原文块第 51 行：输出本行的状态信息或计算结果。
        # 原文块第 52 行：调用 options，使用本行列出的输入完成对应操作。
        # 原文块第 53 行：安装本行指定的 R 套件，并保存到 install.packages.check.source。
        # 原文块第 56 行：检查本行条件；满足时执行对应分支。
        # 原文块第 57 行：安装本行指定的 R 套件。
        # 原文块第 58 行：计算本行表达式并设置 repos，供后续步骤使用。
        # 原文块第 59 行：继续当前表达式，补充参数、类型转换或结果处理。
        # 原文块第 60 行：结束此处的代码块、参数列表或集合定义。
        # 原文块第 61 行：检查指定 R 套件是否可用，并保存到 has_pak。
        # 原文块第 62 行：输出本行的状态信息或计算结果。
        # 原文块第 64 行：构造或计算 core，保存本行指定的集合或索引结果。
        # 原文块第 65 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 66 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 67 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 68 行：构造或计算 full，保存本行指定的集合或索引结果。
        # 原文块第 69 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 70 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 71 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 72 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 73 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 74 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 75 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 76 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 77 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 78 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 79 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 80 行：提供当前表达式所需的文本、字段名称或列表元素。
        # 原文块第 81 行：计算本行表达式并设置 want，供后续步骤使用。
        # 原文块第 88 行：计算本行表达式并设置 ap，供后续步骤使用。
        # 原文块第 89 行：检查本行条件；满足时执行对应分支。
        # 原文块第 90 行：计算本行表达式并设置 gone，供后续步骤使用。
        # 原文块第 91 行：读取 R 套件安装清单，并保存到 gone。
        # 原文块第 92 行：检查本行条件；满足时执行对应分支。
        # 原文块第 93 行：输出本行的状态信息或计算结果。
        # 原文块第 94 行：计算本行表达式并设置 want，供后续步骤使用。
        # 原文块第 95 行：结束此处的代码块、参数列表或集合定义。
        # 原文块第 96 行：结束此处的代码块、参数列表或集合定义。
        # 原文块第 98 行：读取 R 套件安装清单，并保存到 todo。
        # 原文块第 99 行：输出本行的状态信息或计算结果。
        # 原文块第 102 行：检查本行条件；满足时执行对应分支。
        # 原文块第 103 行：计算本行表达式并设置 chunks，供后续步骤使用。
        # 原文块第 104 行：按本行的迭代范围或条件重复执行循环体。
        # 原文块第 105 行：输出本行的状态信息或计算结果。
        # 原文块第 106 行：计算本行表达式并设置 ok，供后续步骤使用。
        # 原文块第 107 行：检查本行条件；满足时执行对应分支。
        # 原文块第 108 行：当前述条件不成立时执行此分支。
        # 原文块第 109 行：处理 TRUE 所指定的操作或当前表达式的后续部分。
        # 原文块第 110 行：继续当前表达式，补充参数、类型转换或结果处理。
        # 原文块第 112 行：检查本行条件；满足时执行对应分支。
        # 原文块第 113 行：按本行的迭代范围或条件重复执行循环体。
        # 原文块第 114 行：安装本行指定的 R 套件。
        # 原文块第 115 行：计算本行表达式并设置 error，供后续步骤使用。
        # 原文块第 116 行：结束此处的代码块、参数列表或集合定义。
        # 原文块第 117 行：结束此处的代码块、参数列表或集合定义。
        # 原文块第 118 行：结束此处的代码块、参数列表或集合定义。
        # 原文块第 119 行：结束此处的代码块、参数列表或集合定义。
        # 原文块第 122 行：读取 R 套件安装清单，并保存到 inst。
        # 原文块第 123 行：计算本行表达式并设置 ok，供后续步骤使用。
        # 原文块第 124 行：输出本行的状态信息或计算结果。
        # 原文块第 125 行：检查本行条件；满足时执行对应分支。
        # 原文块第 126 行：输出本行的状态信息或计算结果。
        # 原文块第 127 行：输出本行的状态信息或计算结果。
        # 原文块第 128 行：结束此处的代码块、参数列表或集合定义。
        # 原文块第 129 行：输出本行的状态信息或计算结果。
        # 原文块第 130 行：提供当前表达式所需的文本、字段名称或列表元素。
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
          "dtplyr", "collapse", "stringi", "fst", "qs2", "vroom", "nanoparquet",
          "RPostgres", "RMariaDB", "pool",
          "xts", "zoo", "tsibble", "fable", "forecast", "TTR", "quantmod",
          "PerformanceAnalytics", "rugarch",
          "tidymodels", "xgboost", "lightgbm", "ranger", "glmnet",
          "survival", "survminer", "grf", "depmixS4",
          "DALEX", "iml", "shapviz", "kernelshap", "pdp",
          "gt", "gtsummary", "flextable", "officer",
          "plotly", "ggiraph", "patchwork", "ggrepel",
          "future", "furrr", "parallelly", "Rcpp", "bench", "profvis",
          "shiny", "bslib", "shinyWidgets", "shinyjs", "DT", "reactable",
          "targets", "testthat", "lintr", "styler", "logger", "reticulate")
want <- if (identical(grp, "core")) core else full

## 3a. 先剔除「CRAN 上已經沒有」的套件
##     理由：pak 的求解器是全域的。只要清單裡有一個找不到的套件，
##     它會把整批 70+ 個套件全部標成 dependency conflict，一個都裝不成。
##     套件被 CRAN 封存（qs -> qs2、fastshap/vip -> shapviz/kernelshap）是常態，
##     所以這裡每次都重新核對，而不是相信寫死的清單。
ap <- tryCatch(rownames(available.packages()), error = function(e) character(0))
if (length(ap)) {
  gone <- setdiff(want, ap)
  gone <- setdiff(gone, rownames(installed.packages()))
  if (length(gone)) {
    cat("NOT ON CRAN (skipped):", paste(gone, collapse = ", "), "\n")
    want <- setdiff(want, gone)
  }
}

todo <- setdiff(want, rownames(installed.packages()))
cat("to install:", length(todo), "\n")

## 3b. 分批安裝：一批失敗不會拖垮其他批次，且進度看得見
if (length(todo)) {
  chunks <- split(todo, ceiling(seq_along(todo) / 12))
  for (i in seq_along(chunks)) {
    cat("=== chunk", i, "of", length(chunks), ":", paste(chunks[[i]], collapse = " "), "\n")
    ok <- tryCatch({
      if (has_pak) pak::pkg_install(chunks[[i]], lib = lib, ask = FALSE)
      else install.packages(chunks[[i]], lib = lib, Ncpus = ncpu)
      TRUE
    }, error = function(e) { cat("chunk", i, "failed:", conditionMessage(e), "\n"); FALSE })
    ## 該批整批失敗時退回逐一安裝，把能裝的先裝起來
    if (!ok) {
      for (p in chunks[[i]]) {
        tryCatch(install.packages(p, lib = lib, Ncpus = ncpu),
                 error = function(e) cat("  ", p, "failed:", conditionMessage(e), "\n"))
      }
    }
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
        # 检查本行条件；满足时执行对应分支。
        if ($PSCmdlet.ShouldProcess('R 個人套件庫', '寫入 .Rprofile 並安裝 ' + $RProfile + ' 套件組（備份：' + $bk + '）')) {
            # 将内容写入目标文件。
            Set-Content -Path $rFile -Value $rCode -Encoding ASCII -WhatIf:$false
            # 计算本行表达式并设置 $env:SETUP_BACKUP，供后续步骤使用。
            $env:SETUP_BACKUP = $bk
            # 计算本行表达式并设置 $env:SETUP_GROUP，供后续步骤使用。
            $env:SETUP_GROUP = $RProfile
            # 调用本行指定的程序或脚本，并传入列出的参数。
            & $rs $rFile
            # 移动或替换指定文件；删除指定路径下的项目。
            Remove-Item $rFile -Force -ErrorAction SilentlyContinue
            # 向终端显示提示或结果。
            Write-Host ''
            # 向终端显示提示或结果。
            Write-Host '  下載量大（full 組約數百 MB），第一次可能要 20-60 分鐘，視網路與防毒掃描而定。'
            # 向终端显示提示或结果。
            Write-Host '  需要「可重現」的專案，請在該專案目錄另外跑 renv::init()，不要靠全域套件庫。' -ForegroundColor Yellow
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================= 6. Python 堆疊
# 检查本行条件；满足时执行对应分支。
if ($SetupPython) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step ('建立 Python 分析環境（uv + Python ' + $PythonVersion + '）')
    # 构造或计算 $uv，保存本行指定的集合或索引结果。
    $uv = Find-Exe 'uv' @("$env:USERPROFILE\.local\bin\uv.exe")
    # 检查本行条件；满足时执行对应分支。
    if (-not $uv) {
        # 显示警告信息；调用 WinGet 执行本行指定的软件管理操作。
        Write-Warning '找不到 uv。安裝方式： winget install --id astral-sh.uv   或   https://docs.astral.sh/uv/'
    # 结束上一代码块并进入另一条件分支。
    } else {
        # 组合父目录与子路径，并保存到 $envDir。
        $envDir = Join-Path $WorkRoot 'envs\ds'
        # 构造或计算 $pkgs，保存本行指定的集合或索引结果。
        $pkgs = @(
            # 提供当前表达式所需的文本、字段名称或列表元素。
            'pandas', 'polars', 'numpy', 'pyarrow', 'duckdb',
            # 提供当前表达式所需的文本、字段名称或列表元素。
            'sqlalchemy', 'pymysql', 'psycopg[binary]', 'pyodbc', 'clickhouse-connect',
            # 提供当前表达式所需的文本、字段名称或列表元素。
            'scikit-learn', 'scipy', 'statsmodels', 'xgboost', 'lightgbm',
            # 提供当前表达式所需的文本、字段名称或列表元素。
            'shap', 'lime', 'lifelines', 'econml', 'dowhy',
            # 提供当前表达式所需的文本、字段名称或列表元素。
            'matplotlib', 'seaborn', 'plotly', 'great-tables',
            # 提供当前表达式所需的文本、字段名称或列表元素。
            'jupyterlab', 'ipykernel', 'papermill',
            # 提供当前表达式所需的文本、字段名称或列表元素。
            'ruff', 'pytest'
        # 结束此处的代码块、参数列表或集合定义。
        )
        # 刻意不放 scikit-survival：它的相依 ecos 沒有 Windows wheel，必須用
        # MSVC C++ Build Tools 從原始碼編譯（本機實測失敗）。Rtools 的 gcc 只服務 R，
        # 不服務 Python。R 端的 survival / survminer / grf 已涵蓋生存分析與因果森林；
        # 真的需要 Python 版，請先裝 Microsoft.VisualStudio.2022.BuildTools（數 GB，
        # 在公司資產上建議先問過 IT）。
        # 检查本行条件；满足时执行对应分支。
        if ($PSCmdlet.ShouldProcess($envDir, 'uv venv + 安裝 ' + $pkgs.Count + ' 個套件')) {
            # 提取路径中的指定部分；创建指定目录、文件或配置项；将不需要的返回值丢弃。
            $null = New-Item -ItemType Directory -Path (Split-Path $envDir -Parent) -Force
            # 调用本行指定的程序或脚本，并传入列出的参数。
            & $uv python install $PythonVersion
            # 调用本行指定的程序或脚本，并传入列出的参数。
            & $uv venv --python $PythonVersion $envDir
            # 组合父目录与子路径，并保存到 $venvPy。
            $venvPy = Join-Path $envDir 'Scripts\python.exe'
            # 检查本行条件；满足时执行对应分支。
            if (Test-Path $venvPy) {
                # 准备或执行 Python 套件管理操作。
                & $uv pip install --python $venvPy @pkgs
                # 向终端显示提示或结果。
                Write-Host ''
                # 向终端显示提示或结果。
                Write-Host '  鎖定版本（可重現的關鍵）：'
                # 组合父目录与子路径，并保存到 $req。
                $req = Join-Path $envDir 'requirements.lock.txt'
                # 将内容写入目标文件；准备或执行 Python 套件管理操作。
                & $uv pip freeze --python $venvPy | Set-Content -Path $req -Encoding UTF8
                # 向终端显示提示或结果；准备或执行 Python 套件管理操作。
                Write-Host ('  已寫出 ' + $req + '（重建環境： uv pip install --python <新venv> -r ' + $req + '）')
                # 向终端显示提示或结果。
                Write-Host ''
                # 向终端显示提示或结果。
                Write-Host '  註冊 Jupyter kernel：'
                # 调用本行指定的程序或脚本，并传入列出的参数。
                & $venvPy -m ipykernel install --user --name ds --display-name ('Python ' + $PythonVersion + ' (ds)')
                # 向终端显示提示或结果。
                Write-Host ''
                # 向终端显示提示或结果。
                Write-Host ('  在 Positron / VS Code 選直譯器時指向：' + $venvPy) -ForegroundColor Green
                # 向终端显示提示或结果；设置当前 R 进程的环境变量。
                Write-Host ('  R 端要用 reticulate 時：Sys.setenv(RETICULATE_PYTHON = "' + $venvPy + '")')
            # 结束上一代码块并进入另一条件分支。
            } else {
                # 显示警告信息。
                Write-Warning ('建立虛擬環境失敗：找不到 ' + $venvPy)
            # 结束此处的代码块、参数列表或集合定义。
            }
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 向终端显示提示或结果。
        Write-Host ''
        # 向终端显示提示或结果；准备或执行 Python 套件管理操作。
        Write-Host '  為什麼不用全域 pip install：全域環境一旦混入互相衝突的版本，就得整台重裝。' -ForegroundColor Yellow
        # 向终端显示提示或结果。
        Write-Host '  正式專案請用 uv init / uv add，讓 pyproject.toml + uv.lock 進版控。' -ForegroundColor Yellow
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================= 7. 需要系統管理員
# 检查本行条件；满足时执行对应分支。
if ($EnableLongPaths) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '啟用 Windows 長路徑'
    # 检查本行条件；满足时执行对应分支。
    if (Assert-Admin '啟用長路徑') {
        # 计算本行表达式并设置 $k，供后续步骤使用。
        $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
        # 计算本行表达式并设置 $cur，供后续步骤使用。
        $cur = $null
        # 开始受异常处理保护的操作。
        try { $cur = (Get-ItemProperty -Path $k -Name LongPathsEnabled -ErrorAction Stop).LongPathsEnabled } catch { }
        # 检查本行条件；满足时执行对应分支。
        if ($cur -eq 1) { Write-Host '  已是啟用狀態。' }
        # 检查本行条件；满足时执行对应分支。
        elseif ($PSCmdlet.ShouldProcess($k, 'LongPathsEnabled = 1')) {
            # 创建或写入指定注册表属性；创建指定目录、文件或配置项；丢弃不需要显示的输出。
            New-ItemProperty -Path $k -Name LongPathsEnabled -Value 1 -PropertyType DWord -Force | Out-Null
            # 向终端显示提示或结果。
            Write-Host '  已啟用（需重新開機；應用程式本身也要支援才有效）。'
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# 检查本行条件；满足时执行对应分支。
if ($SetPageFile) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '固定分頁檔大小（避免大資料運算被系統直接終止）'
    # 检查本行条件；满足时执行对应分支。
    if (Assert-Admin '設定分頁檔') {
        # 查询 Windows 管理接口中的设备或系统信息，并保存到 $ramMB。
        $ramMB = [int]((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)
        # 构造或计算 $initMB，保存本行指定的集合或索引结果。
        $initMB = [int]($ramMB * 0.5)
        # 构造或计算 $maxMB，保存本行指定的集合或索引结果。
        $maxMB = [int]($ramMB * 1.0)
        # 查询 Windows 管理接口中的设备或系统信息，并保存到 $free。
        $free = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1MB
        # 向终端显示提示或结果。
        Write-Host ('  實體記憶體 ' + $ramMB + ' MB；預計設定 C:\pagefile.sys 初始 ' + $initMB + ' MB / 最大 ' + $maxMB + ' MB')
        # 检查本行条件；满足时执行对应分支。
        if ($free -lt ($maxMB + 20480)) {
            # 显示警告信息。
            Write-Warning ('  C: 剩餘空間僅 ' + [int]$free + ' MB，設定 ' + $maxMB + ' MB 分頁檔後會過於吃緊，已略過。請先清出空間。')
        # 结束上一代码块并进入另一条件分支。
        } elseif ($PSCmdlet.ShouldProcess('C:\pagefile.sys', "初始 $initMB MB / 最大 $maxMB MB")) {
            # 组合父目录与子路径，并保存到 $bk。
            $bk = Join-Path $env:USERPROFILE ('pagefile_backup_' + $ts + '.txt')
            # 通过 WMI 查询系统配置；将内容写入目标文件；把结果转换为文本。
            (Get-WmiObject Win32_PageFileSetting | Out-String) | Set-Content -Path $bk -Encoding UTF8 -WhatIf:$false
            # 通过 WMI 查询系统配置；向目标文件追加内容。
            Add-Content -Path $bk -Value ('AutomaticManagedPagefile=' + (Get-WmiObject Win32_ComputerSystem).AutomaticManagedPagefile) -WhatIf:$false
            # 向终端显示提示或结果。
            Write-Host ('  已備份原設定：' + $bk)
            # 通过 WMI 查询系统配置，并保存到 $csw。
            $csw = Get-WmiObject Win32_ComputerSystem -EnableAllPrivileges
            # 检查本行条件；满足时执行对应分支。
            if ($csw.AutomaticManagedPagefile) { $csw.AutomaticManagedPagefile = $false; [void]$csw.Put() }
            # 通过 WMI 查询系统配置；按条件筛选输入记录，并保存到 $pfs。
            $pfs = Get-WmiObject Win32_PageFileSetting | Where-Object { $_.Name -like 'C:*' }
            # 检查本行条件；满足时执行对应分支。
            if ($pfs) {
                # 构造或计算 $pfs.InitialSize，保存本行指定的集合或索引结果。
                $pfs.InitialSize = $initMB; $pfs.MaximumSize = $maxMB; [void]$pfs.Put()
            # 结束上一代码块并进入另一条件分支。
            } else {
                # 处理 Set-WmiInstance 所指定的操作或当前表达式的后续部分；将不需要的返回值丢弃。
                $null = Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{ Name = 'C:\pagefile.sys'; InitialSize = $initMB; MaximumSize = $maxMB }
            # 结束此处的代码块、参数列表或集合定义。
            }
            # 向终端显示提示或结果。
            Write-Host '  已設定，需重新開機生效。還原方式：系統內容 > 進階 > 效能 > 虛擬記憶體 > 自動管理。'
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# 检查本行条件；满足时执行对应分支。
if ($AddDefenderExclusions) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '對開發目錄加入 Microsoft Defender 掃描排除'
    # 检查本行条件；满足时执行对应分支。
    if (Assert-Admin '設定 Defender 排除') {
        # 构造或计算 $paths，保存本行指定的集合或索引结果。
        $paths = @()
        # 计算本行表达式并设置 $paths，供后续步骤使用。
        $paths += $WorkRoot
        # 读取指定作用域的环境变量，并保存到 $rlib。
        $rlib = [Environment]::GetEnvironmentVariable('R_LIBS_USER', 'User')
        # 检查本行条件；满足时执行对应分支。
        if (-not $rlib) { $rlib = Join-Path $env:LOCALAPPDATA 'R\win-library' }
        # 构造或计算 $paths，保存本行指定的集合或索引结果。
        $paths += [Environment]::ExpandEnvironmentVariables($rlib)
        # 组合父目录与子路径，并保存到 $paths。
        $paths += (Join-Path $env:LOCALAPPDATA 'R')
        # 组合父目录与子路径，并保存到 $paths。
        $paths += (Join-Path $env:USERPROFILE '.cache\uv')
        # 组合父目录与子路径，并保存到 $paths。
        $paths += (Join-Path $env:LOCALAPPDATA 'uv')
        # 选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $paths。
        $paths = @($paths | Where-Object { $_ } | Select-Object -Unique)

        # 向终端显示提示或结果。
        Write-Host '  排除掃描 = 用一點安全性換取安裝與讀寫速度。只排「你自己的程式碼與套件庫」，' -ForegroundColor Yellow
        # 向终端显示提示或结果。
        Write-Host '  絕不要排除 Downloads、桌面或整顆 C:。若公司政策不允許，請直接跳過這一步。' -ForegroundColor Yellow
        # 按本行的迭代范围或条件重复执行循环体。
        foreach ($p in $paths) {
            # 检查本行条件；满足时执行对应分支。
            if (-not (Test-Path -LiteralPath $p)) { Write-Host ('  路徑不存在，略過：' + $p); continue }
            # 检查本行条件；满足时执行对应分支。
            if ($PSCmdlet.ShouldProcess($p, 'Add-MpPreference -ExclusionPath')) {
                # 开始受异常处理保护的操作。
                try { Add-MpPreference -ExclusionPath $p -ErrorAction Stop; Write-Host ('  已排除：' + $p) }
                # 捕获并处理前述操作抛出的异常。
                catch { Write-Warning ('  失敗（可能被群組原則鎖定）：' + $_.Exception.Message) }
            # 结束此处的代码块、参数列表或集合定义。
            }
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 向终端显示提示或结果。
        Write-Host ''
        # 向终端显示提示或结果。
        Write-Host '  重要：這只對 Microsoft Defender 有效。機器上的第三方防毒與透明加密／DLP 用戶端' -ForegroundColor Yellow
        # 向终端显示提示或结果。
        Write-Host '  不受這裡影響，必須由貴公司 IT 在他們的管理主控台加白名單。' -ForegroundColor Yellow
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# 向终端显示提示或结果。
Write-Host ''
# 向终端显示提示或结果。
Write-Host '完成。建議流程：重新開機 -> 重跑 Win10_Diagnose_v2.ps1 -> 比對 00_摘要.txt 的發現數量。' -ForegroundColor Green
# 向终端显示提示或结果。
Write-Host ('記錄檔：' + $log)
# 开始受异常处理保护的操作。
try { Stop-Transcript | Out-Null } catch { }
