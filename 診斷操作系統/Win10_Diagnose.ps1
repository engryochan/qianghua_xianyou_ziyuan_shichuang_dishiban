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
# 启用 PowerShell 高级脚本参数绑定及所列功能。
[CmdletBinding()]
# 声明脚本或函数接受的参数及默认值。
param(
    # 声明参数 $OutDir的类型、默认值或校验规则。
    [string]$OutDir = (Join-Path $env:USERPROFILE ('Win10_Diag_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))),
    # 声明参数 $SkipRPackages的类型、默认值或校验规则。
    [switch]$SkipRPackages,
    # 声明参数 $SkipPython的类型、默认值或校验规则。
    [switch]$SkipPython,
    # 声明参数 $SkipWinget的类型、默认值或校验规则。
    [switch]$SkipWinget,
    # 声明参数 $SkipEventLog的类型、默认值或校验规则。
    [switch]$SkipEventLog
# 结束此处的代码块、参数列表或集合定义。
)

# 处理 Set-StrictMode 所指定的操作或当前表达式的后续部分。
Set-StrictMode -Off
# 设置本脚本遇到 PowerShell 错误时的处理方式。
$ErrorActionPreference = 'Continue'
# 开始受异常处理保护的操作。
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
# 创建指定目录、文件或配置项；将不需要的返回值丢弃。
$null = New-Item -ItemType Directory -Path $OutDir -Force
# 创建指定类型的对象，并保存到 $script:Findings。
$script:Findings = New-Object System.Collections.Generic.List[object]
# 创建指定类型的对象，并保存到 $script:Files。
$script:Files = New-Object System.Collections.Generic.List[string]

# ------------------------------------------------------------------ 工具函式
# 定义 Add-Finding，封装此函数内的操作。
function Add-Finding {
    # 声明脚本或函数接受的参数及默认值。
    param(
        # 声明参数 $Level的类型、默认值或校验规则。
        [ValidateSet('警告', '注意', '資訊')][string]$Level,
        # 声明参数 $Area的类型、默认值或校验规则。
        [string]$Area,
        # 声明参数 $Message的类型、默认值或校验规则。
        [string]$Message
    # 结束此处的代码块、参数列表或集合定义。
    )
    # 调用 $script:Findings.Add，使用本行列出的输入完成对应操作。
    $script:Findings.Add([pscustomobject]@{ Level = $Level; Area = $Area; Message = $Message })
# 结束此处的代码块、参数列表或集合定义。
}

# 定义 Section，封装此函数内的操作。
function Section {
    # 声明脚本或函数接受的参数及默认值。
    param([string]$Title)
    # 向终端显示提示或结果。
    Write-Host ''
    # 向终端显示提示或结果。
    Write-Host ('=== ' + $Title + ' ===') -ForegroundColor Cyan
# 结束此处的代码块、参数列表或集合定义。
}

# 定义 Save-Csv，封装此函数内的操作。
function Save-Csv {
    # 声明脚本或函数接受的参数及默认值。
    param($Data, [string]$Name)
    # 检查本行条件；满足时执行对应分支。
    if ($null -eq $Data -or @($Data).Count -eq 0) { return }
    # 组合父目录与子路径；将记录导出为 CSV 文件。
    @($Data) | Export-Csv -Path (Join-Path $OutDir $Name) -NoTypeInformation -Encoding UTF8
    # 调用 $script:Files.Add，使用本行列出的输入完成对应操作。
    $script:Files.Add($Name)
# 结束此处的代码块、参数列表或集合定义。
}

# 定义 Save-Text，封装此函数内的操作。
function Save-Text {
    # 声明脚本或函数接受的参数及默认值。
    param([string]$Text, [string]$Name)
    # 检查本行条件；满足时执行对应分支。
    if ([string]::IsNullOrEmpty($Text)) { return }
    # 组合父目录与子路径；将内容写入目标文件。
    Set-Content -Path (Join-Path $OutDir $Name) -Value $Text -Encoding UTF8
    # 调用 $script:Files.Add，使用本行列出的输入完成对应操作。
    $script:Files.Add($Name)
# 结束此处的代码块、参数列表或集合定义。
}

# 定义 Show-Table，封装此函数内的操作。
function Show-Table {
    # 声明脚本或函数接受的参数及默认值。
    param($Data)
    # 检查本行条件；满足时执行对应分支。
    if ($null -eq $Data -or @($Data).Count -eq 0) { Write-Host '  (無資料)'; return }
    # 把结果排版成表格；把结果转换为文本；向终端显示提示或结果。
    ($Data | Format-Table -AutoSize | Out-String -Width 220).TrimEnd() | Write-Host
# 结束此处的代码块、参数列表或集合定义。
}

# 定义 Test-Admin，封装此函数内的操作。
function Test-Admin {
    # 构造或计算 $id，保存本行指定的集合或索引结果。
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    # 返回本行结果并结束当前函数。
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# 结束此处的代码块、参数列表或集合定义。
}

# 定义 Get-RegValue，封装此函数内的操作。
function Get-RegValue {
    # 声明脚本或函数接受的参数及默认值。
    param([string]$Path, [string]$Name)
    # 开始受异常处理保护的操作。
    try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { return $null }
# 结束此处的代码块、参数列表或集合定义。
}

# 定义 Invoke-Native，封装此函数内的操作。
function Invoke-Native {
    # 声明脚本或函数接受的参数及默认值。
    param([string]$Exe, [string[]]$Arguments = @(), [switch]$StdoutOnly)
    # 开始受异常处理保护的操作。
    try {
        # 检查本行条件；满足时执行对应分支。
        if ($StdoutOnly) { $o = & $Exe @Arguments 2>$null } else { $o = & $Exe @Arguments 2>&1 }
        # 按条件筛选输入记录；逐项处理管道传入的记录，并保存到 $o。
        $o = $o | ForEach-Object { "$_" } | Where-Object { $_ -notmatch '^\s*[-\\|/]+\s*$' }
        # 返回本行结果并结束当前函数。
        return (($o) -join "`n").Trim()
    # 结束上一代码块并进入异常处理。
    } catch { return $null }
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

# 定义 Get-FirstLine，封装此函数内的操作。
function Get-FirstLine {
    # 声明脚本或函数接受的参数及默认值。
    param([string]$Text)
    # 检查本行条件；满足时执行对应分支。
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    # 返回本行结果并结束当前函数。
    return (($Text -split "`n") | Select-Object -First 1).Trim()
# 结束此处的代码块、参数列表或集合定义。
}

# 计算本行表达式并设置 $isAdmin，供后续步骤使用。
$isAdmin = Test-Admin
# 向终端显示提示或结果。
Write-Host ('輸出資料夾：' + $OutDir) -ForegroundColor Green
# 向终端显示提示或结果。
Write-Host ('系統管理員身分：' + $isAdmin)

# ------------------------------------------------------------------ 1. 系統
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '1. 系統與更新'
# 查询 Windows 管理接口中的设备或系统信息，并保存到 $os。
$os = Get-CimInstance Win32_OperatingSystem
# 查询 Windows 管理接口中的设备或系统信息，并保存到 $cs。
$cs = Get-CimInstance Win32_ComputerSystem
# 计算本行表达式并设置 $cvPath，供后续步骤使用。
$cvPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
# 计算本行表达式并设置 $dispVer，供后续步骤使用。
$dispVer = Get-RegValue $cvPath 'DisplayVersion'
# 检查本行条件；满足时执行对应分支。
if (-not $dispVer) { $dispVer = Get-RegValue $cvPath 'ReleaseId' }
# 计算本行表达式并设置 $build，供后续步骤使用。
$build = ('' + (Get-RegValue $cvPath 'CurrentBuild')) + '.' + (Get-RegValue $cvPath 'UBR')
# 生成当前时间或格式化时间戳，并保存到 $uptime。
$uptime = (Get-Date) - $os.LastBootUpTime
# 构造或计算 $ramGB，保存本行指定的集合或索引结果。
$ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
# 构造或计算 $sys，保存本行指定的集合或索引结果。
$sys = [pscustomobject]@{
    # 计算本行表达式并设置 ComputerName，供后续步骤使用。
    ComputerName = $env:COMPUTERNAME
    # 计算本行表达式并设置 OS，供后续步骤使用。
    OS           = $os.Caption
    # 计算本行表达式并设置 Version，供后续步骤使用。
    Version      = $dispVer
    # 计算本行表达式并设置 Build，供后续步骤使用。
    Build        = $build
    # 计算本行表达式并设置 Arch，供后续步骤使用。
    Arch         = $os.OSArchitecture
    # 计算本行表达式并设置 Language，供后续步骤使用。
    Language     = $os.MUILanguages -join ','
    # 计算本行表达式并设置 InstallDate，供后续步骤使用。
    InstallDate  = $os.InstallDate
    # 计算本行表达式并设置 LastBoot，供后续步骤使用。
    LastBoot     = $os.LastBootUpTime
    # 构造或计算 UptimeDays，保存本行指定的集合或索引结果。
    UptimeDays   = [math]::Round($uptime.TotalDays, 1)
    # 计算本行表达式并设置 RAM_GB，供后续步骤使用。
    RAM_GB       = $ramGB
    # 计算本行表达式并设置 PowerShell，供后续步骤使用。
    PowerShell   = $PSVersionTable.PSVersion.ToString()
    # 计算本行表达式并设置 IsAdmin，供后续步骤使用。
    IsAdmin      = $isAdmin
# 结束此处的代码块、参数列表或集合定义。
}
# 处理 Show-Table 所指定的操作或当前表达式的后续部分。
Show-Table $sys
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $sys '01_系統.csv'

# 检查本行条件；满足时执行对应分支。
if ($os.Caption -match 'Windows 10') {
    # 追加一项诊断发现。
    Add-Finding '警告' '系統' 'Windows 10 已於 2025-10-14 結束一般支援。若未加入延伸安全更新 (ESU) 或改用 Windows 11，將不再收到常規安全修補（請以 Microsoft 官方公告為準）。'
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if ($ramGB -lt 8) { Add-Finding '注意' '硬體' ('實體記憶體僅 ' + $ramGB + ' GB：處理大型資料集、GARCH/回測等運算時易記憶體不足。') }
# 检查本行条件；满足时执行对应分支。
elseif ($ramGB -lt 16) { Add-Finding '資訊' '硬體' ('實體記憶體 ' + $ramGB + ' GB：一般分析足夠；大型資料建議 16 GB 以上，或改用 arrow / duckdb 等外存方案。') }
# 检查本行条件；满足时执行对应分支。
if ($uptime.TotalDays -gt 14) { Add-Finding '注意' '系統' ('已連續開機 ' + [math]::Round($uptime.TotalDays, 1) + ' 天，建議重新開機以套用更新並釋放記憶體。') }

# 按指定属性排序输入记录，并保存到 $hot。
$hot = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending
# 选取记录中的指定字段或条目。
Save-Csv ($hot | Select-Object HotFixID, Description, InstalledOn, InstalledBy) '01_更新紀錄.csv'
# 选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $lastHot。
$lastHot = $hot | Where-Object { $_.InstalledOn } | Select-Object -First 1
# 检查本行条件；满足时执行对应分支。
if ($lastHot) {
    # 生成当前时间或格式化时间戳，并保存到 $hotAge。
    $hotAge = ((Get-Date) - $lastHot.InstalledOn).Days
    # 向终端显示提示或结果。
    Write-Host ('最近一次已安裝更新：' + $lastHot.HotFixID + '（' + $lastHot.InstalledOn.ToString('yyyy-MM-dd') + '，距今 ' + $hotAge + ' 天）')
    # 检查本行条件；满足时执行对应分支。
    if ($hotAge -gt 60) { Add-Finding '警告' '更新' ('最近一次已安裝更新距今 ' + $hotAge + ' 天，請檢查 Windows Update 是否被停用或卡住。') }
# 结束上一代码块并进入另一条件分支。
} else {
    # 追加一项诊断发现。
    Add-Finding '注意' '更新' '讀不到更新安裝日期，請手動開啟 設定 > 更新與安全性 > Windows Update 確認。'
# 结束此处的代码块、参数列表或集合定义。
}

# 构造或计算 $pending，保存本行指定的集合或索引结果。
$pending = @()
# 检查本行条件；满足时执行对应分支。
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pending += 'CBS' }
# 检查本行条件；满足时执行对应分支。
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pending += 'WindowsUpdate' }
# 检查本行条件；满足时执行对应分支。
if (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'PendingFileRenameOperations') { $pending += 'PendingFileRename' }
# 检查本行条件；满足时执行对应分支。
if ($pending.Count -gt 0) { Add-Finding '注意' '系統' ('有待完成的重新開機動作：' + ($pending -join ', ')) }

# ------------------------------------------------------------------ 2. 硬體
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '2. 硬體與磁碟'
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目，并保存到 $cpu。
$cpu = Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目，并保存到 $gpu。
$gpu = Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DriverDate
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目，并保存到 $bios。
$bios = Get-CimInstance Win32_BIOS | Select-Object Manufacturer, SMBIOSBIOSVersion, ReleaseDate
# 计算本行表达式并设置 $pd，供后续步骤使用。
$pd = $null
# 开始受异常处理保护的操作。
try {
    # 选取记录中的指定字段或条目，并保存到 $pd。
    $pd = Get-PhysicalDisk -ErrorAction Stop | Select-Object FriendlyName, MediaType, BusType, HealthStatus, OperationalStatus, @{ n = 'Size_GB'; e = { [math]::Round($_.Size / 1GB) } }
# 结束上一代码块并进入异常处理。
} catch { }
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目，并保存到 $vol。
$vol = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object DeviceID, VolumeName, FileSystem,
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ n = 'Size_GB'; e = { [math]::Round($_.Size / 1GB, 1) } },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ n = 'Free_GB'; e = { [math]::Round($_.FreeSpace / 1GB, 1) } },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ n = 'Free_Pct'; e = { if ($_.Size) { [math]::Round(100 * $_.FreeSpace / $_.Size, 1) } } }
# 向终端显示提示或结果。
Write-Host 'CPU'; Show-Table $cpu
# 向终端显示提示或结果。
Write-Host 'GPU'; Show-Table $gpu
# 向终端显示提示或结果。
Write-Host '磁碟'; Show-Table $pd
# 向终端显示提示或结果。
Write-Host '磁碟區'; Show-Table $vol
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $cpu '02_CPU.csv'
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $gpu '02_GPU.csv'
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $bios '02_BIOS.csv'
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $pd '02_實體磁碟.csv'
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $vol '02_磁碟區.csv'

