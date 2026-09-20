#Requires -Version 5.1
<#
.SYNOPSIS
  Windows 10 資料分析工作站「唯讀」診斷 v2。
.DESCRIPTION
  v2 相對 v1 (Win10_Diagnose.ps1) 新增的重點：
    A. 企業管控代理偵測（DLP / 透明加密 / 第三方 EDR）與其對 R/Python 套件安裝的影響。
    B. 重複防毒偵測（Defender Normal 模式 + 第三方同時常駐）。
    C. 雲端同步資料夾（OneDrive / 坚果云 / Dropbox）內是否放著 Git repo、R 專案、venv。
    D. 非 ASCII 路徑風險（使用者資料夾、專案路徑、R_LIBS_USER、TEMP）。
    E. 分頁檔容量 vs 實體記憶體評估（大資料 spill / OOM 防護）。
    F. GPU 是否真的能做運算加速（避免誤以為有顯卡就能跑 CUDA）。
    G. R / Python 堆疊「分組差距分析」，直接指出缺哪一組。
    H. ODBC 驅動盤點與缺口（PostgreSQL / MySQL / ClickHouse / SQLite）。
    I. Git 設定健檢（longpaths / autocrlf / lfs / credential helper）。
    J. 產出 00_摘要.txt 與 99_建議指令.txt：直接給出 Setup_DataStack.ps1 該加哪些開關。
  完全唯讀：不安裝、不刪除、不修改任何設定。
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Win10_Diagnose_v2.ps1
.EXAMPLE
  .\Win10_Diagnose_v2.ps1 -Fast
