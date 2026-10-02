# Find the project root from the validation script location.
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
# Locate the source directory that contains the maintained PowerShell scripts.
$source = Get-ChildItem -LiteralPath $root -Directory | Where-Object { @(Get-ChildItem -LiteralPath $_.FullName -Filter '*.ps1' -File).Count -eq 18 }
# Reject an ambiguous or missing source directory.
if (@($source).Count -ne 1) { throw 'Expected one source directory' }
# Parse all source files without executing their statements.
$rows = @(foreach ($file in Get-ChildItem -LiteralPath $source.FullName -Filter '*.ps1') {
    # Reset token and error references for this file.
    $tokens = $null; $errors = $null
    # Use the current Windows PowerShell parser to validate the annotated file.
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    # Record the number and details of syntax errors.
    [pscustomobject]@{Name=$file.Name;Errors=@($errors).Count;Details=@($errors | ForEach-Object Message)}
# Finish the source-file enumeration.
})
# Save parser evidence beside this validation helper.
$rows | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $PSScriptRoot 'powershell51-validation.json') -Encoding UTF8
# Stop if any script fails the Windows PowerShell 5.1 grammar check.
if (@($rows | Where-Object Errors -ne 0).Count) { throw 'Parser errors found' }
# Report the number of files checked successfully.
Write-Output ('Windows PowerShell ' + $PSVersionTable.PSVersion + ': ' + $rows.Count + ' scripts PASS')
