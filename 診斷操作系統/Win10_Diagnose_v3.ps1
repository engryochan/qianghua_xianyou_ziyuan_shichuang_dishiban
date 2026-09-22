#Requires -Version 5.1
<#
.SYNOPSIS
Windows 10/11 與資料分析工具鏈的唯讀、離線盤點。
.DESCRIPTION
只寫入報告資料夾。不安裝/更新套件、不變更系統、不讀取金鑰、完整環境變數、Git 憑證或程式命令列。
各 CIM/PowerShell 探測在獨立 Windows PowerShell 5.1 子行程內執行，設有逾時。
缺少權限或工具時明確記錄 Unknown/Unavailable，不把失敗當成沒有問題。
Python/R 套件來自已發現直譯器；不遞迴搜尋整顆磁碟或執行使用者啟動設定。
隱私：報告仍含已安裝軟體與本機路徑，分享前請檢視。
.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Win10_Diagnose_v3.ps1 -OutputDirectory .\reports
#>
# 启用 PowerShell 高级脚本参数绑定及所列功能。
[CmdletBinding()]
# 声明脚本或函数接受的参数及默认值。
param(
    # 生成当前时间或格式化时间戳；组合父目录与子路径。
    [Alias('OutDir')][string]$OutputDirectory = (Join-Path $PSScriptRoot ('reports\diagnostics-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))),
    # 声明参数 $ProbeTimeoutSeconds的类型、默认值或校验规则。
    [ValidateRange(10,180)][int]$ProbeTimeoutSeconds = 35,
    # 声明参数 $MaxInterpreters的类型、默认值或校验规则。
    [ValidateRange(1,24)][int]$MaxInterpreters = 8,
    # 声明参数 $AdditionalPythonPaths的类型、默认值或校验规则。
    [string[]]$AdditionalPythonPaths = @(),
    # 声明参数 $AdditionalRPaths的类型、默认值或校验规则。
    [string[]]$AdditionalRPaths = @(),
    # 声明参数 $SkipPackages的类型、默认值或校验规则。
    [switch]$SkipPackages,
    # 声明参数 $SkipEvents的类型、默认值或校验规则。
    [switch]$SkipEvents
# 结束此处的代码块、参数列表或集合定义。
)
# 设置本脚本遇到 PowerShell 错误时的处理方式。
$ErrorActionPreference = 'Stop'
# 组合父目录与子路径，并保存到 $script:PowerShellExe。
$script:PowerShellExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
# 检查本行条件；满足时执行对应分支。
if (-not (Test-Path -LiteralPath $script:PowerShellExe)) { throw '此腳本需要 Windows PowerShell 5.1。' }
# 构造或计算 $OutputDirectory，保存本行指定的集合或索引结果。
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
# 创建指定目录、文件或配置项；将不需要的返回值丢弃。
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
# 创建指定类型的对象，并保存到 $script:Status。
$script:Status = New-Object System.Collections.Generic.List[object]
# 创建指定类型的对象，并保存到 $script:Findings。
$script:Findings = New-Object System.Collections.Generic.List[object]
# 构造或计算 $script:Data，保存本行指定的集合或索引结果。
$script:Data = [ordered]@{}
# 创建指定类型的对象，并保存到 $script:Utf8。
$script:Utf8 = New-Object Text.UTF8Encoding($true)

# 定义 Write-JsonFile，封装此函数内的操作。
function Write-JsonFile { param($Value,[string]$Name)
    # 组合父目录与子路径；把对象序列化为 JSON；将文本写入指定文件。
    [IO.File]::WriteAllText((Join-Path $OutputDirectory $Name), (ConvertTo-Json -InputObject $Value -Depth 16), $script:Utf8)
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Save-Data，封装此函数内的操作。
function Save-Data { param([string]$Name,$Value)
    # 按条件筛选输入记录，并保存到 $rows。
    $rows = @($Value | Where-Object { $null -ne $_ })
    # 构造或计算 $script:Data[$Name]，保存本行指定的集合或索引结果。
    $script:Data[$Name] = $rows
    # 处理 Write-JsonFile 所指定的操作或当前表达式的后续部分。
    Write-JsonFile -Value $rows -Name ($Name + '.json')
    # 检查本行条件；满足时执行对应分支。
    if ($rows.Count -gt 0) { $rows | Export-Csv -LiteralPath (Join-Path $OutputDirectory ($Name + '.csv')) -NoTypeInformation -Encoding UTF8 }
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Add-Status，封装此函数内的操作。
function Add-Status { param([string]$Probe,[string]$State,[string]$Detail,[double]$Seconds=0)
    # 调用 $script:Status.Add，使用本行列出的输入完成对应操作。
    $script:Status.Add([pscustomobject]@{Probe=$Probe;Status=$State;Detail=$Detail;Seconds=[math]::Round($Seconds,2)})
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Add-Finding，封装此函数内的操作。
function Add-Finding { param([string]$Level,[string]$Area,[string]$Message)
    # 调用 $script:Findings.Add，使用本行列出的输入完成对应操作。
    $script:Findings.Add([pscustomobject]@{Level=$Level;Area=$Area;Message=$Message})
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 ConvertTo-NativeArgument，封装此函数内的操作。
function ConvertTo-NativeArgument { param([AllowEmptyString()][string]$Value)
    # Windows CommandLineToArgvW quoting; never interpolate arguments into a shell.
    # 检查本行条件；满足时执行对应分支。
    if ($Value -notmatch '[\s"]' -and $Value.Length -gt 0) { return $Value }
    # 返回本行结果并结束当前函数。
    return '"' + ([regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1')) + '"'
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Invoke-BoundedProcess，封装此函数内的操作。
function Invoke-BoundedProcess {
    # 声明脚本或函数接受的参数及默认值。
    param([string]$FilePath,[string[]]$ArgumentList=@(),[int]$TimeoutSeconds=$ProbeTimeoutSeconds)
    # 构造或计算 $watch，保存本行指定的集合或索引结果。
    $watch = [Diagnostics.Stopwatch]::StartNew()
    # 创建指定类型的对象，并保存到 $process。
    $process = New-Object Diagnostics.Process
    # 开始受异常处理保护的操作。
    try {
        # 创建指定类型的对象，并保存到 $info。
        $info = New-Object Diagnostics.ProcessStartInfo
        # 计算本行表达式并设置 $info.FileName，供后续步骤使用。
        $info.FileName = $FilePath
        # 逐项处理管道传入的记录，并保存到 $info.Arguments。
        $info.Arguments = (($ArgumentList | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
        # 计算本行表达式并设置 $info.UseShellExecute，供后续步骤使用。
        $info.UseShellExecute = $false; $info.CreateNoWindow = $true
        # 计算本行表达式并设置 $info.RedirectStandardOutput，供后续步骤使用。
        $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
        # 创建指定类型的对象，并保存到 $info.StandardOutputEncoding。
        $info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
        # 创建指定类型的对象，并保存到 $info.StandardErrorEncoding。
        $info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
        # 计算本行表达式并设置 $info.WorkingDirectory，供后续步骤使用。
        $info.WorkingDirectory = $OutputDirectory
        # 构造或计算 $info.EnvironmentVariables['PYTHONDONTWRITEBYTECODE']，保存本行指定的集合或索引结果。
        $info.EnvironmentVariables['PYTHONDONTWRITEBYTECODE'] = '1'
        # 构造或计算 $info.EnvironmentVariables['PYTHONUTF8']，保存本行指定的集合或索引结果。
        $info.EnvironmentVariables['PYTHONUTF8'] = '1'
        # 构造或计算 $info.EnvironmentVariables['PYTHONIOENCODING']，保存本行指定的集合或索引结果。
        $info.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
        # 准备或执行 Python 套件管理操作，并保存到 $info.EnvironmentVariables['PIP_DISABLE_PIP_VERSION_CHECK']。
        $info.EnvironmentVariables['PIP_DISABLE_PIP_VERSION_CHECK'] = '1'
        # 检查本行条件；满足时执行对应分支。
        if ($FilePath -eq $script:PowerShellExe) {
            # A pwsh parent can pass incompatible PS7 modules to Windows PowerShell.
            # 构造或计算 $info.EnvironmentVariables['PSModulePath']，保存本行指定的集合或索引结果。
            $info.EnvironmentVariables['PSModulePath'] = "$env:WINDIR\System32\WindowsPowerShell\v1.0\Modules;$env:ProgramFiles\WindowsPowerShell\Modules"
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 计算本行表达式并设置 $process.StartInfo，供后续步骤使用。
        $process.StartInfo = $info
        # 调用 $process.Start，使用本行列出的输入完成对应操作；将不需要的返回值丢弃。
        $null = $process.Start()
        # 构造或计算 $outTask，保存本行指定的集合或索引结果。
        $outTask = $process.StandardOutput.ReadToEndAsync()
        # 构造或计算 $errTask，保存本行指定的集合或索引结果。
        $errTask = $process.StandardError.ReadToEndAsync()
        # 检查本行条件；满足时执行对应分支。
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            # Only the diagnostic child PID and descendants are terminated.
            # 创建指定类型的对象，并保存到 $killer。
            $killer = New-Object Diagnostics.Process
            # 开始受异常处理保护的操作。
            try {
                # 创建指定类型的对象，并保存到 $killer.StartInfo。
                $killer.StartInfo = New-Object Diagnostics.ProcessStartInfo
                # 组合父目录与子路径，并保存到 $killer.StartInfo.FileName。
                $killer.StartInfo.FileName = Join-Path $env:WINDIR 'System32\taskkill.exe'
                # 计算本行表达式并设置 $killer.StartInfo.Arguments，供后续步骤使用。
                $killer.StartInfo.Arguments = '/PID ' + $process.Id + ' /T /F'
                # 计算本行表达式并设置 $killer.StartInfo.UseShellExecute，供后续步骤使用。
                $killer.StartInfo.UseShellExecute = $false; $killer.StartInfo.CreateNoWindow = $true
                # 计算本行表达式并设置 $killer.StartInfo.RedirectStandardOutput，供后续步骤使用。
                $killer.StartInfo.RedirectStandardOutput = $true; $killer.StartInfo.RedirectStandardError = $true
                # 等待子进程结束或到达指定时限；将不需要的返回值丢弃。
                $null = $killer.Start(); $null = $killer.WaitForExit(5000)
                # 检查本行条件；满足时执行对应分支。
                if (-not $process.HasExited) { $process.Kill() }
            # 结束上一代码块并进入必定执行的资源清理。
            } finally { $killer.Dispose() }
            # 返回本行结果并结束当前函数。
            return [pscustomobject]@{State='Timeout';ExitCode=$null;Stdout='';Stderr='已超過探測時限；不代表資料不存在。';Seconds=$watch.Elapsed.TotalSeconds}
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 检查本行条件；满足时执行对应分支。
        if (-not $outTask.Wait(5000) -or -not $errTask.Wait(5000)) { throw '子行程輸出未能在時限內關閉。' }
        # 返回本行结果并结束当前函数。
        return [pscustomobject]@{State='Completed';ExitCode=$process.ExitCode;Stdout=$outTask.Result;Stderr=$errTask.Result;Seconds=$watch.Elapsed.TotalSeconds}
    # 结束上一代码块并进入异常处理。
    } catch {
        # 返回本行结果并结束当前函数。
        return [pscustomobject]@{State='Unavailable';ExitCode=$null;Stdout='';Stderr=$_.Exception.Message;Seconds=$watch.Elapsed.TotalSeconds}
    # 结束上一代码块并进入必定执行的资源清理。
    } finally { $process.Dispose() }
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Invoke-Probe，封装此函数内的操作。
function Invoke-Probe { param([string]$Name,[scriptblock]$Body,[int]$TimeoutSeconds=$ProbeTimeoutSeconds)
    # 向终端显示提示或结果。
    Write-Host ('盤點：' + $Name)
    # 原文块第 1 行：计算本行表达式并设置 $code，供后续步骤使用。
    # 原文块第 2 行：设置本脚本遇到 PowerShell 错误时的处理方式。
    # 原文块第 3 行：计算本行表达式并设置 $ProgressPreference，供后续步骤使用。
    # 原文块第 4 行：创建指定类型的对象。
    # 原文块第 5 行：开始受异常处理保护的操作。
    # 原文块第 6 行：构造或计算 $items，保存本行指定的集合或索引结果。
    # 原文块第 7 行：提供当前表达式所需的文本、字段名称或列表元素。
    # 原文块第 9 行：结束此处的代码块、参数列表或集合定义。
    # 原文块第 10 行：把本行列出的字段组成结构化记录，并按后续管道保存或输出。
    # 原文块第 11 行：结束上一代码块并进入异常处理。
    # 原文块第 12 行：把本行列出的字段组成结构化记录，并按后续管道保存或输出。
    # 原文块第 13 行：结束此处的代码块、参数列表或集合定义。
    # 原文块第 14 行：提供当前表达式所需的文本、字段名称或列表元素。
    $code = @'
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
try {
  $items = @(& {
'@ + $Body.ToString() + @'

  })
  [pscustomobject]@{Success=$true;Data=$items;Error=$null} | ConvertTo-Json -Depth 14 -Compress
} catch {
  [pscustomobject]@{Success=$false;Data=@();Error=$_.Exception.Message} | ConvertTo-Json -Depth 5 -Compress
}
'@
    # 构造或计算 $encoded，保存本行指定的集合或索引结果。
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    # 构造或计算 $result，保存本行指定的集合或索引结果。
    $result = Invoke-BoundedProcess $script:PowerShellExe @('-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',$encoded) $TimeoutSeconds
    # 检查本行条件；满足时执行对应分支。
    if ($result.State -ne 'Completed') { Add-Status $Name $result.State $result.Stderr $result.Seconds; Save-Data $Name @(); return }
    # 开始受异常处理保护的操作。
    try {
        # 把 JSON 文本解析为对象，并保存到 $envelope。
        $envelope = $result.Stdout.Trim() | ConvertFrom-Json
        # 检查本行条件；满足时执行对应分支。
        if (-not $envelope.Success) { throw [string]$envelope.Error }
        # 记录探测步骤的状态及耗时。
        Add-Status $Name 'OK' ('已讀取 ' + @($envelope.Data).Count + ' 筆；空清單只代表此探測沒有回傳項目。') $result.Seconds
        # 将探测结果保存到报告目录。
        Save-Data $Name @($envelope.Data)
    # 结束上一代码块并进入异常处理。
    } catch { Add-Status $Name 'Unavailable' $_.Exception.Message $result.Seconds; Save-Data $Name @() }
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Invoke-Tool，封装此函数内的操作。
function Invoke-Tool { param([string]$Name,[string]$Path,[string[]]$Arguments)
    # 检查本行条件；满足时执行对应分支。
    if (-not $Path) { Add-Status $Name 'Unavailable' '在 PATH 與限定的安裝位置未發現。'; return $null }
    # 检查本行条件；满足时执行对应分支。
    if ([IO.Path]::GetExtension($Path) -in @('.cmd','.bat')) {
        # 把对象序列化为 JSON，并保存到 $payload。
        $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json @{Path=$Path;Args=$Arguments} -Compress)))
        # 把 JSON 文本解析为对象；创建指定类型的对象，并保存到 $cmd。
        $cmd = '[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false); $p=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+$payload+''')) | ConvertFrom-Json; $a=@($p.Args); & $p.Path @a; exit $LASTEXITCODE'
        # 构造或计算 $result，保存本行指定的集合或索引结果。
        $result = Invoke-BoundedProcess $script:PowerShellExe @('-NoProfile','-NonInteractive','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd)))
    # 结束上一代码块并进入另一条件分支。
    } else { $result = Invoke-BoundedProcess $Path $Arguments }
    # 计算本行表达式并设置 $state，供后续步骤使用。
    $state = $result.State
    # 检查本行条件；满足时执行对应分支。
    if ($state -eq 'Completed') { if ($result.ExitCode -eq 0) { $state='OK' } else { $state='Failed' } }
    # 将上一操作的退出状态记录到 $detail。
    $detail = 'ExitCode=' + $result.ExitCode
    # 检查本行条件；满足时执行对应分支。
    if ($state -ne 'OK') { $detail += '; ' + ($result.Stderr -replace '[\r\n]+',' ') }
    # 检查本行条件；满足时执行对应分支。
    if ($detail.Length -gt 700) { $detail = $detail.Substring(0,700) }
    # 记录探测步骤的状态及耗时。
    Add-Status $Name $state $detail $result.Seconds
    # 返回本行结果并结束当前函数。
    return $result
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Find-Executables，封装此函数内的操作。
function Find-Executables { param([string[]]$Names,[string[]]$Patterns=@())
    # 构造或计算 $candidates，保存本行指定的集合或索引结果。
    $candidates = @()
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($name in $Names) { $candidates += @(Get-Command $name -CommandType Application -All -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source) }
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($pattern in $Patterns) { if ($pattern) { $candidates += @(Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName) } }
    # AppExecutionAlias Python stubs can open the Store. Versioned real Store packages are found through registration instead.
    # 选取记录中的指定字段或条目；按条件筛选输入记录。
    @($candidates | Where-Object { $_ -and $_ -notmatch '\\Microsoft\\WindowsApps\\(python[0-9.]*|py)\.exe$' } | Select-Object -Unique)
# 结束此处的代码块、参数列表或集合定义。
}

# 构造或计算 $identity，保存本行指定的集合或索引结果。
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
# 创建指定类型的对象；检查当前身份是否具有指定权限角色，并保存到 $isAdmin。
$isAdmin = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# 生成当前时间或格式化时间戳；将探测结果保存到报告目录。
Save-Data '00_metadata' ([pscustomobject]@{SchemaVersion='3.0';CollectedAt=(Get-Date).ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();IsAdministrator=$isAdmin;Mode='OfflineReadOnly';ProbeTimeoutSeconds=$ProbeTimeoutSeconds;MaxInterpreters=$MaxInterpreters;Scope='Machine software + current user; no other user hives, recursive disk scan, network update check, secrets or command arguments'})

# 运行有时间限制的诊断探测。
Invoke-Probe '01_system' {
    # 查询 Windows 管理接口中的设备或系统信息，并保存到 $os。
    $os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 15
    # 查询 Windows 管理接口中的设备或系统信息，并保存到 $cs。
    $cs=Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 15
    # 读取注册表或对象的属性，并保存到 $cv。
    $cv=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    # 把本行列出的字段组成结构化记录。
    [pscustomobject]@{Caption=$os.Caption;EditionID=$cv.EditionID;DisplayVersion=$cv.DisplayVersion;Build=($cv.CurrentBuild.ToString()+'.'+$cv.UBR);BuildNumber=$os.BuildNumber;Architecture=$os.OSArchitecture;ProductType=$os.ProductType;RAM_GB=[math]::Round($cs.TotalPhysicalMemory/1GB,2);FreeRAM_GB=[math]::Round($os.FreePhysicalMemory/1MB,2);UptimeDays=[math]::Round(((Get-Date)-$os.LastBootUpTime).TotalDays,2);LastBoot=$os.LastBootUpTime.ToString('o');AutomaticManagedPagefile=$cs.AutomaticManagedPagefile;Manufacturer=$cs.Manufacturer;Model=$cs.Model;HypervisorPresent=$cs.HypervisorPresent;PartOfDomain=$cs.PartOfDomain}
# 结束此处的代码块、参数列表或集合定义。
}
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '02_cpu' { Get-CimInstance Win32_Processor -OperationTimeoutSec 15 | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed,AddressWidth,VirtualizationFirmwareEnabled,SecondLevelAddressTranslationExtensions,VMMonitorModeExtensions }
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '03_memory' { Get-CimInstance Win32_PhysicalMemory -OperationTimeoutSec 15 | Select-Object Manufacturer,PartNumber,@{n='Capacity_GB';e={[math]::Round($_.Capacity/1GB,2)}},Speed,ConfiguredClockSpeed }
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '04_gpu' { Get-CimInstance Win32_VideoController -OperationTimeoutSec 15 | Select-Object Name,PNPDeviceID,DriverVersion,DriverDate,VideoProcessor,Status,AdapterRAM }
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '05_bios' { Get-CimInstance Win32_BIOS -OperationTimeoutSec 15 | Select-Object Manufacturer,SMBIOSBIOSVersion,ReleaseDate }
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '06_volumes' { Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -OperationTimeoutSec 15 | Select-Object DeviceID,FileSystem,@{n='Size_GB';e={[math]::Round($_.Size/1GB,2)}},@{n='Free_GB';e={[math]::Round($_.FreeSpace/1GB,2)}},@{n='Free_Percent';e={if ($_.Size) {[math]::Round(100*$_.FreeSpace/$_.Size,1)}}} }
# 选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '07_disks' { Get-PhysicalDisk | Select-Object FriendlyName,@{n='MediaType';e={$_.MediaType.ToString()}},@{n='BusType';e={$_.BusType.ToString()}},@{n='HealthStatus';e={$_.HealthStatus.ToString()}},@{n='OperationalStatus';e={$_.OperationalStatus -join ';'}},@{n='Size_GB';e={[math]::Round($_.Size/1GB,2)}} }
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '08_pagefile' { Get-CimInstance Win32_PageFileUsage -OperationTimeoutSec 15 | Select-Object Name,AllocatedBaseSize,CurrentUsage,PeakUsage,TempPageFile }
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '09_updates' { Get-CimInstance Win32_QuickFixEngineering -OperationTimeoutSec 15 | Select-Object HotFixID,Description,InstalledOn }
# 运行有时间限制的诊断探测。
Invoke-Probe '10_reboot' {
    # 读取注册表或对象的属性，并保存到 $rename。
    $rename=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    # 把本行列出的字段组成结构化记录。
    [pscustomobject]@{CBS=Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending';WindowsUpdate=Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired';PendingFileRename=[bool]$rename.PendingFileRenameOperations}
# 结束此处的代码块、参数列表或集合定义。
}
# 运行有时间限制的诊断探测。
Invoke-Probe '11_software' {
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        # 检查本行条件；满足时执行对应分支。
        if (Test-Path $root) {
            # 读取注册表或对象的属性；枚举指定位置的文件、目录或注册表项；逐项处理管道传入的记录。
            Get-ChildItem $root | ForEach-Object { $p=Get-ItemProperty $_.PSPath; if ($p.DisplayName) { [pscustomobject]@{Name=$p.DisplayName;Version=$p.DisplayVersion;Publisher=$p.Publisher;InstallDate=$p.InstallDate;InstallLocation=$p.InstallLocation;SystemComponent=[bool]$p.SystemComponent;Scope=if ($root -like 'HKCU*') {'CurrentUser'} else {'Machine'};RegistryView=if ($root -like '*WOW6432Node*') {'32bit'} else {'Native'}} } }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 结束此处的代码块、参数列表或集合定义。
}
# 选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '12_appx_current_user' { Get-AppxPackage | Select-Object Name,@{n='Version';e={$_.Version.ToString()}},@{n='Architecture';e={$_.Architecture.ToString()}},IsFramework,SignatureKind,Status }
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '13_startup' { Get-CimInstance Win32_StartupCommand -OperationTimeoutSec 15 | Select-Object Name,Location }
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '14_services' { Get-CimInstance Win32_Service -OperationTimeoutSec 15 | Select-Object Name,DisplayName,State,StartMode,DelayedAutoStart }
# 选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '15_scheduled_tasks' { Get-ScheduledTask | Select-Object TaskName,TaskPath,@{n='State';e={$_.State.ToString()}} }
# 选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '16_defender' { Get-MpComputerStatus | Select-Object AMRunningMode,AMServiceEnabled,AntivirusEnabled,RealTimeProtectionEnabled,BehaviorMonitorEnabled,IsTamperProtected,AntivirusSignatureVersion,AntivirusSignatureLastUpdated,AntivirusSignatureAge,QuickScanEndTime }
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '17_antivirus' { Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntivirusProduct -OperationTimeoutSec 15 | Select-Object displayName,productState }
# 读取网络相关配置；选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '18_firewall' { Get-NetFirewallProfile | Select-Object Name,@{n='Enabled';e={$_.Enabled.ToString()}},DefaultInboundAction,DefaultOutboundAction }
# 运行有时间限制的诊断探测。
Invoke-Probe '19_secure_boot' { [pscustomobject]@{Enabled=Confirm-SecureBootUEFI} }
# 选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '20_tpm' { Get-Tpm | Select-Object TpmPresent,TpmReady,TpmEnabled,TpmActivated,ManufacturerVersion,AutoProvisioning }
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '21_tpm_specification' { Get-CimInstance -Namespace 'root\CIMV2\Security\MicrosoftTpm' -ClassName Win32_Tpm -OperationTimeoutSec 15 | Select-Object SpecVersion,ManufacturerVersion,IsEnabled_InitialValue,IsActivated_InitialValue }
# 选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '22_bitlocker' { Get-BitLockerVolume | Select-Object MountPoint,@{n='VolumeStatus';e={$_.VolumeStatus.ToString()}},@{n='ProtectionStatus';e={$_.ProtectionStatus.ToString()}},EncryptionPercentage,EncryptionMethod }
# 运行有时间限制的诊断探测。
Invoke-Probe '23_security_settings' {
    # 读取注册表或对象的属性，并保存到 $uac。
    $uac=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    # 读取注册表或对象的属性，并保存到 $rdp。
    $rdp=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    # 读取注册表或对象的属性，并保存到 $nla。
    $nla=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
    # 把本行列出的字段组成结构化记录。
    [pscustomobject]@{UACEnabled=$uac.EnableLUA;ConsentPromptBehaviorAdmin=$uac.ConsentPromptBehaviorAdmin;RDPDenied=$rdp.fDenyTSConnections;RDPNetworkLevelAuthentication=$nla.UserAuthentication}
# 结束此处的代码块、参数列表或集合定义。
}
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '24_device_guard' { Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -OperationTimeoutSec 15 | Select-Object VirtualizationBasedSecurityStatus,SecurityServicesConfigured,SecurityServicesRunning,AvailableSecurityProperties }
# 选取记录中的指定字段或条目；按条件筛选输入记录；运行有时间限制的诊断探测。
Invoke-Probe '25_optional_features' { Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -match 'Subsystem-Linux|VirtualMachinePlatform|Hyper-V|Containers|Sandbox|SMB1Protocol|NetFx3' } | Select-Object FeatureName,@{n='State';e={$_.State.ToString()}} }
# 选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '26_smb' { Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol,EnableSMB2Protocol,RequireSecuritySignature,EnableSecuritySignature }
# 运行有时间限制的诊断探测。
Invoke-Probe '27_settings' {
    # 读取注册表或对象的属性，并保存到 $fs。
    $fs=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    # 读取注册表或对象的属性，并保存到 $cp。
    $cp=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage'
    # 把本行列出的字段组成结构化记录。
    [pscustomobject]@{LongPathsEnabled=$fs.LongPathsEnabled;ANSI_CodePage=$cp.ACP;OEM_CodePage=$cp.OEMCP;Culture=(Get-Culture).Name;SystemLocale=(Get-WinSystemLocale).Name;TimeZone=(Get-TimeZone).Id}
# 结束此处的代码块、参数列表或集合定义。
}
# 读取脚本执行策略；选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '28_execution_policy' { Get-ExecutionPolicy -List | Select-Object @{n='Scope';e={$_.Scope.ToString()}},@{n='ExecutionPolicy';e={$_.ExecutionPolicy.ToString()}} }
# 选取记录中的指定字段或条目；运行有时间限制的诊断探测。
Invoke-Probe '29_odbc' { Get-OdbcDriver | Select-Object Name,Platform }
# 运行有时间限制的诊断探测。
Invoke-Probe '30_windows_licensing' {
    # No product key/partial product key or activation identifier is exported.
    # 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目；按条件筛选输入记录。
    Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f'" -OperationTimeoutSec 15 | Where-Object { $_.LicenseStatus -ne 0 -or $_.Name -match 'ESU|Extended Security' } | Select-Object Name,Description,LicenseStatus,GracePeriodRemaining
# 结束此处的代码块、参数列表或集合定义。
}
# 运行有时间限制的诊断探测。
Invoke-Probe '31_editor_extensions' {
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($root in @((Join-Path $env:USERPROFILE '.vscode\extensions'),(Join-Path $env:USERPROFILE '.vscode-insiders\extensions'),(Join-Path $env:USERPROFILE '.positron\extensions'))) {
        # 检查本行条件；满足时执行对应分支。
        if (Test-Path -LiteralPath $root) { foreach ($dir in (Get-ChildItem -LiteralPath $root -Directory | Select-Object -First 400)) {
            # 组合父目录与子路径，并保存到 $manifest。
            $manifest=Join-Path $dir.FullName 'package.json'
            # 检查本行条件；满足时执行对应分支。
            if (Test-Path -LiteralPath $manifest) { $m=Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json; [pscustomobject]@{EditorRoot=$root;Id=($m.publisher+'.'+$m.name);Version=$m.version} }
        # 结束此处的代码块、参数列表或集合定义。
        } }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if ($SkipEvents) { Add-Status '32_events' 'Skipped' '-SkipEvents' } else {
    # 运行有时间限制的诊断探测。
    Invoke-Probe '32_events' {
        # 开始受异常处理保护的操作。
        try { $events=@(Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2;StartTime=(Get-Date).AddDays(-14)} -MaxEvents 300) }
        # 捕获并处理前述操作抛出的异常。
        catch { if ($_.FullyQualifiedErrorId -match 'NoMatchingEventsFound') { $events=@() } else { throw } }
        # 选取记录中的指定字段或条目。
        $events | Group-Object ProviderName,Id | Select-Object Count,Name
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# 组合父目录与子路径；调用 Windows 电源配置工具；运行指定工具并收集输出，并保存到 $power。
$power=Invoke-Tool '33_power_plan' (Join-Path $env:WINDIR 'System32\powercfg.exe') @('/getactivescheme')
# 将探测结果保存到报告目录。
Save-Data '33_power_plan' $(if ($power -and $power.ExitCode -eq 0) { [pscustomobject]@{ActiveScheme=$power.Stdout.Trim()} })
# 构造或计算 $runtimeDefinitions，保存本行指定的集合或索引结果。
$runtimeDefinitions = @(
    # 处理 @{Name='Python';Commands=@('python.exe','python3.exe');Patterns=@("$env:LOCALAPPDATA\Programs\Python\Python*\python.exe","$env:ProgramFiles\Python*\python.exe","$env:USERPROFILE\miniconda3\python.exe","$env:USERPROFILE\anaconda3\python.exe","$env:USERPROFILE\miniforge3\python.exe","$env:LOCALAPPDATA\uv\python\*\python.exe","$env:APPDATA\uv\python\*\python.exe")}, 所指定的操作或当前表达式的后续部分。
    @{Name='Python';Commands=@('python.exe','python3.exe');Patterns=@("$env:LOCALAPPDATA\Programs\Python\Python*\python.exe","$env:ProgramFiles\Python*\python.exe","$env:USERPROFILE\miniconda3\python.exe","$env:USERPROFILE\anaconda3\python.exe","$env:USERPROFILE\miniforge3\python.exe","$env:LOCALAPPDATA\uv\python\*\python.exe","$env:APPDATA\uv\python\*\python.exe")},
    # 处理 @{Name='Rscript';Commands=@('Rscript.exe');Patterns=@("$env:ProgramFiles\R\R-*\bin\Rscript.exe","$env:LOCALAPPDATA\Programs\R\R-*\bin\Rscript.exe","$env:ProgramFiles\R\R-*\bin\x64\Rscript.exe")}, 所指定的操作或当前表达式的后续部分。
    @{Name='Rscript';Commands=@('Rscript.exe');Patterns=@("$env:ProgramFiles\R\R-*\bin\Rscript.exe","$env:LOCALAPPDATA\Programs\R\R-*\bin\Rscript.exe","$env:ProgramFiles\R\R-*\bin\x64\Rscript.exe")},
    # 调用 WinGet 执行本行指定的软件管理操作。
    @{Name='uv';Commands=@('uv.exe');Patterns=@("$env:USERPROFILE\.local\bin\uv.exe","$env:LOCALAPPDATA\Microsoft\WinGet\Links\uv.exe")},
    # 处理 @{Name='Git';Commands=@('git.exe');Patterns=@("$env:ProgramFiles\Git\cmd\git.exe","$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")}, 所指定的操作或当前表达式的后续部分。
    @{Name='Git';Commands=@('git.exe');Patterns=@("$env:ProgramFiles\Git\cmd\git.exe","$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")},
    # 处理 @{Name='Quarto';Commands=@('quarto.exe','quarto.cmd');Patterns=@("$env:ProgramFiles\Quarto\bin\quarto.exe","$env:ProgramFiles\Quarto\bin\quarto.cmd","$env:LOCALAPPDATA\Programs\Quarto\bin\quarto.cmd")}, 所指定的操作或当前表达式的后续部分。
    @{Name='Quarto';Commands=@('quarto.exe','quarto.cmd');Patterns=@("$env:ProgramFiles\Quarto\bin\quarto.exe","$env:ProgramFiles\Quarto\bin\quarto.cmd","$env:LOCALAPPDATA\Programs\Quarto\bin\quarto.cmd")},
    # 处理 @{Name='Pandoc';Commands=@('pandoc.exe');Patterns=@("$env:LOCALAPPDATA\Pandoc\pandoc.exe","$env:ProgramFiles\Pandoc\pandoc.exe")}, 所指定的操作或当前表达式的后续部分。
    @{Name='Pandoc';Commands=@('pandoc.exe');Patterns=@("$env:LOCALAPPDATA\Pandoc\pandoc.exe","$env:ProgramFiles\Pandoc\pandoc.exe")},
    # 处理 @{Name='PowerShell7';Commands=@('pwsh.exe');Patterns=@("$env:ProgramFiles\PowerShell\7\pwsh.exe")}, 所指定的操作或当前表达式的后续部分。
    @{Name='PowerShell7';Commands=@('pwsh.exe');Patterns=@("$env:ProgramFiles\PowerShell\7\pwsh.exe")},
    # 处理 @{Name='Node';Commands=@('node.exe');Patterns=@("$env:ProgramFiles\nodejs\node.exe")}, 所指定的操作或当前表达式的后续部分。
    @{Name='Node';Commands=@('node.exe');Patterns=@("$env:ProgramFiles\nodejs\node.exe")},
    # 处理 @{Name='Java';Commands=@('java.exe');Patterns=@("$env:ProgramFiles\Eclipse 所指定的操作或当前表达式的后续部分。
    @{Name='Java';Commands=@('java.exe');Patterns=@("$env:ProgramFiles\Eclipse Adoptium\*\bin\java.exe","$env:ProgramFiles\Java\*\bin\java.exe")},
    # 处理 @{Name='DuckDB';Commands=@('duckdb.exe');Patterns=@("$env:USERPROFILE\.duckdb\cli\latest\duckdb.exe")}, 所指定的操作或当前表达式的后续部分。
    @{Name='DuckDB';Commands=@('duckdb.exe');Patterns=@("$env:USERPROFILE\.duckdb\cli\latest\duckdb.exe")},
    # 处理 @{Name='PostgreSQL';Commands=@('psql.exe');Patterns=@("$env:ProgramFiles\PostgreSQL\*\bin\psql.exe")}, 所指定的操作或当前表达式的后续部分。
    @{Name='PostgreSQL';Commands=@('psql.exe');Patterns=@("$env:ProgramFiles\PostgreSQL\*\bin\psql.exe")},
    # 处理 @{Name='Docker';Commands=@('docker.exe');Patterns=@("$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe")}, 所指定的操作或当前表达式的后续部分。
    @{Name='Docker';Commands=@('docker.exe');Patterns=@("$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe")},
    # 处理 @{Name='Julia';Commands=@('julia.exe');Patterns=@("$env:LOCALAPPDATA\Programs\Julia*\bin\julia.exe")}, 所指定的操作或当前表达式的后续部分。
    @{Name='Julia';Commands=@('julia.exe');Patterns=@("$env:LOCALAPPDATA\Programs\Julia*\bin\julia.exe")},
    # 调用 WinGet 执行本行指定的软件管理操作。
    @{Name='Winget';Commands=@('winget.exe');Patterns=@()},
    # 处理 @{Name='RtoolsCompiler';Commands=@('gcc.exe');Patterns=@('C:\rtools*\x86_64-w64-mingw32.static.posix\bin\gcc.exe','C:\rtools*\mingw64\bin\gcc.exe')} 所指定的操作或当前表达式的后续部分。
    @{Name='RtoolsCompiler';Commands=@('gcc.exe');Patterns=@('C:\rtools*\x86_64-w64-mingw32.static.posix\bin\gcc.exe','C:\rtools*\mingw64\bin\gcc.exe')}
# 结束此处的代码块、参数列表或集合定义。
)
# 运行有时间限制的诊断探测。
Invoke-Probe '34_registered_interpreters' {
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($base in @('HKCU:\SOFTWARE\Python\PythonCore','HKLM:\SOFTWARE\Python\PythonCore','HKLM:\SOFTWARE\WOW6432Node\Python\PythonCore')) {
        # 检查本行条件；满足时执行对应分支。
        if (Test-Path $base) { foreach ($version in (Get-ChildItem $base)) { $key=Join-Path $version.PSPath 'InstallPath'; if (Test-Path $key) { $p=Get-ItemProperty $key; $path=$p.ExecutablePath; if (-not $path) { $path=Join-Path $p.'(default)' 'python.exe' }; [pscustomobject]@{Runtime='Python';Path=$path} } } }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($base in @('HKCU:\SOFTWARE\R-core\R','HKLM:\SOFTWARE\R-core\R','HKLM:\SOFTWARE\WOW6432Node\R-core\R')) {
        # 检查本行条件；满足时执行对应分支。
        if (Test-Path $base) { foreach ($key in @((Get-Item $base)) + @(Get-ChildItem $base)) { $p=Get-ItemProperty $key.PSPath; if ($p.InstallPath) { [pscustomobject]@{Runtime='Rscript';Path=(Join-Path $p.InstallPath 'bin\Rscript.exe')} } }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 结束此处的代码块、参数列表或集合定义。
}
# 创建指定类型的对象，并保存到 $runtimeRows。
$runtimeRows=New-Object System.Collections.Generic.List[object]
# 构造或计算 $pythonPaths，保存本行指定的集合或索引结果。
$pythonPaths=@(); $rPaths=@()
# 按本行的迭代范围或条件重复执行循环体。
foreach ($definition in $runtimeDefinitions) {
    # 构造或计算 $patterns，保存本行指定的集合或索引结果。
    $patterns=@($definition.Patterns)
    # 检查本行条件；满足时执行对应分支。
    if ($definition.Name -eq 'Python') { $patterns += $AdditionalPythonPaths; $patterns += @($script:Data['34_registered_interpreters'] | Where-Object {$_.Runtime -eq 'Python'} | Select-Object -ExpandProperty Path) }
    # 检查本行条件；满足时执行对应分支。
    if ($definition.Name -eq 'Rscript') { $patterns += $AdditionalRPaths; $patterns += @($script:Data['34_registered_interpreters'] | Where-Object {$_.Runtime -eq 'Rscript'} | Select-Object -ExpandProperty Path) }
    # 构造或计算 $paths，保存本行指定的集合或索引结果。
    $paths=@(Find-Executables $definition.Commands $patterns)
    # 检查本行条件；满足时执行对应分支。
    if ($paths.Count -gt $MaxInterpreters) { Add-Status ('Discovery/'+$definition.Name) 'Partial' ('發現 '+$paths.Count+' 個；限制只探測前 '+$MaxInterpreters+' 個。') }
    # 选取记录中的指定字段或条目，并保存到 $paths。
    $paths=@($paths | Select-Object -First $MaxInterpreters)
    # 检查本行条件；满足时执行对应分支。
    if ($paths.Count -eq 0) { Add-Status ('Runtime/'+$definition.Name) 'Unavailable' '限定的安裝位置未發現；可能是可攜版或另一使用者安裝。'; $runtimeRows.Add([pscustomobject]@{Tool=$definition.Name;Found=$false;Path=$null;Version=$null;Status='Unavailable'}); continue }
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($path in $paths) {
        # 构造或计算 $arguments，保存本行指定的集合或索引结果。
        $arguments=@('--version'); if ($definition.Name -eq 'Java') { $arguments=@('-version') }
        # 检查本行条件；满足时执行对应分支。
        if ($definition.Name -eq 'Python') { $arguments=@('-I','-S','-B','--version'); $pythonPaths += $path }
        # 检查本行条件；满足时执行对应分支。
        if ($definition.Name -eq 'Rscript') { $rPaths += $path }
        # 运行指定工具并收集输出，并保存到 $result。
        $result=Invoke-Tool ('Runtime/'+$definition.Name) $path $arguments
        # 构造或计算 $version，保存本行指定的集合或索引结果。
        $version=''; if ($result) { $version=(($result.Stdout+' '+$result.Stderr).Trim() -split '\r?\n')[0] }
        # 调用 $runtimeRows.Add，使用本行列出的输入完成对应操作。
        $runtimeRows.Add([pscustomobject]@{Tool=$definition.Name;Found=$true;Path=$path;Version=$version;Status=if ($result.ExitCode -eq 0) {'OK'} else {$result.State}})
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 将探测结果保存到报告目录。
Save-Data '35_runtimes' $runtimeRows.ToArray()

# Metadata-only Python inventory: -I -S -B avoids user site startup files, .pth execution and bytecode writes.
# 原文块第 1 行：计算本行表达式并设置 $pythonCode，供后续步骤使用。
# 原文块第 2 行：导入 sys, sysconfig, os, json, site，供后续代码调用。
# 原文块第 3 行：导入 importlib 中的 metadata，供后续代码调用。
# 原文块第 4 行：计算本行表达式并设置 exe_dir，供后续步骤使用。
# 原文块第 5 行：计算本行表达式并设置 venv_root，供后续步骤使用。
# 原文块第 6 行：计算本行表达式并设置 is_venv，供后续步骤使用。
# 原文块第 7 行：构造或计算 paths，保存本行指定的集合或索引结果。
# 原文块第 8 行：计算本行表达式并设置 include_system，供后续步骤使用。
# 原文块第 9 行：处理 if 所指定的操作或当前表达式的后续部分。
# 原文块第 10 行：进入上下文管理器，确保结束时自动释放相应资源。
# 原文块第 11 行：计算本行表达式并设置 include_system，供后续步骤使用。
# 原文块第 12 行：处理 if 所指定的操作或当前表达式的后续部分。
# 原文块第 13 行：调用 paths.extend，使用本行列出的输入完成对应操作。
# 原文块第 14 行：计算本行表达式并设置 user，供后续步骤使用。
# 原文块第 15 行：调用 paths.extend，使用本行列出的输入完成对应操作。
# 原文块第 16 行：构造或计算 paths，保存本行指定的集合或索引结果。
# 原文块第 17 行：构造或计算 rows，保存本行指定的集合或索引结果。
# 原文块第 18 行：按本行的迭代范围或条件重复执行循环体。
# 原文块第 19 行：按本行的迭代范围或条件重复执行循环体。
# 原文块第 20 行：调用 rows.append，使用本行列出的输入完成对应操作。
# 原文块第 21 行：输出本行的状态信息或计算结果。
# 原文块第 22 行：提供当前表达式所需的文本、字段名称或列表元素。
$pythonCode=@'
import sys, sysconfig, os, json, site
from importlib import metadata
exe_dir=os.path.dirname(sys.executable)
venv_root=os.path.dirname(exe_dir) if os.path.basename(exe_dir).lower()=="scripts" else exe_dir
is_venv=os.path.isfile(os.path.join(venv_root,"pyvenv.cfg"))
paths=[os.path.join(venv_root,"Lib","site-packages")]
include_system=not is_venv
if is_venv:
    with open(os.path.join(venv_root,"pyvenv.cfg"),encoding="utf-8") as f:
        include_system="include-system-site-packages = true" in f.read().lower()
if include_system:
    paths.extend([sysconfig.get_paths().get("purelib",""),sysconfig.get_paths().get("platlib","")])
    user=site.getusersitepackages()
    paths.extend(user if isinstance(user,list) else [user])
paths=list(dict.fromkeys(p for p in paths if p and os.path.isdir(p)))
rows=[]
for path in paths:
    for dist in metadata.distributions(path=[path]):
        rows.append({"Name":dist.metadata.get("Name","?"),"Version":dist.version,"Library":path})
print(json.dumps({"Executable":sys.executable,"Version":sys.version.split()[0],"Libraries":paths,"IsVirtualEnvironment":is_venv,"Packages":sorted(rows,key=lambda p:p["Name"].lower()),"Scope":"Static distribution metadata; .pth/editable paths and runtime import behavior not executed"},ensure_ascii=True))
'@
# 组合父目录与子路径，并保存到 $pythonFile。
$pythonFile=Join-Path $OutputDirectory '_probe_python.py'
# 创建指定类型的对象；将文本写入指定文件。
[IO.File]::WriteAllText($pythonFile,$pythonCode,(New-Object Text.UTF8Encoding($false)))
# 创建指定类型的对象，并保存到 $pythonEnvs。
$pythonEnvs=New-Object System.Collections.Generic.List[object]
# 创建指定类型的对象，并保存到 $pythonPackages。
$pythonPackages=New-Object System.Collections.Generic.List[object]
# 检查本行条件；满足时执行对应分支。
if ($SkipPackages) { Add-Status 'PythonPackages' 'Skipped' '-SkipPackages' } elseif ($pythonPaths.Count -eq 0) { Add-Status 'PythonPackages' 'Unavailable' '未找到可用 Python。' } else {
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($path in $pythonPaths) {
        # 运行指定工具并收集输出，并保存到 $result。
        $result=Invoke-Tool ('PythonPackages/'+$path) $path @('-I','-S','-B',$pythonFile)
        # 检查本行条件；满足时执行对应分支。
        if ($result.ExitCode -eq 0) {
            # 开始受异常处理保护的操作。
            try {
                # 把 JSON 文本解析为对象，并保存到 $parsed。
                $parsed=$result.Stdout | ConvertFrom-Json
                # 调用 $pythonEnvs.Add，使用本行列出的输入完成对应操作。
                $pythonEnvs.Add([pscustomobject]@{Executable=$parsed.Executable;Version=$parsed.Version;Libraries=$parsed.Libraries -join ';';IsVirtualEnvironment=$parsed.IsVirtualEnvironment;PackageCount=@($parsed.Packages).Count;Scope=$parsed.Scope})
                # 按本行的迭代范围或条件重复执行循环体。
                foreach ($pkg in $parsed.Packages) { $pythonPackages.Add([pscustomobject]@{Interpreter=$path;Name=$pkg.Name;Version=$pkg.Version;Library=$pkg.Library}) }
            # 结束上一代码块并进入异常处理。
            } catch { Add-Status ('PythonPackagesParse/'+$path) 'Failed' $_.Exception.Message }
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 将探测结果保存到报告目录。
Save-Data '36_python_environments' $pythonEnvs.ToArray()
# 将探测结果保存到报告目录。
Save-Data '37_python_packages' $pythonPackages.ToArray()
# 原文块第 1 行：计算本行表达式并设置 $rCode，供后续步骤使用。
# 原文块第 2 行：计算本行表达式并设置 args，供后续步骤使用。
# 原文块第 3 行：读取 R 套件安装清单，并保存到 ip。
# 原文块第 4 行：将表格写入 CSV 文件。
# 原文块第 5 行：将表格写入 CSV 文件。
# 原文块第 6 行：提供当前表达式所需的文本、字段名称或列表元素。
$rCode=@'
args <- commandArgs(trailingOnly=TRUE)
ip <- installed.packages(noCache=TRUE)
write.csv(data.frame(Package=ip[,"Package"], Version=ip[,"Version"], Built=ip[,"Built"], Library=ip[,"LibPath"]),args[1],row.names=FALSE,fileEncoding="UTF-8")
write.csv(data.frame(Version=R.version.string, RHome=R.home(), Library=.libPaths(), Writable=file.access(.libPaths(),2)==0),args[2],row.names=FALSE,fileEncoding="UTF-8")
'@
# 组合父目录与子路径，并保存到 $rFile。
$rFile=Join-Path $OutputDirectory '_probe_r.R'
# 创建指定类型的对象；将文本写入指定文件。
[IO.File]::WriteAllText($rFile,$rCode,(New-Object Text.UTF8Encoding($false)))
# 创建指定类型的对象，并保存到 $rEnvs。
$rEnvs=New-Object System.Collections.Generic.List[object]; $rPackages=New-Object System.Collections.Generic.List[object]
# 检查本行条件；满足时执行对应分支。
if ($SkipPackages) { Add-Status 'RPackages' 'Skipped' '-SkipPackages' } elseif ($rPaths.Count -eq 0) { Add-Status 'RPackages' 'Unavailable' '未找到 Rscript。' } else {
    # 计算本行表达式并设置 $index，供后续步骤使用。
    $index=0
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($path in $rPaths) {
        # 组合父目录与子路径。
        $index++; $pkgFile=Join-Path $OutputDirectory ('_r_packages_'+$index+'.csv'); $envFile=Join-Path $OutputDirectory ('_r_environment_'+$index+'.csv')
        # The child already runs in OutputDirectory. ASCII relative arguments avoid
        # Rscript's Windows command-line conversion corrupting non-ASCII paths.
        # 运行指定工具并收集输出，并保存到 $result。
        $result=Invoke-Tool ('RPackages/'+$path) $path @('--vanilla','_probe_r.R',([IO.Path]::GetFileName($pkgFile)),([IO.Path]::GetFileName($envFile)))
        # 检查本行条件；满足时执行对应分支。
        if ($result.ExitCode -eq 0 -and (Test-Path -LiteralPath $pkgFile) -and (Test-Path -LiteralPath $envFile)) {
            # 按本行的迭代范围或条件重复执行循环体。
            foreach ($row in (Import-Csv -LiteralPath $envFile -Encoding UTF8)) { $rEnvs.Add([pscustomobject]@{Interpreter=$path;Version=$row.Version;Library=$row.Library;Writable=$row.Writable;Scope='--vanilla; no project .Rprofile/.Renviron executed'}) }
            # 按本行的迭代范围或条件重复执行循环体。
            foreach ($row in (Import-Csv -LiteralPath $pkgFile -Encoding UTF8)) { $rPackages.Add([pscustomobject]@{Interpreter=$path;Name=$row.Package;Version=$row.Version;Built=$row.Built;Library=$row.Library}) }
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 将探测结果保存到报告目录。
Save-Data '38_r_environments' $rEnvs.ToArray()
# 将探测结果保存到报告目录。
Save-Data '39_r_packages' $rPackages.ToArray()

# 选取记录中的指定字段或条目，并保存到 $system。
$system=@($script:Data['01_system'] | Select-Object -First 1)
# 检查本行条件；满足时执行对应分支。
if ($system.Count) {
    # 检查本行条件；满足时执行对应分支。
    if ($system[0].Caption -match 'Windows 10') { Add-Finding '注意' '作業系統' 'Windows 10 一般通道已於 2025-10-14 結束支援；LTSC/IoT/ESU 有不同期限。請依實際 Edition、ESU 授權與 Microsoft 公告確認。啟用狀態不等同最新修補或 ESU 已可用。' }
    # 检查本行条件；满足时执行对应分支。
    if (-not $system[0].AutomaticManagedPagefile) { Add-Finding '注意' '記憶體' '分頁檔不是由 Windows 自動管理；應依 commit peak、當機傾印與可用磁碟評估，避免套用固定 RAM 倍數。' }
# 结束此处的代码块、参数列表或集合定义。
}
# 按本行的迭代范围或条件重复执行循环体。
foreach ($v in $script:Data['06_volumes']) { if ($v.Free_Percent -lt 15) { Add-Finding '注意' '磁碟' ($v.DeviceID+' 剩餘 '+$v.Free_Percent+'%；處理大型資料需預留 spill 與套件快取空間。') } }
# 按本行的迭代范围或条件重复执行循环体。
foreach ($d in $script:Data['07_disks']) { if ($d.HealthStatus -ne 'Healthy') { Add-Finding '警告' '磁碟' ($d.FriendlyName+' 健康狀態：'+$d.HealthStatus+'；請進一步確認並備份。') } }
# 按本行的迭代范围或条件重复执行循环体。
foreach ($f in $script:Data['18_firewall']) { if ($f.Enabled -eq 'False') { Add-Finding '警告' '安全性' ($f.Name+' 防火牆設定檔停用。') } }
# 按本行的迭代范围或条件重复执行循环体。
foreach ($d in $script:Data['16_defender']) { if (-not $d.RealTimeProtectionEnabled) { Add-Finding '注意' '安全性' 'Defender 即時保護未啟用；須结合安全中心防毒產品確認保護狀態，不能單憑此判定缺少防毒。' } }
# 按本行的迭代范围或条件重复执行循环体。
foreach ($r in $script:Data['10_reboot']) { if ($r.CBS -or $r.WindowsUpdate -or $r.PendingFileRename) { Add-Finding '注意' '重啟' '偵測到待重啟標記；PendingFileRename 單獨出現未必代表 Windows 更新需要重啟。' } }
# 按本行的迭代范围或条件重复执行循环体。
foreach ($s in $script:Data['27_settings']) { if ($s.LongPathsEnabled -ne 1) { Add-Finding '建議' '路徑' 'LongPathsEnabled 未啟用。啟用可改善支援 longPathAware 的程式；並非所有舊程式都能突破長路徑限制。' } }
# 追加一项诊断发现。
Add-Finding '說明' 'GPU' 'GPU 名稱/驅動僅供盤點；CUDA、PyTorch 支援與 Windows 11 CPU/TPM/Secure Boot/WDDM 資格須依廠商當前要求另外核實。'
# 追加一项诊断发现。
Add-Finding '說明' '套件' '未安装選用分析套件不等於故障。依工作負載建立獨立 Python/R 專案環境與鎖檔；不建議全域一次升級所有套件。'
# 追加一项诊断发现。
Add-Finding '說明' '範圍' '本次不連網檢查可升級版本；Windows 更新清單不代表完整更新歷史。未搜尋其他使用者、所有可攜程式、每個專案環境、Conda/WSL 容器內部。'
# 将探测结果保存到报告目录。
Save-Data '90_findings' $script:Findings.ToArray()
# 将探测结果保存到报告目录。
Save-Data '91_probe_status' $script:Status.ToArray()
# 处理 Write-JsonFile 所指定的操作或当前表达式的后续部分。
Write-JsonFile ([pscustomobject]$script:Data) 'inventory.json'
# 创建指定类型的对象，并保存到 $summary。
$summary=New-Object Text.StringBuilder
# 向报告缓冲区追加一行文本。
[void]$summary.AppendLine('# Windows 資料分析工作站診斷 v3')
# 向报告缓冲区追加一行文本。
[void]$summary.AppendLine('')
# 生成当前时间或格式化时间戳；向报告缓冲区追加一行文本。
[void]$summary.AppendLine('時間：'+(Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz')+'；系統管理員：'+$isAdmin+'。所有探測離線唯讀，僅寫入本報告資料夾。')
# 向报告缓冲区追加一行文本。
[void]$summary.AppendLine('')
# 检查本行条件；满足时执行对应分支。
if ($system.Count) { [void]$summary.AppendLine('系統：'+$system[0].Caption+' '+$system[0].DisplayVersion+' / '+$system[0].EditionID+' / Build '+$system[0].Build+'；RAM '+$system[0].RAM_GB+' GB，當下可用 '+$system[0].FreeRAM_GB+' GB。') }
# 向报告缓冲区追加一行文本。
[void]$summary.AppendLine('')
# 向报告缓冲区追加一行文本。
[void]$summary.AppendLine('桌面軟體登錄筆數：'+@($script:Data['11_software']).Count+'；目前使用者 Appx：'+@($script:Data['12_appx_current_user']).Count+'；Python 已盤點環境：'+$pythonEnvs.Count+'；R 套件筆數（含不同直譯器）：'+$rPackages.Count+'。')
# 向报告缓冲区追加一行文本。
[void]$summary.AppendLine('')
# 按本行的迭代范围或条件重复执行循环体。
foreach ($finding in $script:Findings) { [void]$summary.AppendLine('- **'+$finding.Level+' / '+$finding.Area+'**：'+$finding.Message) }
# 向报告缓冲区追加一行文本。
[void]$summary.AppendLine('')
# 向报告缓冲区追加一行文本。
[void]$summary.AppendLine('## 工具鏈')
# 向报告缓冲区追加一行文本。
[void]$summary.AppendLine('')
# 向报告缓冲区追加一行文本。
[void]$summary.AppendLine('| 工具 | 發現 | 版本 |')
# 向报告缓冲区追加一行文本。
[void]$summary.AppendLine('|---|---|---|')
# 按本行的迭代范围或条件重复执行循环体。
foreach ($runtime in $runtimeRows) { [void]$summary.AppendLine('| '+$runtime.Tool+' | '+$runtime.Found+' | '+($runtime.Version -replace '\|','\|')+' |') }
# 向报告缓冲区追加一行文本。
[void]$summary.AppendLine('')
# 向报告缓冲区追加一行文本。
[void]$summary.AppendLine('## 未完成或不可用的探測')
# 向报告缓冲区追加一行文本。
[void]$summary.AppendLine('')
# 按条件筛选输入记录，并保存到 $incomplete。
$incomplete=@($script:Status | Where-Object {$_.Status -ne 'OK'})
# 检查本行条件；满足时执行对应分支。
if ($incomplete.Count -eq 0) { [void]$summary.AppendLine('本次所有已安排探測均完成。') }
# 按本行的迭代范围或条件重复执行循环体。
foreach ($status in $incomplete) { [void]$summary.AppendLine('- '+$status.Probe+'：'+$status.Status+' — '+$status.Detail) }
# 向报告缓冲区追加一行文本。
[void]$summary.AppendLine('')
# 向报告缓冲区追加一行文本。
[void]$summary.AppendLine('完整資料：inventory.json；逐項 CSV/JSON；91_probe_status.csv 保存每項結果與耗時。空資料不等於健康，先查探測狀態。探測用 _probe_* 檔案保留以便稽核。報告含軟體與本機路徑，分享前請檢視。')
# 组合父目录与子路径；将文本写入指定文件。
[IO.File]::WriteAllText((Join-Path $OutputDirectory '00_summary.md'),$summary.ToString(),$script:Utf8)
# 组合父目录与子路径；向终端显示提示或结果。
Write-Host ('診斷完成：'+(Join-Path $OutputDirectory '00_summary.md'))
