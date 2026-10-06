$ErrorActionPreference='Stop'
$out='C:\Users\PPCCpcpc\Documents\GitHub\qianghua_xianyou_ziyuan_shichuang_dishiban\reports\2026-10-05\网络改为专用_20261006.json'
try {
 $p=@(Get-NetConnectionProfile | Where-Object {$_.InterfaceAlias -eq '以太网 2' -and $_.Name -eq '网络 2'})
 if($p.Count -ne 1){throw 'Expected exactly one matching network profile; no changes made'}
 $before=[string]$p[0].NetworkCategory
 if($before -eq 'DomainAuthenticated'){throw 'Domain-authenticated profile; no changes made'}
 Set-NetConnectionProfile -InterfaceIndex $p[0].InterfaceIndex -NetworkCategory Private -ErrorAction Stop
 $after=Get-NetConnectionProfile -InterfaceIndex $p[0].InterfaceIndex
 [pscustomobject]@{Time=(Get-Date -Format o);Name=$after.Name;InterfaceAlias=$after.InterfaceAlias;Before=$before;After=[string]$after.NetworkCategory;Success=([string]$after.NetworkCategory -eq 'Private')} | ConvertTo-Json | Set-Content -LiteralPath $out -Encoding UTF8
} catch {[pscustomobject]@{Time=(Get-Date -Format o);Success=$false;Error=$_.Exception.Message} | ConvertTo-Json | Set-Content -LiteralPath $out -Encoding UTF8}
