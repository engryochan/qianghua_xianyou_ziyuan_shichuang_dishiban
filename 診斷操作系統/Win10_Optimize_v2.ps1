#Requires -Version 5.1
<#
.SYNOPSIS
  可預演、可還原的 Windows 資料分析工作站設定。預設僅顯示計畫。
.DESCRIPTION
  -Apply 才變更。每次變更前保存精確的原設定，逐步驗證並記錄。
  不自動重開機，不更改分頁檔、Defender、防火牆、DLP、服務或執行原則。
  高效能電源計畫是選項；不宣稱會提升每項工作負載的速度。
.EXAMPLE
  .\Win10_Optimize_v2.ps1 -EnableLongPaths
.EXAMPLE
  .\Win10_Optimize_v2.ps1 -Apply -EnableLongPaths -WhatIf
.EXAMPLE
  .\Win10_Optimize_v2.ps1 -Apply -EnableLongPaths
.EXAMPLE
  .\Win10_Optimize_v2.ps1 -Apply -RestoreFrom 'C:\reports\system\settings-20260920-120000.json'
#>
# 启用 PowerShell 高级脚本参数绑定及所列功能。
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
# 声明脚本或函数接受的参数及默认值。
param(
    # 声明参数 $Apply的类型、默认值或校验规则。
    [switch]$Apply,
    # 声明参数 $EnableLongPaths的类型、默认值或校验规则。
    [switch]$EnableLongPaths,
    # 声明参数 $PowerPlan的类型、默认值或校验规则。
    [ValidateSet('Keep','Balanced','HighPerformance')][string]$PowerPlan='Keep',
    # 声明参数 $CreateRestorePoint的类型、默认值或校验规则。
    [switch]$CreateRestorePoint,
    # 声明参数 $RestoreFrom的类型、默认值或校验规则。
    [string]$RestoreFrom,
    # 声明参数 $BackupDirectory的类型、默认值或校验规则。
    [string]$BackupDirectory=(Join-Path $PSScriptRoot 'reports\system')
# 结束此处的代码块、参数列表或集合定义。
)
# 处理 Set-StrictMode 所指定的操作或当前表达式的后续部分。
Set-StrictMode -Version 2.0
# 设置本脚本遇到 PowerShell 错误时的处理方式。
$ErrorActionPreference='Stop'
# 计算本行表达式并设置 $key，供后续步骤使用。
$key='HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
# 计算本行表达式并设置 $name，供后续步骤使用。
$name='LongPathsEnabled'
# 检查当前身份是否具有指定权限角色，并保存到 $admin。
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# 创建指定类型的对象，并保存到 $encoding。
$encoding=New-Object System.Text.UTF8Encoding($true)

