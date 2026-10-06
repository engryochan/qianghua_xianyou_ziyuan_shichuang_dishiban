$ErrorActionPreference='Stop'
$out='C:\Users\PPCCpcpc\Documents\GitHub\qianghua_xianyou_ziyuan_shichuang_dishiban\reports\2026-10-05\网络类别安全实测_20261006.json'
$result=[ordered]@{Time=(Get-Date -Format o)}
try {$result.Connection=Get-NetConnectionProfile | Select-Object Name,InterfaceAlias,NetworkCategory} catch {$result.ConnectionError=$_.Exception.Message}
try {$result.Profiles=Get-NetFirewallProfile -PolicyStore ActiveStore | Select-Object Name,Enabled,DefaultInboundAction,DefaultOutboundAction,AllowInboundRules,AllowLocalFirewallRules} catch {$result.ProfileError=$_.Exception.Message}
try {
 $rules=@(Get-NetFirewallRule -PolicyStore ActiveStore -Enabled True -Direction Inbound)
 $result.InboundSummary=foreach($profile in 'Public','Private') {
  $r=@($rules | Where-Object {([string]$_.Profile -eq 'Any') -or ([string]$_.Profile -match $profile)})
  [pscustomobject]@{Profile=$profile;AllowCount=@($r | Where-Object Action -eq Allow).Count;BlockCount=@($r | Where-Object Action -eq Block).Count}
 }
 $result.SharingRemoteRules=@($rules | Where-Object {$_.Name -match '^(FPS-|NETDIS-|RemoteDesktop)' } | Select-Object Name,DisplayName,Profile,Action)
} catch {$result.RuleError=$_.Exception.Message}
try {$result.SecurityProducts=Get-CimInstance -Namespace root/SecurityCenter2 -ClassName FirewallProduct | Select-Object displayName,productState} catch {$result.SecurityProductError=$_.Exception.Message}
try {$result.Listeners=Get-NetTCPConnection -State Listen | Where-Object {$_.LocalPort -in 135,139,445,3389,5985,5986} | Select-Object LocalAddress,LocalPort} catch {$result.ListenerError=$_.Exception.Message}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $out -Encoding UTF8
