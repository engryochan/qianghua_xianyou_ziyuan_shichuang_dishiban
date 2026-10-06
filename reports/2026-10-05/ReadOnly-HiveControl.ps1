Set-Location -LiteralPath 'C:\Users\PPCCpcpc\Documents\GitHub\qianghua_xianyou_ziyuan_shichuang_dishiban'
$out=Join-Path (Get-Location) 'reports\2026-10-05\Win11源映像只读核验'
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class HiveControl {
[DllImport("offreg.dll")] public static extern uint ORCreateHive(out IntPtr h);
[DllImport("offreg.dll",CharSet=CharSet.Unicode)] public static extern uint ORSaveHive(IntPtr h,string p,uint major,uint minor);
[DllImport("offreg.dll")] public static extern uint ORCloseHive(IntPtr h);
[DllImport("advapi32.dll",CharSet=CharSet.Unicode)] public static extern int RegLoadAppKey(string p,out IntPtr h,uint access,uint options,uint reserved);
[DllImport("advapi32.dll")] public static extern int RegCloseKey(IntPtr h);
}
"@
$dest=Join-Path $out 'synthetic-empty-control.hive'
if(Test-Path $dest){throw 'No overwrite'}
[IntPtr]$h=[IntPtr]::Zero
$create=[HiveControl]::ORCreateHive([ref]$h)
$save=$null
if($create -eq 0){try{$save=[HiveControl]::ORSaveHive($h,$dest,6,1)}finally{$null=[HiveControl]::ORCloseHive($h)}}
$results=@([pscustomobject]@{Create=$create;Save=$save})
foreach($name in 'synthetic-empty-control.hive','SYSTEM-source.hive','SOFTWARE-source.hive') {
 $path=Join-Path $out $name
 if($name -ne 'synthetic-empty-control.hive'){$copy=Join-Path $out ($name+'.normalcopy');[IO.File]::WriteAllBytes($copy,[IO.File]::ReadAllBytes($path));$path=$copy}
 [IntPtr]$app=[IntPtr]::Zero
 $r=[HiveControl]::RegLoadAppKey($path,[ref]$app,131097,1,0)
 if($app -ne [IntPtr]::Zero){$null=[HiveControl]::RegCloseKey($app)}
 $results += [pscustomobject]@{Name=$name;Result=$r;Time=(Get-Date -Format o)}
}
$results | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $out 'hive-control.json')
