#Requires -Version 5.1
# 启用 PowerShell 高级脚本参数绑定及所列功能。
[CmdletBinding()]
# 声明脚本或函数接受的参数及默认值。
param([switch]$Apply,[string]$Root)
# 设置本脚本遇到 PowerShell 错误时的处理方式。
$ErrorActionPreference='Stop'
# 检查本行条件；满足时执行对应分支。
if(-not $Root){$Root=Join-Path $PSScriptRoot '..\reports\2026-09-21\update-round2\drivers'}
# 构造或计算 $Root，保存本行指定的集合或索引结果。
$Root=[IO.Path]::GetFullPath($Root)
# 读取文件内容供后续处理；组合父目录与子路径；把 JSON 文本解析为对象，并保存到 $candidates。
$candidates=Get-Content (Join-Path $Root 'compatible-plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json
# 按条件筛选输入记录，并保存到 $plan。
$plan=@($candidates | Where-Object Decision -eq 'Eligible')
# 检查本行条件；满足时执行对应分支。
if($plan.Count -eq 0){throw 'No verified candidates'}
# 检查本行条件；满足时执行对应分支。
if(-not $Apply){$plan | Select-Object Inf,Version,Decision;return}
# 生成当前时间或格式化时间戳；组合父目录与子路径，并保存到 $run。
$run=Join-Path $Root ('installation-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
# 创建指定目录、文件或配置项；将不需要的返回值丢弃。
$null=New-Item -ItemType Directory -Path $run
# 生成当前时间或格式化时间戳，并保存到 $status。
$status=[ordered]@{Started=(Get-Date -Format o);State='Checking';RebootRequired=$false;Steps=@();Error=$null}
# 定义 Save-State，封装此函数内的操作。
function Save-State {$status | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $run 'status.json') -Encoding UTF8}
# 保存当前执行状态到日志文件。
Save-State
# 开始受异常处理保护的操作。
try {
  # 检查当前身份是否具有指定权限角色，并保存到 $admin。
  $admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  # 检查本行条件；满足时执行对应分支。
  if(-not $admin){throw 'Administrator credentials required; no drivers changed.'}
  # 检查本行条件；满足时执行对应分支。
  if((Get-CimInstance Win32_BaseBoard).Product -ne 'PRIME H610M-R D4'){throw 'Motherboard mismatch'}
  # 检查本行条件；满足时执行对应分支。
  if((Get-PSDrive C).Free -lt 8GB){throw 'Less than 8 GiB free; stop before backup'}
  # 查询 Windows 管理接口中的设备或系统信息，并保存到 $before。
  $before=@(Get-CimInstance Win32_PnPSignedDriver)
  # 读取即插即用设备及其当前状态；选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $beforeProblems。
  $beforeProblems=@(Get-PnpDevice -PresentOnly | Where-Object Status -ne 'OK' | Select-Object -ExpandProperty InstanceId)
  # 组合父目录与子路径；将记录导出为 CSV 文件；选取记录中的指定字段或条目。
  $before | Select-Object DeviceID,DeviceName,DriverVersion,DriverProviderName,InfName | Export-Csv (Join-Path $run 'before.csv') -NoTypeInformation -Encoding UTF8
  # Recheck all candidates and current versions BEFORE any changes.
  # 按本行的迭代范围或条件重复执行循环体。
  foreach($entry in $plan){
    # 检查本行条件；满足时执行对应分支。
    if(-not $entry.Inf.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'INF outside reviewed directory'}
    # 检查本行条件；满足时执行对应分支。
    if((Get-FileHash -LiteralPath $entry.Inf).Hash -ne $entry.SHA256){throw 'INF changed'}
    # 检查本行条件；满足时执行对应分支。
    if((Get-FileHash -LiteralPath $entry.Catalog).Hash -ne $entry.CatalogSHA256){throw 'Catalog changed'}
    # 检查本行条件；满足时执行对应分支。
    if((Get-AuthenticodeSignature -LiteralPath $entry.Catalog).Status -ne 'Valid'){throw 'Catalog signature invalid'}
    # 按本行的迭代范围或条件重复执行循环体。
    foreach($device in $entry.Devices){
      # 选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $current。
      $current=$before | Where-Object DeviceID -eq $device.DeviceID | Select-Object -First 1
      # 检查本行条件；满足时执行对应分支。
      if([string]$current.DriverVersion -ne [string]$device.Before){throw "Driver changed since plan: $($device.DeviceID). Re-diagnose."}
      # 检查本行条件；满足时执行对应分支。
      if($current.DriverVersion -and [version]$entry.Version -lt [version]$current.DriverVersion){throw 'Lower version rejected'}
    # 结束此处的代码块、参数列表或集合定义。
    }
  # 结束此处的代码块、参数列表或集合定义。
  }
  # 组合父目录与子路径，并保存到 $backup。
  $backup=Join-Path $run 'driver-backup'
  # 创建指定目录、文件或配置项；将不需要的返回值丢弃。
  $null=New-Item -ItemType Directory -Path $backup
  # 组合父目录与子路径；调用 Windows 即插即用驱动管理工具。
  & pnputil.exe /export-driver '*' $backup *> (Join-Path $run 'backup.log')
  # 检查本行条件；满足时执行对应分支。
  if($LASTEXITCODE -ne 0){throw 'Driver export failed; no installation performed'}
  # Checkpoint is extra protection; exported drivers remain the driver rollback source.
  # 开始受异常处理保护的操作。
  try {
    # 加载所需 PowerShell 模块。
    Import-Module Microsoft.PowerShell.Management -ErrorAction Stop
    # 生成当前时间或格式化时间戳，并保存到 $restoreDescription。
    $restoreDescription='Verified ASUS drivers '+(Get-Date -Format 'yyyyMMdd-HHmmss')
    # 请求建立系统还原点。
    Checkpoint-Computer -Description $restoreDescription -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    # 读取现有系统还原点，并保存到 $points。
    $points=@(Get-ComputerRestorePoint -ErrorAction Stop)
    # 组合父目录与子路径；将内容写入目标文件；把对象序列化为 JSON。
    $points | Select-Object SequenceNumber,Description,CreationTime | ConvertTo-Json | Set-Content (Join-Path $run 'restore-points.json') -Encoding UTF8
    # 计算本行表达式并设置 $status.RestorePoint，供后续步骤使用。
    $status.RestorePoint=if($points.Description -contains $restoreDescription){'New restore point verified'}else{'No new restore point; exported drivers available'}
  # 结束上一代码块并进入异常处理。
  } catch {$status.RestorePoint='Unavailable: '+$_.Exception.Message}
  # 保存当前执行状态到日志文件，并保存到 $status.State。
  $status.State='Installing';Save-State
  # 按本行的迭代范围或条件重复执行循环体。
  foreach($entry in $plan){
    # 提取路径中的指定部分，并保存到 $name。
    $name=Split-Path $entry.Inf -Leaf
    # PnP ranks applicability; never force a lower-ranked driver and never reboot here.
    # 组合父目录与子路径；调用 Windows 即插即用驱动管理工具。
    & pnputil.exe /add-driver $entry.Inf /install *> (Join-Path $run ($name+'.log'))
    # 将上一操作的退出状态记录到 $code。
    $code=$LASTEXITCODE
    # 将上一操作的退出状态记录到 $status.Steps。
    $status.Steps+=@([pscustomobject]@{Inf=$name;Version=$entry.Version;ExitCode=$code})
    # 检查本行条件；满足时执行对应分支。
    if($code -eq 3010){$status.RebootRequired=$true}
    # 保存当前执行状态到日志文件。
    Save-State
    # 检查本行条件；满足时执行对应分支。
    if($code -notin @(0,3010)){throw "Installation stopped at $name, exit $code"}
    # 读取即插即用设备及其当前状态；按条件筛选输入记录，并保存到 $newProblems。
    $newProblems=@(Get-PnpDevice -PresentOnly | Where-Object {$_.Status -ne 'OK' -and $_.InstanceId -notin $beforeProblems})
    # 检查本行条件；满足时执行对应分支。
    if($newProblems.Count){throw ('New device problem; stop further updates: '+($newProblems.InstanceId -join ', '))}
  # 结束此处的代码块、参数列表或集合定义。
  }
  # 查询 Windows 管理接口中的设备或系统信息，并保存到 $after。
  $after=@(Get-CimInstance Win32_PnPSignedDriver)
  # 组合父目录与子路径；将记录导出为 CSV 文件；选取记录中的指定字段或条目。
  $after | Select-Object DeviceID,DeviceName,DriverVersion,DriverProviderName,InfName | Export-Csv (Join-Path $run 'after.csv') -NoTypeInformation -Encoding UTF8
  # 读取即插即用设备及其当前状态；选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $problems。
  $problems=@(Get-PnpDevice -PresentOnly | Where-Object Status -ne 'OK' | Select-Object FriendlyName,Problem,InstanceId)
  # 组合父目录与子路径；将内容写入目标文件；把对象序列化为 JSON。
  ConvertTo-Json -InputObject $problems -Depth 4 | Set-Content (Join-Path $run 'problems-after.json') -Encoding UTF8
  # 构造或计算 $lower，保存本行指定的集合或索引结果。
  $lower=@(foreach($old in $before){
    # 选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $new。
    $new=$after | Where-Object DeviceID -eq $old.DeviceID | Select-Object -First 1
    # 检查本行条件；满足时执行对应分支。
    if([string]$old.DriverVersion -eq [string]$new.DriverVersion){continue}
    # 检查本行条件；满足时执行对应分支。
    if($old.DriverVersion -and $new.DriverVersion){
      # 计算本行表达式并设置 $oldVersion，供后续步骤使用。
      $oldVersion=$null;$newVersion=$null
      # 检查本行条件；满足时执行对应分支。
      if(-not [version]::TryParse([string]$old.DriverVersion,[ref]$oldVersion) -or -not [version]::TryParse([string]$new.DriverVersion,[ref]$newVersion)){
        # 报告本行指定的错误并中止当前执行路径。
        throw ('Changed nonnumeric driver version requires review: '+$old.DeviceID)
      # 结束此处的代码块、参数列表或集合定义。
      }
      # 检查本行条件；满足时执行对应分支。
      if($newVersion -lt $oldVersion){$old.DeviceID}
    # 结束此处的代码块、参数列表或集合定义。
    }
  # 结束此处的代码块、参数列表或集合定义。
  })
  # 检查本行条件；满足时执行对应分支。
  if($lower.Count){throw ('Lower installed version detected; retain backups and review: '+($lower -join ', '))}
  # 计算本行表达式并设置 $status.State，供后续步骤使用。
  $status.State=if($problems.Count){'InstalledNeedsDeviceReview'}else{'InstalledDeviceChecksPassed'}
  # 计算本行表达式并设置 $status.RemainingDeviceProblems，供后续步骤使用。
  $status.RemainingDeviceProblems=$problems.Count
# 结束上一代码块并进入异常处理。
} catch {$status.State='Stopped';$status.Error=$_.Exception.Message;throw}
# 无论是否发生异常，都执行此处的收尾操作。
finally{Save-State}
