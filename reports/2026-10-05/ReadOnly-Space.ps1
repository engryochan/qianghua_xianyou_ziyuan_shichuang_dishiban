$rows=@(); $errors=@()
foreach($d in Get-ChildItem C:\ -Directory -Force -ErrorAction SilentlyContinue){
$e=@(); $m=Get-ChildItem -LiteralPath $d.FullName -File -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable +e | Measure-Object Length -Sum
$rows += [pscustomobject]@{Path=$d.FullName;LogicalBytes=$m.Sum;Files=$m.Count;Errors=$e.Count}; $errors += $e | Select-Object -First 3 | ForEach-Object {$_.ToString()}
}
[ordered]@{Time=(Get-Date -Format o);Method='Logical file lengths; hard links may be counted multiple times; inaccessible paths omitted; not allocated disk bytes';Directories=$rows;ErrorSamples=$errors;Volume=@([IO.DriveInfo]::GetDrives() | Where-Object Name -eq 'C:\' | Select-Object TotalSize,AvailableFreeSpace)} | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 reports\2026-10-05\本轮空间逻辑扫描.json
