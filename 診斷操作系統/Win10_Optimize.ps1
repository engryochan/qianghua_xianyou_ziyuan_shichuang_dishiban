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
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
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
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

if ($All) {
    $RestorePoint = $true; $UpdateApps = $true; $UpdateRPackages = $true; $UpdatePythonTools = $true
    $EnableLongPaths = $true; $CleanTemp = $true; $DefenderUpdate = $true; $OpenWindowsUpdate = $true
}

$anySwitch = $RestorePoint -or $UpdateApps -or $UpdateAllWinget -or $UpdateRPackages -or $UpdatePythonTools -or $UpdatePythonPackages -or
    $EnableLongPaths -or $CleanTemp -or $DefenderUpdate -or $DefenderQuickScan -or $HighPerformancePower -or $RepairImage -or $OpenWindowsUpdate
if (-not $anySwitch) {
    Get-Help $MyInvocation.MyCommand.Path -Full | Out-String -Width 200 | Write-Host
    Write-Host '未指定任何開關，未執行任何動作。請先執行 Win10_Diagnose.ps1，再依結果選擇開關；建議先加 -WhatIf 預演。' -ForegroundColor Yellow
    return
}

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$log = Join-Path $env:USERPROFILE ('Win10_Optimize_' + $ts + '.log')
try { Start-Transcript -Path $log -WhatIf:$false | Out-Null } catch { }

# ------------------------------------------------------------------ 工具函式
function Step { param([string]$Title) Write-Host ''; Write-Host ('>>> ' + $Title) -ForegroundColor Cyan }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    param([string]$What)
    if (-not (Test-Admin)) {
        Write-Warning ($What + ' 需要系統管理員權限，已略過。請以系統管理員身分重新執行。')
        return $false
    }
    return $true
}

function Find-Rscript {
    $c = Get-Command Rscript -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
    if ($c) { return $c.Source }
    foreach ($pat in @("$env:ProgramFiles\R\R-*\bin\x64\Rscript.exe", "$env:ProgramFiles\R\R-*\bin\Rscript.exe", "$env:LOCALAPPDATA\Programs\R\R-*\bin\x64\Rscript.exe")) {
        $hit = Get-ChildItem -Path $pat -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function Get-PythonInvoker {
    $py = Get-Command py -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
    if ($py) { return @{ Exe = $py.Source; Base = @('-3') } }
    $p = Get-Command python -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' -and $_.Source -notlike '*\WindowsApps\*' } | Select-Object -First 1
    if ($p) { return @{ Exe = $p.Source; Base = @() } }
    return $null
}

$isAdmin = Test-Admin
Write-Host ('系統管理員身分：' + $isAdmin + '    預演模式(-WhatIf)：' + [bool]$WhatIfPreference)
Write-Host ('記錄檔：' + $log)

# ------------------------------------------------------------------ 還原點
if ($RestorePoint) {
    Step '建立系統還原點'
    if (Assert-Admin '建立還原點') {
        if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, '建立系統還原點 Win10_Optimize_' + $ts)) {
            try {
                Checkpoint-Computer -Description ('Win10_Optimize_' + $ts) -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
                Write-Host '已建立還原點。'
            } catch {
                Write-Warning ('未能建立還原點（系統保護可能未啟用，或 24 小時內已建立過）：' + $_.Exception.Message)
            }
        }
    }
}

# ------------------------------------------------------------------ winget：資料分析工具鏈
$wingetExe = $null
$wgCmd = Get-Command winget -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
if ($wgCmd) { $wingetExe = $wgCmd.Source }

