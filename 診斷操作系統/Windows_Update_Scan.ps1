#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory=(Join-Path $PSScriptRoot '..\reports\2026-09-21\update-round2'))
$ErrorActionPreference='Stop'
$out=[IO.Path]::GetFullPath($OutputDirectory)
$null=New-Item -ItemType Directory -Path $out -Force
$session=New-Object -ComObject Microsoft.Update.Session
$session.ClientApplicationID='Local workstation verification'
$searcher=$session.CreateUpdateSearcher()
# Keep configured update service and all enterprise policy. No public-service override.
$result=$searcher.Search("IsInstalled=0 and IsHidden=0")
$rows=@(foreach($u in $result.Updates) {
    [pscustomobject]@{Title=$u.Title;Identity=$u.Identity.UpdateID;Revision=$u.Identity.RevisionNumber;Type=[int]$u.Type;Downloaded=$u.IsDownloaded;EulaAccepted=$u.EulaAccepted;MaxDownloadSize=$u.MaxDownloadSize;RebootBehavior=[int]$u.InstallationBehavior.RebootBehavior}
})
[pscustomobject]@{CheckedAt=(Get-Date -Format o);ResultCode=[int]$result.ResultCode;Count=$rows.Count;Updates=$rows} | ConvertTo-Json -Depth 5 | Tee-Object -FilePath (Join-Path $out 'windows-update-scan.json')
