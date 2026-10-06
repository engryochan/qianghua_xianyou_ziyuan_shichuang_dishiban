Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class WimReadProbe {
[DllImport("wimgapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern IntPtr WIMCreateFile(string p,uint a,uint d,uint f,uint c,out uint r);
[DllImport("wimgapi.dll",SetLastError=true)] public static extern uint WIMGetImageCount(IntPtr h);
[DllImport("wimgapi.dll",SetLastError=true)] public static extern IntPtr WIMLoadImage(IntPtr h,uint i);
[DllImport("wimgapi.dll",SetLastError=true)] public static extern bool WIMGetImageInformation(IntPtr h,out IntPtr p,out uint n);
[DllImport("wimgapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern bool WIMSetTemporaryPath(IntPtr h,string p);
[DllImport("wimgapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern bool WIMExtractImagePath(IntPtr h,string p,string d,uint f);
[DllImport("wimgapi.dll")] public static extern bool WIMCloseHandle(IntPtr h);
[DllImport("kernel32.dll")] public static extern IntPtr LocalFree(IntPtr p);
}
"@
$dest=Join-Path (Get-Location) 'reports\2026-10-05\Win11源映像只读核验'
New-Item -ItemType Directory -Path $dest -Force | Out-Null
$src=(Get-ChildItem -LiteralPath 'C:\Users\PPCCpcpc\AppData\Local\Temp' -Filter '*25h2*.esd' -File | Select-Object -First 1).FullName
[uint32]$cr=0;$h=[WimReadProbe]::WIMCreateFile($src,2147483648,3,0,0,[ref]$cr)
if($h -eq [IntPtr]::Zero){throw ('Open WIM failed '+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
try {
$null=[WimReadProbe]::WIMSetTemporaryPath($h,$dest)
$count=[WimReadProbe]::WIMGetImageCount($h)
[IntPtr]$buf=[IntPtr]::Zero;[uint32]$sz=0
if([WimReadProbe]::WIMGetImageInformation($h,[ref]$buf,[ref]$sz)){$xml=[Runtime.InteropServices.Marshal]::PtrToStringUni($buf);$xml | Set-Content -Encoding Unicode (Join-Path $dest 'image-info.xml');$null=[WimReadProbe]::LocalFree($buf)}
[pscustomobject]@{Source=$src;Count=$count} | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $dest 'source.json')
$img=[WimReadProbe]::WIMLoadImage($h,1)
if($img -eq [IntPtr]::Zero){throw ('Load image failed '+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
try {$target=Join-Path $dest 'SYSTEM-source.hive';$ok=[WimReadProbe]::WIMExtractImagePath($img,'\Windows\System32\config\SYSTEM',$target,0);[pscustomobject]@{ExtractSuccess=$ok;Error=[Runtime.InteropServices.Marshal]::GetLastWin32Error();Target=$target} | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $dest 'extract.json')} finally {$null=[WimReadProbe]::WIMCloseHandle($img)}
} finally {$null=[WimReadProbe]::WIMCloseHandle($h)}
Get-Content -LiteralPath (Join-Path $dest 'source.json'),(Join-Path $dest 'extract.json') -Raw
