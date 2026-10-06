Set-Location -LiteralPath 'C:\Users\PPCCpcpc\Documents\GitHub\qianghua_xianyou_ziyuan_shichuang_dishiban'
$out=Join-Path (Get-Location) 'reports\2026-10-05\Win11源映像只读核验'
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class HiveSourceProbe {
[DllImport("wimgapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern IntPtr WIMCreateFile(string p,uint a,uint d,uint f,uint c,out uint r);
[DllImport("wimgapi.dll",SetLastError=true)] public static extern IntPtr WIMLoadImage(IntPtr h,uint i);
[DllImport("wimgapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern bool WIMSetTemporaryPath(IntPtr h,string p);
[DllImport("wimgapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern bool WIMExtractImagePath(IntPtr h,string p,string d,uint f);
[DllImport("wimgapi.dll")] public static extern bool WIMCloseHandle(IntPtr h);
[DllImport("advapi32.dll",CharSet=CharSet.Unicode)] public static extern int RegLoadAppKey(string p,out IntPtr h,uint access,uint options,uint reserved);
[DllImport("advapi32.dll")] public static extern int RegCloseKey(IntPtr h);
}
"@
$results=@(); [uint32]$creation=0
$handle=[HiveSourceProbe]::WIMCreateFile((Join-Path $out 'professional-integrity-test.wim'),2147483648,3,0,0,[ref]$creation)
if($handle -eq [IntPtr]::Zero){throw ('WIM open: '+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
try {
 $null=[HiveSourceProbe]::WIMSetTemporaryPath($handle,$out)
 $img=[HiveSourceProbe]::WIMLoadImage($handle,1)
 if($img -eq [IntPtr]::Zero){throw 'Cannot load diagnostic image'}
 try {
  foreach($name in @('SYSTEM','SOFTWARE')) {
   $dest=Join-Path $out ($name+'-source.hive')
   if(Test-Path $dest){throw 'Existing extraction; no overwrite'}
   $ok=[HiveSourceProbe]::WIMExtractImagePath($img,('\Windows\System32\config\'+$name),$dest,0)
   $err=[Runtime.InteropServices.Marshal]::GetLastWin32Error()
   [IntPtr]$app=[IntPtr]::Zero; $load=$null
   if($ok){$load=[HiveSourceProbe]::RegLoadAppKey($dest,[ref]$app,131097,1,0);if($app -ne [IntPtr]::Zero){$null=[HiveSourceProbe]::RegCloseKey($app)}}
   $results += [pscustomobject]@{Name=$name;ExtractSuccess=$ok;ExtractError=$err;ProcessPrivateReadOnlyHiveLoadResult=$load;Time=(Get-Date -Format o)}
  }
 } finally {$null=[HiveSourceProbe]::WIMCloseHandle($img)}
} finally {$null=[HiveSourceProbe]::WIMCloseHandle($handle)}
$results | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $out 'hive-probe.json')
