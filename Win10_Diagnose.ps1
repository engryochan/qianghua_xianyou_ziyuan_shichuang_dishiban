#Requires -Version 5.1
<#
.SYNOPSIS
  Windows 10 唯讀診斷：系統、軟體、應用、設定，並重點檢查資料分析工具鏈（R / RStudio / Positron / Python / Git / Quarto ...）。
.DESCRIPTION
  * 完全唯讀：不安裝、不刪除、不修改任何系統設定。
  * 一般使用者身分即可執行；以系統管理員身分執行可額外收集 BitLocker / Secure Boot / TPM / SMB1。
  * 輸出到 -OutDir：00_摘要.txt 為總覽，其餘為 CSV / TXT 明細。
  * 明細內含電腦名稱、使用者名稱、已安裝軟體清單。分享前請先自行檢視。
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Win10_Diagnose.ps1
.EXAMPLE
  .\Win10_Diagnose.ps1 -SkipRPackages -SkipPython -SkipWinget   # 加速：略過需要聯網的比對
#>
[CmdletBinding()]
param(
    [string]$OutDir = (Join-Path $env:USERPROFILE ('Win10_Diag_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))),
    [switch]$SkipRPackages,
    [switch]$SkipPython,
    [switch]$SkipWinget,
    [switch]$SkipEventLog
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$null = New-Item -ItemType Directory -Path $OutDir -Force
$script:Findings = New-Object System.Collections.Generic.List[object]
$script:Files = New-Object System.Collections.Generic.List[string]

# ------------------------------------------------------------------ 工具函式
function Add-Finding {
    param(
        [ValidateSet('警告', '注意', '資訊')][string]$Level,
        [string]$Area,
        [string]$Message
    )
    $script:Findings.Add([pscustomobject]@{ Level = $Level; Area = $Area; Message = $Message })
}

function Section {
    param([string]$Title)
    Write-Host ''
    Write-Host ('=== ' + $Title + ' ===') -ForegroundColor Cyan
}

function Save-Csv {
    param($Data, [string]$Name)
    if ($null -eq $Data -or @($Data).Count -eq 0) { return }
    @($Data) | Export-Csv -Path (Join-Path $OutDir $Name) -NoTypeInformation -Encoding UTF8
    $script:Files.Add($Name)
}

function Save-Text {
    param([string]$Text, [string]$Name)
    if ([string]::IsNullOrEmpty($Text)) { return }
    Set-Content -Path (Join-Path $OutDir $Name) -Value $Text -Encoding UTF8
    $script:Files.Add($Name)
}

function Show-Table {
    param($Data)
    if ($null -eq $Data -or @($Data).Count -eq 0) { Write-Host '  (無資料)'; return }
    ($Data | Format-Table -AutoSize | Out-String -Width 220).TrimEnd() | Write-Host
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}

function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments = @(), [switch]$StdoutOnly)
    try {
        if ($StdoutOnly) { $o = & $Exe @Arguments 2>$null } else { $o = & $Exe @Arguments 2>&1 }
        $o = $o | ForEach-Object { "$_" } | Where-Object { $_ -notmatch '^\s*[-\\|/]+\s*$' }
        return (($o) -join "`n").Trim()
    } catch { return $null }
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

function Get-FirstLine {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    return (($Text -split "`n") | Select-Object -First 1).Trim()
}

$isAdmin = Test-Admin
Write-Host ('輸出資料夾：' + $OutDir) -ForegroundColor Green
Write-Host ('系統管理員身分：' + $isAdmin)

# ------------------------------------------------------------------ 1. 系統
Section '1. 系統與更新'
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$cvPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$dispVer = Get-RegValue $cvPath 'DisplayVersion'
if (-not $dispVer) { $dispVer = Get-RegValue $cvPath 'ReleaseId' }
$build = ('' + (Get-RegValue $cvPath 'CurrentBuild')) + '.' + (Get-RegValue $cvPath 'UBR')
$uptime = (Get-Date) - $os.LastBootUpTime
$ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$sys = [pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    OS           = $os.Caption
    Version      = $dispVer
    Build        = $build
    Arch         = $os.OSArchitecture
    Language     = $os.MUILanguages -join ','
    InstallDate  = $os.InstallDate
    LastBoot     = $os.LastBootUpTime
    UptimeDays   = [math]::Round($uptime.TotalDays, 1)
    RAM_GB       = $ramGB
    PowerShell   = $PSVersionTable.PSVersion.ToString()
    IsAdmin      = $isAdmin
}
Show-Table $sys
Save-Csv $sys '01_系統.csv'

if ($os.Caption -match 'Windows 10') {
    Add-Finding '警告' '系統' 'Windows 10 已於 2025-10-14 結束一般支援。若未加入延伸安全更新 (ESU) 或改用 Windows 11，將不再收到常規安全修補（請以 Microsoft 官方公告為準）。'
}
if ($ramGB -lt 8) { Add-Finding '注意' '硬體' ('實體記憶體僅 ' + $ramGB + ' GB：處理大型資料集、GARCH/回測等運算時易記憶體不足。') }
elseif ($ramGB -lt 16) { Add-Finding '資訊' '硬體' ('實體記憶體 ' + $ramGB + ' GB：一般分析足夠；大型資料建議 16 GB 以上，或改用 arrow / duckdb 等外存方案。') }
if ($uptime.TotalDays -gt 14) { Add-Finding '注意' '系統' ('已連續開機 ' + [math]::Round($uptime.TotalDays, 1) + ' 天，建議重新開機以套用更新並釋放記憶體。') }

$hot = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending
Save-Csv ($hot | Select-Object HotFixID, Description, InstalledOn, InstalledBy) '01_更新紀錄.csv'
$lastHot = $hot | Where-Object { $_.InstalledOn } | Select-Object -First 1
if ($lastHot) {
    $hotAge = ((Get-Date) - $lastHot.InstalledOn).Days
    Write-Host ('最近一次已安裝更新：' + $lastHot.HotFixID + '（' + $lastHot.InstalledOn.ToString('yyyy-MM-dd') + '，距今 ' + $hotAge + ' 天）')
    if ($hotAge -gt 60) { Add-Finding '警告' '更新' ('最近一次已安裝更新距今 ' + $hotAge + ' 天，請檢查 Windows Update 是否被停用或卡住。') }
} else {
    Add-Finding '注意' '更新' '讀不到更新安裝日期，請手動開啟 設定 > 更新與安全性 > Windows Update 確認。'
}

$pending = @()
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pending += 'CBS' }
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pending += 'WindowsUpdate' }
if (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'PendingFileRenameOperations') { $pending += 'PendingFileRename' }
if ($pending.Count -gt 0) { Add-Finding '注意' '系統' ('有待完成的重新開機動作：' + ($pending -join ', ')) }