# 按本行的迭代范围或条件重复执行循环体。
foreach ($v in $vol) {
    # 检查本行条件；满足时执行对应分支。
    if ($v.Free_Pct -ne $null -and $v.Free_Pct -lt 15) {
        # 追加一项诊断发现。
        Add-Finding '警告' '磁碟' ($v.DeviceID + ' 剩餘空間僅 ' + $v.Free_Pct + '% (' + $v.Free_GB + ' GB)：R/Python 套件庫、暫存檔與 Windows 更新都可能因此失敗。')
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 按本行的迭代范围或条件重复执行循环体。
foreach ($d in @($pd)) {
    # 检查本行条件；满足时执行对应分支。
    if ($d.HealthStatus -and $d.HealthStatus -ne 'Healthy') { Add-Finding '警告' '磁碟' ($d.FriendlyName + ' 健康狀態為 ' + $d.HealthStatus + '，請立即備份並檢查。') }
    # 检查本行条件；满足时执行对应分支。
    if ($d.MediaType -eq 'HDD') { Add-Finding '資訊' '磁碟' ($d.FriendlyName + ' 為機械硬碟：R/Python 套件庫與暫存目錄建議放在 SSD。') }
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if (Test-Path 'C:\Windows.old') { Add-Finding '資訊' '磁碟' '存在 C:\Windows.old（舊版 Windows 備份），可用「磁碟清理」釋放空間。' }

# ------------------------------------------------------------------ 3. 已安裝軟體
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '3. 已安裝軟體（傳統桌面程式）'
# 构造或计算 $unPaths，保存本行指定的集合或索引结果。
$unPaths = @(
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
# 结束此处的代码块、参数列表或集合定义。
)
# 读取注册表或对象的属性，并保存到 $programs。
$programs = Get-ItemProperty -Path $unPaths -ErrorAction SilentlyContinue |
    # 按条件筛选输入记录。
    Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
    # 选取记录中的指定字段或条目。
    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation,
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ n = 'Scope'; e = { if ($_.PSPath -like '*HKEY_CURRENT_USER*') { 'User' } else { 'Machine' } } } |
    # 按指定属性排序输入记录。
    Sort-Object DisplayName
# 向终端显示提示或结果。
Write-Host ('共 ' + @($programs).Count + ' 筆，完整清單見 03_已安裝軟體.csv')
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $programs '03_已安裝軟體.csv'

# 构造或计算 $daPatterns，保存本行指定的集合或索引结果。
$daPatterns = [ordered]@{
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'R'          = '^R for Windows|^R \d+\.\d+'
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'Rtools'     = '^Rtools'
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'RStudio'    = 'RStudio'
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'Positron'   = 'Positron'
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'Python'     = '^Python \d'
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'Conda'      = 'Anaconda|Miniconda|Miniforge|Mambaforge'
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'Git'        = '^Git( |$)|Git version'
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'Quarto'     = 'Quarto'
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'Pandoc'     = 'Pandoc'
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'VSCode'     = 'Visual Studio Code'
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'Java'       = 'Java|JDK|JRE|Temurin|OpenJDK'
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'NodeJS'     = 'Node\.js'
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'Julia'      = 'Julia'
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'Database'   = 'PostgreSQL|MySQL|MariaDB|SQLite|DBeaver|DuckDB|SQL Server'
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'BI_Stats'   = 'Power BI|Tableau|MATLAB|Stata|SPSS|JASP|jamovi'
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'Docker_WSL' = 'Docker|Windows Subsystem for Linux'
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'Office_WPS' = 'Microsoft 365|Microsoft Office|WPS|金山'
# 结束此处的代码块、参数列表或集合定义。
}
# 构造或计算 $daRows，保存本行指定的集合或索引结果。
$daRows = @()
# 构造或计算 $daMissing，保存本行指定的集合或索引结果。
$daMissing = @()
# 按本行的迭代范围或条件重复执行循环体。
foreach ($k in $daPatterns.Keys) {
    # 按条件筛选输入记录，并保存到 $hits。
    $hits = @($programs | Where-Object { $_.DisplayName -match $daPatterns[$k] })
    # 检查本行条件；满足时执行对应分支。
    if ($hits.Count -eq 0) { $daMissing += $k }
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($h in $hits) {
        # 构造或计算 $daRows，保存本行指定的集合或索引结果。
        $daRows += [pscustomobject]@{ Category = $k; DisplayName = $h.DisplayName; Version = $h.DisplayVersion; Publisher = $h.Publisher; InstallLocation = $h.InstallLocation }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 处理 Show-Table 所指定的操作或当前表达式的后续部分。
Show-Table $daRows
# 向终端显示提示或结果。
Write-Host ('未在已安裝程式中偵測到：' + ($daMissing -join ', '))
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $daRows '03_資料分析相關軟體.csv'

# 按条件筛选输入记录，并保存到 $hasR。
$hasR = @($daRows | Where-Object { $_.Category -eq 'R' }).Count -gt 0
# 按条件筛选输入记录，并保存到 $hasRtools。
$hasRtools = @($daRows | Where-Object { $_.Category -eq 'Rtools' }).Count -gt 0
# 检查本行条件；满足时执行对应分支。
if (-not $hasRtools) { $hasRtools = @(Get-ChildItem 'C:\' -Directory -Filter 'rtools*' -ErrorAction SilentlyContinue).Count -gt 0 }
# 检查本行条件；满足时执行对应分支。
if ($hasR -and -not $hasRtools) { Add-Finding '注意' 'R' '偵測到 R 但沒有 Rtools：需從原始碼編譯的套件（含許多 GitHub 套件）會安裝失敗。' }

# ------------------------------------------------------------------ 4. Store / UWP 應用
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '4. Microsoft Store / UWP 應用（目前使用者）'
# 选取记录中的指定字段或条目，并保存到 $appx。
$appx = Get-AppxPackage -ErrorAction SilentlyContinue | Select-Object Name, Version, Publisher, Architecture, InstallLocation
# 向终端显示提示或结果。
Write-Host ('共 ' + @($appx).Count + ' 個，完整清單見 04_Store應用.csv')
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $appx '04_Store應用.csv'
# 检查本行条件；满足时执行对应分支。
if (@($appx | Where-Object { $_.Name -like '*549981C3F5F10*' }).Count -gt 0) {
    # 追加一项诊断发现。
    Add-Finding '資訊' '應用' '仍安裝 Cortana 套件 (Microsoft.549981C3F5F10)：Cortana 獨立應用已退役，可視需要移除。'
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if (@($appx | Where-Object { $_.Name -like '*Copilot*' }).Count -gt 0) {
    # 追加一项诊断发现。
    Add-Finding '資訊' '應用' '偵測到 Copilot 相關套件。'
# 结束此处的代码块、参数列表或集合定义。
}

# ------------------------------------------------------------------ 5. winget
# 调用 WinGet 执行本行指定的软件管理操作。
Section '5. winget（套件管理員）'
# 查找当前环境可用的命令及其位置；选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $wg。
$wg = Get-Command winget -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
# 检查本行条件；满足时执行对应分支。
if ($SkipWinget) {
    # 向终端显示提示或结果；调用 WinGet 执行本行指定的软件管理操作。
    Write-Host '已略過 (-SkipWinget)'
# 结束上一代码块并进入另一条件分支。
} elseif ($wg) {
    # 构造或计算 $wgVer，保存本行指定的集合或索引结果。
    $wgVer = Invoke-Native $wg.Source @('--version')
    # 向终端显示提示或结果；调用 WinGet 执行本行指定的软件管理操作。
    Write-Host ('winget 版本：' + $wgVer)
    # 调用 WinGet 执行本行指定的软件管理操作。
    Save-Text (Invoke-Native $wg.Source @('list', '--accept-source-agreements')) '05_winget_已安裝.txt'
    # 构造或计算 $up，保存本行指定的集合或索引结果。
    $up = Invoke-Native $wg.Source @('upgrade', '--accept-source-agreements')
    # 调用 WinGet 执行本行指定的软件管理操作。
    Save-Text $up '05_winget_可升級.txt'
    # 调用 WinGet 执行本行指定的软件管理操作；追加一项诊断发现。
    Add-Finding '資訊' '軟體' '請查看 05_winget_可升級.txt，了解可由 winget 升級的軟體。'
# 结束上一代码块并进入另一条件分支。
} else {
    # 调用 WinGet 执行本行指定的软件管理操作；追加一项诊断发现。
    Add-Finding '資訊' '軟體' '找不到 winget。可能需要到 Microsoft Store 安裝或更新「應用安裝程式 (App Installer)」。'
    # 向终端显示提示或结果；调用 WinGet 执行本行指定的软件管理操作。
    Write-Host '找不到 winget'
# 结束此处的代码块、参数列表或集合定义。
}

# ------------------------------------------------------------------ 6. 資料分析工具鏈
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '6. 資料分析工具鏈'
# 构造或计算 $probeDefs，保存本行指定的集合或索引结果。
$probeDefs = @(
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ Name = 'Rscript'; Exe = 'Rscript'; Args = @('--version'); Fb = @("$env:ProgramFiles\R\R-*\bin\x64\Rscript.exe", "$env:ProgramFiles\R\R-*\bin\Rscript.exe", "$env:LOCALAPPDATA\Programs\R\R-*\bin\x64\Rscript.exe") },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ Name = 'git'; Exe = 'git'; Args = @('--version'); Fb = @("$env:ProgramFiles\Git\cmd\git.exe") },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ Name = 'python'; Exe = 'python'; Args = @('--version'); Fb = @() },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ Name = 'py (launcher)'; Exe = 'py'; Args = @('--version'); Fb = @() },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ Name = 'conda'; Exe = 'conda'; Args = @('--version'); Fb = @("$env:USERPROFILE\miniconda3\Scripts\conda.exe", "$env:USERPROFILE\anaconda3\Scripts\conda.exe", "$env:ProgramData\miniconda3\Scripts\conda.exe", "$env:ProgramData\anaconda3\Scripts\conda.exe") },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ Name = 'quarto'; Exe = 'quarto'; Args = @('--version'); Fb = @("$env:LOCALAPPDATA\Programs\Quarto\bin\quarto.cmd", "$env:ProgramFiles\Quarto\bin\quarto.cmd") },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ Name = 'pandoc'; Exe = 'pandoc'; Args = @('--version'); Fb = @("$env:LOCALAPPDATA\Pandoc\pandoc.exe", "$env:ProgramFiles\Pandoc\pandoc.exe") },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ Name = 'java'; Exe = 'java'; Args = @('-version'); Fb = @() },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ Name = 'node'; Exe = 'node'; Args = @('--version'); Fb = @() },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ Name = 'julia'; Exe = 'julia'; Args = @('--version'); Fb = @() },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ Name = 'code (VS Code)'; Exe = 'code'; Args = @('--version'); Fb = @() },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ Name = 'duckdb'; Exe = 'duckdb'; Args = @('--version'); Fb = @() },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ Name = 'psql'; Exe = 'psql'; Args = @('--version'); Fb = @() },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ Name = 'docker'; Exe = 'docker'; Args = @('--version'); Fb = @() }
# 结束此处的代码块、参数列表或集合定义。
)
# 构造或计算 $toolRows，保存本行指定的集合或索引结果。
$toolRows = @()
# 按本行的迭代范围或条件重复执行循环体。
foreach ($d in $probeDefs) {
    # 计算本行表达式并设置 $p，供后续步骤使用。
    $p = Find-Exe $d.Exe $d.Fb
    # 计算本行表达式并设置 $ver，供后续步骤使用。
    $ver = ''
    # 检查本行条件；满足时执行对应分支。
    if ($p) { $ver = Get-FirstLine (Invoke-Native $p $d.Args) }
    # 构造或计算 $toolRows，保存本行指定的集合或索引结果。
    $toolRows += [pscustomobject]@{ Tool = $d.Name; Found = [bool]$p; Path = $p; Version = $ver }
# 结束此处的代码块、参数列表或集合定义。
}
# 处理 Show-Table 所指定的操作或当前表达式的后续部分。
Show-Table $toolRows
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $toolRows '06_工具鏈.csv'

