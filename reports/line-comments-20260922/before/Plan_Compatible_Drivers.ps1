#Requires -Version 5.1
param([string]$Root=(Join-Path $PSScriptRoot '..\reports\2026-09-21\update-round2\drivers'))
$ErrorActionPreference='Stop'
$Root=[IO.Path]::GetFullPath($Root)
$board=Get-CimInstance Win32_BaseBoard
if ($board.Product -ne 'PRIME H610M-R D4') {throw 'Wrong motherboard'}
$present=@{}
Get-PnpDevice -PresentOnly | ForEach-Object {$present[$_.InstanceId]=$true}
$devices=@(Get-CimInstance Win32_PnPEntity | Where-Object {$present.ContainsKey($_.DeviceID)})
$installed=@{}
Get-CimInstance Win32_PnPSignedDriver | ForEach-Object {$installed[$_.DeviceID]=$_}
$plans=New-Object System.Collections.Generic.List[object]
$packages=@('DRV_Chipset_ADL_SZ_TSD_W11_64_V101375_20251209R','DRV_SerialIO_RPL_SZ_TSD_W11_64_V30100253131_20251210R','DRV_LAN_Realtek_8111_SZ-TSD_W11_64_V11682750919_20251230R','DRV_MEI_Intel_Consumer_SZ_TSD_W11_64_V25528100_20260120R')
foreach($package in $packages){
  foreach($inf in (Get-ChildItem (Join-Path $Root $package) -Recurse -Filter '*.inf')){
    $body=Get-Content -LiteralPath $inf.FullName -Raw
    $version=[regex]::Match($body,'(?im)^\s*DriverVer\s*=\s*[^,\r\n]+,\s*([\d.]+)').Groups[1].Value
    if(-not $version){continue}
    $matchesFound=New-Object System.Collections.Generic.List[object]
    $lower=$false
    foreach($device in $devices){
      $hit=$false
      foreach($hw in @($device.HardwareID)+@($device.CompatibleID)){
        if($hw -and $body -match ('(?im)^[^;\r\n][^\r\n]*,\s*'+[regex]::Escape($hw)+'\s*(?:,|;|$)')){$hit=$true;break}
      }
      if($hit){
        $old=$installed[$device.DeviceID]
        if($old.DriverVersion -and [version]$version -lt [version]$old.DriverVersion){$lower=$true}
        $matchesFound.Add([pscustomobject]@{Name=$device.Name;DeviceID=$device.DeviceID;Before=$old.DriverVersion;BeforeInf=$old.InfName;Problem=$device.ConfigManagerErrorCode})
      }
    }
    if($matchesFound.Count -eq 0){continue}
    $catalog=[regex]::Match($body,'(?im)^\s*CatalogFile(?:\.[^=\s]+)?\s*=\s*([^;\r\n]+)').Groups[1].Value.Trim().Trim('"')
    $catPath=Join-Path $inf.DirectoryName $catalog
    $signature=if($catalog -and (Test-Path -LiteralPath $catPath)){Get-AuthenticodeSignature -LiteralPath $catPath}else{$null}
    $plans.Add([pscustomobject]@{Inf=$inf.FullName;Version=$version;SHA256=(Get-FileHash -LiteralPath $inf.FullName).Hash;Catalog=$catPath;CatalogSHA256=$(if(Test-Path -LiteralPath $catPath -PathType Leaf){(Get-FileHash -LiteralPath $catPath).Hash});Signature=[string]$signature.Status;Signer=$signature.SignerCertificate.Subject;Decision=$(if($lower){'SkipLowerVersion'}elseif($signature.Status -ne 'Valid'){'SkipUnverifiedSignature'}else{'Eligible'});Devices=$matchesFound.ToArray()})
  }
}
$plans.ToArray() | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $Root 'compatible-plan.json') -Encoding UTF8
$plans | Select-Object @{n='INF';e={Split-Path $_.Inf -Leaf}},Version,Decision,@{n='Devices';e={($_.Devices.Name -join '; ')}} | Format-Table -Wrap
