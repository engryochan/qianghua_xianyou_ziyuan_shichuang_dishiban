$ErrorActionPreference='Stop'
Set-Location -LiteralPath 'C:\Users\PPCCpcpc\Documents\GitHub\qianghua_xianyou_ziyuan_shichuang_dishiban'
$out='reports\2026-10-05\Win11官方ISO挂载核验.json'
try {
 $iso=(Resolve-Path 'reports\2026-10-05\Windows11_Client_x64_zh-cn_26300_9457.iso').Path
 $disk=Get-DiskImage -ImagePath $iso
 if(-not $disk.Attached){$disk=Mount-DiskImage -ImagePath $iso -Access ReadOnly -PassThru}
 $vol=$disk | Get-Volume
 $setup=Join-Path ($vol.DriveLetter+':\') 'setup.exe'
 $sig=Get-AuthenticodeSignature -LiteralPath $setup
 $file=Get-Item -LiteralPath $setup
 [pscustomobject]@{Time=(Get-Date -Format o);ISO=$iso;Drive=($vol.DriveLetter+':');Setup=$setup;SignatureStatus=[string]$sig.Status;Signer=$sig.SignerCertificate.Subject;FileVersion=$file.VersionInfo.FileVersion;SetupStarted=$false} | ConvertTo-Json | Set-Content -LiteralPath $out -Encoding UTF8
} catch { [pscustomobject]@{Time=(Get-Date -Format o);Error=$_.Exception.Message;SetupStarted=$false} | ConvertTo-Json | Set-Content -LiteralPath $out -Encoding UTF8 }
