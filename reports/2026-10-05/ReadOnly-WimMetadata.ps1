Set-Location -LiteralPath 'C:\Users\PPCCpcpc\Documents\GitHub\qianghua_xianyou_ziyuan_shichuang_dishiban'
$out='reports\2026-10-05\Win11源映像只读核验'
$src=(Get-ChildItem -LiteralPath 'C:\Users\PPCCpcpc\AppData\Local\Temp' -Filter '*25h2*.esd' -File | Select-Object -First 1).FullName
& dism /Get-WimInfo "/WimFile:$src" 2>&1 | Out-File -Encoding UTF8 (Join-Path $out 'dism-source-info.txt'); $exit=$LASTEXITCODE
& fltmc filters 2>&1 | Out-File -Encoding UTF8 (Join-Path $out 'filters.txt')
[pscustomobject]@{Time=(Get-Date -Format o);DismSourceInfoExit=$exit;Source=$src} | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $out 'dism-source-done.json')
