$ErrorActionPreference='Continue'
Set-Location -LiteralPath 'C:\Users\PPCCpcpc\Documents\GitHub\qianghua_xianyou_ziyuan_shichuang_dishiban'
$out='reports\2026-10-05\Win11根因只读诊断'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$id=[Security.Principal.WindowsIdentity]::GetCurrent();$principal=New-Object Security.Principal.WindowsPrincipal($id)
$results=[ordered]@{Time=(Get-Date -Format o);Account=$id.Name;Elevated=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}
$results | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $out 'started.json')
if(-not $results.Elevated){exit 740}
& reagentc /info 2>&1 | Out-File -Encoding UTF8 (Join-Path $out 'reagentc.txt'); $results.ReagentExit=$LASTEXITCODE
& dism /Online /Cleanup-Image /CheckHealth 2>&1 | Out-File -Encoding UTF8 (Join-Path $out 'dism-checkhealth.txt');$results.CheckHealthExit=$LASTEXITCODE
& dism /Online /Cleanup-Image /ScanHealth 2>&1 | Out-File -Encoding UTF8 (Join-Path $out 'dism-scanhealth.txt');$results.ScanHealthExit=$LASTEXITCODE
& sfc /verifyonly 2>&1 | Out-File -Encoding UTF8 (Join-Path $out 'sfc-verifyonly.txt');$results.SfcExit=$LASTEXITCODE
Get-WinEvent -FilterHashtable @{LogName='System';StartTime=(Get-Date).AddDays(-2);Id=7,51,55,98,129,153} -ErrorAction SilentlyContinue | Select-Object TimeCreated,Id,ProviderName,Message | ConvertTo-Json -Depth 3 | Set-Content -Encoding UTF8 (Join-Path $out 'disk-events.json')
Get-Content -LiteralPath 'C:\Windows\Logs\CBS\CBS.log' -Tail 1500 -ErrorAction SilentlyContinue | Select-String '\[SR\]|corrupt|cannot repair' | ForEach-Object {$_.Line} | Set-Content -Encoding UTF8 (Join-Path $out 'cbs-evidence.txt')
$results.End=(Get-Date -Format o);$results | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $out 'done.json')