# ------------------------------------------------------------------ 2. 硬體
Section '2. 硬體與磁碟'
$cpu = Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed
$gpu = Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DriverDate
$bios = Get-CimInstance Win32_BIOS | Select-Object Manufacturer, SMBIOSBIOSVersion, ReleaseDate
$pd = $null
try {
    $pd = Get-PhysicalDisk -ErrorAction Stop | Select-Object FriendlyName, MediaType, BusType, HealthStatus, OperationalStatus, @{ n = 'Size_GB'; e = { [math]::Round($_.Size / 1GB) } }
} catch { }
$vol = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object DeviceID, VolumeName, FileSystem,
    @{ n = 'Size_GB'; e = { [math]::Round($_.Size / 1GB, 1) } },
    @{ n = 'Free_GB'; e = { [math]::Round($_.FreeSpace / 1GB, 1) } },
    @{ n = 'Free_Pct'; e = { if ($_.Size) { [math]::Round(100 * $_.FreeSpace / $_.Size, 1) } } }
Write-Host 'CPU'; Show-Table $cpu
Write-Host 'GPU'; Show-Table $gpu
Write-Host '磁碟'; Show-Table $pd
Write-Host '磁碟區'; Show-Table $vol
Save-Csv $cpu '02_CPU.csv'
Save-Csv $gpu '02_GPU.csv'
Save-Csv $bios '02_BIOS.csv'
Save-Csv $pd '02_實體磁碟.csv'
Save-Csv $vol '02_磁碟區.csv'

foreach ($v in $vol) {
    if ($v.Free_Pct -ne $null -and $v.Free_Pct -lt 15) {
        Add-Finding '警告' '磁碟' ($v.DeviceID + ' 剩餘空間僅 ' + $v.Free_Pct + '% (' + $v.Free_GB + ' GB)：R/Python 套件庫、暫存檔與 Windows 更新都可能因此失敗。')
    }
}
foreach ($d in @($pd)) {
    if ($d.HealthStatus -and $d.HealthStatus -ne 'Healthy') { Add-Finding '警告' '磁碟' ($d.FriendlyName + ' 健康狀態為 ' + $d.HealthStatus + '，請立即備份並檢查。') }
    if ($d.MediaType -eq 'HDD') { Add-Finding '資訊' '磁碟' ($d.FriendlyName + ' 為機械硬碟：R/Python 套件庫與暫存目錄建議放在 SSD。') }
}
if (Test-Path 'C:\Windows.old') { Add-Finding '資訊' '磁碟' '存在 C:\Windows.old（舊版 Windows 備份），可用「磁碟清理」釋放空間。' }

# ------------------------------------------------------------------ 3. 已安裝軟體
Section '3. 已安裝軟體（傳統桌面程式）'
$unPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$programs = Get-ItemProperty -Path $unPaths -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation,
        @{ n = 'Scope'; e = { if ($_.PSPath -like '*HKEY_CURRENT_USER*') { 'User' } else { 'Machine' } } } |
    Sort-Object DisplayName
Write-Host ('共 ' + @($programs).Count + ' 筆，完整清單見 03_已安裝軟體.csv')
Save-Csv $programs '03_已安裝軟體.csv'

