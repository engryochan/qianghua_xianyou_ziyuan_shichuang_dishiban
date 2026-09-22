#Requires -Version 5.1
<#
.SYNOPSIS
  Windows 10 保守型優化：更新資料分析工具鏈、修補常見設定，每一項都是獨立開關，且支援 -WhatIf 預演。
.DESCRIPTION
  設計原則
    1. 先診斷（Win10_Diagnose.ps1），再依診斷結果選擇性執行。
    2. 每一步都是明確開關；不帶任何開關時只顯示說明，不做任何事。
    3. 全部支援 -WhatIf（預演）與 -Confirm（逐項確認）；全程寫入 Win10_Optimize_時間.log。
    4. 會改變狀態的步驟先備份（R 套件清單、pip freeze、系統還原點）。
    5. 不做的事：登錄檔「一鍵優化」、關閉遙測/服務/Defender、清理工具式的大量刪除。

  建議分兩次執行（權限不同）
    一般使用者： .\Win10_Optimize.ps1 -UpdateApps -UpdateRPackages -UpdatePythonTools
    系統管理員： .\Win10_Optimize.ps1 -RestorePoint -EnableLongPaths -CleanTemp -DefenderUpdate
  先預演： 任何指令後加 -WhatIf
.EXAMPLE
  .\Win10_Optimize.ps1 -UpdateApps -WhatIf
.EXAMPLE
  .\Win10_Optimize.ps1 -All           # 等同下列「-All 包含」清單，不含高影響項目
#>
# 启用 PowerShell 高级脚本参数绑定及所列功能。
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
# 声明脚本或函数接受的参数及默认值。
param(
    [switch]$RestorePoint,          # 系統管理員：建立系統還原點
    [switch]$UpdateApps,            # 用 winget 升級「已安裝」的資料分析工具（R/Rtools/RStudio/Positron/Quarto/Git/Pandoc/VS Code/Python）
    [switch]$UpdateAllWinget,       # 高影響：winget upgrade --all（升級所有 winget 可升級軟體）
    [switch]$UpdateRPackages,       # 更新 R 套件（先備份清單；一般使用者身分較佳）
    [switch]$UpdatePythonTools,     # 只升級 pip 本身
    [switch]$UpdatePythonPackages,  # 高影響：逐一升級所有過期 pip 套件（先 pip freeze 備份，最後 pip check）
    [switch]$EnableLongPaths,       # 系統管理員：啟用 Windows 長路徑
    [switch]$CleanTemp,             # 清除 7 天前的暫存檔（使用者 TEMP；管理員身分時另含 Windows\Temp）
    [switch]$DefenderUpdate,        # 系統管理員：更新 Defender 病毒定義
    [switch]$DefenderQuickScan,     # 系統管理員：Defender 快速掃描
    [switch]$HighPerformancePower,  # 切換到高效能電源計畫（筆電會較耗電）
    [switch]$RepairImage,           # 系統管理員：DISM RestoreHealth + sfc /scannow（耗時）
    [switch]$OpenWindowsUpdate,     # 開啟 Windows Update 設定頁
    [switch]$All                    # 包含：RestorePoint UpdateApps UpdateRPackages UpdatePythonTools EnableLongPaths CleanTemp DefenderUpdate OpenWindowsUpdate
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
    # 计算本行表达式并设置 $RestorePoint，供后续步骤使用。
    $RestorePoint = $true; $UpdateApps = $true; $UpdateRPackages = $true; $UpdatePythonTools = $true
    # 计算本行表达式并设置 $EnableLongPaths，供后续步骤使用。
    $EnableLongPaths = $true; $CleanTemp = $true; $DefenderUpdate = $true; $OpenWindowsUpdate = $true
# 结束此处的代码块、参数列表或集合定义。
}

