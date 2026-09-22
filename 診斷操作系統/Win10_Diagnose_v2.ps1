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
# 启用 PowerShell 高级脚本参数绑定及所列功能。
[CmdletBinding()]
# 声明脚本或函数接受的参数及默认值。
param(
    # 声明参数 $OutDir的类型、默认值或校验规则。
    [string]$OutDir = (Join-Path $env:USERPROFILE ('Win10_Diag2_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))),
    [string]$WorkRoot = 'C:\work',   # 工作區根目錄；用來尋找專案虛擬環境（需與 Setup_DataStack.ps1 一致）
    # 声明参数 $Fast的类型、默认值或校验规则。
    [switch]$Fast,
    # 声明参数 $SkipWinget的类型、默认值或校验规则。
    [switch]$SkipWinget,
    # 声明参数 $SkipRPackages的类型、默认值或校验规则。
    [switch]$SkipRPackages,
    # 声明参数 $SkipPython的类型、默认值或校验规则。
    [switch]$SkipPython
# 结束此处的代码块、参数列表或集合定义。
)

# 处理 Set-StrictMode 所指定的操作或当前表达式的后续部分。
Set-StrictMode -Off
# 设置本脚本遇到 PowerShell 错误时的处理方式。
$ErrorActionPreference = 'Continue'
# 开始受异常处理保护的操作。
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
# 检查本行条件；满足时执行对应分支。
if ($Fast) { $SkipWinget = $true; $SkipRPackages = $true; $SkipPython = $true }
# 创建指定目录、文件或配置项；将不需要的返回值丢弃。
$null = New-Item -ItemType Directory -Path $OutDir -Force

# 创建指定类型的对象，并保存到 $script:Findings。
$script:Findings = New-Object System.Collections.Generic.List[object]
# 创建指定类型的对象，并保存到 $script:Actions。
$script:Actions = New-Object System.Collections.Generic.List[string]
# 创建指定类型的对象，并保存到 $script:Files。
$script:Files = New-Object System.Collections.Generic.List[string]

# ---------------------------------------------------------------- 共用函式
# 定义 Add-Finding，封装此函数内的操作。
function Add-Finding {
    # 声明脚本或函数接受的参数及默认值。
    param([ValidateSet('嚴重', '警告', '注意', '資訊')][string]$Level, [string]$Area, [string]$Message)
    # 调用 $script:Findings.Add，使用本行列出的输入完成对应操作。
    $script:Findings.Add([pscustomobject]@{ Level = $Level; Area = $Area; Message = $Message })
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Add-Action，封装此函数内的操作。
function Add-Action { param([string]$Text) if ($script:Actions -notcontains $Text) { $script:Actions.Add($Text) } }
# 定义 Section，封装此函数内的操作。
function Section { param([string]$T) Write-Host ''; Write-Host ('=== ' + $T + ' ===') -ForegroundColor Cyan }
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
    ($Data | Format-Table -AutoSize | Out-String -Width 240).TrimEnd() | Write-Host
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
        # 返回本行结果并结束当前函数。
        return ((@($o) | ForEach-Object { "$_" }) -join "`n").Trim()
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
# 定义 Test-NonAscii，封装此函数内的操作。
function Test-NonAscii { param([string]$s) return ($s -and ($s -match '[^\x00-\x7F]')) }

# 计算本行表达式并设置 $isAdmin，供后续步骤使用。
$isAdmin = Test-Admin
# 向终端显示提示或结果。
Write-Host ('輸出資料夾：' + $OutDir) -ForegroundColor Green
# 向终端显示提示或结果。
Write-Host ('系統管理員身分：' + $isAdmin + '    快速模式：' + [bool]$Fast)

# ---------------------------------------------------------------- 1. 系統與硬體
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '1. 系統與硬體'
# 查询 Windows 管理接口中的设备或系统信息，并保存到 $os。
$os = Get-CimInstance Win32_OperatingSystem
# 查询 Windows 管理接口中的设备或系统信息，并保存到 $cs。
$cs = Get-CimInstance Win32_ComputerSystem
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目，并保存到 $cpu。
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
# 计算本行表达式并设置 $cv，供后续步骤使用。
$cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
# 计算本行表达式并设置 $dispVer，供后续步骤使用。
$dispVer = Get-RegValue $cv 'DisplayVersion'
# 检查本行条件；满足时执行对应分支。
if (-not $dispVer) { $dispVer = Get-RegValue $cv 'ReleaseId' }
# 计算本行表达式并设置 $build，供后续步骤使用。
$build = ('' + (Get-RegValue $cv 'CurrentBuild')) + '.' + (Get-RegValue $cv 'UBR')
# 构造或计算 $ramGB，保存本行指定的集合或索引结果。
$ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
# 构造或计算 $freeRamGB，保存本行指定的集合或索引结果。
$freeRamGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
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
    # 计算本行表达式并设置 CPU，供后续步骤使用。
    CPU          = $cpu.Name
    # 计算本行表达式并设置 Cores，供后续步骤使用。
    Cores        = $cpu.NumberOfCores
    # 计算本行表达式并设置 Threads，供后续步骤使用。
    Threads      = $cpu.NumberOfLogicalProcessors
    # 计算本行表达式并设置 RAM_GB，供后续步骤使用。
    RAM_GB       = $ramGB
    # 计算本行表达式并设置 FreeRAM_GB，供后续步骤使用。
    FreeRAM_GB   = $freeRamGB
    # 生成当前时间或格式化时间戳，并保存到 UptimeDays。
    UptimeDays   = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1)
    # 计算本行表达式并设置 PowerShell，供后续步骤使用。
    PowerShell   = $PSVersionTable.PSVersion.ToString()
    # 计算本行表达式并设置 IsAdmin，供后续步骤使用。
    IsAdmin      = $isAdmin
# 结束此处的代码块、参数列表或集合定义。
}
# 把结果转换为文本；向终端显示提示或结果。
$sys | Format-List | Out-String -Width 240 | Write-Host
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $sys '01_系統.csv'

# 判 OS 一律用 Build，不要用字串比對：
# Win10 就地升級到 Win11 之後，註冊表 ProductName 仍會留著 "Windows 10"，
# 只有 CurrentBuild 會誠實地跳到 22000 以上。
# 计算本行表达式并设置 $buildNum，供后续步骤使用。
$buildNum = 0
# 继续当前表达式，补充参数、类型转换或结果处理。
[void][int]::TryParse(('' + (Get-RegValue $cv 'CurrentBuild')), [ref]$buildNum)
# 检查本行条件；满足时执行对应分支。
if ($buildNum -ge 22000) {
    # 追加一项诊断发现。
    Add-Finding '資訊' '系統' ('已在 Windows 11（Build ' + $buildNum + '）。註冊表 ProductName 若仍顯示 Windows 10 屬就地升級的已知現象，以 Build 為準。')
    # 追加一项诊断发现。
    Add-Finding '注意' '系統' '剛完成大版本升級：顯示卡、音效、網路卡驅動有可能被保留成升級前的舊版本，或被回退成微軟通用驅動。請先確認 GPU 一節的驅動版本再下任何結論。'
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
elseif ($buildNum -gt 0) {
    # 追加一项诊断发现。
    Add-Finding '警告' '系統' 'Windows 10 一般支援已於 2025-10-14 結束。請確認公司是否已購買 ESU；否則作業系統層級的「最強化」上限就在這裡（以 Microsoft 官方公告與貴公司 IT 政策為準）。'
# 结束此处的代码块、参数列表或集合定义。
}
# 這支腳本本身跑在 5.1（為了相容性），所以不能用「我是什麼版本」來判斷機器上有沒有 7。
# 要看的是機器上裝了沒有。
# 构造或计算 $pwshInstalled，保存本行指定的集合或索引结果。
$pwshInstalled = [bool](Find-Exe 'pwsh' @("$env:ProgramFiles\PowerShell\7\pwsh.exe", "$env:ProgramFiles\PowerShell\*\pwsh.exe"))
# 检查本行条件；满足时执行对应分支。
if (-not $pwshInstalled) {
    # 逐项处理管道传入的记录；追加一项诊断发现。
    Add-Finding '注意' '工具' '機器上只有 Windows PowerShell 5.1。PowerShell 7 有 ForEach-Object -Parallel、更正確的 UTF-8 與 JSON 處理，對資料前處理腳本幫助很大，且可與 5.1 並存。'
    # 记录建议执行的后续操作。
    Add-Action '-InstallToolchain'
# 结束此处的代码块、参数列表或集合定义。
}

# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目，并保存到 $gpus。
$gpus = Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DriverDate
# 处理 Show-Table 所指定的操作或当前表达式的后续部分。
Show-Table $gpus
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $gpus '01_GPU.csv'
# 按本行的迭代范围或条件重复执行循环体。
foreach ($g in @($gpus)) {
    # 检查本行条件；满足时执行对应分支。
    if ($g.Name -match 'GT (7|6|5)\d\d|GTX (6|7)\d\d|Quadro K|NVS ') {
        # 追加一项诊断发现。
        Add-Finding '資訊' 'GPU' ($g.Name + ' 屬舊世代 NVIDIA（Kepler/Fermi 級）。現行 CUDA / PyTorch / XGBoost-GPU 都已不支援這種運算能力。模型訓練一律走 CPU 路線（XGBoost/LightGBM 的 hist 演算法 + 多執行緒）。')
        # 2026-09-20 修正：原本這裡寫「請把它當只負責顯示」，已被實機推翻。
        # 舊世代顯卡配上舊驅動，在 Windows 11 上「連顯示都不一定做得到」——
        # Chromium 系瀏覽器（Comet/Chrome/Edge）會出現「視窗開得出來、內容區全黑」。
        # 驅動年齡必須實測，不能因為「有顯卡」就假設顯示沒問題。
        # 计算本行表达式并设置 $digits，供后续步骤使用。
        $digits = ($g.DriverVersion -replace '\.', '')
        # 检查本行条件；满足时执行对应分支。
        if ($digits.Length -ge 5) {
            # 计算本行表达式并设置 $tail，供后续步骤使用。
            $tail = $digits.Substring($digits.Length - 5, 5)
            # 构造或计算 $nvVer，保存本行指定的集合或索引结果。
            $nvVer = [double]($tail.Substring(0, 3) + '.' + $tail.Substring(3, 2))
            # 追加一项诊断发现。
            Add-Finding '資訊' 'GPU' ($g.Name + ' 的 NVIDIA 驅動實際版本為 ' + $nvVer + '（Windows 版本字串 ' + $g.DriverVersion + '，日期 ' + $g.DriverDate + '）。')
            # 检查本行条件；满足时执行对应分支。
            if ($nvVer -lt 470) {
                # 2026-09-20 實測修正：本機驅動確實是 391.35，但它「不是」黑屏的原因。
                # 同一台機器上 Chrome 內容區近黑 0%、平均亮度 243.3，渲染完全正常；
                # 只有不在 DLP 支援清單上的 Comet 黑屏。原本斷言「Chromium 系的
                # DirectComposition 會失敗」屬過度推論，已降級並改寫。
                # 追加一项诊断发现。
                Add-Finding '警告' 'GPU' ('驅動 ' + $nvVer + ' 低於 Kepler 最後支援分支 472.xx，且從未針對 Windows 11 發行，屬長期風險（無安全修補、新版瀏覽器可能逐步停止支援）。但請注意：本機實測顯示 Chromium 系渲染在此驅動下正常運作，**不要直接把應用黑屏歸因於它**——先用對照組（另一個正常的同類應用）與 Win11_App_RealTest.ps1 做像素級實測。')
                # 记录建议执行的后续操作。
                Add-Action '升級 NVIDIA 驅動至 472.12（需管理員）'
            # 结束此处的代码块、参数列表或集合定义。
            }
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if ($cpu.Name -match 'i\d-\d+F') {
    # 追加一项诊断发现。
    Add-Finding '資訊' 'CPU' ($cpu.Name + ' 為 F 版（無內顯），顯示完全依賴獨立顯卡；不影響 CPU 運算效能。')
# 结束此处的代码块、参数列表或集合定义。
}

# ---------------------------------------------------------------- 2. 磁碟與記憶體策略
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '2. 磁碟、分頁檔與記憶體策略'
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目，并保存到 $vol。
$vol = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object DeviceID, FileSystem,
# 处理 @{n 所指定的操作或当前表达式的后续部分。
@{n = 'Size_GB'; e = { [math]::Round($_.Size / 1GB, 1) } },
# 处理 @{n 所指定的操作或当前表达式的后续部分。
@{n = 'Free_GB'; e = { [math]::Round($_.FreeSpace / 1GB, 1) } },
# 处理 @{n 所指定的操作或当前表达式的后续部分。
@{n = 'Free_Pct'; e = { if ($_.Size) { [math]::Round(100 * $_.FreeSpace / $_.Size, 1) } } }
# 计算本行表达式并设置 $pd，供后续步骤使用。
$pd = $null
# 开始受异常处理保护的操作。
try { $pd = Get-PhysicalDisk | Select-Object FriendlyName, MediaType, BusType, HealthStatus, @{n = 'Size_GB'; e = { [math]::Round($_.Size / 1GB) } } } catch { }
# 处理 Show-Table 所指定的操作或当前表达式的后续部分。
Show-Table $vol
# 处理 Show-Table 所指定的操作或当前表达式的后续部分。
Show-Table $pd
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $vol '02_磁碟區.csv'
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $pd '02_實體磁碟.csv'

# 按本行的迭代范围或条件重复执行循环体。
foreach ($v in @($vol)) {
    # 检查本行条件；满足时执行对应分支。
    if ($null -ne $v.Free_Pct -and $v.Free_Pct -lt 20) {
        # 追加一项诊断发现。
        Add-Finding '警告' '磁碟' ($v.DeviceID + ' 剩餘 ' + $v.Free_Pct + '% (' + $v.Free_GB + ' GB)。DuckDB / Arrow 在處理大表時會把中間結果 spill 到磁碟，空間不足會讓查詢直接失敗。')
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if (@($pd).Count -eq 1 -and @($vol).Count -eq 1) {
    # 追加一项诊断发现。
    Add-Finding '注意' '磁碟' '全機只有一顆磁碟、一個分割區：系統、套件庫、資料集、暫存檔、spill 檔全部互搶空間與 IO。若要再往上強化，加一顆 NVMe SSD 專放 data/ 與 TEMP 是本機投資報酬率最高的硬體升級。'
# 结束此处的代码块、参数列表或集合定义。
}
# 按本行的迭代范围或条件重复执行循环体。
foreach ($d in @($pd)) {
    # 检查本行条件；满足时执行对应分支。
    if ($d.HealthStatus -and $d.HealthStatus -ne 'Healthy') { Add-Finding '嚴重' '磁碟' ($d.FriendlyName + ' 健康狀態 ' + $d.HealthStatus + '：立刻備份。') }
# 结束此处的代码块、参数列表或集合定义。
}

# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目，并保存到 $pf。
$pf = Get-CimInstance Win32_PageFileUsage | Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage
# 处理 Show-Table 所指定的操作或当前表达式的后续部分。
Show-Table $pf
# 向终端显示提示或结果。
Write-Host ('自動管理分頁檔：' + $cs.AutomaticManagedPagefile)
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $pf '02_分頁檔.csv'
# 计算本行表达式并设置 $pfMB，供后续步骤使用。
$pfMB = 0
# 按本行的迭代范围或条件重复执行循环体。
foreach ($p in @($pf)) { $pfMB += [int]$p.AllocatedBaseSize }
# 检查本行条件；满足时执行对应分支。
if ($pfMB -gt 0 -and $pfMB -lt ($ramGB * 1024 * 0.5)) {
    # 追加一项诊断发现。
    Add-Finding '注意' '記憶體' ('分頁檔僅 ' + $pfMB + ' MB，不到實體記憶體 (' + $ramGB + ' GB) 的一半。R 的 rugarch/回測、Python 的大表 join 一旦超過實體記憶體，會直接被系統終止而不是變慢。建議固定 ' + [int]($ramGB * 1024 * 0.5) + '～' + [int]($ramGB * 1024) + ' MB。')
    # 记录建议执行的后续操作。
    Add-Action '-SetPageFile'
# 结束此处的代码块、参数列表或集合定义。
}

# ---------------------------------------------------------------- 3. 企業管控代理
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '3. 企業管控代理 / 防毒 / 加密用戶端'
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
    # 选取记录中的指定字段或条目；按指定属性排序输入记录。
    Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation | Sort-Object DisplayName
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $programs '03_已安裝軟體.csv'
# 向终端显示提示或结果。
Write-Host ('已安裝程式共 ' + @($programs).Count + ' 筆（見 03_已安裝軟體.csv）')

# 计算本行表达式并设置 $agentPattern，供后续步骤使用。
$agentPattern = '亿赛通|億賽通|eSafeNet|DocGuard|Ping32|深信服|Sangfor|奇安信|QiAnXin|360\s*(安全|終端|终端)|天珣|IP-guard|域之盾|安全管控|文档加密|文檔加密|Kaspersky|卡巴斯基|Symantec|McAfee|Trellix|Trend Micro|趨勢|趋势|CrowdStrike|SentinelOne|Cortex XDR|Carbon Black|ESET|Bitdefender|Sophos|Ivanti|LANDesk|Intune|Endpoint Manager'
# 按条件筛选输入记录，并保存到 $agents。
$agents = @($programs | Where-Object { $_.DisplayName -match $agentPattern })
# 选取记录中的指定字段或条目。
Show-Table ($agents | Select-Object DisplayName, DisplayVersion, Publisher)
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $agents '03_管控代理.csv'

# 天锐绿盾 Tipray 裝在 C:\Inetpub\ftproot\Tipray\LdTerm\，沒有標準解除安裝登錄項，
# 只比對「已安裝程式」清單會完全漏掉（2026-09-20 實測踩到）。必須靠行程名與模組補抓。
# 计算本行表达式并设置 $agentProcPattern，供后续步骤使用。
$agentProcPattern = '^Cdg|^CDG|esafe|docguard|^avp$|klnagent|ksde|^360|sfdesk|Sangfor|qaxsafe|SentinelAgent|CSFalcon|MsMpEng|^LdTerm|^LdApproval|Tipray'
# 读取正在运行的进程信息；按条件筛选输入记录，并保存到 $agentProcs。
$agentProcs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $agentProcPattern } |
    # 选取记录中的指定字段或条目；按指定属性排序输入记录。
    Select-Object Name, Id, @{n = 'WS_MB'; e = { [math]::Round($_.WorkingSet64 / 1MB) } } | Sort-Object Name
# 处理 Show-Table 所指定的操作或当前表达式的后续部分。
Show-Table $agentProcs
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $agentProcs '03_管控代理行程.csv'

# 最可靠的偵測：看管控代理實際把哪些 DLL 注入到一般應用程式裡。
# 已安裝程式清單可以漏、行程名可以改，但要攔截就一定得注入模組。
# 順便量出「哪個應用被注入的模組比較少」——那往往就是它不在支援清單上、
# 只套到半套掛鉤而行為異常的原因（2026-09-20 Comet 黑屏即為此）。
# 构造或计算 $injRows，保存本行指定的集合或索引结果。
$injRows = @()
# 只在「同一類」應用之間比較，否則沒有意義（explorer 本來就比瀏覽器多）。
# 且必須抓「有主視窗的那個行程」：Chromium 的 renderer 子行程在沙箱裡，
# 本來就不會被注入，用記憶體最大的那個會抓到 renderer 而量出 0，造成誤判。
# 构造或计算 $groups，保存本行指定的集合或索引结果。
$groups = @{ '瀏覽器' = @('chrome', 'msedge', 'firefox', 'comet'); 'IDE' = @('rstudio', 'positron', 'pycharm64') }
# 按本行的迭代范围或条件重复执行循环体。
foreach ($grp in $groups.Keys) {
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($pn in $groups[$grp]) {
        # 读取正在运行的进程信息，并保存到 $cands。
        $cands = @(Get-Process $pn -ErrorAction SilentlyContinue)
        # 检查本行条件；满足时执行对应分支。
        if ($cands.Count -eq 0) { continue }
        # 选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $pp。
        $pp = @($cands | Where-Object { $_.MainWindowHandle -ne 0 }) | Select-Object -First 1
        if (-not $pp) { $pp = @($cands | Sort-Object StartTime) | Select-Object -First 1 }   # 退而求其次：最早啟動的通常是主行程
        # 检查本行条件；满足时执行对应分支。
        if (-not $pp) { continue }
        # 构造或计算 $dlp，保存本行指定的集合或索引结果。
        $dlp = @()
        # 开始受异常处理保护的操作。
        try { $dlp = @($pp.Modules | Where-Object { $_.FileName -match 'Tipray|EsafeNet|Cobra|Kaspersky|Sangfor|360' }) } catch { continue }
        # 构造或计算 $injRows，保存本行指定的集合或索引结果。
        $injRows += [pscustomobject]@{
            # 计算本行表达式并设置 Group，供后续步骤使用。
            Group     = $grp
            # 计算本行表达式并设置 Process，供后续步骤使用。
            Process   = $pn
            # 计算本行表达式并设置 HasWindow，供后续步骤使用。
            HasWindow = ($pp.MainWindowHandle -ne 0)
            # 计算本行表达式并设置 DLP模組數，供后续步骤使用。
            DLP模組數 = $dlp.Count
            # 提取路径中的指定部分；按指定属性排序输入记录；逐项处理管道传入的记录。
            模組清單  = (($dlp | ForEach-Object { Split-Path $_.FileName -Leaf } | Sort-Object) -join ' ')
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if ($injRows.Count -gt 0) {
    # 向终端显示提示或结果。
    Write-Host '同類應用被注入的管控模組數（同組內落差通常代表某支不在支援清單上）：'
    # 选取记录中的指定字段或条目。
    Show-Table ($injRows | Select-Object Group, Process, HasWindow, DLP模組數)
    # 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
    Save-Csv $injRows '03_管控模組注入比對.csv'
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($grp in $groups.Keys) {
        # 只比對「有主視窗」的行程，數字才是同一個基準
        # 按条件筛选输入记录，并保存到 $g。
        $g = @($injRows | Where-Object { $_.Group -eq $grp -and $_.DLP模組數 -gt 0 -and $_.HasWindow })
        # 检查本行条件；满足时执行对应分支。
        if ($g.Count -lt 2) { continue }
        # 计算本行表达式并设置 $mx，供后续步骤使用。
        $mx = ($g | Measure-Object DLP模組數 -Maximum).Maximum
        # 按本行的迭代范围或条件重复执行循环体。
        foreach ($o in @($g | Where-Object { $_.DLP模組數 -lt $mx })) {
            # 注意措辭：模組數落差是「線索」，不是「原因」。
            # 2026-09-20 實測反證：Positron 與 Comet 拿到完全相同的 13 個通用模組，
            # Positron 渲染正常、Comet 全黑。所以落差本身不足以解釋故障，
            # 只能當成「這支應用不在管控軟體的支援清單上」的佐證。
            # 追加一项诊断发现。
            Add-Finding '資訊' '管控' ($o.Process + ' 被注入 ' + $o.DLP模組數 + ' 個管控模組，同組（' + $grp + '）其他應用有 ' + $mx + ' 個。這代表它可能不在管控軟體的支援清單上。這是線索而非結論——模組數落差本身不足以證明故障（已有反例）。若該應用確有異常，請連同此差異一併回報 IT。')
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 检查本行条件；满足时执行对应分支。
    if (@($injRows | Where-Object { $_.模組清單 -match 'Ld|Browser' }).Count -gt 0) {
        # 追加一项诊断发现。
        Add-Finding '資訊' '管控' '偵測到天锐绿盾 (Tipray) 的注入模組。它安裝於 C:\Inetpub\ftproot\Tipray\，沒有標準解除安裝登錄項，僅比對已安裝程式清單會漏掉。'
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# 检查本行条件；满足时执行对应分支。
if (@($agents).Count -gt 0 -or @($agentProcs).Count -gt 0) {
    # 构造或计算 $names，保存本行指定的集合或索引结果。
    $names = @()
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($a in @($agents)) { $names += $a.DisplayName }
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($p in @($agentProcs | Select-Object -ExpandProperty Name -Unique)) { $names += $p }
    # 选取记录中的指定字段或条目；追加一项诊断发现。
    Add-Finding '警告' '管控' ('偵測到企業管控／防毒／透明加密用戶端：' + (($names | Select-Object -Unique) -join ', ') + '。這類代理會攔截每一次檔案讀寫，是 R/Python 套件安裝變慢或失敗、git 操作卡住、Parquet 檔讀寫異常的頭號原因。')
    # 追加一项诊断发现。
    Add-Finding '嚴重' '管控' '不要自行停用或解除安裝這些代理：一來多半被策略鎖定，二來在公司資產上這通常違反資安規範。正確做法是向 IT 申請「開發目錄排除」（R 套件庫、Python venv、專案 data 目錄、TEMP），由 IT 在管理主控台加白名單。'
    # 记录建议执行的后续操作。
    Add-Action '-AddDefenderExclusions'
# 结束此处的代码块、参数列表或集合定义。
}

# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目，并保存到 $avs。
$avs = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntivirusProduct -ErrorAction SilentlyContinue | Select-Object displayName, productState
# 处理 Show-Table 所指定的操作或当前表达式的后续部分。
Show-Table $avs
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $avs '03_防毒註冊.csv'
# 计算本行表达式并设置 $def，供后续步骤使用。
$def = $null
# 开始受异常处理保护的操作。
try { $def = Get-MpComputerStatus -ErrorAction Stop } catch { }
# 检查本行条件；满足时执行对应分支。
if ($def) {
    # 向终端显示提示或结果。
    Write-Host ('Defender RunningMode=' + $def.AMRunningMode + '  RealTime=' + $def.RealTimeProtectionEnabled)
    # 按条件筛选输入记录，并保存到 $thirdParty。
    $thirdParty = @($avs | Where-Object { $_.displayName -notmatch 'Defender' })
    # 检查本行条件；满足时执行对应分支。
    if ($thirdParty.Count -gt 0 -and $def.AMRunningMode -eq 'Normal' -and $def.RealTimeProtectionEnabled) {
        # 逐项处理管道传入的记录；准备或执行 Python 套件管理操作；追加一项诊断发现。
        Add-Finding '警告' '安全' ('安全中心同時註冊了 ' + (($thirdParty | ForEach-Object { $_.displayName }) -join ', ') + ' 與 Microsoft Defender，而 Defender 目前是 Normal 模式且即時保護開啟。兩套即時掃描同時掛在檔案系統上，會讓「安裝數百個 R 套件 / pip 解壓 wheel」這類小檔案密集操作慢上數倍。請回報 IT，由他們決定是否讓 Defender 轉為 Passive。')
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 检查本行条件；满足时执行对应分支。
    if ($def.AntivirusSignatureLastUpdated) {
        # 生成当前时间或格式化时间戳，并保存到 $sigAge。
        $sigAge = ((Get-Date) - $def.AntivirusSignatureLastUpdated).Days
        # 检查本行条件；满足时执行对应分支。
        if ($sigAge -gt 3) { Add-Finding '警告' '安全' ('Defender 病毒定義已 ' + $sigAge + ' 天未更新。') }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 读取网络相关配置；选取记录中的指定字段或条目，并保存到 $fw。
$fw = Get-NetFirewallProfile -ErrorAction SilentlyContinue | Select-Object Name, Enabled
# 处理 Show-Table 所指定的操作或当前表达式的后续部分。
Show-Table $fw
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $fw '03_防火牆.csv'
# 按本行的迭代范围或条件重复执行循环体。
foreach ($f in @($fw)) { if ("$($f.Enabled)" -eq 'False') { Add-Finding '警告' '安全' ('防火牆設定檔 ' + $f.Name + ' 已停用。') } }

# ---------------------------------------------------------------- 4. 工作區位置
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '4. 工作區位置（雲端同步與非 ASCII 路徑）'
# 构造或计算 $syncRoots，保存本行指定的集合或索引结果。
$syncRoots = @()
# 按本行的迭代范围或条件重复执行循环体。
foreach ($e in @('OneDrive', 'OneDriveCommercial', 'OneDriveConsumer')) {
    # 读取指定作用域的环境变量，并保存到 $v。
    $v = [Environment]::GetEnvironmentVariable($e)
    # 检查本行条件；满足时执行对应分支。
    if ($v -and (Test-Path -LiteralPath $v)) { $syncRoots += $v }
# 结束此处的代码块、参数列表或集合定义。
}
# 按本行的迭代范围或条件重复执行循环体。
foreach ($n in @('Dropbox', 'Nutstore', '坚果云', 'Google Drive', 'iCloudDrive', 'Box')) {
    # 组合父目录与子路径，并保存到 $p。
    $p = Join-Path $env:USERPROFILE $n
    # 检查本行条件；满足时执行对应分支。
    if (Test-Path -LiteralPath $p) { $syncRoots += $p }
# 结束此处的代码块、参数列表或集合定义。
}
# 选取记录中的指定字段或条目，并保存到 $syncRoots。
$syncRoots = @($syncRoots | Select-Object -Unique)
# 向终端显示提示或结果。
Write-Host ('偵測到的雲端同步根目錄：' + ($syncRoots -join ', '))

# 构造或计算 $repoRows，保存本行指定的集合或索引结果。
$repoRows = @()
# 按本行的迭代范围或条件重复执行循环体。
foreach ($r in $syncRoots) {
    # 枚举指定位置的文件、目录或注册表项，并保存到 $gits。
    $gits = Get-ChildItem -LiteralPath $r -Directory -Filter '.git' -Recurse -Force -Depth 4 -ErrorAction SilentlyContinue
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($g in $gits) { $repoRows += [pscustomobject]@{ Type = 'Git repo'; Path = $g.Parent.FullName } }
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($marker in @('renv.lock', 'pyproject.toml', 'uv.lock', '.venv')) {
        # 枚举指定位置的文件、目录或注册表项，并保存到 $hits。
        $hits = Get-ChildItem -LiteralPath $r -Filter $marker -Recurse -Force -Depth 4 -ErrorAction SilentlyContinue
        # 按本行的迭代范围或条件重复执行循环体。
        foreach ($h in $hits) { $repoRows += [pscustomobject]@{ Type = $marker; Path = $h.FullName } }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 按指定属性排序输入记录，并保存到 $repoRows。
$repoRows = @($repoRows | Sort-Object Type, Path -Unique)
# 选取记录中的指定字段或条目。
Show-Table ($repoRows | Select-Object -First 25)
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $repoRows '04_雲端同步內的專案.csv'
# 检查本行条件；满足时执行对应分支。
if ($repoRows.Count -gt 0) {
    # 追加一项诊断发现。
    Add-Finding '警告' '工作區' ('在雲端同步資料夾中發現 ' + $repoRows.Count + ' 個專案/環境標記（見 04_雲端同步內的專案.csv）。同步用戶端會在 .git、renv/library、.venv、*.parquet 上造成檔案鎖定與版本衝突，輕則變慢，重則 repo 或環境毀損。建議把程式與資料移到未同步的本機路徑（例如 C:\work），只讓文件與報告留在雲端。')
    # 记录建议执行的后续操作。
    Add-Action '-PrepareWorkspace'
# 结束此处的代码块、参数列表或集合定义。
}

# 构造或计算 $pathChecks，保存本行指定的集合或索引结果。
$pathChecks = [ordered]@{
    # 提供当前表达式所需的文本、字段名称或列表元素。
    '使用者資料夾' = $env:USERPROFILE
    # 提供当前表达式所需的文本、字段名称或列表元素。
    '目前工作目錄' = (Get-Location).Path
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'TEMP'         = $env:TEMP
    # 读取指定作用域的环境变量。
    'R_LIBS_USER'  = [Environment]::GetEnvironmentVariable('R_LIBS_USER', 'User')
# 结束此处的代码块、参数列表或集合定义。
}
# 按本行的迭代范围或条件重复执行循环体。
foreach ($k in $pathChecks.Keys) {
    # 构造或计算 $p，保存本行指定的集合或索引结果。
    $p = $pathChecks[$k]
    # 检查本行条件；满足时执行对应分支。
    if (Test-NonAscii $p) {
        # 追加一项诊断发现。
        Add-Finding '注意' '路徑' ($k + ' 含非 ASCII 字元：' + $p + '。R 從原始碼編譯、部分 Python C 擴充、LaTeX/Quarto 產 PDF 時，遇到中文路徑仍有機率出錯。純 ASCII 的工作路徑（如 C:\work）最安全。')
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ---------------------------------------------------------------- 5. 系統設定
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '5. 系統設定（編碼、長路徑、電源）'
# 计算本行表达式并设置 $acp，供后续步骤使用。
$acp = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' 'ACP'
# 计算本行表达式并设置 $long，供后续步骤使用。
$long = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled'
# 调用 Windows 电源配置工具，并保存到 $power。
$power = Invoke-Native 'powercfg.exe' @('/getactivescheme')
# 构造或计算 $set，保存本行指定的集合或索引结果。
$set = [pscustomobject]@{ ANSI碼頁 = $acp; LongPathsEnabled = $long; 電源計畫 = $power; SystemLocale = (Get-WinSystemLocale).Name }
# 把结果转换为文本；向终端显示提示或结果。
$set | Format-List | Out-String -Width 240 | Write-Host
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $set '05_設定.csv'

# 检查本行条件；满足时执行对应分支。
if ($long -ne 1) {
    # 追加一项诊断发现。
    Add-Finding '注意' '設定' 'Windows 長路徑未啟用 (LongPathsEnabled=0)。R 套件（尤其 tidyverse 系）與 node_modules 的巢狀路徑很容易超過 260 字元而安裝失敗。'
    # 记录建议执行的后续操作。
    Add-Action '-EnableLongPaths'
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if ($acp -and "$acp" -ne '65001') {
    # 追加一项诊断发现。
    Add-Finding '注意' '編碼' ('系統 ANSI 碼頁為 ' + $acp + '（非 UTF-8）。中文 CSV 在 Excel / R / Python 之間來回時的亂碼多半來自這裡。比起切換「UTF-8 Beta」（會讓部分舊程式亂碼），更安全的做法是在程式碼一律明示編碼：R 用 readr::read_csv(locale = locale(encoding = "UTF-8"))，Python 用 encoding="utf-8-sig"。')
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if ($power -match 'Power saver|節能|节能') {
    # 追加一项诊断发现。
    Add-Finding '注意' '效能' '目前是省電電源計畫，會壓低 CPU 全核心頻率。'
    # 记录建议执行的后续操作。
    Add-Action '-PowerPlanHigh'
# 结束上一代码块并进入另一条件分支。
} elseif ($power -match 'Balanced|平衡') {
    # 追加一项诊断发现。
    Add-Finding '資訊' '效能' '目前是「平衡」電源計畫。桌機長時間跑回測／訓練時，切到「高效能」可避免降頻；筆電則會較耗電發熱。'
    # 记录建议执行的后续操作。
    Add-Action '-PowerPlanHigh'
# 结束此处的代码块、参数列表或集合定义。
}

# ---------------------------------------------------------------- 6. 工具鏈
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '6. 資料分析工具鏈'
# 构造或计算 $probe，保存本行指定的集合或索引结果。
$probe = @(
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ N = 'Rscript'; E = 'Rscript'; A = @('--version'); F = @("$env:ProgramFiles\R\R-*\bin\x64\Rscript.exe", "$env:LOCALAPPDATA\Programs\R\R-*\bin\x64\Rscript.exe") },
    # Rtools 的 gcc 不在 usr\bin，而在 x86_64-w64-mingw32.static.posix\bin（Rtools4x 佈局）。
    # usr\bin 只有 make / sh 等 msys2 工具。找錯路徑會把「已安裝」誤報成「沒安裝」。
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ N = 'Rtools'; E = 'gcc'; A = @('--version'); F = @(
            # 提供当前表达式所需的文本、字段名称或列表元素。
            "C:\rtools*\x86_64-w64-mingw32.static.posix\bin\gcc.exe",
            # 提供当前表达式所需的文本、字段名称或列表元素。
            "C:\rtools*\ucrt64\bin\gcc.exe",
            # 提供当前表达式所需的文本、字段名称或列表元素。
            "C:\rtools*\mingw64\bin\gcc.exe",
            # 提供当前表达式所需的文本、字段名称或列表元素。
            "$env:ProgramFiles\Rtools*\x86_64-w64-mingw32.static.posix\bin\gcc.exe") },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ N = 'python'; E = 'python'; A = @('--version'); F = @() },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ N = 'py'; E = 'py'; A = @('--version'); F = @() },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ N = 'uv'; E = 'uv'; A = @('--version'); F = @("$env:USERPROFILE\.local\bin\uv.exe") },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ N = 'conda'; E = 'conda'; A = @('--version'); F = @("$env:USERPROFILE\miniconda3\Scripts\conda.exe", "$env:USERPROFILE\anaconda3\Scripts\conda.exe") },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ N = 'git'; E = 'git'; A = @('--version'); F = @("$env:ProgramFiles\Git\cmd\git.exe") },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ N = 'quarto'; E = 'quarto'; A = @('--version'); F = @("$env:LOCALAPPDATA\Programs\Quarto\bin\quarto.cmd", "$env:ProgramFiles\Quarto\bin\quarto.cmd") },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ N = 'pandoc'; E = 'pandoc'; A = @('--version'); F = @("$env:LOCALAPPDATA\Pandoc\pandoc.exe") },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ N = 'duckdb'; E = 'duckdb'; A = @('--version'); F = @() },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ N = 'psql'; E = 'psql'; A = @('--version'); F = @() },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ N = 'pwsh'; E = 'pwsh'; A = @('--version'); F = @() },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ N = 'node'; E = 'node'; A = @('--version'); F = @() },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ N = 'java'; E = 'java'; A = @('-version'); F = @() },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ N = 'docker'; E = 'docker'; A = @('--version'); F = @() },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ N = 'code'; E = 'code'; A = @('--version'); F = @() },
    # 处理 @{ 所指定的操作或当前表达式的后续部分。
    @{ N = 'positron'; E = 'positron'; A = @('--version'); F = @("$env:LOCALAPPDATA\Programs\Positron\bin\positron.cmd") }
# 结束此处的代码块、参数列表或集合定义。
)
# PATH 判定必須看「登錄檔裡持久化的 PATH」，而不是目前這個行程的 $env:PATH。
# 行程的 PATH 是啟動當下複製的快照：剛改過 PATH 的機器，舊 session 看到的是舊值，
# 會把已經修好的項目誤報成「不在 PATH 上」，讓人白忙一場。
# 构造或计算 $script:PersistedPathDirs，保存本行指定的集合或索引结果。
$script:PersistedPathDirs = @()
# 按本行的迭代范围或条件重复执行循环体。
foreach ($scope in @('Machine', 'User')) {
    # 读取指定作用域的环境变量，并保存到 $raw。
    $raw = [Environment]::GetEnvironmentVariable('Path', $scope)
    # 检查本行条件；满足时执行对应分支。
    if (-not $raw) { continue }
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($e in ($raw -split ';')) {
        # 检查本行条件；满足时执行对应分支。
        if ($e.Trim()) { $script:PersistedPathDirs += ([Environment]::ExpandEnvironmentVariables($e.Trim())).TrimEnd('\') }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Test-OnPersistedPath，封装此函数内的操作。
function Test-OnPersistedPath {
    # 声明脚本或函数接受的参数及默认值。
    param([string]$ExePath)
    # 检查本行条件；满足时执行对应分支。
    if (-not $ExePath) { return $false }
    # 提取路径中的指定部分，并保存到 $dir。
    $dir = (Split-Path $ExePath -Parent)
    # 检查本行条件；满足时执行对应分支。
    if (-not $dir) { return $false }
    # 计算本行表达式并设置 $dir，供后续步骤使用。
    $dir = $dir.TrimEnd('\')
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($d in $script:PersistedPathDirs) { if ($d -ieq $dir) { return $true } }
    # 有些程式是透過 PATH 上的「應用程式執行別名」啟動的（Store 應用最常見，
    # 例如 pwsh 的別名在 WindowsApps，但 Get-Command 會解析成套件實際目錄）。
    # 只比對目錄會把「其實叫得到」誤判成「不在 PATH 上」，所以再用檔名找一次。
    # 提取路径中的指定部分，并保存到 $leaf。
    $leaf = Split-Path $ExePath -Leaf
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($d in $script:PersistedPathDirs) {
        # 检查本行条件；满足时执行对应分支。
        if (Test-Path -LiteralPath (Join-Path $d $leaf)) { return $true }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 返回本行结果并结束当前函数。
    return $false
# 结束此处的代码块、参数列表或集合定义。
}

# 构造或计算 $tools，保存本行指定的集合或索引结果。
$tools = @()
# 按本行的迭代范围或条件重复执行循环体。
foreach ($d in $probe) {
    # 计算本行表达式并设置 $p，供后续步骤使用。
    $p = Find-Exe $d.E $d.F
    # 计算本行表达式并设置 $ver，供后续步骤使用。
    $ver = ''
    # 检查本行条件；满足时执行对应分支。
    if ($p) { $ver = (((Invoke-Native $p $d.A) -split "`n") | Select-Object -First 1).Trim() }
    # 构造或计算 $tools，保存本行指定的集合或索引结果。
    $tools += [pscustomobject]@{
        # 计算本行表达式并设置 Tool，供后续步骤使用。
        Tool    = $d.N
        # 构造或计算 Found，保存本行指定的集合或索引结果。
        Found   = [bool]$p
        OnPATH  = (Test-OnPersistedPath $p)   # 指「新開的視窗看不看得到」
        # 计算本行表达式并设置 Version，供后续步骤使用。
        Version = $ver
        # 计算本行表达式并设置 Path，供后续步骤使用。
        Path    = $p
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 选取记录中的指定字段或条目。
Show-Table ($tools | Select-Object Tool, Found, OnPATH, Version)
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $tools '06_工具鏈.csv'
# 向终端显示提示或结果。
Write-Host 'OnPATH 欄位的判定依據是登錄檔中持久化的 PATH，也就是「重開視窗後」的狀態，不是目前這個 session。'

# Rtools 不列入 PATH 檢查：R 是透過登錄機碼找它的，刻意不進 PATH
# （rtools\usr\bin 的 sh/find/sort 會蓋掉 Windows 內建同名指令）。
# 构造或计算 $pathExempt，保存本行指定的集合或索引结果。
$pathExempt = @('Rtools')
# 按本行的迭代范围或条件重复执行循环体。
foreach ($t in $tools) {
    # 检查本行条件；满足时执行对应分支。
    if ($t.Found -and -not $t.OnPATH -and ($pathExempt -notcontains $t.Tool)) {
        # 追加一项诊断发现。
        Add-Finding '警告' 'PATH' ($t.Tool + ' 已安裝於 ' + $t.Path + ' 但不在持久化的 PATH 上。代表你只能在 IDE 內使用它，命令列、quarto render、排程工作、CI 都會找不到。')
        # 记录建议执行的后续操作。
        Add-Action '-FixPath'
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# python 是否被 Store 別名攔截：要看持久化 PATH 的「先後順序」，
# 而不是目前 session 解析到哪一個。
# 计算本行表达式并设置 $realPyDir，供后续步骤使用。
$realPyDir = $null
# 计算本行表达式并设置 $storeIdx，供后续步骤使用。
$storeIdx = -1
# 计算本行表达式并设置 $realIdx，供后续步骤使用。
$realIdx = -1
# 按本行的迭代范围或条件重复执行循环体。
for ($i = 0; $i -lt $script:PersistedPathDirs.Count; $i++) {
    # 构造或计算 $d，保存本行指定的集合或索引结果。
    $d = $script:PersistedPathDirs[$i]
    # 检查本行条件；满足时执行对应分支。
    if ($storeIdx -lt 0 -and $d -like '*\WindowsApps') { $storeIdx = $i }
    # 检查本行条件；满足时执行对应分支。
    if ($realIdx -lt 0 -and (Test-Path -LiteralPath (Join-Path $d 'python.exe')) -and $d -notlike '*\WindowsApps') {
        # 计算本行表达式并设置 $realIdx，供后续步骤使用。
        $realIdx = $i; $realPyDir = $d
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if ($realIdx -ge 0 -and ($storeIdx -lt 0 -or $realIdx -lt $storeIdx)) {
    # 追加一项诊断发现。
    Add-Finding '資訊' 'Python' ('PATH 上的 python 會解析到真正的直譯器：' + $realPyDir + '（已排在 WindowsApps 別名之前）。')
# 结束上一代码块并进入另一条件分支。
} elseif ($storeIdx -ge 0) {
    # 追加一项诊断发现。
    Add-Finding '警告' 'Python' 'PATH 上的 python 會先命中 Microsoft Store 應用程式執行別名，不是真正的直譯器。任何 python xxx.py 都可能被導去 Store 而失敗。請到「設定 > 應用程式 > 應用程式執行別名」關閉 python.exe / python3.exe，或讓真正的 Python 目錄排在 PATH 前面。'
    # 记录建议执行的后续操作。
    Add-Action '-FixPath'
# 结束此处的代码块、参数列表或集合定义。
}
# 选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $rsTool。
$rsTool = $tools | Where-Object { $_.Tool -eq 'Rscript' } | Select-Object -First 1
# 选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $rtTool。
$rtTool = $tools | Where-Object { $_.Tool -eq 'Rtools' } | Select-Object -First 1
# R 靠登錄機碼 HKLM\SOFTWARE\R-core\Rtools 找工具鏈，不是靠 PATH。
# 所以這裡以登錄機碼為準，檔案探測只當輔助。
# 读取注册表或对象的属性，并保存到 $rtReg。
$rtReg = @(Get-ItemProperty 'HKLM:\SOFTWARE\R-core\Rtools\*', 'HKCU:\SOFTWARE\R-core\Rtools\*' -ErrorAction SilentlyContinue |
        # 检查目标路径是否存在；按条件筛选输入记录。
        Where-Object { $_.InstallPath -and (Test-Path -LiteralPath $_.InstallPath) })
# 检查本行条件；满足时执行对应分支。
if ($rtReg.Count -gt 0) {
    # 逐项处理管道传入的记录；向终端显示提示或结果。
    Write-Host ('Rtools（登錄機碼）：' + (($rtReg | ForEach-Object { $_.PSChildName + ' -> ' + $_.InstallPath }) -join '; '))
    # 选取记录中的指定字段或条目。
    Save-Csv ($rtReg | Select-Object PSChildName, InstallPath) '06_Rtools.csv'
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if ($rsTool.Found -and $rtReg.Count -eq 0 -and -not $rtTool.Found) {
    # 追加一项诊断发现。
    Add-Finding '警告' 'R' '已安裝 R 但沒有 Rtools。任何需要編譯的套件（大量 GitHub 套件、部分 CRAN 套件的最新版）都會安裝失敗，也無法用 Rcpp 自行寫 C++ 加速。'
    # 记录建议执行的后续操作。
    Add-Action '-InstallRtools'
# 结束上一代码块并进入另一条件分支。
} elseif ($rtReg.Count -gt 0) {
    # 逐项处理管道传入的记录；追加一项诊断发现。
    Add-Finding '資訊' 'R' ('Rtools 已註冊（' + (($rtReg | ForEach-Object { $_.PSChildName }) -join ', ') + '）。注意：Rtools 的版本號不必然等於 R 的次版本——R 4.6 使用的就是 Rtools45，CRAN 並沒有發行 rtools46。是否真的能編譯，請以 R CMD SHLIB 實測為準，不要靠版本號推論。')
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if (-not ($tools | Where-Object { $_.Tool -eq 'duckdb' -and $_.Found })) {
    # 追加一项诊断发现。
    Add-Finding '資訊' '資料庫' '沒有 DuckDB CLI。以 32 GB 記憶體 / 單 SSD 的配置，DuckDB 是處理千萬列級資料最划算的引擎：可直接對 Parquet 下 SQL，不必先把整份資料讀進記憶體。'
    # 记录建议执行的后续操作。
    Add-Action '-InstallToolchain'
# 结束此处的代码块、参数列表或集合定义。
}

# ---------------------------------------------------------------- 7. R 堆疊差距
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '7. R 套件堆疊差距分析'
# 计算本行表达式并设置 $rscript，供后续步骤使用。
$rscript = $rsTool.Path
# 检查本行条件；满足时执行对应分支。
if (-not $rscript) {
    # 追加一项诊断发现。
    Add-Finding '注意' 'R' '找不到 Rscript，略過 R 套件分析。'
# 结束上一代码块并进入另一条件分支。
} elseif ($SkipRPackages) {
    # 向终端显示提示或结果。
    Write-Host '已略過 (-SkipRPackages / -Fast)'
# 结束上一代码块并进入另一条件分支。
} else {
    # 原文块第 1 行：计算本行表达式并设置 $rCode，供后续步骤使用。
    # 原文块第 2 行：读取 R 进程的环境变量，并保存到 out。
    # 原文块第 3 行：输出本行的状态信息或计算结果。
    # 原文块第 4 行：输出本行的状态信息或计算结果。
    # 原文块第 5 行：按本行的迭代范围或条件重复执行循环体。
    # 原文块第 6 行：输出本行的状态信息或计算结果。
    # 原文块第 7 行：输出本行的状态信息或计算结果。
    # 原文块第 8 行：读取 R 套件安装清单，并保存到 ip。
    # 原文块第 9 行：计算本行表达式并设置 inst，供后续步骤使用。
    # 原文块第 10 行：输出本行的状态信息或计算结果。
    # 原文块第 11 行：将表格写入 CSV 文件。
    # 原文块第 12 行：计算本行表达式并设置 stringsAsFactors，供后续步骤使用。
    # 原文块第 13 行：补充当前函数调用的命名参数。
    # 原文块第 14 行：构造或计算 groups，保存本行指定的集合或索引结果。
    # 原文块第 15 行：提供当前表达式所需的文本、字段名称或列表元素。
    # 原文块第 16 行：提供当前表达式所需的文本、字段名称或列表元素。
    # 原文块第 17 行：提供当前表达式所需的文本、字段名称或列表元素。
    # 原文块第 18 行：提供当前表达式所需的文本、字段名称或列表元素。
    # 原文块第 19 行：提供当前表达式所需的文本、字段名称或列表元素。
    # 原文块第 20 行：提供当前表达式所需的文本、字段名称或列表元素。
    # 原文块第 21 行：提供当前表达式所需的文本、字段名称或列表元素。
    # 原文块第 22 行：提供当前表达式所需的文本、字段名称或列表元素。
    # 原文块第 23 行：提供当前表达式所需的文本、字段名称或列表元素。
    # 原文块第 24 行：提供当前表达式所需的文本、字段名称或列表元素。
    # 原文块第 25 行：提供当前表达式所需的文本、字段名称或列表元素。
    # 原文块第 26 行：准备或执行 Python 套件管理操作。
    # 原文块第 27 行：结束此处的代码块、参数列表或集合定义。
    # 原文块第 28 行：计算本行表达式并设置 rows，供后续步骤使用。
    # 原文块第 29 行：构造或计算 pk，保存本行指定的集合或索引结果。
    # 原文块第 30 行：调用 data.frame，使用本行列出的输入完成对应操作。
    # 原文块第 31 行：计算本行表达式并设置 Missing，供后续步骤使用。
    # 原文块第 32 行：结束此处的代码块、参数列表或集合定义。
    # 原文块第 33 行：将表格写入 CSV 文件。
    # 原文块第 34 行：按本行的迭代范围或条件重复执行循环体。
    # 原文块第 35 行：输出本行的状态信息或计算结果。
    # 原文块第 36 行：结束此处的代码块、参数列表或集合定义。
    # 原文块第 37 行：输出本行的状态信息或计算结果。
    # 原文块第 38 行：提供当前表达式所需的文本、字段名称或列表元素。
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
  "03_bigdata"  = c("arrow", "duckdb", "fst", "qs2", "vroom", "nanoparquet"),
  "04_database" = c("DBI", "RSQLite", "odbc", "RPostgres", "RMariaDB", "dbplyr", "pool"),
  "05_timeser"  = c("xts", "zoo", "tsibble", "fable", "forecast", "TTR", "quantmod", "PerformanceAnalytics", "rugarch"),
  "06_model"    = c("tidymodels", "xgboost", "lightgbm", "ranger", "glmnet", "survival", "survminer", "grf", "depmixS4"),
  "07_explain"  = c("DALEX", "iml", "shapviz", "kernelshap", "pdp"),
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
    # 组合父目录与子路径，并保存到 $rFile。
    $rFile = Join-Path $OutDir '_diag_r.R'
    # 将内容写入目标文件。
    Set-Content -Path $rFile -Value $rCode -Encoding ASCII
    # 计算本行表达式并设置 $env:DIAG_OUT，供后续步骤使用。
    $env:DIAG_OUT = $OutDir
    # 构造或计算 $rOut，保存本行指定的集合或索引结果。
    $rOut = Invoke-Native $rscript @($rFile)
    # 处理 Save-Text 所指定的操作或当前表达式的后续部分。
    Save-Text $rOut '07_R_診斷.txt'
    # 向终端显示提示或结果。
    Write-Host $rOut
    # 移动或替换指定文件；删除指定路径下的项目。
    Remove-Item $rFile -Force -ErrorAction SilentlyContinue
    # 检查本行条件；满足时执行对应分支。
    if ($rOut -match 'TOTAL_MISSING:\s*(\d+)') {
        # 构造或计算 $miss，保存本行指定的集合或索引结果。
        $miss = [int]$Matches[1]
        # 检查本行条件；满足时执行对应分支。
        if ($miss -gt 0) {
            # 追加一项诊断发现。
            Add-Finding '警告' 'R' ('R 分析堆疊缺少 ' + $miss + ' 個關鍵套件（分組明細見 07_R_gap.csv）。')
            # 记录建议执行的后续操作。
            Add-Action '-SetupR'
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 检查本行条件；满足时执行对应分支。
    if ($rOut -match 'writable=FALSE' -and $rOut -notmatch 'writable=TRUE') {
        # 追加一项诊断发现。
        Add-Finding '嚴重' 'R' 'R 沒有任何可寫入的套件庫，安裝套件必定失敗。'
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ---------------------------------------------------------------- 8. Python 堆疊差距
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '8. Python 堆疊差距分析'
# 检查本行条件；满足时执行对应分支。
if ($SkipPython) {
    # 向终端显示提示或结果。
    Write-Host '已略過 (-SkipPython / -Fast)'
# 结束上一代码块并进入另一条件分支。
} else {
    # 计算本行表达式并设置 $pyExe，供后续步骤使用。
    $pyExe = $null
    # 构造或计算 $pyBase，保存本行指定的集合或索引结果。
    $pyBase = @()
    # 计算本行表达式并设置 $pl，供后续步骤使用。
    $pl = Find-Exe 'py'
    # 检查本行条件；满足时执行对应分支。
    if ($pl) { $pyExe = $pl; $pyBase = @('-3') }
    # 当前述条件不成立时执行此分支。
    else {
        # 查找当前环境可用的命令及其位置，并保存到 $pp。
        $pp = Get-Command python -ErrorAction SilentlyContinue |
            # 选取记录中的指定字段或条目；按条件筛选输入记录。
            Where-Object { $_.CommandType -eq 'Application' -and $_.Source -notlike '*\WindowsApps\*' } | Select-Object -First 1
        # 检查本行条件；满足时执行对应分支。
        if ($pp) { $pyExe = $pp.Source }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 检查本行条件；满足时执行对应分支。
    if (-not $pyExe) {
        # 追加一项诊断发现。
        Add-Finding '注意' 'Python' '找不到可用的 Python 直譯器（Store 別名不算）。'
    # 结束上一代码块并进入另一条件分支。
    } else {
        # 处理 Save-Text 所指定的操作或当前表达式的后续部分。
        Save-Text (Invoke-Native $pyExe @('-0p')) '08_python_版本清單.txt'
        # 构造或计算 $pyVer，保存本行指定的集合或索引结果。
        $pyVer = Invoke-Native $pyExe ($pyBase + @('-c', 'import sys;print(sys.version.split()[0])')) -StdoutOnly
        # 向终端显示提示或结果。
        Write-Host ('預設 Python：' + $pyVer + '  (' + $pyExe + ')')
        # 准备或执行 Python 套件管理操作，并保存到 $pipJson。
        $pipJson = Invoke-Native $pyExe ($pyBase + @('-m', 'pip', 'list', '--format=json')) -StdoutOnly
        # 构造或计算 $installed，保存本行指定的集合或索引结果。
        $installed = @()
        # 开始受异常处理保护的操作。
        try { $installed = ($pipJson | ConvertFrom-Json) | ForEach-Object { $_.name.ToLower() } } catch { }
        # 向终端显示提示或结果；准备或执行 Python 套件管理操作。
        Write-Host ('pip 套件數：' + @($installed).Count)
        # 准备或执行 Python 套件管理操作。
        Save-Text $pipJson '08_pip_已安裝.json'

        # 构造或计算 $pyGroups，保存本行指定的集合或索引结果。
        $pyGroups = [ordered]@{
            # 不把 uv / pip 列進來：uv 是獨立執行檔（已在第 6 節的工具鏈盤點），
            # 而 uv 建立的 venv 刻意不安裝 pip。把它們當成「缺的套件」是誤報。
            # 提供当前表达式所需的文本、字段名称或列表元素。
            '01_env'      = @('ruff', 'pytest')
            # 提供当前表达式所需的文本、字段名称或列表元素。
            '02_wrangle'  = @('pandas', 'polars', 'numpy', 'pyarrow', 'duckdb')
            # 提供当前表达式所需的文本、字段名称或列表元素。
            '03_database' = @('sqlalchemy', 'psycopg', 'pymysql', 'clickhouse-connect', 'pyodbc')
            # 提供当前表达式所需的文本、字段名称或列表元素。
            '04_model'    = @('scikit-learn', 'xgboost', 'lightgbm', 'statsmodels', 'scipy')
            # 提供当前表达式所需的文本、字段名称或列表元素。
            '05_explain'  = @('shap', 'lime')
            # 提供当前表达式所需的文本、字段名称或列表元素。
            '06_survival' = @('lifelines', 'scikit-survival', 'econml', 'dowhy')
            # 提供当前表达式所需的文本、字段名称或列表元素。
            '07_viz'      = @('matplotlib', 'plotly', 'seaborn', 'great-tables')
            # 提供当前表达式所需的文本、字段名称或列表元素。
            '08_notebook' = @('jupyterlab', 'ipykernel', 'nbclient', 'papermill')
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 构造或计算 $pyRows，保存本行指定的集合或索引结果。
        $pyRows = @()
        # 计算本行表达式并设置 $pyMiss，供后续步骤使用。
        $pyMiss = 0
        # 按本行的迭代范围或条件重复执行循环体。
        foreach ($g in $pyGroups.Keys) {
            # 构造或计算 $pk，保存本行指定的集合或索引结果。
            $pk = $pyGroups[$g]
            # 按条件筛选输入记录，并保存到 $have。
            $have = @($pk | Where-Object { $installed -contains $_.ToLower() })
            # 按条件筛选输入记录，并保存到 $missing。
            $missing = @($pk | Where-Object { $installed -notcontains $_.ToLower() })
            # 计算本行表达式并设置 $pyMiss，供后续步骤使用。
            $pyMiss += $missing.Count
            # 构造或计算 $pyRows，保存本行指定的集合或索引结果。
            $pyRows += [pscustomobject]@{ Group = $g; Total = $pk.Count; Have = $have.Count; Missing = ($missing -join ' ') }
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 处理 Show-Table 所指定的操作或当前表达式的后续部分。
        Show-Table $pyRows
        # 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
        Save-Csv $pyRows '08_Python_堆疊差距.csv'

        # 只看全域直譯器會嚴重誤判：正確做法就是把套件裝在專案環境裡，
        # 所以全域「缺一堆套件」往往代表做對了，而不是做錯了。
        # 這裡把工作區裡的虛擬環境一併納入，再決定要不要示警。
        # 构造或计算 $venvRoots，保存本行指定的集合或索引结果。
        $venvRoots = @("$WorkRoot\envs", "$env:USERPROFILE\.virtualenvs")
        # 构造或计算 $venvPys，保存本行指定的集合或索引结果。
        $venvPys = @()
        # 按本行的迭代范围或条件重复执行循环体。
        foreach ($r in $venvRoots) {
            # 检查本行条件；满足时执行对应分支。
            if (-not (Test-Path -LiteralPath $r)) { continue }
            # 枚举指定位置的文件、目录或注册表项，并保存到 $venvPys。
            $venvPys += @(Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue |
                    # 组合父目录与子路径；逐项处理管道传入的记录。
                    ForEach-Object { Join-Path $_.FullName 'Scripts\python.exe' } |
                    # 检查目标路径是否存在；按条件筛选输入记录。
                    Where-Object { Test-Path -LiteralPath $_ })
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 计算本行表达式并设置 $bestMiss，供后续步骤使用。
        $bestMiss = $pyMiss
        # 计算本行表达式并设置 $bestName，供后续步骤使用。
        $bestName = '全域直譯器'
        # uv 建立的 venv 預設「不安裝 pip」——uv 自己管套件。
        # 所以不能用 python -m pip list 去問，那會回空清單，把完整環境誤報成空環境。
        # 改用標準庫的 importlib.metadata，對 pip / uv / venv 一律有效。
        # 刻意不在這段 Python 裡用任何引號：Windows PowerShell 5.1 把參數傳給原生程式時
        # 會把內嵌的引號吃掉，d.metadata["Name"] 會變成 d.metadata[Name] 而拋 NameError。
        # d.name 是 Python 3.10+ 的等效屬性，不需要引號。
        # 将结果序列化为 JSON 文本，并保存到 $listCode。
        $listCode = 'import json,importlib.metadata as m;print(json.dumps([d.name for d in m.distributions() if d.name]))'
        # 按本行的迭代范围或条件重复执行循环体。
        foreach ($vp in $venvPys) {
            # 构造或计算 $vjson，保存本行指定的集合或索引结果。
            $vjson = Invoke-Native $vp @('-c', $listCode) -StdoutOnly
            # 构造或计算 $vinst，保存本行指定的集合或索引结果。
            $vinst = @()
            # 开始受异常处理保护的操作。
            try { $vinst = ($vjson | ConvertFrom-Json) | ForEach-Object { "$_".ToLower() } } catch { }
            # 计算本行表达式并设置 $vmiss，供后续步骤使用。
            $vmiss = 0
            # 构造或计算 $vrows，保存本行指定的集合或索引结果。
            $vrows = @()
            # 按本行的迭代范围或条件重复执行循环体。
            foreach ($g in $pyGroups.Keys) {
                # 构造或计算 $pk，保存本行指定的集合或索引结果。
                $pk = $pyGroups[$g]
                # 按条件筛选输入记录，并保存到 $mm。
                $mm = @($pk | Where-Object { $vinst -notcontains $_.ToLower() })
                # 计算本行表达式并设置 $vmiss，供后续步骤使用。
                $vmiss += $mm.Count
                # 构造或计算 $vrows，保存本行指定的集合或索引结果。
                $vrows += [pscustomobject]@{ Env = $vp; Group = $g; Total = $pk.Count; Have = ($pk.Count - $mm.Count); Missing = ($mm -join ' ') }
            # 结束此处的代码块、参数列表或集合定义。
            }
            # 向终端显示提示或结果。
            Write-Host ('虛擬環境 ' + $vp + '：' + @($vinst).Count + ' 套件，關鍵套件缺 ' + $vmiss + ' 個')
            # 提取路径中的指定部分。
            Save-Csv $vrows ('08_Python_堆疊差距_' + (Split-Path (Split-Path $vp -Parent) -Leaf) + '.csv')
            # 检查本行条件；满足时执行对应分支。
            if ($vmiss -lt $bestMiss) { $bestMiss = $vmiss; $bestName = $vp }
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 检查本行条件；满足时执行对应分支。
        if ($bestMiss -gt 0) {
            # 追加一项诊断发现。
            Add-Finding '警告' 'Python' ('最完整的 Python 環境（' + $bestName + '）仍缺少 ' + $bestMiss + ' 個關鍵套件（見 08_Python_堆疊差距*.csv）。')
            # 记录建议执行的后续操作。
            Add-Action '-SetupPython'
        # 结束上一代码块并进入另一条件分支。
        } else {
            # 追加一项诊断发现。
            Add-Finding '資訊' 'Python' ('分析堆疊完整的環境：' + $bestName + '。全域直譯器缺 ' + $pyMiss + ' 個套件是正常且正確的——套件本來就該待在專案環境裡。')
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 检查本行条件；满足时执行对应分支。
        if ($pyVer -match '^3\.(1[4-9]|2\d)') {
            # 追加一项诊断发现。
            Add-Finding '注意' 'Python' ('目前預設 Python 為 ' + $pyVer + '。最新版常有部分科學計算套件尚未提供 Windows wheel，只能退回原始碼編譯（本機沒有 C++ 編譯器就會失敗）。建議「工作用」環境鎖在次新的穩定版（3.13 或 3.12），由 uv 管理，與系統 Python 並存。')
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 检查本行条件；满足时执行对应分支。
        if (@($installed).Count -le 3) {
            # 追加一项诊断发现。
            Add-Finding '資訊' 'Python' '全域 Python 幾乎是空的——這其實是好事。請維持全域乾淨，所有專案套件都放在 uv / venv 專案環境裡，避免日後的依賴地獄。'
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 构造或计算 $uvPath，保存本行指定的集合或索引结果。
    $uvPath = Find-Exe 'uv' @("$env:USERPROFILE\.local\bin\uv.exe")
    # 检查本行条件；满足时执行对应分支。
    if ($uvPath) {
        # 处理 Save-Text 所指定的操作或当前表达式的后续部分。
        Save-Text (Invoke-Native $uvPath @('python', 'list')) '08_uv_可用版本.txt'
        # 准备或执行 Python 套件管理操作；追加一项诊断发现。
        Add-Finding '資訊' 'Python' ('已安裝 uv (' + $uvPath + ')。這是目前 Windows 上建立可重現 Python 環境最快的工具，建議一律用 uv 而非全域 pip install。')
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ---------------------------------------------------------------- 9. ODBC
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '9. ODBC 驅動'
# 构造或计算 $odbc，保存本行指定的集合或索引结果。
$odbc = @()
# 开始受异常处理保护的操作。
try { $odbc = Get-OdbcDriver -ErrorAction Stop | Select-Object Name, Platform } catch { }
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $odbc '09_ODBC驅動.csv'
# 逐项处理管道传入的记录，并保存到 $odbcNames。
$odbcNames = (($odbc | ForEach-Object { $_.Name }) -join ' | ')
# 向终端显示提示或结果。
Write-Host ('ODBC 驅動數：' + @($odbc).Count)
# 构造或计算 $wantOdbc，保存本行指定的集合或索引结果。
$wantOdbc = [ordered]@{
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'PostgreSQL'            = 'PostgreSQL'
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'MySQL/StarRocks/Doris' = 'MySQL'
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'ClickHouse'            = 'ClickHouse'
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'SQLite'                = 'SQLite'
# 结束此处的代码块、参数列表或集合定义。
}
# 构造或计算 $odbcMissing，保存本行指定的集合或索引结果。
$odbcMissing = @()
# 按本行的迭代范围或条件重复执行循环体。
foreach ($k in $wantOdbc.Keys) { if ($odbcNames -notmatch $wantOdbc[$k]) { $odbcMissing += $k } }
# 检查本行条件；满足时执行对应分支。
if ($odbcMissing.Count -gt 0) {
    # 追加一项诊断发现。
    Add-Finding '資訊' '資料庫' ('未安裝以下 ODBC 驅動：' + ($odbcMissing -join ', ') + '。若要用 R 的 odbc/DBI 或 Python 的 pyodbc 直連倉庫（StarRocks / Doris 走 MySQL 協定），需要先裝對應驅動。')
    # 记录建议执行的后续操作。
    Add-Action '-InstallODBC'
# 结束此处的代码块、参数列表或集合定义。
}

# ---------------------------------------------------------------- 10. Git 設定
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '10. Git 設定'
# 按条件筛选输入记录，并保存到 $gitExe。
$gitExe = ($tools | Where-Object { $_.Tool -eq 'git' }).Path
# 检查本行条件；满足时执行对应分支。
if ($gitExe) {
    # 构造或计算 $gcfg，保存本行指定的集合或索引结果。
    $gcfg = Invoke-Native $gitExe @('config', '--global', '--list')
    # 处理 Save-Text 所指定的操作或当前表达式的后续部分。
    Save-Text $gcfg '10_git設定.txt'
    # 向终端显示提示或结果。
    Write-Host $gcfg
    # 检查本行条件；满足时执行对应分支。
    if ($gcfg -notmatch 'core\.longpaths=true') { Add-Finding '注意' 'Git' 'git 未設定 core.longpaths=true，長路徑的 checkout 會失敗。'; Add-Action '-ConfigureGit' }
    # 检查本行条件；满足时执行对应分支。
    if ($gcfg -notmatch 'core\.autocrlf') { Add-Finding '注意' 'Git' 'git 未設定 core.autocrlf。Windows 與 Linux/容器混用時，CRLF 會造成整檔 diff 與腳本在 Linux 上執行異常。'; Add-Action '-ConfigureGit' }
    # 检查本行条件；满足时执行对应分支。
    if ($gcfg -notmatch 'credential\.helper') { Add-Finding '資訊' 'Git' 'git 未設定 credential.helper（建議 manager）。'; Add-Action '-ConfigureGit' }
    # 检查本行条件；满足时执行对应分支。
    if ($gcfg -match 'filter\.lfs') { Add-Finding '資訊' 'Git' '已啟用 Git LFS。放大型資料集（Parquet/CSV）時請務必走 LFS，或乾脆不進版控。' }
# 结束上一代码块并进入另一条件分支。
} else {
    # 追加一项诊断发现。
    Add-Finding '注意' 'Git' '找不到 git。'
# 结束此处的代码块、参数列表或集合定义。
}

# ---------------------------------------------------------------- 11. winget
# 检查本行条件；满足时执行对应分支。
if (-not $SkipWinget) {
    # 调用 WinGet 执行本行指定的软件管理操作。
    Section '11. winget 可升級'
    # 调用 WinGet 执行本行指定的软件管理操作，并保存到 $wg。
    $wg = Find-Exe 'winget'
    # 检查本行条件；满足时执行对应分支。
    if ($wg) {
        # 构造或计算 $up，保存本行指定的集合或索引结果。
        $up = Invoke-Native $wg @('upgrade', '--accept-source-agreements')
        # 调用 WinGet 执行本行指定的软件管理操作。
        Save-Text $up '11_winget_可升級.txt'
        # 向终端显示提示或结果。
        Write-Host $up
        # 检查本行条件；满足时执行对应分支。
        if ($up -match '(升級可用|upgrades available|可升级)') {
            # 调用 WinGet 执行本行指定的软件管理操作；追加一项诊断发现。
            Add-Finding '注意' '軟體' 'winget 回報有可升級軟體（見 11_winget_可升級.txt）。'
            # 记录建议执行的后续操作。
            Add-Action '-UpdateApps'
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束上一代码块并进入另一条件分支。
    } else { Add-Finding '注意' '軟體' '找不到 winget。' }
# 结束此处的代码块、参数列表或集合定义。
}

# ---------------------------------------------------------------- 12. 啟動項目
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '12. 啟動項目'
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目，并保存到 $startup。
$startup = Get-CimInstance Win32_StartupCommand | Select-Object Name, Location, Command
# 选取记录中的指定字段或条目。
Show-Table ($startup | Select-Object Name, Location)
# 处理 Save-Csv 所指定的操作或当前表达式的后续部分。
Save-Csv $startup '12_啟動項目.csv'
# 检查本行条件；满足时执行对应分支。
if (@($startup).Count -gt 12) { Add-Finding '注意' '效能' ('啟動項目 ' + @($startup).Count + ' 筆，開機後會長時間搶 CPU 與磁碟。') }

# ---------------------------------------------------------------- 摘要
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '摘要'
# 计算本行表达式并设置 $order，供后续步骤使用。
$order = @{ '嚴重' = 0; '警告' = 1; '注意' = 2; '資訊' = 3 }
# 按指定属性排序输入记录，并保存到 $sorted。
$sorted = $script:Findings | Sort-Object { $order[$_.Level] }, Area
# 创建指定类型的对象，并保存到 $sb。
$sb = New-Object System.Text.StringBuilder
# 生成当前时间或格式化时间戳；向报告缓冲区追加一行文本。
[void]$sb.AppendLine('Windows 10 資料分析工作站診斷 v2   ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('主機：' + $env:COMPUTERNAME + '   ' + $os.Caption + ' ' + $dispVer + ' (Build ' + $build + ')')
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('CPU：' + $cpu.Name + '  ' + $cpu.NumberOfCores + 'C/' + $cpu.NumberOfLogicalProcessors + 'T    RAM：' + $ramGB + ' GB')
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('管理員身分：' + $isAdmin)
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('')
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('--- 發現 (' + @($sorted).Count + ') ---')
# 按本行的迭代范围或条件重复执行循环体。
foreach ($f in $sorted) { [void]$sb.AppendLine('[' + $f.Level + '] ' + $f.Area + ' - ' + $f.Message) }
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('')
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('--- 工具鏈 ---')
# 把结果排版成表格；把结果转换为文本；向报告缓冲区追加一行文本。
[void]$sb.AppendLine((($tools | Format-Table Tool, Found, OnPATH, Version -AutoSize | Out-String -Width 240).TrimEnd()))
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

# 创建指定类型的对象，并保存到 $ab。
$ab = New-Object System.Text.StringBuilder
# 向报告缓冲区追加一行文本。
[void]$ab.AppendLine('# 根據本次診斷，建議用 Setup_DataStack.ps1 執行的開關')
# 向报告缓冲区追加一行文本。
[void]$ab.AppendLine('# 第一次一律先加 -WhatIf 預演，確認沒問題再拿掉。')
# 向报告缓冲区追加一行文本。
[void]$ab.AppendLine('')
# 构造或计算 $adminSwitches，保存本行指定的集合或索引结果。
$adminSwitches = @('-EnableLongPaths', '-SetPageFile', '-AddDefenderExclusions')
# 检查本行条件；满足时执行对应分支。
if ($script:Actions.Count -eq 0) {
    # 向报告缓冲区追加一行文本。
    [void]$ab.AppendLine('# 沒有偵測到需要處理的項目。')
# 结束上一代码块并进入另一条件分支。
} else {
    # 向报告缓冲区追加一行文本。
    [void]$ab.AppendLine('# --- 一般使用者身分 ---')
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($a in $script:Actions) { if ($adminSwitches -notcontains $a) { [void]$ab.AppendLine('.\Setup_DataStack.ps1 ' + $a + ' -WhatIf') } }
    # 向报告缓冲区追加一行文本。
    [void]$ab.AppendLine('')
    # 向报告缓冲区追加一行文本。
    [void]$ab.AppendLine('# --- 需要系統管理員身分 ---')
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($a in $script:Actions) { if ($adminSwitches -contains $a) { [void]$ab.AppendLine('.\Setup_DataStack.ps1 ' + $a + ' -WhatIf') } }
# 结束此处的代码块、参数列表或集合定义。
}
# 组合父目录与子路径；将内容写入目标文件。
Set-Content -Path (Join-Path $OutDir '99_建議指令.txt') -Value $ab.ToString() -Encoding UTF8
# 向终端显示提示或结果。
Write-Host ''
# 向终端显示提示或结果。
Write-Host ($ab.ToString()) -ForegroundColor Yellow
# 向终端显示提示或结果。
Write-Host ('完成。報告位置：' + $OutDir) -ForegroundColor Green
# 向终端显示提示或结果。
Write-Host '提醒：報告內含電腦名稱、使用者名稱、已安裝軟體與管控代理清單，分享前請自行檢視。' -ForegroundColor Yellow