$daPatterns = [ordered]@{
    'R'          = '^R for Windows|^R \d+\.\d+'
    'Rtools'     = '^Rtools'
    'RStudio'    = 'RStudio'
    'Positron'   = 'Positron'
    'Python'     = '^Python \d'
    'Conda'      = 'Anaconda|Miniconda|Miniforge|Mambaforge'
    'Git'        = '^Git( |$)|Git version'
    'Quarto'     = 'Quarto'
    'Pandoc'     = 'Pandoc'
    'VSCode'     = 'Visual Studio Code'
    'Java'       = 'Java|JDK|JRE|Temurin|OpenJDK'
    'NodeJS'     = 'Node\.js'
    'Julia'      = 'Julia'
    'Database'   = 'PostgreSQL|MySQL|MariaDB|SQLite|DBeaver|DuckDB|SQL Server'
    'BI_Stats'   = 'Power BI|Tableau|MATLAB|Stata|SPSS|JASP|jamovi'
    'Docker_WSL' = 'Docker|Windows Subsystem for Linux'
    'Office_WPS' = 'Microsoft 365|Microsoft Office|WPS|金山'
}
$daRows = @()
$daMissing = @()
foreach ($k in $daPatterns.Keys) {
    $hits = @($programs | Where-Object { $_.DisplayName -match $daPatterns[$k] })
    if ($hits.Count -eq 0) { $daMissing += $k }
    foreach ($h in $hits) {
        $daRows += [pscustomobject]@{ Category = $k; DisplayName = $h.DisplayName; Version = $h.DisplayVersion; Publisher = $h.Publisher; InstallLocation = $h.InstallLocation }
    }
}
Show-Table $daRows
Write-Host ('未在已安裝程式中偵測到：' + ($daMissing -join ', '))
Save-Csv $daRows '03_資料分析相關軟體.csv'