if ($UpdateApps) {
    Step '升級已安裝的資料分析工具（winget，僅處理「已安裝」者）'
    if (-not $wingetExe) {
        Write-Warning '找不到 winget。請先到 Microsoft Store 安裝或更新「應用安裝程式 (App Installer)」。'
    } else {
        # 已確認存在的 ID：RProject.R / RProject.Rtools / Posit.RStudio。
        # 其餘 ID 為常見慣例，未逐一驗證；不存在或未安裝者會被自動略過。
        $ids = @('RProject.R', 'RProject.Rtools', 'Posit.RStudio', 'Posit.Positron', 'Posit.Quarto',
            'Git.Git', 'JohnMacFarlane.Pandoc', 'Microsoft.VisualStudioCode',
            'Python.Python.3.14', 'Python.Python.3.13', 'Python.Python.3.12', 'Python.Python.3.11', 'Python.Python.3.10')
        foreach ($id in $ids) {
            $found = & $wingetExe list --id $id --exact --accept-source-agreements 2>$null | Out-String
            if ($LASTEXITCODE -ne 0 -or $found -notmatch [regex]::Escape($id)) {
                Write-Host ('  略過（未安裝或 ID 不存在）：' + $id)
                continue
            }
            if ($PSCmdlet.ShouldProcess($id, 'winget upgrade')) {
                & $wingetExe upgrade --id $id --exact --silent --accept-source-agreements --accept-package-agreements
                Write-Host ('  ' + $id + ' -> ExitCode ' + $LASTEXITCODE + '（無可用更新時也可能為非 0）')
            }
        }
        Write-Host '注意：R 的次版本升級（例如 4.4 -> 4.5）會使用新的套件庫；升級後請重新安裝或更新套件（見 -UpdateRPackages）。'
        Write-Host '注意：Python 只會在同一個次版本內升級；要用更新的次版本請並存安裝。'
    }
}

if ($UpdateAllWinget) {
    Step '升級 winget 可升級的所有軟體（高影響）'
    if (-not $wingetExe) { Write-Warning '找不到 winget。' }
    elseif ($PSCmdlet.ShouldProcess('所有 winget 可升級軟體', 'winget upgrade --all')) {
        & $wingetExe upgrade --all --silent --accept-source-agreements --accept-package-agreements
        Write-Host ('ExitCode ' + $LASTEXITCODE)
    }
}

# ------------------------------------------------------------------ R 套件
if ($UpdateRPackages) {
    Step '更新 R 套件（先備份套件清單；不從原始碼編譯，故不需 Rtools）'
    if ($isAdmin) { Write-Warning '目前為系統管理員身分：套件可能被寫入系統套件庫。建議改以一般使用者身分執行本步驟。' }
    $rs = Find-Rscript
    if (-not $rs) {
        Write-Warning '找不到 Rscript，已略過。'
    } else {
        $backup = Join-Path $env:USERPROFILE ('R_packages_backup_' + $ts + '.csv')
        $rFile = Join-Path $env:TEMP ('opt_update_' + $ts + '.R')
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
        if ($PSCmdlet.ShouldProcess('R 套件庫', 'update.packages（備份：' + $backup + '）')) {
            Set-Content -Path $rFile -Value $rCode -Encoding ASCII
            $env:OPT_BACKUP = $backup
            & $rs $rFile
            Remove-Item $rFile -Force -ErrorAction SilentlyContinue
            Write-Host ('R 套件清單備份：' + $backup)
            Write-Host '仍列為過期者，通常是二進位版尚未發布；若需最新原始碼版，請先安裝 Rtools 再手動安裝。'
            Write-Host '需要可重現分析的專案，請用 renv 鎖定版本，而不是追最新。'
        }
    }
}

# ------------------------------------------------------------------ Python
if ($UpdatePythonTools -or $UpdatePythonPackages) {
    Step 'Python：pip'
    $inv = Get-PythonInvoker
    if (-not $inv) {
        Write-Warning '找不到可用的 Python（python 指令若只是 Microsoft Store 別名則不算）。'
    } else {
        if ($UpdatePythonTools) {
            $a = @($inv.Base) + @('-m', 'pip', 'install', '--upgrade', 'pip')
            if ($PSCmdlet.ShouldProcess($inv.Exe, 'pip install --upgrade pip')) { & $inv.Exe @a }
        }
        if ($UpdatePythonPackages) {
            $freeze = Join-Path $env:USERPROFILE ('pip_freeze_backup_' + $ts + '.txt')
            $fa = @($inv.Base) + @('-m', 'pip', 'freeze')
            if ($PSCmdlet.ShouldProcess($inv.Exe, '升級所有過期 pip 套件（備份：' + $freeze + '）')) {
                (& $inv.Exe @fa) | Set-Content -Path $freeze -Encoding UTF8
                Write-Host ('pip freeze 備份：' + $freeze + '（還原：pip install -r 此檔）')
                $la = @($inv.Base) + @('-m', 'pip', 'list', '--outdated', '--format=json')
                $json = (& $inv.Exe @la 2>$null) | Out-String
                try {
                    $od = $json | ConvertFrom-Json
                    foreach ($p in @($od)) {
                        Write-Host ('  升級 ' + $p.name + ' ' + $p.version + ' -> ' + $p.latest_version)
                        $ua = @($inv.Base) + @('-m', 'pip', 'install', '--upgrade', $p.name)
                        & $inv.Exe @ua
                    }
                } catch { Write-Warning ('讀取過期清單失敗：' + $_.Exception.Message) }
                $ca = @($inv.Base) + @('-m', 'pip', 'check')
                Write-Host '--- pip check ---'
                & $inv.Exe @ca
            }
        }
    }
}