#>
[CmdletBinding()]
param(
    [string]$OutDir = (Join-Path $env:USERPROFILE ('Win10_Diag2_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))),
    [switch]$Fast,
    [switch]$SkipWinget,
    [switch]$SkipRPackages,
    [switch]$SkipPython
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
if ($Fast) { $SkipWinget = $true; $SkipRPackages = $true; $SkipPython = $true }
$null = New-Item -ItemType Directory -Path $OutDir -Force

$script:Findings = New-Object System.Collections.Generic.List[object]
$script:Actions = New-Object System.Collections.Generic.List[string]
$script:Files = New-Object System.Collections.Generic.List[string]

# ---------------------------------------------------------------- 共用函式
function Add-Finding {
    param([ValidateSet('嚴重', '警告', '注意', '資訊')][string]$Level, [string]$Area, [string]$Message)
    $script:Findings.Add([pscustomobject]@{ Level = $Level; Area = $Area; Message = $Message })
}
function Add-Action { param([string]$Text) if ($script:Actions -notcontains $Text) { $script:Actions.Add($Text) } }
function Section { param([string]$T) Write-Host ''; Write-Host ('=== ' + $T + ' ===') -ForegroundColor Cyan }
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
    ($Data | Format-Table -AutoSize | Out-String -Width 240).TrimEnd() | Write-Host
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
        return ((@($o) | ForEach-Object { "$_" }) -join "`n").Trim()
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
function Test-NonAscii { param([string]$s) return ($s -and ($s -match '[^\x00-\x7F]')) }

$isAdmin = Test-Admin
Write-Host ('輸出資料夾：' + $OutDir) -ForegroundColor Green
Write-Host ('系統管理員身分：' + $isAdmin + '    快速模式：' + [bool]$Fast)

# ---------------------------------------------------------------- 1. 系統與硬體
Section '1. 系統與硬體'
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$dispVer = Get-RegValue $cv 'DisplayVersion'
if (-not $dispVer) { $dispVer = Get-RegValue $cv 'ReleaseId' }
$build = ('' + (Get-RegValue $cv 'CurrentBuild')) + '.' + (Get-RegValue $cv 'UBR')
$ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$freeRamGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
$sys = [pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    OS           = $os.Caption
    Version      = $dispVer
    Build        = $build
    CPU          = $cpu.Name
    Cores        = $cpu.NumberOfCores
    Threads      = $cpu.NumberOfLogicalProcessors
    RAM_GB       = $ramGB
    FreeRAM_GB   = $freeRamGB
    UptimeDays   = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1)
    PowerShell   = $PSVersionTable.PSVersion.ToString()
    IsAdmin      = $isAdmin
}
$sys | Format-List | Out-String -Width 240 | Write-Host
Save-Csv $sys '01_系統.csv'

if ($os.Caption -match 'Windows 10') {
    Add-Finding '警告' '系統' 'Windows 10 一般支援已於 2025-10-14 結束。請確認公司是否已購買 ESU；否則作業系統層級的「最強化」上限就在這裡（以 Microsoft 官方公告與貴公司 IT 政策為準）。'
}
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Add-Finding '注意' '工具' ('目前只有 Windows PowerShell ' + $PSVersionTable.PSVersion + '。PowerShell 7 有 ForEach-Object -Parallel、更正確的 UTF-8 與 JSON 處理，對資料前處理腳本幫助很大，且可與 5.1 並存。')
    Add-Action '-InstallToolchain'
}

$gpus = Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DriverDate
Show-Table $gpus
Save-Csv $gpus '01_GPU.csv'
foreach ($g in @($gpus)) {
    if ($g.Name -match 'GT (7|6|5)\d\d|GTX (6|7)\d\d|Quadro K|NVS ') {
        Add-Finding '資訊' 'GPU' ($g.Name + ' 屬舊世代 NVIDIA（Kepler/Fermi 級）。現行 CUDA / PyTorch / XGBoost-GPU 都已不支援這種運算能力。請把它當「只負責顯示」，模型訓練一律走 CPU 路線（XGBoost/LightGBM 的 hist 演算法 + 多執行緒）。')
    }
}
if ($cpu.Name -match 'i\d-\d+F') {
    Add-Finding '資訊' 'CPU' ($cpu.Name + ' 為 F 版（無內顯），顯示完全依賴獨立顯卡；不影響 CPU 運算效能。')
}

# ---------------------------------------------------------------- 2. 磁碟與記憶體策略
Section '2. 磁碟、分頁檔與記憶體策略'
$vol = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object DeviceID, FileSystem,
@{n = 'Size_GB'; e = { [math]::Round($_.Size / 1GB, 1) } },
@{n = 'Free_GB'; e = { [math]::Round($_.FreeSpace / 1GB, 1) } },
@{n = 'Free_Pct'; e = { if ($_.Size) { [math]::Round(100 * $_.FreeSpace / $_.Size, 1) } } }
$pd = $null
try { $pd = Get-PhysicalDisk | Select-Object FriendlyName, MediaType, BusType, HealthStatus, @{n = 'Size_GB'; e = { [math]::Round($_.Size / 1GB) } } } catch { }
Show-Table $vol
Show-Table $pd
Save-Csv $vol '02_磁碟區.csv'
Save-Csv $pd '02_實體磁碟.csv'

foreach ($v in @($vol)) {
    if ($null -ne $v.Free_Pct -and $v.Free_Pct -lt 20) {
        Add-Finding '警告' '磁碟' ($v.DeviceID + ' 剩餘 ' + $v.Free_Pct + '% (' + $v.Free_GB + ' GB)。DuckDB / Arrow 在處理大表時會把中間結果 spill 到磁碟，空間不足會讓查詢直接失敗。')
    }
}
if (@($pd).Count -eq 1 -and @($vol).Count -eq 1) {
    Add-Finding '注意' '磁碟' '全機只有一顆磁碟、一個分割區：系統、套件庫、資料集、暫存檔、spill 檔全部互搶空間與 IO。若要再往上強化，加一顆 NVMe SSD 專放 data/ 與 TEMP 是本機投資報酬率最高的硬體升級。'
}
foreach ($d in @($pd)) {
    if ($d.HealthStatus -and $d.HealthStatus -ne 'Healthy') { Add-Finding '嚴重' '磁碟' ($d.FriendlyName + ' 健康狀態 ' + $d.HealthStatus + '：立刻備份。') }
}

$pf = Get-CimInstance Win32_PageFileUsage | Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage
Show-Table $pf
Write-Host ('自動管理分頁檔：' + $cs.AutomaticManagedPagefile)
Save-Csv $pf '02_分頁檔.csv'
$pfMB = 0
foreach ($p in @($pf)) { $pfMB += [int]$p.AllocatedBaseSize }
if ($pfMB -gt 0 -and $pfMB -lt ($ramGB * 1024 * 0.5)) {
    Add-Finding '注意' '記憶體' ('分頁檔僅 ' + $pfMB + ' MB，不到實體記憶體 (' + $ramGB + ' GB) 的一半。R 的 rugarch/回測、Python 的大表 join 一旦超過實體記憶體，會直接被系統終止而不是變慢。建議固定 ' + [int]($ramGB * 1024 * 0.5) + '～' + [int]($ramGB * 1024) + ' MB。')
    Add-Action '-SetPageFile'
}

# ---------------------------------------------------------------- 3. 企業管控代理
Section '3. 企業管控代理 / 防毒 / 加密用戶端'
$unPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$programs = Get-ItemProperty -Path $unPaths -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation | Sort-Object DisplayName
Save-Csv $programs '03_已安裝軟體.csv'
Write-Host ('已安裝程式共 ' + @($programs).Count + ' 筆（見 03_已安裝軟體.csv）')

$agentPattern = '亿赛通|億賽通|eSafeNet|DocGuard|Ping32|深信服|Sangfor|奇安信|QiAnXin|360\s*(安全|終端|终端)|天珣|IP-guard|域之盾|安全管控|文档加密|文檔加密|Kaspersky|卡巴斯基|Symantec|McAfee|Trellix|Trend Micro|趨勢|趋势|CrowdStrike|SentinelOne|Cortex XDR|Carbon Black|ESET|Bitdefender|Sophos|Ivanti|LANDesk|Intune|Endpoint Manager'
$agents = @($programs | Where-Object { $_.DisplayName -match $agentPattern })
Show-Table ($agents | Select-Object DisplayName, DisplayVersion, Publisher)
Save-Csv $agents '03_管控代理.csv'

$agentProcPattern = '^Cdg|^CDG|esafe|docguard|^avp$|klnagent|ksde|^360|sfdesk|Sangfor|qaxsafe|SentinelAgent|CSFalcon|MsMpEng'
$agentProcs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $agentProcPattern } |
    Select-Object Name, Id, @{n = 'WS_MB'; e = { [math]::Round($_.WorkingSet64 / 1MB) } } | Sort-Object Name
