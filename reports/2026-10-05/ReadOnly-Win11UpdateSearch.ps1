$ErrorActionPreference='Stop'
$sw=[Diagnostics.Stopwatch]::StartNew()
try {
$session=New-Object -ComObject Microsoft.Update.Session
$searcher=$session.CreateUpdateSearcher()
$searcher.Online=$true
$result=$searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
$updates=@(); for($i=0;$i -lt $result.Updates.Count;$i++){ $u=$result.Updates.Item($i);$updates += [pscustomobject]@{Title=$u.Title;IsDownloaded=$u.IsDownloaded;Identity=$u.Identity.UpdateID} }
$sw.Stop()
$r=[ordered]@{Time=(Get-Date -Format o);Mode='Search only; default configured update source; no downloader/installer; no policy changes';ResultCode=[int]$result.ResultCode;Seconds=$sw.Elapsed.TotalSeconds;Count=$result.Updates.Count;Updates=$updates;Error=$null}
} catch {$sw.Stop();$r=[ordered]@{Time=(Get-Date -Format o);Mode='Search only';Seconds=$sw.Elapsed.TotalSeconds;Error=$_.Exception.Message;HResult=$_.Exception.HResult}}
$r | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 reports\2026-10-05\Win11更新提供实测.json
$r | ConvertTo-Json -Depth 5
