Set-Location -LiteralPath 'C:\Users\PPCCpcpc\Documents\GitHub\qianghua_xianyou_ziyuan_shichuang_dishiban'
$out=Join-Path (Get-Location) 'reports\2026-10-05\Win11源映像只读核验'
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class OfflineHiveProbe {
[DllImport("offreg.dll",CharSet=CharSet.Unicode)] public static extern uint OROpenHive(string path,out IntPtr handle);
[DllImport("offreg.dll")] public static extern uint ORCloseHive(IntPtr handle);
}
"@
$results=foreach($name in 'SYSTEM','SOFTWARE') {
 $path=Join-Path $out ($name+'-source.hive')
 try {
  $b=[IO.File]::ReadAllBytes($path);[IntPtr]$h=[IntPtr]::Zero
  $r=[OfflineHiveProbe]::OROpenHive($path,[ref]$h)
  if($h -ne [IntPtr]::Zero){$null=[OfflineHiveProbe]::ORCloseHive($h)}
  [pscustomobject]@{Name=$name;Length=$b.Length;Signature=[Text.Encoding]::ASCII.GetString($b,0,4);Sequence1=[BitConverter]::ToUInt32($b,4);Sequence2=[BitConverter]::ToUInt32($b,8);Major=[BitConverter]::ToUInt32($b,20);Minor=[BitConverter]::ToUInt32($b,24);OfflineLibraryOpenResult=$r}
 } catch {[pscustomobject]@{Name=$name;Error=$_.Exception.Message}}
}
$results | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $out 'offline-hive-probe.json')