# 定义 Read-LongPaths，封装此函数内的操作。
function Read-LongPaths {
    # 计算本行表达式并设置 $rk，供后续步骤使用。
    $rk=Get-Item -LiteralPath $key
    # 构造或计算 $exists，保存本行指定的集合或索引结果。
    $exists=@($rk.GetValueNames()) -contains $name
    # 检查本行条件；满足时执行对应分支。
    if ($exists) {
        # 计算本行表达式并设置 $kind，供后续步骤使用。
        $kind=$rk.GetValueKind($name).ToString()
        # 检查本行条件；满足时执行对应分支。
        if ($kind -ne 'DWord') { throw "Unexpected registry type $kind; inspect manually before changing." }
        # 构造或计算 $value，保存本行指定的集合或索引结果。
        $value=[int]$rk.GetValue($name)
        # 检查本行条件；满足时执行对应分支。
        if ($value -notin @(0,1)) { throw 'Unexpected LongPathsEnabled value; inspect manually before changing.' }
        # 返回本行结果并结束当前函数。
        return [pscustomobject]@{Exists=$true;Kind=$kind;Value=$value}
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 返回本行结果并结束当前函数。
    return [pscustomobject]@{Exists=$false;Kind='DWord';Value=$null}
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Read-PowerPlan，封装此函数内的操作。
function Read-PowerPlan {
    # 调用 Windows 电源配置工具，并保存到 $raw。
    $raw=& "$env:SystemRoot\System32\powercfg.exe" /getactivescheme 2>&1
    # 检查本行条件；满足时执行对应分支。
    if ($LASTEXITCODE -ne 0) { throw "powercfg failed ($LASTEXITCODE): $raw" }
    # 构造或计算 $m，保存本行指定的集合或索引结果。
    $m=[regex]::Match(($raw -join ' '),'[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}')
    # 检查本行条件；满足时执行对应分支。
    if (-not $m.Success) { throw 'Cannot parse active power plan GUID.' }
    # 返回本行结果并结束当前函数。
    return $m.Value.ToLowerInvariant()
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Set-PowerPlan，封装此函数内的操作。
function Set-PowerPlan([string]$Guid) {
    # 构造或计算 $validated，保存本行指定的集合或索引结果。
    $validated=[guid]::Parse($Guid).ToString()
    # 丢弃不需要显示的输出；调用 Windows 电源配置工具。
    & "$env:SystemRoot\System32\powercfg.exe" /setactive $validated | Out-Null
    # 检查本行条件；满足时执行对应分支。
    if ($LASTEXITCODE -ne 0) { throw "powercfg failed with exit code $LASTEXITCODE" }
    # 检查本行条件；满足时执行对应分支。
    if ((Read-PowerPlan) -ne $validated) { throw 'Power plan verification failed.' }
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Save-Journal，封装此函数内的操作。
function Save-Journal {
    # Write temporary file beside destination; never discard the prior journal on serialization failure.
    # 把对象序列化为 JSON，并保存到 $text。
    $text=$script:journal | ConvertTo-Json -Depth 8
    # 将文本写入指定文件。
    [IO.File]::WriteAllText(($script:journalPath+'.tmp'),$text,$encoding)
    # 移动或替换指定文件。
    Move-Item -LiteralPath ($script:journalPath+'.tmp') -Destination $script:journalPath -Force
# 结束此处的代码块、参数列表或集合定义。
}

# 检查本行条件；满足时执行对应分支。
if ($RestoreFrom) {
    # 检查本行条件；满足时执行对应分支。
    if ($EnableLongPaths -or $PowerPlan -ne 'Keep' -or $CreateRestorePoint) { throw 'RestoreFrom cannot be combined with other actions.' }
    # 读取文件内容供后续处理；把 JSON 文本解析为对象，并保存到 $snapshot。
    $snapshot=Get-Content -LiteralPath $RestoreFrom -Raw -Encoding UTF8 | ConvertFrom-Json
    # 检查本行条件；满足时执行对应分支。
    if ($snapshot.Schema -ne 'DataWorkbench.SystemSettings.v1' -or $snapshot.ComputerName -ne $env:COMPUTERNAME) {
        # 报告本行指定的错误并中止当前执行路径。
        throw 'Unsupported snapshot or snapshot belongs to a different computer.'
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($change in @($snapshot.Changes)) {
        # 检查本行条件；满足时执行对应分支。
        if ($change.Name -notin @('LongPaths','PowerPlan')) { throw 'Snapshot contains an unsupported action.' }
        # 检查本行条件；满足时执行对应分支。
        if ($change.Name -eq 'LongPaths') {
            # 检查本行条件；满足时执行对应分支。
            if ($change.Before.Kind -ne 'DWord' -or $change.After.Kind -ne 'DWord' -or
                # 处理 $change.Before.Exists 所指定的操作或当前表达式的后续部分。
                $change.Before.Exists -isnot [bool] -or $change.After.Value -ne 1 -or
                # 继续当前表达式，补充参数、类型转换或结果处理。
                ($change.Before.Exists -and $change.Before.Value -notin @(0,1))) { throw 'Invalid LongPaths snapshot.' }
        # 结束上一代码块并进入另一条件分支。
        } else {
            # 继续当前表达式，补充参数、类型转换或结果处理。
            [void][guid]::Parse([string]$change.Before)
            # 继续当前表达式，补充参数、类型转换或结果处理。
            [void][guid]::Parse([string]$change.After)
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 检查本行条件；满足时执行对应分支。
    if (-not $Apply) {
        # 向终端显示提示或结果。
        Write-Host '僅顯示還原計畫；加 -Apply 才會還原。'
        # 选取记录中的指定字段或条目。
        $snapshot.Changes | Select-Object Name,Before,After,Status
        # 返回本行结果并结束当前函数。
        return
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 检查本行条件；满足时执行对应分支。
    if (-not $admin -and -not $WhatIfPreference) { throw '請在系統管理員 PowerShell 執行還原。' }
    # 构造或计算 $restoreActions，保存本行指定的集合或索引结果。
    $restoreActions=@($snapshot.Changes)
    # 继续当前表达式，补充参数、类型转换或结果处理。
    [array]::Reverse($restoreActions)
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($change in $restoreActions) {
        # 检查本行条件；满足时执行对应分支。
        if ($change.Status -notin @('Applied','Pending','Failed')) { continue }
        # 检查本行条件；满足时执行对应分支。
        if ($change.Name -eq 'LongPaths') {
            # 计算本行表达式并设置 $current，供后续步骤使用。
            $current=Read-LongPaths
            # 检查本行条件；满足时执行对应分支。
            if ($current.Exists -eq $change.Before.Exists -and $current.Value -eq $change.Before.Value) { Write-Host 'LongPaths 已是原設定。'; continue }
            # 检查本行条件；满足时执行对应分支。
            if (-not $current.Exists -or $current.Value -ne $change.After.Value) { throw 'LongPaths changed since this run; refusing to overwrite a later setting.' }
            # 检查本行条件；满足时执行对应分支。
            if ($PSCmdlet.ShouldProcess($key,'還原 LongPathsEnabled')) {
                # 检查本行条件；满足时执行对应分支。
                if ($change.Before.Exists) {
                    # 创建或写入指定注册表属性；创建指定目录、文件或配置项；丢弃不需要显示的输出。
                    New-ItemProperty -LiteralPath $key -Name $name -PropertyType DWord -Value ([int]$change.Before.Value) -Force | Out-Null
                # 结束上一代码块并进入另一条件分支。
                } else { Remove-ItemProperty -LiteralPath $key -Name $name }
                # 计算本行表达式并设置 $verified，供后续步骤使用。
                $verified=Read-LongPaths
                # 检查本行条件；满足时执行对应分支。
                if ($verified.Exists -ne $change.Before.Exists -or $verified.Value -ne $change.Before.Value) { throw 'LongPaths rollback verification failed.' }
                # 向终端显示提示或结果。
                Write-Host 'LongPaths 已還原並驗證。'
            # 结束此处的代码块、参数列表或集合定义。
            }
        # 结束上一代码块并进入另一条件分支。
        } else {
            # 计算本行表达式并设置 $current，供后续步骤使用。
            $current=Read-PowerPlan
            # 检查本行条件；满足时执行对应分支。
            if ($current -eq $change.Before) { Write-Host '電源計畫已是原設定。'; continue }
            # 检查本行条件；满足时执行对应分支。
            if ($current -ne $change.After) { throw 'Power plan changed since this run; refusing to overwrite a later setting.' }
            # 检查本行条件；满足时执行对应分支。
            if ($PSCmdlet.ShouldProcess([string]$change.Before,'還原原電源計畫')) { Set-PowerPlan $change.Before; Write-Host '電源計畫已還原並驗證。' }
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 返回本行结果并结束当前函数。
    return
# 结束此处的代码块、参数列表或集合定义。
}

# 创建指定类型的对象，并保存到 $changes。
$changes=New-Object System.Collections.Generic.List[object]
# 检查本行条件；满足时执行对应分支。
if ($EnableLongPaths) {
    # 计算本行表达式并设置 $before，供后续步骤使用。
    $before=Read-LongPaths
    # 检查本行条件；满足时执行对应分支。
    if ($before.Exists -and $before.Value -eq 1) { Write-Host '長路徑已啟用，無需變更。' }
    # 当前述条件不成立时执行此分支。
    else { $changes.Add([pscustomobject]@{Name='LongPaths';Before=$before;After=[pscustomobject]@{Exists=$true;Kind='DWord';Value=1};Status='Planned';Error=$null}) }
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if ($PowerPlan -ne 'Keep') {
    # 计算本行表达式并设置 $before，供后续步骤使用。
    $before=Read-PowerPlan
    # 计算本行表达式并设置 $target，供后续步骤使用。
    $target=if ($PowerPlan -eq 'Balanced') {'381b4222-f694-41f0-9685-ff5bb260df2e'} else {'8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'}
    # 调用 Windows 电源配置工具，并保存到 $available。
    $available=& "$env:SystemRoot\System32\powercfg.exe" /list 2>&1
    # 检查本行条件；满足时执行对应分支。
    if ($LASTEXITCODE -ne 0 -or ($available -join ' ') -notmatch [regex]::Escape($target)) { throw 'Requested power plan does not exist on this device.' }
    # 检查本行条件；满足时执行对应分支。
    if ($before -eq $target) { Write-Host '目前已使用指定的電源計畫。' }
    # 当前述条件不成立时执行此分支。
    else { $changes.Add([pscustomobject]@{Name='PowerPlan';Before=$before;After=$target;Status='Planned';Error=$null}) }
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if (-not $Apply) {
    # 向终端显示提示或结果。
    Write-Host '預覽模式：沒有變更設定；加 -Apply 才會執行。'
    # 检查本行条件；满足时执行对应分支。
    if (-not $EnableLongPaths -and $PowerPlan -eq 'Keep' -and -not $CreateRestorePoint) {
        # 向终端显示提示或结果。
        Write-Host '建議依診斷選用 -EnableLongPaths。電源計畫與分頁檔先保留現況。'
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 选取记录中的指定字段或条目。
    $changes.ToArray() | Select-Object Name,Before,After,Status
    # 检查本行条件；满足时执行对应分支。
    if ($CreateRestorePoint) { Write-Host '計畫：建立 Windows 系統還原點。' }
    # 返回本行结果并结束当前函数。
    return
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if (-not $admin -and -not $WhatIfPreference) { throw '此部分需要系統管理員 PowerShell；未變更任何設定。資料分析套件安裝不需要管理員。' }
# 检查本行条件；满足时执行对应分支。
if ($WhatIfPreference) {
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($change in $changes) { [void]$PSCmdlet.ShouldProcess($change.Name,'保存原設定並套用新設定') }
    # 检查本行条件；满足时执行对应分支。
    if ($CreateRestorePoint) { [void]$PSCmdlet.ShouldProcess('Windows','建立系統還原點') }
    # 返回本行结果并结束当前函数。
    return
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if ($CreateRestorePoint -and $PSCmdlet.ShouldProcess('Windows','建立系統還原點')) {
    # Fail rather than claiming a backup exists when System Protection is disabled.
    # 请求建立系统还原点；生成当前时间或格式化时间戳。
    Checkpoint-Computer -Description ('DataWorkbench '+(Get-Date -Format 'yyyyMMdd-HHmmss')) -RestorePointType MODIFY_SETTINGS
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if ($changes.Count -eq 0) { Write-Host '沒有需要變更的設定。'; return }
# 计算本行表达式并设置 $script:journalPath，供后续步骤使用。
$script:journalPath=$null
# 生成当前时间或格式化时间戳，并保存到 $script:journal。
$script:journal=[ordered]@{Schema='DataWorkbench.SystemSettings.v1';ComputerName=$env:COMPUTERNAME;Created=(Get-Date).ToString('o');Changes=$changes.ToArray()}
# 按本行的迭代范围或条件重复执行循环体。
foreach ($change in $changes) {
    # 检查本行条件；满足时执行对应分支。
    if (-not $PSCmdlet.ShouldProcess($change.Name,'保存原設定、套用並驗證')) { continue }
    # 检查本行条件；满足时执行对应分支。
    if (-not $script:journalPath) {
        # 构造或计算 $folder，保存本行指定的集合或索引结果。
        $folder=[IO.Path]::GetFullPath($BackupDirectory)
        # 继续当前表达式，补充参数、类型转换或结果处理。
        [void][IO.Directory]::CreateDirectory($folder)
        # 生成当前时间或格式化时间戳；组合父目录与子路径，并保存到 $script:journalPath。
        $script:journalPath=Join-Path $folder ('settings-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.json')
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 计算本行表达式并设置 $change.Status，供后续步骤使用。
    $change.Status='Pending'
    # 保存可用于审查和恢复的变更记录。
    Save-Journal
    # 开始受异常处理保护的操作。
    try {
        # 检查本行条件；满足时执行对应分支。
        if ($change.Name -eq 'LongPaths') {
            # 创建或写入指定注册表属性；创建指定目录、文件或配置项；丢弃不需要显示的输出。
            New-ItemProperty -LiteralPath $key -Name $name -PropertyType DWord -Value 1 -Force | Out-Null
            # 检查本行条件；满足时执行对应分支。
            if ((Read-LongPaths).Value -ne 1) { throw 'LongPaths verification failed.' }
        # 结束上一代码块并进入另一条件分支。
        } else { Set-PowerPlan $change.After }
        # 计算本行表达式并设置 $change.Status，供后续步骤使用。
        $change.Status='Applied'
        # 保存可用于审查和恢复的变更记录。
        Save-Journal
        # 向终端显示提示或结果。
        Write-Host ($change.Name+'：已套用並驗證。')
    # 结束上一代码块并进入异常处理。
    } catch {
        # 计算本行表达式并设置 $change.Status，供后续步骤使用。
        $change.Status='Failed'; $change.Error=$_.Exception.Message
        # 保存可用于审查和恢复的变更记录。
        Save-Journal
        # 报告本行指定的错误并中止当前执行路径。
        throw
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if ($script:journalPath) { Write-Host ('還原資料：'+$script:journalPath) }
# 向终端显示提示或结果。
Write-Host '完成。長路徑需要應用程式支援，部分程序須重新啟動或重新開機才會生效。'