# 调用 WinGet 执行本行指定的软件管理操作，并保存到 $anySwitch。
$anySwitch = $RestorePoint -or $UpdateApps -or $UpdateAllWinget -or $UpdateRPackages -or $UpdatePythonTools -or $UpdatePythonPackages -or
    # 处理 $EnableLongPaths 所指定的操作或当前表达式的后续部分。
    $EnableLongPaths -or $CleanTemp -or $DefenderUpdate -or $DefenderQuickScan -or $HighPerformancePower -or $RepairImage -or $OpenWindowsUpdate
# 检查本行条件；满足时执行对应分支。
if (-not $anySwitch) {
    # 把结果转换为文本；向终端显示提示或结果。
    Get-Help $MyInvocation.MyCommand.Path -Full | Out-String -Width 200 | Write-Host
    # 向终端显示提示或结果。
    Write-Host '未指定任何開關，未執行任何動作。請先執行 Win10_Diagnose.ps1，再依結果選擇開關；建議先加 -WhatIf 預演。' -ForegroundColor Yellow
    # 返回本行结果并结束当前函数。
    return
# 结束此处的代码块、参数列表或集合定义。
}

# 生成当前时间或格式化时间戳，并保存到 $ts。
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
# 组合父目录与子路径，并保存到 $log。
$log = Join-Path $env:USERPROFILE ('Win10_Optimize_' + $ts + '.log')
# 开始受异常处理保护的操作。
try { Start-Transcript -Path $log -WhatIf:$false | Out-Null } catch { }

# ------------------------------------------------------------------ 工具函式
# 定义 Step，封装此函数内的操作。
function Step { param([string]$Title) Write-Host ''; Write-Host ('>>> ' + $Title) -ForegroundColor Cyan }

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
    if (-not (Test-Admin)) {
        # 显示警告信息。
        Write-Warning ($What + ' 需要系統管理員權限，已略過。請以系統管理員身分重新執行。')
        # 返回本行结果并结束当前函数。
        return $false
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 返回本行结果并结束当前函数。
    return $true
# 结束此处的代码块、参数列表或集合定义。
}