$hasR = @($daRows | Where-Object { $_.Category -eq 'R' }).Count -gt 0
$hasRtools = @($daRows | Where-Object { $_.Category -eq 'Rtools' }).Count -gt 0
if (-not $hasRtools) { $hasRtools = @(Get-ChildItem 'C:\' -Directory -Filter 'rtools*' -ErrorAction SilentlyContinue).Count -gt 0 }
if ($hasR -and -not $hasRtools) { Add-Finding '注意' 'R' '偵測到 R 但沒有 Rtools：需從原始碼編譯的套件（含許多 GitHub 套件）會安裝失敗。' }

# ------------------------------------------------------------------ 4. Store / UWP 應用
Section '4. Microsoft Store / UWP 應用（目前使用者）'
$appx = Get-AppxPackage -ErrorAction SilentlyContinue | Select-Object Name, Version, Publisher, Architecture, InstallLocation
Write-Host ('共 ' + @($appx).Count + ' 個，完整清單見 04_Store應用.csv')
Save-Csv $appx '04_Store應用.csv'
if (@($appx | Where-Object { $_.Name -like '*549981C3F5F10*' }).Count -gt 0) {
    Add-Finding '資訊' '應用' '仍安裝 Cortana 套件 (Microsoft.549981C3F5F10)：Cortana 獨立應用已退役，可視需要移除。'
}
if (@($appx | Where-Object { $_.Name -like '*Copilot*' }).Count -gt 0) {
    Add-Finding '資訊' '應用' '偵測到 Copilot 相關套件。'
}

# ------------------------------------------------------------------ 5. winget
Section '5. winget（套件管理員）'
$wg = Get-Command winget -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
if ($SkipWinget) {
    Write-Host '已略過 (-SkipWinget)'
} elseif ($wg) {
    $wgVer = Invoke-Native $wg.Source @('--version')
    Write-Host ('winget 版本：' + $wgVer)
    Save-Text (Invoke-Native $wg.Source @('list', '--accept-source-agreements')) '05_winget_已安裝.txt'
    $up = Invoke-Native $wg.Source @('upgrade', '--accept-source-agreements')
    Save-Text $up '05_winget_可升級.txt'
    Add-Finding '資訊' '軟體' '請查看 05_winget_可升級.txt，了解可由 winget 升級的軟體。'
} else {
    Add-Finding '資訊' '軟體' '找不到 winget。可能需要到 Microsoft Store 安裝或更新「應用安裝程式 (App Installer)」。'
    Write-Host '找不到 winget'
}

# ------------------------------------------------------------------ 6. 資料分析工具鏈
Section '6. 資料分析工具鏈'
$probeDefs = @(
    @{ Name = 'Rscript'; Exe = 'Rscript'; Args = @('--version'); Fb = @("$env:ProgramFiles\R\R-*\bin\x64\Rscript.exe", "$env:ProgramFiles\R\R-*\bin\Rscript.exe", "$env:LOCALAPPDATA\Programs\R\R-*\bin\x64\Rscript.exe") },
    @{ Name = 'git'; Exe = 'git'; Args = @('--version'); Fb = @("$env:ProgramFiles\Git\cmd\git.exe") },
    @{ Name = 'python'; Exe = 'python'; Args = @('--version'); Fb = @() },
    @{ Name = 'py (launcher)'; Exe = 'py'; Args = @('--version'); Fb = @() },
    @{ Name = 'conda'; Exe = 'conda'; Args = @('--version'); Fb = @("$env:USERPROFILE\miniconda3\Scripts\conda.exe", "$env:USERPROFILE\anaconda3\Scripts\conda.exe", "$env:ProgramData\miniconda3\Scripts\conda.exe", "$env:ProgramData\anaconda3\Scripts\conda.exe") },
    @{ Name = 'quarto'; Exe = 'quarto'; Args = @('--version'); Fb = @("$env:LOCALAPPDATA\Programs\Quarto\bin\quarto.cmd", "$env:ProgramFiles\Quarto\bin\quarto.cmd") },
    @{ Name = 'pandoc'; Exe = 'pandoc'; Args = @('--version'); Fb = @("$env:LOCALAPPDATA\Pandoc\pandoc.exe", "$env:ProgramFiles\Pandoc\pandoc.exe") },
    @{ Name = 'java'; Exe = 'java'; Args = @('-version'); Fb = @() },
    @{ Name = 'node'; Exe = 'node'; Args = @('--version'); Fb = @() },
    @{ Name = 'julia'; Exe = 'julia'; Args = @('--version'); Fb = @() },
    @{ Name = 'code (VS Code)'; Exe = 'code'; Args = @('--version'); Fb = @() },
    @{ Name = 'duckdb'; Exe = 'duckdb'; Args = @('--version'); Fb = @() },
    @{ Name = 'psql'; Exe = 'psql'; Args = @('--version'); Fb = @() },
    @{ Name = 'docker'; Exe = 'docker'; Args = @('--version'); Fb = @() }
)
$toolRows = @()
foreach ($d in $probeDefs) {
    $p = Find-Exe $d.Exe $d.Fb
    $ver = ''
    if ($p) { $ver = Get-FirstLine (Invoke-Native $p $d.Args) }
    $toolRows += [pscustomobject]@{ Tool = $d.Name; Found = [bool]$p; Path = $p; Version = $ver }
}
Show-Table $toolRows
Save-Csv $toolRows '06_工具鏈.csv'

foreach ($t in $toolRows) {
    if ($t.Path -and $t.Path -match '[^\x00-\x7F]') {
        Add-Finding '注意' '路徑' ($t.Tool + ' 的安裝路徑含非 ASCII 字元：' + $t.Path + '。部分工具（R 套件編譯、Quarto、Python 舊套件）遇到中文路徑可能出錯。')
    }
    if ($t.Tool -eq 'python' -and $t.Version -match 'Microsoft Store') {
        Add-Finding '注意' 'Python' 'python 指令只是 Microsoft Store 的應用程式執行別名（並未真正安裝 Python）。請安裝 Python，或到 設定 > 應用 > 應用執行別名 關閉。'
    }
}
if ($env:USERPROFILE -match '[^\x00-\x7F]') {
    Add-Finding '注意' '路徑' ('使用者資料夾路徑含非 ASCII 字元：' + $env:USERPROFILE + '。R 的個人套件庫預設在此路徑之下，建議把 R_LIBS_USER 指到純 ASCII 路徑。')
}

# ---- Python
if ($SkipPython) {
    Write-Host 'Python 明細已略過 (-SkipPython)'
} else {
    $pyExe = $null
    $pyBase = @()
    $pyLauncher = Find-Exe 'py'
    if ($pyLauncher) {
        $pyExe = $pyLauncher
        $pyBase = @('-3')
        Save-Text (Invoke-Native $pyLauncher @('-0p')) '06_python_已安裝版本.txt'
    } else {
        $pp = Get-Command python -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' -and $_.Source -notlike '*\WindowsApps\*' } | Select-Object -First 1
        if ($pp) { $pyExe = $pp.Source }
    }
    if ($pyExe) {
        Write-Host ('Python 直譯器：' + $pyExe + ' ' + ($pyBase -join ' '))
        Write-Host ('pip：' + (Get-FirstLine (Invoke-Native $pyExe ($pyBase + @('-m', 'pip', '--version')))))
        $pipJson = Invoke-Native $pyExe ($pyBase + @('-m', 'pip', 'list', '--format=json')) -StdoutOnly
        try {
            $pk = $pipJson | ConvertFrom-Json
            Save-Csv ($pk | Select-Object name, version) '06_pip_已安裝.csv'
            Write-Host ('pip 已安裝套件數：' + @($pk).Count)
        } catch { }
        Write-Host '檢查 pip 過期套件（需聯網，可能較慢）...'
        $outJson = Invoke-Native $pyExe ($pyBase + @('-m', 'pip', 'list', '--outdated', '--format=json')) -StdoutOnly
        try {
            $od = $outJson | ConvertFrom-Json
            if (@($od).Count -gt 0) {
                Save-Csv ($od | Select-Object name, version, latest_version, latest_filetype) '06_pip_可升級.csv'
                Add-Finding '注意' 'Python' ('有 ' + @($od).Count + ' 個 pip 套件可升級（見 06_pip_可升級.csv）。')
            } else { Write-Host 'pip：沒有過期套件' }
        } catch { }
        $chk = Invoke-Native $pyExe ($pyBase + @('-m', 'pip', 'check'))
        Save-Text $chk '06_pip_check.txt'
        if ($chk -and $chk -notmatch 'No broken requirements') { Add-Finding '警告' 'Python' 'pip check 回報依賴衝突，見 06_pip_check.txt。建議改用虛擬環境 (venv/conda) 隔離專案。' }
    } else {
        Add-Finding '資訊' 'Python' '未偵測到可用的 Python 直譯器。'
    }
    $condaExe = ($toolRows | Where-Object { $_.Tool -eq 'conda' } | Select-Object -First 1).Path
    if ($condaExe) { Save-Text (Invoke-Native $condaExe @('env', 'list')) '06_conda_環境.txt' }
}

# ---- R
$rscript = ($toolRows | Where-Object { $_.Tool -eq 'Rscript' } | Select-Object -First 1).Path
if ($SkipRPackages) {
    Write-Host 'R 套件明細已略過 (-SkipRPackages)'
} elseif ($rscript) {
    Write-Host ('Rscript：' + $rscript)
    Write-Host '收集 R 環境與套件資訊（含過期比對，需聯網，可能較慢）...'
    $rCode = @'
options(warn = 1)
out <- Sys.getenv("DIAG_OUT")
cat("R.version.string:", R.version.string, "\n")
cat("platform:", R.version$platform, "\n")
cat("R_HOME:", R.home(), "\n")
cat(".libPaths:\n")
for (p in .libPaths()) cat("  ", p, "  writable=", file.access(p, 2) == 0, "\n", sep = "")
cat("Sys.getlocale:", Sys.getlocale(), "\n")
li <- l10n_info()
cat("l10n_info:", paste(names(li), unlist(li), sep = "=", collapse = "; "), "\n")
cat("detectCores:", parallel::detectCores(), "\n")
es <- extSoftVersion()
cat("BLAS:", es[["BLAS"]], "\n")
cat("LAPACK:", tryCatch(La_library(), error = function(e) "NA"), "\n")
cat("pkgType:", getOption("pkgType"), "\n")
repos <- getOption("repos")
cat("repos:", paste(names(repos), repos, sep = "=", collapse = "; "), "\n")
ip <- installed.packages(fields = "Built")
df <- data.frame(Package = ip[, "Package"], Version = ip[, "Version"], Built = ip[, "Built"],
                 Priority = ip[, "Priority"], LibPath = ip[, "LibPath"], stringsAsFactors = FALSE)
write.csv(df, file.path(out, "06_R_installed.csv"), row.names = FALSE, fileEncoding = "UTF-8")
cat("installed package count:", nrow(df), "\n")
key <- c("renv", "pak", "tidyverse", "data.table", "arrow", "duckdb", "collapse", "targets",
         "quarto", "rmarkdown", "knitr", "xts", "zoo", "TTR", "quantmod", "PerformanceAnalytics",
         "rugarch", "forecast", "tsibble", "fable", "tidymodels", "xgboost", "lightgbm",
         "reticulate", "BiocManager", "devtools", "testthat", "lintr", "styler", "conflicted")
shiny_pkgs <- c("shiny", "shinythemes", "shinydashboard", "shinydashboardPlus", "memoise",
                "dashboardthemes", "shinyWidgets", "shinyjs", "shinyBS", "XML", "xml2", "bs4Dash",
                "htmltools", "shiny.i18n", "shinyvalidate", "shinyFeedback", "shinyMobile",
                "shinymanager", "shinyjqui", "miniUI", "sass", "BBmisc")
cat("key packages present:", paste(key[key %in% df$Package], collapse = ", "), "\n")
cat("key packages missing:", paste(setdiff(key, df$Package), collapse = ", "), "\n")
cat("shiny app packages present:", paste(shiny_pkgs[shiny_pkgs %in% df$Package], collapse = ", "), "\n")
cat("shiny app packages missing:", paste(setdiff(shiny_pkgs, df$Package), collapse = ", "), "\n")
if (is.null(repos) || is.na(repos["CRAN"]) || repos["CRAN"] == "@CRAN@") repos <- c(CRAN = "https://cloud.r-project.org")
old <- tryCatch(old.packages(repos = repos, checkBuilt = TRUE),
                error = function(e) { cat("old.packages failed:", conditionMessage(e), "\n"); NULL })
if (!is.null(old) && nrow(old) > 0) {
  write.csv(as.data.frame(old, stringsAsFactors = FALSE), file.path(out, "06_R_outdated.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  cat("outdated package count:", nrow(old), "\n")
} else {
  cat("outdated package count: 0\n")
}
'@
    $rFile = Join-Path $OutDir '_diag.R'
    Set-Content -Path $rFile -Value $rCode -Encoding ASCII
    $env:DIAG_OUT = $OutDir
    $rOut = Invoke-Native $rscript @($rFile)
    Save-Text $rOut '06_R_診斷.txt'
    $rOut -split "`n" | Select-Object -First 40 | ForEach-Object { Write-Host ('  ' + $_) }
    Remove-Item $rFile -Force -ErrorAction SilentlyContinue

    if ($rOut -match 'outdated package count:\s*(\d+)') {
        $n = [int]$Matches[1]
        if ($n -gt 0) { Add-Finding '注意' 'R' ('有 ' + $n + ' 個 R 套件可升級或需重建（見 06_R_outdated.csv）。') }
    }
    if ($rOut -match 'writable=' -and $rOut -notmatch 'writable=TRUE') { Add-Finding '警告' 'R' 'R 的套件庫路徑皆不可寫入：安裝或更新套件將失敗，請建立個人套件庫 (R_LIBS_USER) 並確認權限。' }
    if ($rOut -match 'BLAS:.*Rblas\.dll') { Add-Finding '資訊' 'R' 'R 使用內建參考 BLAS (Rblas.dll)。大型矩陣運算若要提速，可研究改用 OpenBLAS（屬進階自訂，需自行評估相容性）。' }
    if ($rOut -match 'key packages missing:.*renv') { Add-Finding '資訊' 'R' '未安裝 renv：多專案並行或需要可重現分析時，建議每個專案用 renv 鎖定套件版本。' }
} else {
    Write-Host '未找到 Rscript，略過 R 明細。'
}

# ------------------------------------------------------------------ 7. 啟動項目、排程、服務
Section '7. 啟動項目 / 排程工作 / 服務'
$startup = Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User
Show-Table $startup
Save-Csv $startup '07_啟動項目.csv'
if (@($startup).Count -gt 15) { Add-Finding '注意' '效能' ('啟動項目共 ' + @($startup).Count + ' 筆，過多會拖慢開機；請在 工作管理員 > 啟動 檢視並停用不需要者。') }

$tasks = $null
try {
    $tasks = Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and $_.State -ne 'Disabled' } |
        Select-Object TaskName, TaskPath, State, @{ n = 'Actions'; e = { ($_.Actions | ForEach-Object { ('' + $_.Execute + ' ' + $_.Arguments).Trim() }) -join ' ; ' } }
} catch { }
Write-Host '非 Microsoft 且已啟用的排程工作'
Show-Table $tasks
Save-Csv $tasks '07_非Microsoft排程工作.csv'

$svc = Get-CimInstance Win32_Service | Where-Object { $_.StartMode -eq 'Auto' } |
    Select-Object Name, DisplayName, State, StartMode, DelayedAutoStart, PathName | Sort-Object State, Name
Save-Csv $svc '07_自動啟動服務.csv'
Write-Host ('自動啟動服務共 ' + @($svc).Count + ' 個（明細見 07_自動啟動服務.csv）')

# ------------------------------------------------------------------ 8. 安全
Section '8. 安全性'
try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    $mpRow = $mp | Select-Object AMServiceEnabled, AntivirusEnabled, RealTimeProtectionEnabled, AntivirusSignatureLastUpdated, AntivirusSignatureVersion, QuickScanEndTime, FullScanEndTime
    Show-Table $mpRow
    Save-Csv $mpRow '08_Defender.csv'
    if (-not $mp.RealTimeProtectionEnabled) { Add-Finding '警告' '安全' 'Microsoft Defender 即時保護未啟用（若使用第三方防毒軟體可忽略）。' }
    if ($mp.AntivirusSignatureLastUpdated) {
        $sigAge = ((Get-Date) - $mp.AntivirusSignatureLastUpdated).Days
        if ($sigAge -gt 3) { Add-Finding '警告' '安全' ('Defender 病毒定義已 ' + $sigAge + ' 天未更新。') }
    }
} catch { Write-Host 'Get-MpComputerStatus 不可用（可能由第三方防毒接管）' }
$av = Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntivirusProduct -ErrorAction SilentlyContinue | Select-Object displayName, productState
Write-Host '已註冊的防毒產品'; Show-Table $av
Save-Csv $av '08_防毒產品.csv'
if (@($av).Count -eq 0) { Add-Finding '警告' '安全' '安全中心未註冊任何防毒產品。' }

$fw = Get-NetFirewallProfile -ErrorAction SilentlyContinue | Select-Object Name, Enabled
Write-Host '防火牆'; Show-Table $fw
Save-Csv $fw '08_防火牆.csv'
foreach ($f in @($fw)) { if ($f.Enabled -eq $false -or "$($f.Enabled)" -eq 'False') { Add-Finding '警告' '安全' ('防火牆設定檔 ' + $f.Name + ' 已停用。') } }

if ((Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA') -eq 0) { Add-Finding '警告' '安全' 'UAC (EnableLUA) 已被關閉。' }
if ((Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections') -eq 0) { Add-Finding '注意' '安全' '遠端桌面 (RDP) 已啟用；若不需要請關閉，若需要請務必設定強密碼與網路層級驗證。' }

try {
    $admins = Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | Select-Object Name, ObjectClass, PrincipalSource
    Write-Host '本機系統管理員群組成員'; Show-Table $admins
    Save-Csv $admins '08_本機管理員.csv'
} catch { }

$ep = Get-ExecutionPolicy -List | Select-Object Scope, ExecutionPolicy
Save-Csv $ep '08_執行原則.csv'

if ($isAdmin) {
    try {
        $bl = Get-BitLockerVolume -ErrorAction Stop | Select-Object MountPoint, VolumeStatus, ProtectionStatus, EncryptionPercentage
        Write-Host 'BitLocker'; Show-Table $bl
        Save-Csv $bl '08_BitLocker.csv'
    } catch { Write-Host 'BitLocker 資訊不可用（此版本或未啟用）' }
    try { Write-Host ('Secure Boot：' + (Confirm-SecureBootUEFI)) } catch { Write-Host 'Secure Boot：不適用或為傳統 BIOS' }
    try {
        $tpm = Get-Tpm | Select-Object TpmPresent, TpmReady, ManufacturerVersion
        Show-Table $tpm
    } catch { }
    try {
        $smb = Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol, EnableSMB2Protocol
        Show-Table $smb
        if ($smb.EnableSMB1Protocol) { Add-Finding '警告' '安全' 'SMB1 協定已啟用（老舊且有高風險漏洞），除非有老設備需求，建議停用。' }
    } catch { }
} else {
    Add-Finding '資訊' '安全' '未以系統管理員身分執行：已略過 BitLocker / Secure Boot / TPM / SMB1 檢查。'
}

# ------------------------------------------------------------------ 9. 與資料分析有關的系統設定
Section '9. 系統設定（編碼、長路徑、電源、記憶體、PATH、環境變數）'
$acp = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' 'ACP'
$oemcp = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' 'OEMCP'
$culture = (Get-Culture).Name
$sysLocale = (Get-WinSystemLocale).Name
$langList = (Get-WinUserLanguageList | ForEach-Object { $_.LanguageTag }) -join ', '
$homeLoc = ''
try { $homeLoc = (Get-WinHomeLocation).HomeLocation } catch { }
$long = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled'
$power = Invoke-Native 'powercfg.exe' @('/getactivescheme')
$pf = Get-CimInstance Win32_PageFileUsage | Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage
$proxyOn = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' 'ProxyEnable'
$proxySrv = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' 'ProxyServer'
$set = [pscustomobject]@{
    ACP_ANSI碼頁 = $acp; OEM碼頁 = $oemcp; Culture = $culture; SystemLocale = $sysLocale; 語言清單 = $langList; 地區 = $homeLoc
    LongPathsEnabled = $long; 電源計畫 = $power; 自動管理分頁檔 = $cs.AutomaticManagedPagefile; ProxyEnable = $proxyOn; ProxyServer = $proxySrv
}
$set | Format-List | Out-String -Width 220 | Write-Host
Save-Csv $set '09_設定.csv'
Save-Csv $pf '09_分頁檔.csv'

if ($acp -and $acp -ne '65001') { Add-Finding '資訊' '編碼' ('系統 ANSI 碼頁為 ' + $acp + '（非 UTF-8）。讀寫非 UTF-8 的 CSV/文字檔時請明確指定編碼（R: fileEncoding / readr locale；Python: encoding=utf-8）。') }
if ($long -ne 1) { Add-Finding '注意' '設定' 'Windows 長路徑 (LongPathsEnabled) 未啟用：套件路徑過深時可能安裝失敗。' }
if ($power -match 'Power saver|節能|节能') { Add-Finding '注意' '效能' '目前電源計畫為省電模式，會降低運算效能。' }
if ($proxyOn -eq 1) { Add-Finding '資訊' '網路' ('系統啟用了 Proxy：' + $proxySrv + '。R/Python 下載失敗時請檢查 HTTP(S)_PROXY 設定。') }

# PATH 檢查
$pathRows = @()
foreach ($scope in @('Machine', 'User')) {
    $raw = [Environment]::GetEnvironmentVariable('Path', $scope)
    if ($raw) {
        foreach ($e in ($raw -split ';')) {
            if ([string]::IsNullOrWhiteSpace($e)) { continue }
            $exp = [Environment]::ExpandEnvironmentVariables($e.Trim())
            $pathRows += [pscustomobject]@{ Scope = $scope; Entry = $e.Trim(); Expanded = $exp; Exists = (Test-Path -LiteralPath $exp) }
        }
    }
}
Save-Csv $pathRows '09_PATH.csv'
$missingPath = @($pathRows | Where-Object { -not $_.Exists })
$dupPath = @($pathRows | Group-Object { $_.Expanded.ToLower() } | Where-Object { $_.Count -gt 1 })
Write-Host ('PATH 條目 ' + @($pathRows).Count + ' 個；不存在 ' + $missingPath.Count + ' 個；重複 ' + $dupPath.Count + ' 組')
if ($missingPath.Count -gt 0) { Add-Finding '資訊' 'PATH' ('PATH 內有 ' + $missingPath.Count + ' 個不存在的目錄（見 09_PATH.csv）。') }
if ($dupPath.Count -gt 0) { Add-Finding '資訊' 'PATH' ('PATH 內有 ' + $dupPath.Count + ' 組重複條目。') }

# 環境變數
$envNames = @('R_HOME', 'R_LIBS_USER', 'R_LIBS_SITE', 'R_ENVIRON_USER', 'PYTHONPATH', 'PYTHONHOME', 'CONDA_PREFIX', 'VIRTUAL_ENV', 'HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY', 'TEMP', 'TMP')
$envRows = foreach ($n in $envNames) {
    [pscustomobject]@{ Name = $n; Process = [Environment]::GetEnvironmentVariable($n, 'Process'); User = [Environment]::GetEnvironmentVariable($n, 'User'); Machine = [Environment]::GetEnvironmentVariable($n, 'Machine') }
}
Save-Csv ($envRows | Where-Object { $_.Process -or $_.User -or $_.Machine }) '09_環境變數.csv'

# TEMP 大小
try {
    $tmpBytes = (Get-ChildItem -LiteralPath $env:TEMP -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    $tmpGB = [math]::Round($tmpBytes / 1GB, 2)
    Write-Host ('使用者 TEMP 大小：' + $tmpGB + ' GB')
    if ($tmpGB -gt 2) { Add-Finding '注意' '磁碟' ('使用者 TEMP 資料夾已達 ' + $tmpGB + ' GB，可清理超過 7 天的舊檔。') }
} catch { }

# ------------------------------------------------------------------ 10. 事件記錄
if (-not $SkipEventLog) {
    Section '10. 近 14 天事件記錄摘要'
    $since = (Get-Date).AddDays(-14)
    try {
        $ev = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1, 2; StartTime = $since } -MaxEvents 500 -ErrorAction Stop
        $top = $ev | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 15 Count, Name
        Show-Table $top
        Save-Csv $top '10_系統錯誤_來源統計.csv'
        $hw = @($top | Where-Object { $_.Name -match 'disk|Ntfs|WHEA|volmgr|storahci|stornvme|nvme' })
        if ($hw.Count -gt 0) { Add-Finding '警告' '硬體' ('系統事件中出現疑似儲存/硬體錯誤來源：' + (($hw | ForEach-Object { $_.Name }) -join ', ') + '，建議檢查磁碟健康與備份。') }
    } catch { Write-Host '近 14 天沒有 System 錯誤/嚴重事件，或無法讀取。' }
    try {
        $crash = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = $since } -MaxEvents 300 -ErrorAction Stop
        $ct = $crash | Group-Object { $_.Properties[0].Value } | Sort-Object Count -Descending | Select-Object -First 15 Count, Name
        Show-Table $ct
        Save-Csv $ct '10_應用程式當機統計.csv'
        Add-Finding '注意' '穩定性' ('近 14 天有應用程式當機紀錄（見 10_應用程式當機統計.csv）。')
    } catch { Write-Host '近 14 天沒有應用程式當機紀錄，或無法讀取。' }
}

# ------------------------------------------------------------------ 摘要
Section '摘要'
$order = @{ '警告' = 0; '注意' = 1; '資訊' = 2 }
$sorted = $script:Findings | Sort-Object { $order[$_.Level] }, Area
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('Windows 10 診斷摘要  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
[void]$sb.AppendLine('系統：' + $os.Caption + ' ' + $dispVer + ' (Build ' + $build + ')，RAM ' + $ramGB + ' GB，管理員身分=' + $isAdmin)
[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- 發現 (' + @($sorted).Count + ') ---')
foreach ($f in $sorted) { [void]$sb.AppendLine('[' + $f.Level + '] ' + $f.Area + ' - ' + $f.Message) }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- 資料分析工具鏈 ---')
[void]$sb.AppendLine((($toolRows | Format-Table Tool, Found, Version, Path -AutoSize | Out-String -Width 220).TrimEnd()))
[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- 產出檔案 ---')
foreach ($f in $script:Files) { [void]$sb.AppendLine('  ' + $f) }
$sumText = $sb.ToString()
Set-Content -Path (Join-Path $OutDir '00_摘要.txt') -Value $sumText -Encoding UTF8
Write-Host $sumText
Write-Host ''
Write-Host ('完成。報告位置：' + $OutDir) -ForegroundColor Green
Write-Host '提示：00_摘要.txt 為總覽；分享前請先檢視是否含有不想公開的資訊。' -ForegroundColor Yellow