Show-Table $agentProcs
Save-Csv $agentProcs '03_管控代理行程.csv'

if (@($agents).Count -gt 0 -or @($agentProcs).Count -gt 0) {
    $names = @()
    foreach ($a in @($agents)) { $names += $a.DisplayName }
    foreach ($p in @($agentProcs | Select-Object -ExpandProperty Name -Unique)) { $names += $p }
    Add-Finding '警告' '管控' ('偵測到企業管控／防毒／透明加密用戶端：' + (($names | Select-Object -Unique) -join ', ') + '。這類代理會攔截每一次檔案讀寫，是 R/Python 套件安裝變慢或失敗、git 操作卡住、Parquet 檔讀寫異常的頭號原因。')
    Add-Finding '嚴重' '管控' '不要自行停用或解除安裝這些代理：一來多半被策略鎖定，二來在公司資產上這通常違反資安規範。正確做法是向 IT 申請「開發目錄排除」（R 套件庫、Python venv、專案 data 目錄、TEMP），由 IT 在管理主控台加白名單。'
    Add-Action '-AddDefenderExclusions'
}

$avs = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntivirusProduct -ErrorAction SilentlyContinue | Select-Object displayName, productState
Show-Table $avs
Save-Csv $avs '03_防毒註冊.csv'
$def = $null
try { $def = Get-MpComputerStatus -ErrorAction Stop } catch { }
if ($def) {
    Write-Host ('Defender RunningMode=' + $def.AMRunningMode + '  RealTime=' + $def.RealTimeProtectionEnabled)
    $thirdParty = @($avs | Where-Object { $_.displayName -notmatch 'Defender' })
    if ($thirdParty.Count -gt 0 -and $def.AMRunningMode -eq 'Normal' -and $def.RealTimeProtectionEnabled) {
        Add-Finding '警告' '安全' ('安全中心同時註冊了 ' + (($thirdParty | ForEach-Object { $_.displayName }) -join ', ') + ' 與 Microsoft Defender，而 Defender 目前是 Normal 模式且即時保護開啟。兩套即時掃描同時掛在檔案系統上，會讓「安裝數百個 R 套件 / pip 解壓 wheel」這類小檔案密集操作慢上數倍。請回報 IT，由他們決定是否讓 Defender 轉為 Passive。')
    }
    if ($def.AntivirusSignatureLastUpdated) {
        $sigAge = ((Get-Date) - $def.AntivirusSignatureLastUpdated).Days
        if ($sigAge -gt 3) { Add-Finding '警告' '安全' ('Defender 病毒定義已 ' + $sigAge + ' 天未更新。') }
    }
}
$fw = Get-NetFirewallProfile -ErrorAction SilentlyContinue | Select-Object Name, Enabled
Show-Table $fw
Save-Csv $fw '03_防火牆.csv'
foreach ($f in @($fw)) { if ("$($f.Enabled)" -eq 'False') { Add-Finding '警告' '安全' ('防火牆設定檔 ' + $f.Name + ' 已停用。') } }

# ---------------------------------------------------------------- 4. 工作區位置
Section '4. 工作區位置（雲端同步與非 ASCII 路徑）'
$syncRoots = @()
foreach ($e in @('OneDrive', 'OneDriveCommercial', 'OneDriveConsumer')) {
    $v = [Environment]::GetEnvironmentVariable($e)
    if ($v -and (Test-Path -LiteralPath $v)) { $syncRoots += $v }
}
foreach ($n in @('Dropbox', 'Nutstore', '坚果云', 'Google Drive', 'iCloudDrive', 'Box')) {
    $p = Join-Path $env:USERPROFILE $n
    if (Test-Path -LiteralPath $p) { $syncRoots += $p }
}
$syncRoots = @($syncRoots | Select-Object -Unique)
Write-Host ('偵測到的雲端同步根目錄：' + ($syncRoots -join ', '))

$repoRows = @()
foreach ($r in $syncRoots) {
    $gits = Get-ChildItem -LiteralPath $r -Directory -Filter '.git' -Recurse -Force -Depth 4 -ErrorAction SilentlyContinue
    foreach ($g in $gits) { $repoRows += [pscustomobject]@{ Type = 'Git repo'; Path = $g.Parent.FullName } }
    foreach ($marker in @('renv.lock', 'pyproject.toml', 'uv.lock', '.venv')) {
        $hits = Get-ChildItem -LiteralPath $r -Filter $marker -Recurse -Force -Depth 4 -ErrorAction SilentlyContinue
        foreach ($h in $hits) { $repoRows += [pscustomobject]@{ Type = $marker; Path = $h.FullName } }
    }
}
$repoRows = @($repoRows | Sort-Object Type, Path -Unique)
Show-Table ($repoRows | Select-Object -First 25)
Save-Csv $repoRows '04_雲端同步內的專案.csv'
if ($repoRows.Count -gt 0) {
    Add-Finding '警告' '工作區' ('在雲端同步資料夾中發現 ' + $repoRows.Count + ' 個專案/環境標記（見 04_雲端同步內的專案.csv）。同步用戶端會在 .git、renv/library、.venv、*.parquet 上造成檔案鎖定與版本衝突，輕則變慢，重則 repo 或環境毀損。建議把程式與資料移到未同步的本機路徑（例如 C:\work），只讓文件與報告留在雲端。')
    Add-Action '-PrepareWorkspace'
}