# 按本行的迭代范围或条件重复执行循环体。
foreach ($t in $toolRows) {
    # 检查本行条件；满足时执行对应分支。
    if ($t.Path -and $t.Path -match '[^\x00-\x7F]') {
        # 追加一项诊断发现。
        Add-Finding '注意' '路徑' ($t.Tool + ' 的安裝路徑含非 ASCII 字元：' + $t.Path + '。部分工具（R 套件編譯、Quarto、Python 舊套件）遇到中文路徑可能出錯。')
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 检查本行条件；满足时执行对应分支。
    if ($t.Tool -eq 'python' -and $t.Version -match 'Microsoft Store') {
        # 追加一项诊断发现。
        Add-Finding '注意' 'Python' 'python 指令只是 Microsoft Store 的應用程式執行別名（並未真正安裝 Python）。請安裝 Python，或到 設定 > 應用 > 應用執行別名 關閉。'
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if ($env:USERPROFILE -match '[^\x00-\x7F]') {
    # 追加一项诊断发现。
    Add-Finding '注意' '路徑' ('使用者資料夾路徑含非 ASCII 字元：' + $env:USERPROFILE + '。R 的個人套件庫預設在此路徑之下，建議把 R_LIBS_USER 指到純 ASCII 路徑。')
# 结束此处的代码块、参数列表或集合定义。
}

# ---- Python
# 检查本行条件；满足时执行对应分支。
if ($SkipPython) {
    # 向终端显示提示或结果。
    Write-Host 'Python 明細已略過 (-SkipPython)'
# 结束上一代码块并进入另一条件分支。
} else {
    # 计算本行表达式并设置 $pyExe，供后续步骤使用。
    $pyExe = $null
    # 构造或计算 $pyBase，保存本行指定的集合或索引结果。
    $pyBase = @()
    # 计算本行表达式并设置 $pyLauncher，供后续步骤使用。
    $pyLauncher = Find-Exe 'py'
    # 检查本行条件；满足时执行对应分支。
    if ($pyLauncher) {
        # 计算本行表达式并设置 $pyExe，供后续步骤使用。
        $pyExe = $pyLauncher
        # 构造或计算 $pyBase，保存本行指定的集合或索引结果。
        $pyBase = @('-3')
        # 处理 Save-Text 所指定的操作或当前表达式的后续部分。
        Save-Text (Invoke-Native $pyLauncher @('-0p')) '06_python_已安裝版本.txt'
    # 结束上一代码块并进入另一条件分支。
    } else {
        # 查找当前环境可用的命令及其位置；选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $pp。
        $pp = Get-Command python -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' -and $_.Source -notlike '*\WindowsApps\*' } | Select-Object -First 1
        # 检查本行条件；满足时执行对应分支。
        if ($pp) { $pyExe = $pp.Source }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 检查本行条件；满足时执行对应分支。
    if ($pyExe) {
        # 向终端显示提示或结果。
        Write-Host ('Python 直譯器：' + $pyExe + ' ' + ($pyBase -join ' '))
        # 向终端显示提示或结果；准备或执行 Python 套件管理操作。
        Write-Host ('pip：' + (Get-FirstLine (Invoke-Native $pyExe ($pyBase + @('-m', 'pip', '--version')))))
        # 准备或执行 Python 套件管理操作，并保存到 $pipJson。
        $pipJson = Invoke-Native $pyExe ($pyBase + @('-m', 'pip', 'list', '--format=json')) -StdoutOnly
        # 开始受异常处理保护的操作。
        try {
            # 把 JSON 文本解析为对象；准备或执行 Python 套件管理操作，并保存到 $pk。
            $pk = $pipJson | ConvertFrom-Json
            # 选取记录中的指定字段或条目；准备或执行 Python 套件管理操作。
            Save-Csv ($pk | Select-Object name, version) '06_pip_已安裝.csv'
            # 向终端显示提示或结果；准备或执行 Python 套件管理操作。
            Write-Host ('pip 已安裝套件數：' + @($pk).Count)
        # 结束上一代码块并进入异常处理。
        } catch { }
        # 向终端显示提示或结果；准备或执行 Python 套件管理操作。
        Write-Host '檢查 pip 過期套件（需聯網，可能較慢）...'
        # 准备或执行 Python 套件管理操作，并保存到 $outJson。
        $outJson = Invoke-Native $pyExe ($pyBase + @('-m', 'pip', 'list', '--outdated', '--format=json')) -StdoutOnly
        # 开始受异常处理保护的操作。
        try {
            # 把 JSON 文本解析为对象，并保存到 $od。
            $od = $outJson | ConvertFrom-Json
            # 检查本行条件；满足时执行对应分支。
            if (@($od).Count -gt 0) {
                # 选取记录中的指定字段或条目；准备或执行 Python 套件管理操作。
                Save-Csv ($od | Select-Object name, version, latest_version, latest_filetype) '06_pip_可升級.csv'
                # 准备或执行 Python 套件管理操作；追加一项诊断发现。
                Add-Finding '注意' 'Python' ('有 ' + @($od).Count + ' 個 pip 套件可升級（見 06_pip_可升級.csv）。')
            # 结束上一代码块并进入另一条件分支。
            } else { Write-Host 'pip：沒有過期套件' }
        # 结束上一代码块并进入异常处理。
        } catch { }
        # 准备或执行 Python 套件管理操作，并保存到 $chk。
        $chk = Invoke-Native $pyExe ($pyBase + @('-m', 'pip', 'check'))
        # 准备或执行 Python 套件管理操作。
        Save-Text $chk '06_pip_check.txt'
        # 检查本行条件；满足时执行对应分支。
        if ($chk -and $chk -notmatch 'No broken requirements') { Add-Finding '警告' 'Python' 'pip check 回報依賴衝突，見 06_pip_check.txt。建議改用虛擬環境 (venv/conda) 隔離專案。' }
    # 结束上一代码块并进入另一条件分支。
    } else {
        # 追加一项诊断发现。
        Add-Finding '資訊' 'Python' '未偵測到可用的 Python 直譯器。'
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $condaExe。
    $condaExe = ($toolRows | Where-Object { $_.Tool -eq 'conda' } | Select-Object -First 1).Path
    # 检查本行条件；满足时执行对应分支。
    if ($condaExe) { Save-Text (Invoke-Native $condaExe @('env', 'list')) '06_conda_環境.txt' }
# 结束此处的代码块、参数列表或集合定义。
}

# ---- R
# 选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $rscript。
$rscript = ($toolRows | Where-Object { $_.Tool -eq 'Rscript' } | Select-Object -First 1).Path
# 检查本行条件；满足时执行对应分支。
if ($SkipRPackages) {
    # 向终端显示提示或结果。
    Write-Host 'R 套件明細已略過 (-SkipRPackages)'
# 结束上一代码块并进入另一条件分支。
} elseif ($rscript) {
    # 向终端显示提示或结果。
    Write-Host ('Rscript：' + $rscript)
    # 向终端显示提示或结果。
    Write-Host '收集 R 環境與套件資訊（含過期比對，需聯網，可能較慢）...'
    # 原文块第 1 行：计算本行表达式并设置 $rCode，供后续步骤使用。
    # 原文块第 2 行：调用 options，使用本行列出的输入完成对应操作。
    # 原文块第 3 行：读取 R 进程的环境变量，并保存到 out。
    # 原文块第 4 行：输出本行的状态信息或计算结果。
    # 原文块第 5 行：输出本行的状态信息或计算结果。
    # 原文块第 6 行：输出本行的状态信息或计算结果。
    # 原文块第 7 行：输出本行的状态信息或计算结果。
    # 原文块第 8 行：按本行的迭代范围或条件重复执行循环体。
    # 原文块第 9 行：输出本行的状态信息或计算结果。
    # 原文块第 10 行：计算本行表达式并设置 li，供后续步骤使用。
    # 原文块第 11 行：输出本行的状态信息或计算结果。
    # 原文块第 12 行：输出本行的状态信息或计算结果。
    # 原文块第 13 行：计算本行表达式并设置 es，供后续步骤使用。
    # 原文块第 14 行：输出本行的状态信息或计算结果。
    # 原文块第 15 行：输出本行的状态信息或计算结果。
    # 原文块第 16 行：输出本行的状态信息或计算结果。
    # 原文块第 17 行：计算本行表达式并设置 repos，供后续步骤使用。
    # 原文块第 18 行：输出本行的状态信息或计算结果。
    # 原文块第 19 行：读取 R 套件安装清单，并保存到 ip。
    # 原文块第 20 行：构造或计算 df，保存本行指定的集合或索引结果。
    # 原文块第 21 行：构造或计算 Priority，保存本行指定的集合或索引结果。
    # 原文块第 22 行：将表格写入 CSV 文件。
    # 原文块第 23 行：输出本行的状态信息或计算结果。
    # 原文块第 24 行：构造或计算 key，保存本行指定的集合或索引结果。
    # 原文块第 25 行：提供当前表达式所需的文本、字段名称或列表元素。
    # 原文块第 26 行：提供当前表达式所需的文本、字段名称或列表元素。
    # 原文块第 27 行：提供当前表达式所需的文本、字段名称或列表元素。
    # 原文块第 28 行：构造或计算 shiny_pkgs，保存本行指定的集合或索引结果。
    # 原文块第 29 行：提供当前表达式所需的文本、字段名称或列表元素。
    # 原文块第 30 行：提供当前表达式所需的文本、字段名称或列表元素。
    # 原文块第 31 行：提供当前表达式所需的文本、字段名称或列表元素。
    # 原文块第 32 行：输出本行的状态信息或计算结果。
    # 原文块第 33 行：输出本行的状态信息或计算结果。
    # 原文块第 34 行：输出本行的状态信息或计算结果。
    # 原文块第 35 行：输出本行的状态信息或计算结果。
    # 原文块第 36 行：检查本行条件；满足时执行对应分支。
    # 原文块第 37 行：计算本行表达式并设置 old，供后续步骤使用。
    # 原文块第 38 行：计算本行表达式并设置 error，供后续步骤使用。
    # 原文块第 39 行：检查本行条件；满足时执行对应分支。
    # 原文块第 40 行：将表格写入 CSV 文件。
    # 原文块第 41 行：输出本行的状态信息或计算结果。
    # 原文块第 42 行：结束上一代码块并进入另一条件分支。
    # 原文块第 43 行：输出本行的状态信息或计算结果。
    # 原文块第 44 行：结束此处的代码块、参数列表或集合定义。
    # 原文块第 45 行：提供当前表达式所需的文本、字段名称或列表元素。
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
    # 组合父目录与子路径，并保存到 $rFile。
    $rFile = Join-Path $OutDir '_diag.R'
    # 将内容写入目标文件。
    Set-Content -Path $rFile -Value $rCode -Encoding ASCII
    # 计算本行表达式并设置 $env:DIAG_OUT，供后续步骤使用。
    $env:DIAG_OUT = $OutDir
    # 构造或计算 $rOut，保存本行指定的集合或索引结果。
    $rOut = Invoke-Native $rscript @($rFile)
    # 处理 Save-Text 所指定的操作或当前表达式的后续部分。
    Save-Text $rOut '06_R_診斷.txt'
    # 选取记录中的指定字段或条目；逐项处理管道传入的记录；向终端显示提示或结果。
    $rOut -split "`n" | Select-Object -First 40 | ForEach-Object { Write-Host ('  ' + $_) }
    # 移动或替换指定文件；删除指定路径下的项目。
    Remove-Item $rFile -Force -ErrorAction SilentlyContinue

    # 检查本行条件；满足时执行对应分支。
    if ($rOut -match 'outdated package count:\s*(\d+)') {
        # 构造或计算 $n，保存本行指定的集合或索引结果。
        $n = [int]$Matches[1]
        # 检查本行条件；满足时执行对应分支。
        if ($n -gt 0) { Add-Finding '注意' 'R' ('有 ' + $n + ' 個 R 套件可升級或需重建（見 06_R_outdated.csv）。') }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 检查本行条件；满足时执行对应分支。
    if ($rOut -match 'writable=' -and $rOut -notmatch 'writable=TRUE') { Add-Finding '警告' 'R' 'R 的套件庫路徑皆不可寫入：安裝或更新套件將失敗，請建立個人套件庫 (R_LIBS_USER) 並確認權限。' }
    # 检查本行条件；满足时执行对应分支。
    if ($rOut -match 'BLAS:.*Rblas\.dll') { Add-Finding '資訊' 'R' 'R 使用內建參考 BLAS (Rblas.dll)。大型矩陣運算若要提速，可研究改用 OpenBLAS（屬進階自訂，需自行評估相容性）。' }
    # 检查本行条件；满足时执行对应分支。
    if ($rOut -match 'key packages missing:.*renv') { Add-Finding '資訊' 'R' '未安裝 renv：多專案並行或需要可重現分析時，建議每個專案用 renv 鎖定套件版本。' }
# 结束上一代码块并进入另一条件分支。
} else {
    # 向终端显示提示或结果。
    Write-Host '未找到 Rscript，略過 R 明細。'
# 结束此处的代码块、参数列表或集合定义。
}

# ------------------------------------------------------------------ 7. 啟動項目、排程、服務
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '7. 啟動項目 / 排程工作 / 服務'
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目，并保存到 $startup。
$startup = Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User
# 处理 Show-Table 所指定的操作或当前表达式的后续部分。
Show-Table $startup
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $startup '07_啟動項目.csv'
# 检查本行条件；满足时执行对应分支。
if (@($startup).Count -gt 15) { Add-Finding '注意' '效能' ('啟動項目共 ' + @($startup).Count + ' 筆，過多會拖慢開機；請在 工作管理員 > 啟動 檢視並停用不需要者。') }

# 计算本行表达式并设置 $tasks，供后续步骤使用。
$tasks = $null
# 开始受异常处理保护的操作。
try {
    # 按条件筛选输入记录，并保存到 $tasks。
    $tasks = Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and $_.State -ne 'Disabled' } |
        # 选取记录中的指定字段或条目；逐项处理管道传入的记录。
        Select-Object TaskName, TaskPath, State, @{ n = 'Actions'; e = { ($_.Actions | ForEach-Object { ('' + $_.Execute + ' ' + $_.Arguments).Trim() }) -join ' ; ' } }
# 结束上一代码块并进入异常处理。
} catch { }
# 向终端显示提示或结果。
Write-Host '非 Microsoft 且已啟用的排程工作'
# 处理 Show-Table 所指定的操作或当前表达式的后续部分。
Show-Table $tasks
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $tasks '07_非Microsoft排程工作.csv'

# 查询 Windows 管理接口中的设备或系统信息；按条件筛选输入记录，并保存到 $svc。
$svc = Get-CimInstance Win32_Service | Where-Object { $_.StartMode -eq 'Auto' } |
    # 选取记录中的指定字段或条目；按指定属性排序输入记录。
    Select-Object Name, DisplayName, State, StartMode, DelayedAutoStart, PathName | Sort-Object State, Name
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $svc '07_自動啟動服務.csv'
# 向终端显示提示或结果。
Write-Host ('自動啟動服務共 ' + @($svc).Count + ' 個（明細見 07_自動啟動服務.csv）')

# ------------------------------------------------------------------ 8. 安全
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '8. 安全性'
# 开始受异常处理保护的操作。
try {
    # 计算本行表达式并设置 $mp，供后续步骤使用。
    $mp = Get-MpComputerStatus -ErrorAction Stop
    # 选取记录中的指定字段或条目，并保存到 $mpRow。
    $mpRow = $mp | Select-Object AMServiceEnabled, AntivirusEnabled, RealTimeProtectionEnabled, AntivirusSignatureLastUpdated, AntivirusSignatureVersion, QuickScanEndTime, FullScanEndTime
    # 处理 Show-Table 所指定的操作或当前表达式的后续部分。
    Show-Table $mpRow
    # 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
    Save-Csv $mpRow '08_Defender.csv'
    # 检查本行条件；满足时执行对应分支。
    if (-not $mp.RealTimeProtectionEnabled) { Add-Finding '警告' '安全' 'Microsoft Defender 即時保護未啟用（若使用第三方防毒軟體可忽略）。' }
    # 检查本行条件；满足时执行对应分支。
    if ($mp.AntivirusSignatureLastUpdated) {
        # 生成当前时间或格式化时间戳，并保存到 $sigAge。
        $sigAge = ((Get-Date) - $mp.AntivirusSignatureLastUpdated).Days
        # 检查本行条件；满足时执行对应分支。
        if ($sigAge -gt 3) { Add-Finding '警告' '安全' ('Defender 病毒定義已 ' + $sigAge + ' 天未更新。') }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束上一代码块并进入异常处理。
} catch { Write-Host 'Get-MpComputerStatus 不可用（可能由第三方防毒接管）' }
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目，并保存到 $av。
$av = Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntivirusProduct -ErrorAction SilentlyContinue | Select-Object displayName, productState
# 向终端显示提示或结果。
Write-Host '已註冊的防毒產品'; Show-Table $av
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $av '08_防毒產品.csv'
# 检查本行条件；满足时执行对应分支。
if (@($av).Count -eq 0) { Add-Finding '警告' '安全' '安全中心未註冊任何防毒產品。' }

# 读取网络相关配置；选取记录中的指定字段或条目，并保存到 $fw。
$fw = Get-NetFirewallProfile -ErrorAction SilentlyContinue | Select-Object Name, Enabled
# 向终端显示提示或结果。
Write-Host '防火牆'; Show-Table $fw
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $fw '08_防火牆.csv'
# 按本行的迭代范围或条件重复执行循环体。
foreach ($f in @($fw)) { if ($f.Enabled -eq $false -or "$($f.Enabled)" -eq 'False') { Add-Finding '警告' '安全' ('防火牆設定檔 ' + $f.Name + ' 已停用。') } }

# 检查本行条件；满足时执行对应分支。
if ((Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA') -eq 0) { Add-Finding '警告' '安全' 'UAC (EnableLUA) 已被關閉。' }
# 检查本行条件；满足时执行对应分支。
if ((Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections') -eq 0) { Add-Finding '注意' '安全' '遠端桌面 (RDP) 已啟用；若不需要請關閉，若需要請務必設定強密碼與網路層級驗證。' }

# 开始受异常处理保护的操作。
try {
    # 选取记录中的指定字段或条目，并保存到 $admins。
    $admins = Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | Select-Object Name, ObjectClass, PrincipalSource
    # 向终端显示提示或结果。
    Write-Host '本機系統管理員群組成員'; Show-Table $admins
    # 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
    Save-Csv $admins '08_本機管理員.csv'
# 结束上一代码块并进入异常处理。
} catch { }

# 读取脚本执行策略；选取记录中的指定字段或条目，并保存到 $ep。
$ep = Get-ExecutionPolicy -List | Select-Object Scope, ExecutionPolicy
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $ep '08_執行原則.csv'

# 检查本行条件；满足时执行对应分支。
if ($isAdmin) {
    # 开始受异常处理保护的操作。
    try {
        # 选取记录中的指定字段或条目，并保存到 $bl。
        $bl = Get-BitLockerVolume -ErrorAction Stop | Select-Object MountPoint, VolumeStatus, ProtectionStatus, EncryptionPercentage
        # 向终端显示提示或结果。
        Write-Host 'BitLocker'; Show-Table $bl
        # 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
        Save-Csv $bl '08_BitLocker.csv'
    # 结束上一代码块并进入异常处理。
    } catch { Write-Host 'BitLocker 資訊不可用（此版本或未啟用）' }
    # 开始受异常处理保护的操作。
    try { Write-Host ('Secure Boot：' + (Confirm-SecureBootUEFI)) } catch { Write-Host 'Secure Boot：不適用或為傳統 BIOS' }
    # 开始受异常处理保护的操作。
    try {
        # 选取记录中的指定字段或条目，并保存到 $tpm。
        $tpm = Get-Tpm | Select-Object TpmPresent, TpmReady, ManufacturerVersion
        # 处理 Show-Table 所指定的操作或当前表达式的后续部分。
        Show-Table $tpm
    # 结束上一代码块并进入异常处理。
    } catch { }
    # 开始受异常处理保护的操作。
    try {
        # 选取记录中的指定字段或条目，并保存到 $smb。
        $smb = Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol, EnableSMB2Protocol
        # 处理 Show-Table 所指定的操作或当前表达式的后续部分。
        Show-Table $smb
        # 检查本行条件；满足时执行对应分支。
        if ($smb.EnableSMB1Protocol) { Add-Finding '警告' '安全' 'SMB1 協定已啟用（老舊且有高風險漏洞），除非有老設備需求，建議停用。' }
    # 结束上一代码块并进入异常处理。
    } catch { }
# 结束上一代码块并进入另一条件分支。
} else {
    # 追加一项诊断发现。
    Add-Finding '資訊' '安全' '未以系統管理員身分執行：已略過 BitLocker / Secure Boot / TPM / SMB1 檢查。'
# 结束此处的代码块、参数列表或集合定义。
}

# ------------------------------------------------------------------ 9. 與資料分析有關的系統設定
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '9. 系統設定（編碼、長路徑、電源、記憶體、PATH、環境變數）'
# 计算本行表达式并设置 $acp，供后续步骤使用。
$acp = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' 'ACP'
# 计算本行表达式并设置 $oemcp，供后续步骤使用。
$oemcp = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' 'OEMCP'
# 计算本行表达式并设置 $culture，供后续步骤使用。
$culture = (Get-Culture).Name
# 计算本行表达式并设置 $sysLocale，供后续步骤使用。
$sysLocale = (Get-WinSystemLocale).Name
# 逐项处理管道传入的记录，并保存到 $langList。
$langList = (Get-WinUserLanguageList | ForEach-Object { $_.LanguageTag }) -join ', '
# 计算本行表达式并设置 $homeLoc，供后续步骤使用。
$homeLoc = ''
# 开始受异常处理保护的操作。
try { $homeLoc = (Get-WinHomeLocation).HomeLocation } catch { }
# 计算本行表达式并设置 $long，供后续步骤使用。
$long = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled'
# 调用 Windows 电源配置工具，并保存到 $power。
$power = Invoke-Native 'powercfg.exe' @('/getactivescheme')
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目，并保存到 $pf。
$pf = Get-CimInstance Win32_PageFileUsage | Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage
# 计算本行表达式并设置 $proxyOn，供后续步骤使用。
$proxyOn = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' 'ProxyEnable'
# 计算本行表达式并设置 $proxySrv，供后续步骤使用。
$proxySrv = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' 'ProxyServer'
# 构造或计算 $set，保存本行指定的集合或索引结果。
$set = [pscustomobject]@{
    # 计算本行表达式并设置 ACP_ANSI碼頁，供后续步骤使用。
    ACP_ANSI碼頁 = $acp; OEM碼頁 = $oemcp; Culture = $culture; SystemLocale = $sysLocale; 語言清單 = $langList; 地區 = $homeLoc
    # 计算本行表达式并设置 LongPathsEnabled，供后续步骤使用。
    LongPathsEnabled = $long; 電源計畫 = $power; 自動管理分頁檔 = $cs.AutomaticManagedPagefile; ProxyEnable = $proxyOn; ProxyServer = $proxySrv
# 结束此处的代码块、参数列表或集合定义。
}
# 把结果转换为文本；向终端显示提示或结果。
$set | Format-List | Out-String -Width 220 | Write-Host
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $set '09_設定.csv'
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $pf '09_分頁檔.csv'

# 检查本行条件；满足时执行对应分支。
if ($acp -and $acp -ne '65001') { Add-Finding '資訊' '編碼' ('系統 ANSI 碼頁為 ' + $acp + '（非 UTF-8）。讀寫非 UTF-8 的 CSV/文字檔時請明確指定編碼（R: fileEncoding / readr locale；Python: encoding=utf-8）。') }
# 检查本行条件；满足时执行对应分支。
if ($long -ne 1) { Add-Finding '注意' '設定' 'Windows 長路徑 (LongPathsEnabled) 未啟用：套件路徑過深時可能安裝失敗。' }
# 检查本行条件；满足时执行对应分支。
if ($power -match 'Power saver|節能|节能') { Add-Finding '注意' '效能' '目前電源計畫為省電模式，會降低運算效能。' }
# 检查本行条件；满足时执行对应分支。
if ($proxyOn -eq 1) { Add-Finding '資訊' '網路' ('系統啟用了 Proxy：' + $proxySrv + '。R/Python 下載失敗時請檢查 HTTP(S)_PROXY 設定。') }

# PATH 檢查
# 构造或计算 $pathRows，保存本行指定的集合或索引结果。
$pathRows = @()
# 按本行的迭代范围或条件重复执行循环体。
foreach ($scope in @('Machine', 'User')) {
    # 读取指定作用域的环境变量，并保存到 $raw。
    $raw = [Environment]::GetEnvironmentVariable('Path', $scope)
    # 检查本行条件；满足时执行对应分支。
    if ($raw) {
        # 按本行的迭代范围或条件重复执行循环体。
        foreach ($e in ($raw -split ';')) {
            # 检查本行条件；满足时执行对应分支。
            if ([string]::IsNullOrWhiteSpace($e)) { continue }
            # 构造或计算 $exp，保存本行指定的集合或索引结果。
            $exp = [Environment]::ExpandEnvironmentVariables($e.Trim())
            # 检查目标路径是否存在，并保存到 $pathRows。
            $pathRows += [pscustomobject]@{ Scope = $scope; Entry = $e.Trim(); Expanded = $exp; Exists = (Test-Path -LiteralPath $exp) }
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $pathRows '09_PATH.csv'
# 按条件筛选输入记录，并保存到 $missingPath。
$missingPath = @($pathRows | Where-Object { -not $_.Exists })
# 按条件筛选输入记录，并保存到 $dupPath。
$dupPath = @($pathRows | Group-Object { $_.Expanded.ToLower() } | Where-Object { $_.Count -gt 1 })
# 向终端显示提示或结果。
Write-Host ('PATH 條目 ' + @($pathRows).Count + ' 個；不存在 ' + $missingPath.Count + ' 個；重複 ' + $dupPath.Count + ' 組')
# 检查本行条件；满足时执行对应分支。
if ($missingPath.Count -gt 0) { Add-Finding '資訊' 'PATH' ('PATH 內有 ' + $missingPath.Count + ' 個不存在的目錄（見 09_PATH.csv）。') }
# 检查本行条件；满足时执行对应分支。
if ($dupPath.Count -gt 0) { Add-Finding '資訊' 'PATH' ('PATH 內有 ' + $dupPath.Count + ' 組重複條目。') }

# 環境變數
# 构造或计算 $envNames，保存本行指定的集合或索引结果。
$envNames = @('R_HOME', 'R_LIBS_USER', 'R_LIBS_SITE', 'R_ENVIRON_USER', 'PYTHONPATH', 'PYTHONHOME', 'CONDA_PREFIX', 'VIRTUAL_ENV', 'HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY', 'TEMP', 'TMP')
# 计算本行表达式并设置 $envRows，供后续步骤使用。
$envRows = foreach ($n in $envNames) {
    # 把本行列出的字段组成结构化记录。
    [pscustomobject]@{ Name = $n; Process = [Environment]::GetEnvironmentVariable($n, 'Process'); User = [Environment]::GetEnvironmentVariable($n, 'User'); Machine = [Environment]::GetEnvironmentVariable($n, 'Machine') }
# 结束此处的代码块、参数列表或集合定义。
}
# 按条件筛选输入记录。
Save-Csv ($envRows | Where-Object { $_.Process -or $_.User -or $_.Machine }) '09_環境變數.csv'

# TEMP 大小
# 开始受异常处理保护的操作。
try {
    # 枚举指定位置的文件、目录或注册表项，并保存到 $tmpBytes。
    $tmpBytes = (Get-ChildItem -LiteralPath $env:TEMP -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    # 构造或计算 $tmpGB，保存本行指定的集合或索引结果。
    $tmpGB = [math]::Round($tmpBytes / 1GB, 2)
    # 向终端显示提示或结果。
    Write-Host ('使用者 TEMP 大小：' + $tmpGB + ' GB')
    # 检查本行条件；满足时执行对应分支。
    if ($tmpGB -gt 2) { Add-Finding '注意' '磁碟' ('使用者 TEMP 資料夾已達 ' + $tmpGB + ' GB，可清理超過 7 天的舊檔。') }
# 结束上一代码块并进入异常处理。
} catch { }

# ------------------------------------------------------------------ 10. 事件記錄
# 检查本行条件；满足时执行对应分支。
if (-not $SkipEventLog) {
    # 处理 Section 所指定的操作或当前表达式的后续部分。
    Section '10. 近 14 天事件記錄摘要'
    # 生成当前时间或格式化时间戳，并保存到 $since。
    $since = (Get-Date).AddDays(-14)
    # 开始受异常处理保护的操作。
    try {
        # 计算本行表达式并设置 $ev，供后续步骤使用。
        $ev = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1, 2; StartTime = $since } -MaxEvents 500 -ErrorAction Stop
        # 选取记录中的指定字段或条目；按指定属性排序输入记录，并保存到 $top。
        $top = $ev | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 15 Count, Name
        # 处理 Show-Table 所指定的操作或当前表达式的后续部分。
        Show-Table $top
        # 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
        Save-Csv $top '10_系統錯誤_來源統計.csv'
        # 按条件筛选输入记录，并保存到 $hw。
        $hw = @($top | Where-Object { $_.Name -match 'disk|Ntfs|WHEA|volmgr|storahci|stornvme|nvme' })
        # 检查本行条件；满足时执行对应分支。
        if ($hw.Count -gt 0) { Add-Finding '警告' '硬體' ('系統事件中出現疑似儲存/硬體錯誤來源：' + (($hw | ForEach-Object { $_.Name }) -join ', ') + '，建議檢查磁碟健康與備份。') }
    # 结束上一代码块并进入异常处理。
    } catch { Write-Host '近 14 天沒有 System 錯誤/嚴重事件，或無法讀取。' }
    # 开始受异常处理保护的操作。
    try {
        # 计算本行表达式并设置 $crash，供后续步骤使用。
        $crash = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = $since } -MaxEvents 300 -ErrorAction Stop
        # 选取记录中的指定字段或条目；按指定属性排序输入记录，并保存到 $ct。
        $ct = $crash | Group-Object { $_.Properties[0].Value } | Sort-Object Count -Descending | Select-Object -First 15 Count, Name
        # 处理 Show-Table 所指定的操作或当前表达式的后续部分。
        Show-Table $ct
        # 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
        Save-Csv $ct '10_應用程式當機統計.csv'
        # 追加一项诊断发现。
        Add-Finding '注意' '穩定性' ('近 14 天有應用程式當機紀錄（見 10_應用程式當機統計.csv）。')
    # 结束上一代码块并进入异常处理。
    } catch { Write-Host '近 14 天沒有應用程式當機紀錄，或無法讀取。' }
# 结束此处的代码块、参数列表或集合定义。
}

# ------------------------------------------------------------------ 摘要
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '摘要'
# 计算本行表达式并设置 $order，供后续步骤使用。
$order = @{ '警告' = 0; '注意' = 1; '資訊' = 2 }
# 按指定属性排序输入记录，并保存到 $sorted。
$sorted = $script:Findings | Sort-Object { $order[$_.Level] }, Area
# 创建指定类型的对象，并保存到 $sb。
$sb = New-Object System.Text.StringBuilder
# 生成当前时间或格式化时间戳；向报告缓冲区追加一行文本。
[void]$sb.AppendLine('Windows 10 診斷摘要  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('系統：' + $os.Caption + ' ' + $dispVer + ' (Build ' + $build + ')，RAM ' + $ramGB + ' GB，管理員身分=' + $isAdmin)
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('')
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('--- 發現 (' + @($sorted).Count + ') ---')
# 按本行的迭代范围或条件重复执行循环体。
foreach ($f in $sorted) { [void]$sb.AppendLine('[' + $f.Level + '] ' + $f.Area + ' - ' + $f.Message) }
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('')
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('--- 資料分析工具鏈 ---')
# 把结果排版成表格；把结果转换为文本；向报告缓冲区追加一行文本。
[void]$sb.AppendLine((($toolRows | Format-Table Tool, Found, Version, Path -AutoSize | Out-String -Width 220).TrimEnd()))
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('')
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('--- 產出檔案 ---')
# 按本行的迭代范围或条件重复执行循环体。
foreach ($f in $script:Files) { [void]$sb.AppendLine('  ' + $f) }
# 计算本行表达式并设置 $sumText，供后续步骤使用。
$sumText = $sb.ToString()
# 组合父目录与子路径；将内容写入目标文件。
Set-Content -Path (Join-Path $OutDir '00_摘要.txt') -Value $sumText -Encoding UTF8
# 向终端显示提示或结果。
Write-Host $sumText
# 向终端显示提示或结果。
Write-Host ''
# 向终端显示提示或结果。
Write-Host ('完成。報告位置：' + $OutDir) -ForegroundColor Green
# 向终端显示提示或结果。
Write-Host '提示：00_摘要.txt 為總覽；分享前請先檢視是否含有不想公開的資訊。' -ForegroundColor Yellow