# 定义 Find-Rscript，封装此函数内的操作。
function Find-Rscript {
    # 查找当前环境可用的命令及其位置；选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $c。
    $c = Get-Command Rscript -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
    # 检查本行条件；满足时执行对应分支。
    if ($c) { return $c.Source }
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($pat in @("$env:ProgramFiles\R\R-*\bin\x64\Rscript.exe", "$env:ProgramFiles\R\R-*\bin\Rscript.exe", "$env:LOCALAPPDATA\Programs\R\R-*\bin\x64\Rscript.exe")) {
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

# 定义 Get-PythonInvoker，封装此函数内的操作。
function Get-PythonInvoker {
    # 查找当前环境可用的命令及其位置；选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $py。
    $py = Get-Command py -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
    # 检查本行条件；满足时执行对应分支。
    if ($py) { return @{ Exe = $py.Source; Base = @('-3') } }
    # 查找当前环境可用的命令及其位置；选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $p。
    $p = Get-Command python -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' -and $_.Source -notlike '*\WindowsApps\*' } | Select-Object -First 1
    # 检查本行条件；满足时执行对应分支。
    if ($p) { return @{ Exe = $p.Source; Base = @() } }
    # 返回本行结果并结束当前函数。
    return $null
# 结束此处的代码块、参数列表或集合定义。
}

# 计算本行表达式并设置 $isAdmin，供后续步骤使用。
$isAdmin = Test-Admin
# 向终端显示提示或结果。
Write-Host ('系統管理員身分：' + $isAdmin + '    預演模式(-WhatIf)：' + [bool]$WhatIfPreference)
# 向终端显示提示或结果。
Write-Host ('記錄檔：' + $log)

# ------------------------------------------------------------------ 還原點
# 检查本行条件；满足时执行对应分支。
if ($RestorePoint) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '建立系統還原點'
    # 检查本行条件；满足时执行对应分支。
    if (Assert-Admin '建立還原點') {
        # 检查本行条件；满足时执行对应分支。
        if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, '建立系統還原點 Win10_Optimize_' + $ts)) {
            # 开始受异常处理保护的操作。
            try {
                # 请求建立系统还原点。
                Checkpoint-Computer -Description ('Win10_Optimize_' + $ts) -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
                # 向终端显示提示或结果。
                Write-Host '已建立還原點。'
            # 结束上一代码块并进入异常处理。
            } catch {
                # 显示警告信息。
                Write-Warning ('未能建立還原點（系統保護可能未啟用，或 24 小時內已建立過）：' + $_.Exception.Message)
            # 结束此处的代码块、参数列表或集合定义。
            }
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ------------------------------------------------------------------ winget：資料分析工具鏈
# 调用 WinGet 执行本行指定的软件管理操作，并保存到 $wingetExe。
$wingetExe = $null
# 查找当前环境可用的命令及其位置；选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $wgCmd。
$wgCmd = Get-Command winget -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
# 检查本行条件；满足时执行对应分支。
if ($wgCmd) { $wingetExe = $wgCmd.Source }

# 检查本行条件；满足时执行对应分支。
if ($UpdateApps) {
    # 调用 WinGet 执行本行指定的软件管理操作。
    Step '升級已安裝的資料分析工具（winget，僅處理「已安裝」者）'
    # 检查本行条件；满足时执行对应分支。
    if (-not $wingetExe) {
        # 显示警告信息；调用 WinGet 执行本行指定的软件管理操作。
        Write-Warning '找不到 winget。請先到 Microsoft Store 安裝或更新「應用安裝程式 (App Installer)」。'
    # 结束上一代码块并进入另一条件分支。
    } else {
        # 已確認存在的 ID：RProject.R / RProject.Rtools / Posit.RStudio。
        # 其餘 ID 為常見慣例，未逐一驗證；不存在或未安裝者會被自動略過。
        # 构造或计算 $ids，保存本行指定的集合或索引结果。
        $ids = @('RProject.R', 'RProject.Rtools', 'Posit.RStudio', 'Posit.Positron', 'Posit.Quarto',
            # 提供当前表达式所需的文本、字段名称或列表元素。
            'Git.Git', 'JohnMacFarlane.Pandoc', 'Microsoft.VisualStudioCode',
            # 提供当前表达式所需的文本、字段名称或列表元素。
            'Python.Python.3.14', 'Python.Python.3.13', 'Python.Python.3.12', 'Python.Python.3.11', 'Python.Python.3.10')
        # 按本行的迭代范围或条件重复执行循环体。
        foreach ($id in $ids) {
            # 把结果转换为文本；调用 WinGet 执行本行指定的软件管理操作，并保存到 $found。
            $found = & $wingetExe list --id $id --exact --accept-source-agreements 2>$null | Out-String
            # 检查本行条件；满足时执行对应分支。
            if ($LASTEXITCODE -ne 0 -or $found -notmatch [regex]::Escape($id)) {
                # 向终端显示提示或结果。
                Write-Host ('  略過（未安裝或 ID 不存在）：' + $id)
                # 跳过本次循环余下操作。
                continue
            # 结束此处的代码块、参数列表或集合定义。
            }
            # 检查本行条件；满足时执行对应分支。
            if ($PSCmdlet.ShouldProcess($id, 'winget upgrade')) {
                # 调用 WinGet 执行本行指定的软件管理操作。
                & $wingetExe upgrade --id $id --exact --silent --accept-source-agreements --accept-package-agreements
                # 向终端显示提示或结果。
                Write-Host ('  ' + $id + ' -> ExitCode ' + $LASTEXITCODE + '（無可用更新時也可能為非 0）')
            # 结束此处的代码块、参数列表或集合定义。
            }
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 向终端显示提示或结果。
        Write-Host '注意：R 的次版本升級（例如 4.4 -> 4.5）會使用新的套件庫；升級後請重新安裝或更新套件（見 -UpdateRPackages）。'
        # 向终端显示提示或结果。
        Write-Host '注意：Python 只會在同一個次版本內升級；要用更新的次版本請並存安裝。'
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# 检查本行条件；满足时执行对应分支。
if ($UpdateAllWinget) {
    # 调用 WinGet 执行本行指定的软件管理操作。
    Step '升級 winget 可升級的所有軟體（高影響）'
    # 检查本行条件；满足时执行对应分支。
    if (-not $wingetExe) { Write-Warning '找不到 winget。' }
    # 检查本行条件；满足时执行对应分支。
    elseif ($PSCmdlet.ShouldProcess('所有 winget 可升級軟體', 'winget upgrade --all')) {
        # 调用 WinGet 执行本行指定的软件管理操作。
        & $wingetExe upgrade --all --silent --accept-source-agreements --accept-package-agreements
        # 向终端显示提示或结果。
        Write-Host ('ExitCode ' + $LASTEXITCODE)
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ------------------------------------------------------------------ R 套件
# 检查本行条件；满足时执行对应分支。
if ($UpdateRPackages) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '更新 R 套件（先備份套件清單；不從原始碼編譯，故不需 Rtools）'
    # 检查本行条件；满足时执行对应分支。
    if ($isAdmin) { Write-Warning '目前為系統管理員身分：套件可能被寫入系統套件庫。建議改以一般使用者身分執行本步驟。' }
    # 计算本行表达式并设置 $rs，供后续步骤使用。
    $rs = Find-Rscript
    # 检查本行条件；满足时执行对应分支。
    if (-not $rs) {
        # 显示警告信息。
        Write-Warning '找不到 Rscript，已略過。'
    # 结束上一代码块并进入另一条件分支。
    } else {
        # 组合父目录与子路径，并保存到 $backup。
        $backup = Join-Path $env:USERPROFILE ('R_packages_backup_' + $ts + '.csv')
        # 组合父目录与子路径，并保存到 $rFile。
        $rFile = Join-Path $env:TEMP ('opt_update_' + $ts + '.R')
        # 原文块第 1 行：计算本行表达式并设置 $rCode，供后续步骤使用。
        # 原文块第 2 行：调用 options，使用本行列出的输入完成对应操作。
        # 原文块第 3 行：读取 R 进程的环境变量，并保存到 bk。
        # 原文块第 4 行：读取 R 套件安装清单，并保存到 ip。
        # 原文块第 5 行：将表格写入 CSV 文件。
        # 原文块第 6 行：构造或计算 LibPath，保存本行指定的集合或索引结果。
        # 原文块第 7 行：处理 bk, 所指定的操作或当前表达式的后续部分。
        # 原文块第 8 行：输出本行的状态信息或计算结果。
        # 原文块第 9 行：计算本行表达式并设置 libs，供后续步骤使用。
        # 原文块第 10 行：构造或计算 w，保存本行指定的集合或索引结果。
        # 原文块第 11 行：检查本行条件；满足时执行对应分支。
        # 原文块第 12 行：读取 R 进程的环境变量，并保存到 ul。
        # 原文块第 13 行：检查本行条件；满足时执行对应分支。
        # 原文块第 14 行：调用 dir.create，使用本行列出的输入完成对应操作。
        # 原文块第 15 行：调用 .libPaths，使用本行列出的输入完成对应操作。
        # 原文块第 16 行：计算本行表达式并设置 w，供后续步骤使用。
        # 原文块第 17 行：结束此处的代码块、参数列表或集合定义。
        # 原文块第 18 行：结束此处的代码块、参数列表或集合定义。
        # 原文块第 19 行：检查本行条件；满足时执行对应分支。
        # 原文块第 20 行：计算本行表达式并设置 repos，供后续步骤使用。
        # 原文块第 21 行：检查本行条件；满足时执行对应分支。
        # 原文块第 22 行：安装本行指定的 R 套件。
        # 原文块第 23 行：调用 update.packages，使用本行列出的输入完成对应操作。
        # 原文块第 24 行：输出本行的状态信息或计算结果。
        # 原文块第 25 行：计算本行表达式并设置 old，供后续步骤使用。
        # 原文块第 26 行：检查本行条件；满足时执行对应分支。
        # 原文块第 27 行：提供当前表达式所需的文本、字段名称或列表元素。
        $rCode = @'
options(warn = 1)
bk <- Sys.getenv("OPT_BACKUP")
ip <- installed.packages(fields = "Built")
write.csv(data.frame(Package = ip[, "Package"], Version = ip[, "Version"], Built = ip[, "Built"],
                     LibPath = ip[, "LibPath"], stringsAsFactors = FALSE),
          bk, row.names = FALSE, fileEncoding = "UTF-8")
cat("backup written:", bk, "\n")
libs <- .libPaths()
w <- libs[file.access(libs, 2) == 0]
if (length(w) == 0) {
  ul <- Sys.getenv("R_LIBS_USER")
  if (nzchar(ul)) {
    dir.create(ul, recursive = TRUE, showWarnings = FALSE)
    .libPaths(c(ul, .libPaths()))
    w <- ul
  }
}
if (length(w) == 0) stop("no writable library path")
repos <- getOption("repos")
if (is.null(repos) || is.na(repos["CRAN"]) || repos["CRAN"] == "@CRAN@") repos <- c(CRAN = "https://cloud.r-project.org")
options(install.packages.compile.from.source = "never")
update.packages(lib.loc = w, repos = repos, ask = FALSE, checkBuilt = TRUE)
cat("re-check outdated packages:\n")
old <- old.packages(lib.loc = w, repos = repos, checkBuilt = TRUE)
if (is.null(old)) cat("no outdated packages\n") else print(old[, c("Package", "Installed", "ReposVer")])
'@
        # 检查本行条件；满足时执行对应分支。
        if ($PSCmdlet.ShouldProcess('R 套件庫', 'update.packages（備份：' + $backup + '）')) {
            # 将内容写入目标文件。
            Set-Content -Path $rFile -Value $rCode -Encoding ASCII
            # 计算本行表达式并设置 $env:OPT_BACKUP，供后续步骤使用。
            $env:OPT_BACKUP = $backup
            # 调用本行指定的程序或脚本，并传入列出的参数。
            & $rs $rFile
            # 移动或替换指定文件；删除指定路径下的项目。
            Remove-Item $rFile -Force -ErrorAction SilentlyContinue
            # 向终端显示提示或结果。
            Write-Host ('R 套件清單備份：' + $backup)
            # 向终端显示提示或结果。
            Write-Host '仍列為過期者，通常是二進位版尚未發布；若需最新原始碼版，請先安裝 Rtools 再手動安裝。'
            # 向终端显示提示或结果。
            Write-Host '需要可重現分析的專案，請用 renv 鎖定版本，而不是追最新。'
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ------------------------------------------------------------------ Python
# 检查本行条件；满足时执行对应分支。
if ($UpdatePythonTools -or $UpdatePythonPackages) {
    # 准备或执行 Python 套件管理操作。
    Step 'Python：pip'
    # 计算本行表达式并设置 $inv，供后续步骤使用。
    $inv = Get-PythonInvoker
    # 检查本行条件；满足时执行对应分支。
    if (-not $inv) {
        # 显示警告信息。
        Write-Warning '找不到可用的 Python（python 指令若只是 Microsoft Store 別名則不算）。'
    # 结束上一代码块并进入另一条件分支。
    } else {
        # 检查本行条件；满足时执行对应分支。
        if ($UpdatePythonTools) {
            # 准备或执行 Python 套件管理操作，并保存到 $a。
            $a = @($inv.Base) + @('-m', 'pip', 'install', '--upgrade', 'pip')
            # 检查本行条件；满足时执行对应分支。
            if ($PSCmdlet.ShouldProcess($inv.Exe, 'pip install --upgrade pip')) { & $inv.Exe @a }
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 检查本行条件；满足时执行对应分支。
        if ($UpdatePythonPackages) {
            # 组合父目录与子路径；准备或执行 Python 套件管理操作，并保存到 $freeze。
            $freeze = Join-Path $env:USERPROFILE ('pip_freeze_backup_' + $ts + '.txt')
            # 准备或执行 Python 套件管理操作，并保存到 $fa。
            $fa = @($inv.Base) + @('-m', 'pip', 'freeze')
            # 检查本行条件；满足时执行对应分支。
            if ($PSCmdlet.ShouldProcess($inv.Exe, '升級所有過期 pip 套件（備份：' + $freeze + '）')) {
                # 将内容写入目标文件。
                (& $inv.Exe @fa) | Set-Content -Path $freeze -Encoding UTF8
                # 向终端显示提示或结果；准备或执行 Python 套件管理操作。
                Write-Host ('pip freeze 備份：' + $freeze + '（還原：pip install -r 此檔）')
                # 准备或执行 Python 套件管理操作，并保存到 $la。
                $la = @($inv.Base) + @('-m', 'pip', 'list', '--outdated', '--format=json')
                # 把结果转换为文本，并保存到 $json。
                $json = (& $inv.Exe @la 2>$null) | Out-String
                # 开始受异常处理保护的操作。
                try {
                    # 把 JSON 文本解析为对象，并保存到 $od。
                    $od = $json | ConvertFrom-Json
                    # 按本行的迭代范围或条件重复执行循环体。
                    foreach ($p in @($od)) {
                        # 向终端显示提示或结果。
                        Write-Host ('  升級 ' + $p.name + ' ' + $p.version + ' -> ' + $p.latest_version)
                        # 准备或执行 Python 套件管理操作，并保存到 $ua。
                        $ua = @($inv.Base) + @('-m', 'pip', 'install', '--upgrade', $p.name)
                        # 调用本行指定的程序或脚本，并传入列出的参数。
                        & $inv.Exe @ua
                    # 结束此处的代码块、参数列表或集合定义。
                    }
                # 结束上一代码块并进入异常处理。
                } catch { Write-Warning ('讀取過期清單失敗：' + $_.Exception.Message) }
                # 准备或执行 Python 套件管理操作，并保存到 $ca。
                $ca = @($inv.Base) + @('-m', 'pip', 'check')
                # 向终端显示提示或结果；准备或执行 Python 套件管理操作。
                Write-Host '--- pip check ---'
                # 调用本行指定的程序或脚本，并传入列出的参数。
                & $inv.Exe @ca
            # 结束此处的代码块、参数列表或集合定义。
            }
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ------------------------------------------------------------------ Windows 設定
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
        if ($cur -eq 1) {
            # 向终端显示提示或结果。
            Write-Host '已是啟用狀態。'
        # 结束上一代码块并进入另一条件分支。
        } elseif ($PSCmdlet.ShouldProcess($k, 'LongPathsEnabled = 1')) {
            # 创建或写入指定注册表属性；创建指定目录、文件或配置项；丢弃不需要显示的输出。
            New-ItemProperty -Path $k -Name LongPathsEnabled -Value 1 -PropertyType DWord -Force | Out-Null
            # 向终端显示提示或结果。
            Write-Host '已啟用（需重新開機；且應用程式本身需支援長路徑）。'
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# 检查本行条件；满足时执行对应分支。
if ($HighPerformancePower) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '切換電源計畫：高效能'
    # 检查本行条件；满足时执行对应分支。
    if ($PSCmdlet.ShouldProcess('電源計畫', 'powercfg /setactive SCHEME_MIN')) {
        # 调用 Windows 电源配置工具。
        & powercfg.exe /setactive SCHEME_MIN
        # 检查本行条件；满足时执行对应分支。
        if ($LASTEXITCODE -ne 0) { Write-Warning '切換失敗：此裝置可能沒有「高效能」計畫。' } else { Write-Host '已切換。' }
        # 调用 Windows 电源配置工具。
        & powercfg.exe /getactivescheme
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# 检查本行条件；满足时执行对应分支。
if ($CleanTemp) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '清除 7 天前的暫存檔'
    # 生成当前时间或格式化时间戳，并保存到 $cut。
    $cut = (Get-Date).AddDays(-7)
    # 构造或计算 $targets，保存本行指定的集合或索引结果。
    $targets = @($env:TEMP)
    # 检查本行条件；满足时执行对应分支。
    if ($isAdmin) { $targets += (Join-Path $env:windir 'Temp') } else { Write-Host '  非系統管理員：略過 Windows\Temp。' }
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($t in $targets) {
        # 检查本行条件；满足时执行对应分支。
        if (-not (Test-Path -LiteralPath $t)) { continue }
        # 枚举指定位置的文件、目录或注册表项；按条件筛选输入记录，并保存到 $files。
        $files = @(Get-ChildItem -LiteralPath $t -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cut })
        # 构造或计算 $mb，保存本行指定的集合或索引结果。
        $mb = [math]::Round((($files | Measure-Object Length -Sum).Sum) / 1MB, 1)
        # 检查本行条件；满足时执行对应分支。
        if ($PSCmdlet.ShouldProcess($t, ('刪除 ' + $files.Count + ' 個檔案，約 ' + $mb + ' MB'))) {
            # 移动或替换指定文件；删除指定路径下的项目。
            $files | Remove-Item -Force -ErrorAction SilentlyContinue
            # 向终端显示提示或结果。
            Write-Host ('  ' + $t + '：已嘗試刪除 ' + $files.Count + ' 個檔案（使用中的檔案會被略過）')
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ------------------------------------------------------------------ Defender / 系統修復 / Windows Update
# 检查本行条件；满足时执行对应分支。
if ($DefenderUpdate) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '更新 Defender 病毒定義'
    # 检查本行条件；满足时执行对应分支。
    if (Assert-Admin '更新 Defender 定義') {
        # 检查本行条件；满足时执行对应分支。
        if ($PSCmdlet.ShouldProcess('Microsoft Defender', 'Update-MpSignature')) {
            # 开始受异常处理保护的操作。
            try { Update-MpSignature -ErrorAction Stop; Write-Host '完成。' } catch { Write-Warning $_.Exception.Message }
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# 检查本行条件；满足时执行对应分支。
if ($DefenderQuickScan) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step 'Defender 快速掃描'
    # 检查本行条件；满足时执行对应分支。
    if (Assert-Admin 'Defender 掃描') {
        # 检查本行条件；满足时执行对应分支。
        if ($PSCmdlet.ShouldProcess('Microsoft Defender', 'Start-MpScan -ScanType QuickScan')) {
            # 开始受异常处理保护的操作。
            try { Start-MpScan -ScanType QuickScan -ErrorAction Stop; Write-Host '完成。' } catch { Write-Warning $_.Exception.Message }
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# 检查本行条件；满足时执行对应分支。
if ($RepairImage) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '系統映像修復：DISM RestoreHealth 與 sfc /scannow（可能需數十分鐘）'
    # 检查本行条件；满足时执行对应分支。
    if (Assert-Admin '系統修復') {
        # 检查本行条件；满足时执行对应分支。
        if ($PSCmdlet.ShouldProcess('Windows 映像', 'DISM /RestoreHealth 與 sfc /scannow')) {
            # 调用本行指定的程序或脚本，并传入列出的参数。
            & DISM.exe /Online /Cleanup-Image /RestoreHealth
            # 调用本行指定的程序或脚本，并传入列出的参数。
            & sfc.exe /scannow
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# 检查本行条件；满足时执行对应分支。
if ($OpenWindowsUpdate) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '開啟 Windows Update'
    # 检查本行条件；满足时执行对应分支。
    if ($PSCmdlet.ShouldProcess('設定', '開啟 ms-settings:windowsupdate')) { Start-Process 'ms-settings:windowsupdate' }
# 结束此处的代码块、参数列表或集合定义。
}

# 向终端显示提示或结果。
Write-Host ''
# 向终端显示提示或结果。
Write-Host '完成。建議：重新開機一次，然後重新執行 Win10_Diagnose.ps1 對照前後差異。' -ForegroundColor Green
# 开始受异常处理保护的操作。
try { Stop-Transcript | Out-Null } catch { }