$pathChecks = [ordered]@{
    '使用者資料夾' = $env:USERPROFILE
    '目前工作目錄' = (Get-Location).Path
    'TEMP'         = $env:TEMP
    'R_LIBS_USER'  = [Environment]::GetEnvironmentVariable('R_LIBS_USER', 'User')
}
foreach ($k in $pathChecks.Keys) {
    $p = $pathChecks[$k]
    if (Test-NonAscii $p) {
        Add-Finding '注意' '路徑' ($k + ' 含非 ASCII 字元：' + $p + '。R 從原始碼編譯、部分 Python C 擴充、LaTeX/Quarto 產 PDF 時，遇到中文路徑仍有機率出錯。純 ASCII 的工作路徑（如 C:\work）最安全。')
    }
}

# ---------------------------------------------------------------- 5. 系統設定
Section '5. 系統設定（編碼、長路徑、電源）'
$acp = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' 'ACP'
$long = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled'
$power = Invoke-Native 'powercfg.exe' @('/getactivescheme')
$set = [pscustomobject]@{ ANSI碼頁 = $acp; LongPathsEnabled = $long; 電源計畫 = $power; SystemLocale = (Get-WinSystemLocale).Name }
$set | Format-List | Out-String -Width 240 | Write-Host
Save-Csv $set '05_設定.csv'

if ($long -ne 1) {
    Add-Finding '注意' '設定' 'Windows 長路徑未啟用 (LongPathsEnabled=0)。R 套件（尤其 tidyverse 系）與 node_modules 的巢狀路徑很容易超過 260 字元而安裝失敗。'
    Add-Action '-EnableLongPaths'
}
if ($acp -and "$acp" -ne '65001') {
    Add-Finding '注意' '編碼' ('系統 ANSI 碼頁為 ' + $acp + '（非 UTF-8）。中文 CSV 在 Excel / R / Python 之間來回時的亂碼多半來自這裡。比起切換「UTF-8 Beta」（會讓部分舊程式亂碼），更安全的做法是在程式碼一律明示編碼：R 用 readr::read_csv(locale = locale(encoding = "UTF-8"))，Python 用 encoding="utf-8-sig"。')
}
if ($power -match 'Power saver|節能|节能') {
    Add-Finding '注意' '效能' '目前是省電電源計畫，會壓低 CPU 全核心頻率。'
    Add-Action '-PowerPlanHigh'
} elseif ($power -match 'Balanced|平衡') {
    Add-Finding '資訊' '效能' '目前是「平衡」電源計畫。桌機長時間跑回測／訓練時，切到「高效能」可避免降頻；筆電則會較耗電發熱。'
    Add-Action '-PowerPlanHigh'
}

