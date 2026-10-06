Set-Location -LiteralPath 'C:\Users\PPCCpcpc\Documents\GitHub\qianghua_xianyou_ziyuan_shichuang_dishiban'
$out='reports\2026-10-05\Win11源映像只读核验'
$src=(Get-ChildItem -LiteralPath 'C:\Users\PPCCpcpc\AppData\Local\Temp' -Filter '*25h2*.esd' -File | Select-Object -First 1).FullName
$dest=Join-Path (Get-Location) (Join-Path $out 'professional-integrity-test.wim')
if(Test-Path -LiteralPath $dest){throw 'Diagnostic image already exists; no overwrite'}
& dism /Export-Image "/SourceImageFile:$src" /SourceIndex:7 "/DestinationImageFile:$dest" /Compress:max /CheckIntegrity 2>&1 | Out-File -Encoding UTF8 (Join-Path $out 'export-integrity.txt')
[pscustomobject]@{Time=(Get-Date -Format o);ExitCode=$LASTEXITCODE;Destination=$dest} | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $out 'export-done.json')