# ------------------------------------------------------------------ Windows 設定
if ($EnableLongPaths) {
    Step '啟用 Windows 長路徑'
    if (Assert-Admin '啟用長路徑') {
        $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
        $cur = $null
        try { $cur = (Get-ItemProperty -Path $k -Name LongPathsEnabled -ErrorAction Stop).LongPathsEnabled } catch { }
        if ($cur -eq 1) {
            Write-Host '已是啟用狀態。'
        } elseif ($PSCmdlet.ShouldProcess($k, 'LongPathsEnabled = 1')) {
            New-ItemProperty -Path $k -Name LongPathsEnabled -Value 1 -PropertyType DWord -Force | Out-Null
            Write-Host '已啟用（需重新開機；且應用程式本身需支援長路徑）。'
        }
    }
}

if ($HighPerformancePower) {
    Step '切換電源計畫：高效能'
    if ($PSCmdlet.ShouldProcess('電源計畫', 'powercfg /setactive SCHEME_MIN')) {
        & powercfg.exe /setactive SCHEME_MIN
        if ($LASTEXITCODE -ne 0) { Write-Warning '切換失敗：此裝置可能沒有「高效能」計畫。' } else { Write-Host '已切換。' }
        & powercfg.exe /getactivescheme
    }
}

if ($CleanTemp) {
    Step '清除 7 天前的暫存檔'
    $cut = (Get-Date).AddDays(-7)
    $targets = @($env:TEMP)
    if ($isAdmin) { $targets += (Join-Path $env:windir 'Temp') } else { Write-Host '  非系統管理員：略過 Windows\Temp。' }
    foreach ($t in $targets) {
        if (-not (Test-Path -LiteralPath $t)) { continue }
        $files = @(Get-ChildItem -LiteralPath $t -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cut })
        $mb = [math]::Round((($files | Measure-Object Length -Sum).Sum) / 1MB, 1)
        if ($PSCmdlet.ShouldProcess($t, ('刪除 ' + $files.Count + ' 個檔案，約 ' + $mb + ' MB'))) {
            $files | Remove-Item -Force -ErrorAction SilentlyContinue
            Write-Host ('  ' + $t + '：已嘗試刪除 ' + $files.Count + ' 個檔案（使用中的檔案會被略過）')
        }
    }
}

# ------------------------------------------------------------------ Defender / 系統修復 / Windows Update
if ($DefenderUpdate) {
    Step '更新 Defender 病毒定義'
    if (Assert-Admin '更新 Defender 定義') {
        if ($PSCmdlet.ShouldProcess('Microsoft Defender', 'Update-MpSignature')) {
            try { Update-MpSignature -ErrorAction Stop; Write-Host '完成。' } catch { Write-Warning $_.Exception.Message }
        }
    }
}

if ($DefenderQuickScan) {
    Step 'Defender 快速掃描'
    if (Assert-Admin 'Defender 掃描') {
        if ($PSCmdlet.ShouldProcess('Microsoft Defender', 'Start-MpScan -ScanType QuickScan')) {
            try { Start-MpScan -ScanType QuickScan -ErrorAction Stop; Write-Host '完成。' } catch { Write-Warning $_.Exception.Message }
        }
    }
}

if ($RepairImage) {
    Step '系統映像修復：DISM RestoreHealth 與 sfc /scannow（可能需數十分鐘）'
    if (Assert-Admin '系統修復') {
        if ($PSCmdlet.ShouldProcess('Windows 映像', 'DISM /RestoreHealth 與 sfc /scannow')) {
            & DISM.exe /Online /Cleanup-Image /RestoreHealth
            & sfc.exe /scannow
        }
    }
}

if ($OpenWindowsUpdate) {
    Step '開啟 Windows Update'
    if ($PSCmdlet.ShouldProcess('設定', '開啟 ms-settings:windowsupdate')) { Start-Process 'ms-settings:windowsupdate' }
}

Write-Host ''
Write-Host '完成。建議：重新開機一次，然後重新執行 Win10_Diagnose.ps1 對照前後差異。' -ForegroundColor Green
try { Stop-Transcript | Out-Null } catch { }