# ---------------------------------------------------------------- 6. 工具鏈
Section '6. 資料分析工具鏈'
$probe = @(
    @{ N = 'Rscript'; E = 'Rscript'; A = @('--version'); F = @("$env:ProgramFiles\R\R-*\bin\x64\Rscript.exe", "$env:LOCALAPPDATA\Programs\R\R-*\bin\x64\Rscript.exe") },
    # Rtools 的 gcc 不在 usr\bin，而在 x86_64-w64-mingw32.static.posix\bin（Rtools4x 佈局）。
    # usr\bin 只有 make / sh 等 msys2 工具。找錯路徑會把「已安裝」誤報成「沒安裝」。
    @{ N = 'Rtools'; E = 'gcc'; A = @('--version'); F = @(
            "C:\rtools*\x86_64-w64-mingw32.static.posix\bin\gcc.exe",
            "C:\rtools*\ucrt64\bin\gcc.exe",
            "C:\rtools*\mingw64\bin\gcc.exe",
            "$env:ProgramFiles\Rtools*\x86_64-w64-mingw32.static.posix\bin\gcc.exe") },
    @{ N = 'python'; E = 'python'; A = @('--version'); F = @() },
    @{ N = 'py'; E = 'py'; A = @('--version'); F = @() },
    @{ N = 'uv'; E = 'uv'; A = @('--version'); F = @("$env:USERPROFILE\.local\bin\uv.exe") },
    @{ N = 'conda'; E = 'conda'; A = @('--version'); F = @("$env:USERPROFILE\miniconda3\Scripts\conda.exe", "$env:USERPROFILE\anaconda3\Scripts\conda.exe") },
    @{ N = 'git'; E = 'git'; A = @('--version'); F = @("$env:ProgramFiles\Git\cmd\git.exe") },
    @{ N = 'quarto'; E = 'quarto'; A = @('--version'); F = @("$env:LOCALAPPDATA\Programs\Quarto\bin\quarto.cmd", "$env:ProgramFiles\Quarto\bin\quarto.cmd") },
    @{ N = 'pandoc'; E = 'pandoc'; A = @('--version'); F = @("$env:LOCALAPPDATA\Pandoc\pandoc.exe") },
    @{ N = 'duckdb'; E = 'duckdb'; A = @('--version'); F = @() },
    @{ N = 'psql'; E = 'psql'; A = @('--version'); F = @() },
    @{ N = 'pwsh'; E = 'pwsh'; A = @('--version'); F = @() },
    @{ N = 'node'; E = 'node'; A = @('--version'); F = @() },
    @{ N = 'java'; E = 'java'; A = @('-version'); F = @() },
    @{ N = 'docker'; E = 'docker'; A = @('--version'); F = @() },
    @{ N = 'code'; E = 'code'; A = @('--version'); F = @() },
    @{ N = 'positron'; E = 'positron'; A = @('--version'); F = @("$env:LOCALAPPDATA\Programs\Positron\bin\positron.cmd") }
)
$tools = @()
foreach ($d in $probe) {
    $p = Find-Exe $d.E $d.F
    $ver = ''
    if ($p) { $ver = (((Invoke-Native $p $d.A) -split "`n") | Select-Object -First 1).Trim() }
    $onPath = [bool](Get-Command $d.E -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' })
    $tools += [pscustomobject]@{ Tool = $d.N; Found = [bool]$p; OnPATH = $onPath; Version = $ver; Path = $p }
}
Show-Table ($tools | Select-Object Tool, Found, OnPATH, Version)
Save-Csv $tools '06_工具鏈.csv'

foreach ($t in $tools) {
    if ($t.Found -and -not $t.OnPATH) {
        Add-Finding '警告' 'PATH' ($t.Tool + ' 已安裝於 ' + $t.Path + ' 但不在 PATH 上。代表你只能在 IDE 內使用它，命令列、quarto render、排程工作、CI 都會找不到。')
        Add-Action '-FixPath'
    }
}
$pyTool = $tools | Where-Object { $_.Tool -eq 'python' } | Select-Object -First 1
if ($pyTool -and $pyTool.Path -like '*\WindowsApps\*') {
    Add-Finding '警告' 'Python' ('PATH 上的 python 指向 Microsoft Store 應用程式執行別名 (' + $pyTool.Path + ')，不是真正的直譯器。任何 python xxx.py 都可能被導去 Store 而失敗。請到「設定 > 應用程式 > 應用程式執行別名」關閉 python.exe / python3.exe，或讓真正的 Python 目錄排在 PATH 前面。')
    Add-Action '-FixPath'
}
$rsTool = $tools | Where-Object { $_.Tool -eq 'Rscript' } | Select-Object -First 1
$rtTool = $tools | Where-Object { $_.Tool -eq 'Rtools' } | Select-Object -First 1
# R 靠登錄機碼 HKLM\SOFTWARE\R-core\Rtools 找工具鏈，不是靠 PATH。
# 所以這裡以登錄機碼為準，檔案探測只當輔助。
$rtReg = @(Get-ItemProperty 'HKLM:\SOFTWARE\R-core\Rtools\*', 'HKCU:\SOFTWARE\R-core\Rtools\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.InstallPath -and (Test-Path -LiteralPath $_.InstallPath) })
if ($rtReg.Count -gt 0) {
    Write-Host ('Rtools（登錄機碼）：' + (($rtReg | ForEach-Object { $_.PSChildName + ' -> ' + $_.InstallPath }) -join '; '))
    Save-Csv ($rtReg | Select-Object PSChildName, InstallPath) '06_Rtools.csv'
}
if ($rsTool.Found -and $rtReg.Count -eq 0 -and -not $rtTool.Found) {
    Add-Finding '警告' 'R' '已安裝 R 但沒有 Rtools。任何需要編譯的套件（大量 GitHub 套件、部分 CRAN 套件的最新版）都會安裝失敗，也無法用 Rcpp 自行寫 C++ 加速。'
    Add-Action '-InstallRtools'
} elseif ($rtReg.Count -gt 0) {
    Add-Finding '資訊' 'R' ('Rtools 已註冊（' + (($rtReg | ForEach-Object { $_.PSChildName }) -join ', ') + '）。注意：Rtools 的版本號不必然等於 R 的次版本——R 4.6 使用的就是 Rtools45，CRAN 並沒有發行 rtools46。是否真的能編譯，請以 R CMD SHLIB 實測為準，不要靠版本號推論。')
}
if (-not ($tools | Where-Object { $_.Tool -eq 'duckdb' -and $_.Found })) {
    Add-Finding '資訊' '資料庫' '沒有 DuckDB CLI。以 32 GB 記憶體 / 單 SSD 的配置，DuckDB 是處理千萬列級資料最划算的引擎：可直接對 Parquet 下 SQL，不必先把整份資料讀進記憶體。'
    Add-Action '-InstallToolchain'
}

# ---------------------------------------------------------------- 7. R 堆疊差距
Section '7. R 套件堆疊差距分析'
$rscript = $rsTool.Path
if (-not $rscript) {
    Add-Finding '注意' 'R' '找不到 Rscript，略過 R 套件分析。'
} elseif ($SkipRPackages) {
    Write-Host '已略過 (-SkipRPackages / -Fast)'
} else {
    $rCode = @'
out <- Sys.getenv("DIAG_OUT")
cat("R.version.string:", R.version.string, "\n")
cat("R_HOME:", R.home(), "\n")
for (p in .libPaths()) cat("libPath:", p, " writable=", file.access(p, 2) == 0, "\n", sep = "")
cat("Ncpus option:", getOption("Ncpus"), "\n")
cat("repos:", paste(getOption("repos"), collapse = ","), "\n")
ip <- installed.packages()
inst <- rownames(ip)
cat("installed count:", length(inst), "\n")
write.csv(data.frame(Package = ip[, "Package"], Version = ip[, "Version"], LibPath = ip[, "LibPath"],
                     stringsAsFactors = FALSE), file.path(out, "07_R_installed.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")
groups <- list(
  "01_env"      = c("renv", "pak", "here", "conflicted", "sessioninfo"),
  "02_wrangle"  = c("tidyverse", "data.table", "dtplyr", "collapse", "janitor", "lubridate", "stringi"),
  "03_bigdata"  = c("arrow", "duckdb", "fst", "qs", "vroom"),
  "04_database" = c("DBI", "RSQLite", "odbc", "RPostgres", "RMariaDB", "dbplyr", "pool"),
  "05_timeser"  = c("xts", "zoo", "tsibble", "fable", "forecast", "TTR", "quantmod", "PerformanceAnalytics", "rugarch"),
  "06_model"    = c("tidymodels", "xgboost", "lightgbm", "ranger", "glmnet", "survival", "survminer", "grf", "depmixS4"),
  "07_explain"  = c("DALEX", "iml", "fastshap", "vip", "pdp"),
  "08_report"   = c("quarto", "rmarkdown", "knitr", "gt", "gtsummary", "flextable", "officer"),
  "09_viz"      = c("ggplot2", "plotly", "ggiraph", "patchwork", "scales", "ggrepel"),
  "10_perf"     = c("future", "furrr", "parallelly", "Rcpp", "RcppArmadillo", "bench", "profvis"),
  "11_shiny"    = c("shiny", "bslib", "shinyWidgets", "shinyjs", "DT", "reactable"),
  "12_pipeline" = c("targets", "testthat", "lintr", "styler", "logger")
)
rows <- do.call(rbind, lapply(names(groups), function(g) {
  pk <- groups[[g]]
  data.frame(Group = g, Total = length(pk), Have = sum(pk %in% inst),
             Missing = paste(setdiff(pk, inst), collapse = " "), stringsAsFactors = FALSE)
}))
write.csv(rows, file.path(out, "07_R_gap.csv"), row.names = FALSE, fileEncoding = "UTF-8")
for (i in seq_len(nrow(rows))) {
  cat(sprintf("%-12s %2d/%2d  missing: %s\n", rows$Group[i], rows$Have[i], rows$Total[i], rows$Missing[i]))
}
cat("TOTAL_MISSING:", sum(rows$Total) - sum(rows$Have), "\n")
'@
    $rFile = Join-Path $OutDir '_diag_r.R'
    Set-Content -Path $rFile -Value $rCode -Encoding ASCII
    $env:DIAG_OUT = $OutDir
    $rOut = Invoke-Native $rscript @($rFile)
    Save-Text $rOut '07_R_診斷.txt'
    Write-Host $rOut
    Remove-Item $rFile -Force -ErrorAction SilentlyContinue
    if ($rOut -match 'TOTAL_MISSING:\s*(\d+)') {
        $miss = [int]$Matches[1]
        if ($miss -gt 0) {
            Add-Finding '警告' 'R' ('R 分析堆疊缺少 ' + $miss + ' 個關鍵套件（分組明細見 07_R_gap.csv）。')
            Add-Action '-SetupR'
        }
    }
    if ($rOut -match 'writable=FALSE' -and $rOut -notmatch 'writable=TRUE') {
        Add-Finding '嚴重' 'R' 'R 沒有任何可寫入的套件庫，安裝套件必定失敗。'
    }
}

# ---------------------------------------------------------------- 8. Python 堆疊差距
Section '8. Python 堆疊差距分析'
if ($SkipPython) {
    Write-Host '已略過 (-SkipPython / -Fast)'
} else {
    $pyExe = $null
    $pyBase = @()
    $pl = Find-Exe 'py'
    if ($pl) { $pyExe = $pl; $pyBase = @('-3') }
    else {
        $pp = Get-Command python -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandType -eq 'Application' -and $_.Source -notlike '*\WindowsApps\*' } | Select-Object -First 1
        if ($pp) { $pyExe = $pp.Source }
    }
    if (-not $pyExe) {
        Add-Finding '注意' 'Python' '找不到可用的 Python 直譯器（Store 別名不算）。'
    } else {
        Save-Text (Invoke-Native $pyExe @('-0p')) '08_python_版本清單.txt'
        $pyVer = Invoke-Native $pyExe ($pyBase + @('-c', 'import sys;print(sys.version.split()[0])')) -StdoutOnly
        Write-Host ('預設 Python：' + $pyVer + '  (' + $pyExe + ')')
        $pipJson = Invoke-Native $pyExe ($pyBase + @('-m', 'pip', 'list', '--format=json')) -StdoutOnly
        $installed = @()
        try { $installed = ($pipJson | ConvertFrom-Json) | ForEach-Object { $_.name.ToLower() } } catch { }
        Write-Host ('pip 套件數：' + @($installed).Count)
        Save-Text $pipJson '08_pip_已安裝.json'

        $pyGroups = [ordered]@{
            '01_env'      = @('uv', 'pip', 'ruff', 'pytest')
            '02_wrangle'  = @('pandas', 'polars', 'numpy', 'pyarrow', 'duckdb')
            '03_database' = @('sqlalchemy', 'psycopg', 'pymysql', 'clickhouse-connect', 'pyodbc')
            '04_model'    = @('scikit-learn', 'xgboost', 'lightgbm', 'statsmodels', 'scipy')
            '05_explain'  = @('shap', 'lime')
            '06_survival' = @('lifelines', 'scikit-survival', 'econml', 'dowhy')
            '07_viz'      = @('matplotlib', 'plotly', 'seaborn', 'great-tables')
            '08_notebook' = @('jupyterlab', 'ipykernel', 'nbclient', 'papermill')
        }
        $pyRows = @()
        $pyMiss = 0
        foreach ($g in $pyGroups.Keys) {
            $pk = $pyGroups[$g]
            $have = @($pk | Where-Object { $installed -contains $_.ToLower() })
            $missing = @($pk | Where-Object { $installed -notcontains $_.ToLower() })
            $pyMiss += $missing.Count
            $pyRows += [pscustomobject]@{ Group = $g; Total = $pk.Count; Have = $have.Count; Missing = ($missing -join ' ') }
        }
        Show-Table $pyRows
        Save-Csv $pyRows '08_Python_堆疊差距.csv'
        if ($pyMiss -gt 0) {
            Add-Finding '警告' 'Python' ('Python 分析堆疊缺少 ' + $pyMiss + ' 個關鍵套件（見 08_Python_堆疊差距.csv）。')
            Add-Action '-SetupPython'
        }
        if ($pyVer -match '^3\.(1[4-9]|2\d)') {
            Add-Finding '注意' 'Python' ('目前預設 Python 為 ' + $pyVer + '。最新版常有部分科學計算套件尚未提供 Windows wheel，只能退回原始碼編譯（本機沒有 C++ 編譯器就會失敗）。建議「工作用」環境鎖在次新的穩定版（3.13 或 3.12），由 uv 管理，與系統 Python 並存。')
        }
        if (@($installed).Count -le 3) {
            Add-Finding '資訊' 'Python' '全域 Python 幾乎是空的——這其實是好事。請維持全域乾淨，所有專案套件都放在 uv / venv 專案環境裡，避免日後的依賴地獄。'
        }
    }
    $uvPath = Find-Exe 'uv' @("$env:USERPROFILE\.local\bin\uv.exe")
    if ($uvPath) {
        Save-Text (Invoke-Native $uvPath @('python', 'list')) '08_uv_可用版本.txt'
        Add-Finding '資訊' 'Python' ('已安裝 uv (' + $uvPath + ')。這是目前 Windows 上建立可重現 Python 環境最快的工具，建議一律用 uv 而非全域 pip install。')
    }
}

# ---------------------------------------------------------------- 9. ODBC
Section '9. ODBC 驅動'
$odbc = @()
try { $odbc = Get-OdbcDriver -ErrorAction Stop | Select-Object Name, Platform } catch { }
Save-Csv $odbc '09_ODBC驅動.csv'
$odbcNames = (($odbc | ForEach-Object { $_.Name }) -join ' | ')
Write-Host ('ODBC 驅動數：' + @($odbc).Count)
$wantOdbc = [ordered]@{
    'PostgreSQL'            = 'PostgreSQL'
    'MySQL/StarRocks/Doris' = 'MySQL'
    'ClickHouse'            = 'ClickHouse'
    'SQLite'                = 'SQLite'
}
$odbcMissing = @()
foreach ($k in $wantOdbc.Keys) { if ($odbcNames -notmatch $wantOdbc[$k]) { $odbcMissing += $k } }
if ($odbcMissing.Count -gt 0) {
    Add-Finding '資訊' '資料庫' ('未安裝以下 ODBC 驅動：' + ($odbcMissing -join ', ') + '。若要用 R 的 odbc/DBI 或 Python 的 pyodbc 直連倉庫（StarRocks / Doris 走 MySQL 協定），需要先裝對應驅動。')
    Add-Action '-InstallODBC'
}

# ---------------------------------------------------------------- 10. Git 設定
Section '10. Git 設定'
$gitExe = ($tools | Where-Object { $_.Tool -eq 'git' }).Path
if ($gitExe) {
    $gcfg = Invoke-Native $gitExe @('config', '--global', '--list')
    Save-Text $gcfg '10_git設定.txt'
    Write-Host $gcfg
    if ($gcfg -notmatch 'core\.longpaths=true') { Add-Finding '注意' 'Git' 'git 未設定 core.longpaths=true，長路徑的 checkout 會失敗。'; Add-Action '-ConfigureGit' }
    if ($gcfg -notmatch 'core\.autocrlf') { Add-Finding '注意' 'Git' 'git 未設定 core.autocrlf。Windows 與 Linux/容器混用時，CRLF 會造成整檔 diff 與腳本在 Linux 上執行異常。'; Add-Action '-ConfigureGit' }
    if ($gcfg -notmatch 'credential\.helper') { Add-Finding '資訊' 'Git' 'git 未設定 credential.helper（建議 manager）。'; Add-Action '-ConfigureGit' }
    if ($gcfg -match 'filter\.lfs') { Add-Finding '資訊' 'Git' '已啟用 Git LFS。放大型資料集（Parquet/CSV）時請務必走 LFS，或乾脆不進版控。' }
} else {
    Add-Finding '注意' 'Git' '找不到 git。'
}

# ---------------------------------------------------------------- 11. winget
if (-not $SkipWinget) {
    Section '11. winget 可升級'
    $wg = Find-Exe 'winget'
    if ($wg) {
        $up = Invoke-Native $wg @('upgrade', '--accept-source-agreements')
        Save-Text $up '11_winget_可升級.txt'
        Write-Host $up
        if ($up -match '(升級可用|upgrades available|可升级)') {
            Add-Finding '注意' '軟體' 'winget 回報有可升級軟體（見 11_winget_可升級.txt）。'
            Add-Action '-UpdateApps'
        }
    } else { Add-Finding '注意' '軟體' '找不到 winget。' }
}

# ---------------------------------------------------------------- 12. 啟動項目
Section '12. 啟動項目'
$startup = Get-CimInstance Win32_StartupCommand | Select-Object Name, Location, Command
Show-Table ($startup | Select-Object Name, Location)
Save-Csv $startup '12_啟動項目.csv'
if (@($startup).Count -gt 12) { Add-Finding '注意' '效能' ('啟動項目 ' + @($startup).Count + ' 筆，開機後會長時間搶 CPU 與磁碟。') }

# ---------------------------------------------------------------- 摘要
Section '摘要'
$order = @{ '嚴重' = 0; '警告' = 1; '注意' = 2; '資訊' = 3 }
$sorted = $script:Findings | Sort-Object { $order[$_.Level] }, Area
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('Windows 10 資料分析工作站診斷 v2   ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
[void]$sb.AppendLine('主機：' + $env:COMPUTERNAME + '   ' + $os.Caption + ' ' + $dispVer + ' (Build ' + $build + ')')
[void]$sb.AppendLine('CPU：' + $cpu.Name + '  ' + $cpu.NumberOfCores + 'C/' + $cpu.NumberOfLogicalProcessors + 'T    RAM：' + $ramGB + ' GB')
[void]$sb.AppendLine('管理員身分：' + $isAdmin)
[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- 發現 (' + @($sorted).Count + ') ---')
foreach ($f in $sorted) { [void]$sb.AppendLine('[' + $f.Level + '] ' + $f.Area + ' - ' + $f.Message) }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- 工具鏈 ---')
[void]$sb.AppendLine((($tools | Format-Table Tool, Found, OnPATH, Version -AutoSize | Out-String -Width 240).TrimEnd()))
[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- 產出檔案 ---')
foreach ($f in $script:Files) { [void]$sb.AppendLine('  ' + $f) }
$sumText = $sb.ToString()
Set-Content -Path (Join-Path $OutDir '00_摘要.txt') -Value $sumText -Encoding UTF8
Write-Host $sumText

$ab = New-Object System.Text.StringBuilder
[void]$ab.AppendLine('# 根據本次診斷，建議用 Setup_DataStack.ps1 執行的開關')
[void]$ab.AppendLine('# 第一次一律先加 -WhatIf 預演，確認沒問題再拿掉。')
[void]$ab.AppendLine('')
$adminSwitches = @('-EnableLongPaths', '-SetPageFile', '-AddDefenderExclusions')
if ($script:Actions.Count -eq 0) {
    [void]$ab.AppendLine('# 沒有偵測到需要處理的項目。')
} else {
    [void]$ab.AppendLine('# --- 一般使用者身分 ---')
    foreach ($a in $script:Actions) { if ($adminSwitches -notcontains $a) { [void]$ab.AppendLine('.\Setup_DataStack.ps1 ' + $a + ' -WhatIf') } }
    [void]$ab.AppendLine('')
    [void]$ab.AppendLine('# --- 需要系統管理員身分 ---')
    foreach ($a in $script:Actions) { if ($adminSwitches -contains $a) { [void]$ab.AppendLine('.\Setup_DataStack.ps1 ' + $a + ' -WhatIf') } }
}
Set-Content -Path (Join-Path $OutDir '99_建議指令.txt') -Value $ab.ToString() -Encoding UTF8
Write-Host ''
Write-Host ($ab.ToString()) -ForegroundColor Yellow
Write-Host ('完成。報告位置：' + $OutDir) -ForegroundColor Green
Write-Host '提醒：報告內含電腦名稱、使用者名稱、已安裝軟體與管控代理清單，分享前請自行檢視。' -ForegroundColor Yellow
