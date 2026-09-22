#Requires -Version 5.1
# 声明脚本或函数接受的参数及默认值。
param([string]$Root=(Join-Path $PSScriptRoot '..\reports\2026-09-21\update-round2\drivers'))
# 设置本脚本遇到 PowerShell 错误时的处理方式。
$ErrorActionPreference='Stop'
# 构造或计算 $Root，保存本行指定的集合或索引结果。
$Root=[IO.Path]::GetFullPath($Root)
# 查询 Windows 管理接口中的设备或系统信息，并保存到 $board。
$board=Get-CimInstance Win32_BaseBoard
# 检查本行条件；满足时执行对应分支。
if ($board.Product -ne 'PRIME H610M-R D4') {throw 'Wrong motherboard'}
# 计算本行表达式并设置 $present，供后续步骤使用。
$present=@{}
# 读取即插即用设备及其当前状态；逐项处理管道传入的记录。
Get-PnpDevice -PresentOnly | ForEach-Object {$present[$_.InstanceId]=$true}
# 查询 Windows 管理接口中的设备或系统信息；按条件筛选输入记录，并保存到 $devices。
$devices=@(Get-CimInstance Win32_PnPEntity | Where-Object {$present.ContainsKey($_.DeviceID)})
# 计算本行表达式并设置 $installed，供后续步骤使用。
$installed=@{}
# 查询 Windows 管理接口中的设备或系统信息；逐项处理管道传入的记录。
Get-CimInstance Win32_PnPSignedDriver | ForEach-Object {$installed[$_.DeviceID]=$_}
# 创建指定类型的对象，并保存到 $plans。
$plans=New-Object System.Collections.Generic.List[object]
# 构造或计算 $packages，保存本行指定的集合或索引结果。
$packages=@('DRV_Chipset_ADL_SZ_TSD_W11_64_V101375_20251209R','DRV_SerialIO_RPL_SZ_TSD_W11_64_V30100253131_20251210R','DRV_LAN_Realtek_8111_SZ-TSD_W11_64_V11682750919_20251230R','DRV_MEI_Intel_Consumer_SZ_TSD_W11_64_V25528100_20260120R')
# 按本行的迭代范围或条件重复执行循环体。
foreach($package in $packages){
  # 按本行的迭代范围或条件重复执行循环体。
  foreach($inf in (Get-ChildItem (Join-Path $Root $package) -Recurse -Filter '*.inf')){
    # 读取文件内容供后续处理，并保存到 $body。
    $body=Get-Content -LiteralPath $inf.FullName -Raw
    # 构造或计算 $version，保存本行指定的集合或索引结果。
    $version=[regex]::Match($body,'(?im)^\s*DriverVer\s*=\s*[^,\r\n]+,\s*([\d.]+)').Groups[1].Value
    # 检查本行条件；满足时执行对应分支。
    if(-not $version){continue}
    # 创建指定类型的对象，并保存到 $matchesFound。
    $matchesFound=New-Object System.Collections.Generic.List[object]
    # 计算本行表达式并设置 $lower，供后续步骤使用。
    $lower=$false
    # 按本行的迭代范围或条件重复执行循环体。
    foreach($device in $devices){
      # 计算本行表达式并设置 $hit，供后续步骤使用。
      $hit=$false
      # 按本行的迭代范围或条件重复执行循环体。
      foreach($hw in @($device.HardwareID)+@($device.CompatibleID)){
        # 检查本行条件；满足时执行对应分支。
        if($hw -and $body -match ('(?im)^[^;\r\n][^\r\n]*,\s*'+[regex]::Escape($hw)+'\s*(?:,|;|$)')){$hit=$true;break}
      # 结束此处的代码块、参数列表或集合定义。
      }
      # 检查本行条件；满足时执行对应分支。
      if($hit){
        # 构造或计算 $old，保存本行指定的集合或索引结果。
        $old=$installed[$device.DeviceID]
        # 检查本行条件；满足时执行对应分支。
        if($old.DriverVersion -and [version]$version -lt [version]$old.DriverVersion){$lower=$true}
        # 调用 $matchesFound.Add，使用本行列出的输入完成对应操作。
        $matchesFound.Add([pscustomobject]@{Name=$device.Name;DeviceID=$device.DeviceID;Before=$old.DriverVersion;BeforeInf=$old.InfName;Problem=$device.ConfigManagerErrorCode})
      # 结束此处的代码块、参数列表或集合定义。
      }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 检查本行条件；满足时执行对应分支。
    if($matchesFound.Count -eq 0){continue}
    # 构造或计算 $catalog，保存本行指定的集合或索引结果。
    $catalog=[regex]::Match($body,'(?im)^\s*CatalogFile(?:\.[^=\s]+)?\s*=\s*([^;\r\n]+)').Groups[1].Value.Trim().Trim('"')
    # 组合父目录与子路径，并保存到 $catPath。
    $catPath=Join-Path $inf.DirectoryName $catalog
    # 读取文件签名及其验证状态；检查目标路径是否存在，并保存到 $signature。
    $signature=if($catalog -and (Test-Path -LiteralPath $catPath)){Get-AuthenticodeSignature -LiteralPath $catPath}else{$null}
    # 计算文件哈希以核对内容是否变化；检查目标路径是否存在。
    $plans.Add([pscustomobject]@{Inf=$inf.FullName;Version=$version;SHA256=(Get-FileHash -LiteralPath $inf.FullName).Hash;Catalog=$catPath;CatalogSHA256=$(if(Test-Path -LiteralPath $catPath -PathType Leaf){(Get-FileHash -LiteralPath $catPath).Hash});Signature=[string]$signature.Status;Signer=$signature.SignerCertificate.Subject;Decision=$(if($lower){'SkipLowerVersion'}elseif($signature.Status -ne 'Valid'){'SkipUnverifiedSignature'}else{'Eligible'});Devices=$matchesFound.ToArray()})
  # 结束此处的代码块、参数列表或集合定义。
  }
# 结束此处的代码块、参数列表或集合定义。
}
# 组合父目录与子路径；将内容写入目标文件；把对象序列化为 JSON。
$plans.ToArray() | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $Root 'compatible-plan.json') -Encoding UTF8
# 提取路径中的指定部分；选取记录中的指定字段或条目；把结果排版成表格。
$plans | Select-Object @{n='INF';e={Split-Path $_.Inf -Leaf}},Version,Decision,@{n='Devices';e={($_.Devices.Name -join '; ')}} | Format-Table -Wrap
