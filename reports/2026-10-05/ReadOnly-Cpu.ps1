Add-Type -TypeDefinition 'using System; using System.Diagnostics; public static class ReadOnlyCpuProbe { public static double Run(int n) { double s=0; for(int i=1;i<=n;i++) s+=Math.Sqrt(i); return s; } }'
$null=[ReadOnlyCpuProbe]::Run(10000)
$times=@();$checks=@()
1..5 | ForEach-Object { $sw=[Diagnostics.Stopwatch]::StartNew();$checks += [ReadOnlyCpuProbe]::Run(20000000);$sw.Stop();$times += $sw.Elapsed.TotalSeconds }
$r=[ordered]@{Time=(Get-Date -Format o);Method='Single thread sum sqrt(i), i=1..20000000; .NET JIT warmup 10000; five repeats; result retained; no disk writes except this report';Seconds=$times;Checksums=$checks;Runtime=[Environment]::Version.ToString();OldComparable=$false}
$r | ConvertTo-Json | Set-Content -Encoding UTF8 reports\2026-10-05\本轮CPU微基准.json
$r | ConvertTo-Json
