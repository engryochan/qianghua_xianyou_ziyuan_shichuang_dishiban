#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory=(Join-Path $PSScriptRoot '..\reports\2026-09-21\update-round2'))
$ErrorActionPreference='Stop'
$out=[IO.Path]::GetFullPath($OutputDirectory)
$null=New-Item -ItemType Directory -Path $out -Force
$rows=New-Object System.Collections.Generic.List[object]
# Exact products already installed and found by winget upgrade. No force or reboot flag.
$ids=@('MoonshotAI.Kimi','Microsoft.Teams','JetBrains.PyCharm','Adobe.Acrobat.Reader.64-bit','Microsoft.Edge','Microsoft.VCRedist.2015+.x64','Microsoft.VCRedist.2015+.x86')
foreach ($id in $ids) {
    Write-Host ('Updating '+$id+' at '+(Get-Date -Format o))
    $file=Join-Path $out ($id+'.log')
    & winget upgrade --id $id --exact --source winget --silent --accept-source-agreements --accept-package-agreements --disable-interactivity *> $file
    $code=$LASTEXITCODE
    $rows.Add([pscustomobject]@{Id=$id;ExitCode=$code;Finished=(Get-Date -Format o);Log=$file})
    $rows | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $out 'apps-install-results.json') -Encoding UTF8
    Write-Host ('Exit='+$code+' '+$id)
    Get-Content -LiteralPath $file -Tail 6 | Write-Host
}
& winget upgrade --source winget --accept-source-agreements --disable-interactivity *> (Join-Path $out 'winget-after.txt')
Get-Content (Join-Path $out 'winget-after.txt') -Tail 25
