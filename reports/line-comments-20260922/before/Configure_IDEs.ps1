<#
.SYNOPSIS
    Apply the analyst / quant-research configuration to RStudio, Positron and PyCharm.

.DESCRIPTION
    MUST be run from a NORMAL PowerShell window (Win+X -> Terminal), NOT from inside
    the Claude desktop app. The Claude app is an MSIX-packaged application: everything
    it writes into %APPDATA% / %LOCALAPPDATA% is silently redirected into
    ...\Packages\Claude_<id>\LocalCache\, where the real IDEs never look. This script
    refuses to run when it detects that redirection.

    Every file it touches is copied to a timestamped backup folder first.
    Nothing here needs administrator rights.

.PARAMETER InstallTinyTeX
    Also install TinyTeX (~320 MB, user-level) so Quarto / R Markdown can produce PDF.

.PARAMETER InstallRPackages
    Also install the missing R packages used by the checks (tseries, RhpcBLASctl, svglite).

.EXAMPLE
    .\Configure_IDEs.ps1 -WhatIf
    .\Configure_IDEs.ps1
    .\Configure_IDEs.ps1 -InstallTinyTeX -InstallRPackages
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$SkipRStudio,
    [switch]$SkipPositron,
    [switch]$SkipPyCharm,
    [switch]$InstallTinyTeX,
    [switch]$InstallRPackages
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$PythonEnv = 'C:/work/envs/ds/Scripts/python.exe'
$RscriptExe = 'C:/Program Files/R/R-4.6.1/bin/x64/Rscript.exe'

function Write-Head($t) { Write-Host ''; Write-Host ('=== ' + $t + ' ===') -ForegroundColor Cyan }
function Write-Ok  ($t) { Write-Host ('  [OK]   ' + $t) -ForegroundColor Green }
function Write-Warn($t) { Write-Host ('  [WARN] ' + $t) -ForegroundColor Yellow }
function Write-Bad ($t) { Write-Host ('  [FAIL] ' + $t) -ForegroundColor Red }

# ---------------------------------------------------------------- guard rails
Write-Head 'Pre-flight'

# The probe deliberately uses [System.IO.File] rather than Set-Content: this check
# must still run under -WhatIf, otherwise the very run that is meant to be a dry run
# is the one that silently skips the sandbox detection.
$probeName = '_redir_probe_' + [guid]::NewGuid().ToString('N') + '.tmp'
$probe = Join-Path $env:APPDATA $probeName
[System.IO.File]::WriteAllText($probe, 'probe')
$redirected = $false
foreach ($pkg in (Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -ErrorAction SilentlyContinue)) {
    $shadow = Join-Path $pkg.FullName ('LocalCache/Roaming/' + $probeName)
    if ([System.IO.File]::Exists($shadow)) {
        $redirected = $true
        Write-Bad ('%APPDATA% writes are being redirected into ' + $pkg.Name)
    }
}
if ([System.IO.File]::Exists($probe)) { [System.IO.File]::Delete($probe) }
if ($redirected) {
    Write-Bad 'Run this script from a normal PowerShell window instead. Aborting.'
    exit 2
}
Write-Ok 'Writes to %APPDATA% are real (not sandboxed).'

$busy = Get-Process -Name 'rstudio', 'rsession', 'Positron', 'pycharm64', 'Rgui', 'Rterm' -ErrorAction SilentlyContinue
if ($busy) {
    Write-Bad ('Close these first, they rewrite their settings on exit: ' + (($busy.Name | Sort-Object -Unique) -join ', '))
    exit 3
}
Write-Ok 'No RStudio / Positron / PyCharm / R process is running.'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backup = Join-Path $env:USERPROFILE ('ide_config_backup_' + $stamp)
if ($PSCmdlet.ShouldProcess($backup, 'create backup folder')) {
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
}
Write-Ok ('Backups -> ' + $backup)

function Backup-One($path, $asName) {
    if (Test-Path $path) {
        Copy-Item -LiteralPath $path -Destination (Join-Path $backup $asName) -Force
        Write-Ok ('backed up ' + $path)
    }
    else {
        Write-Warn ('not present yet, will be created: ' + $path)
    }
}

function Read-JsonAsHashtable($path) {
    $h = @{}
    if (Test-Path $path) {
        $raw = Get-Content -LiteralPath $path -Raw
        if ($raw -and $raw.Trim()) {
            ($raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }
        }
    }
    return $h
}

# ------------------------------------------------------------------- RStudio
if (-not $SkipRStudio) {
    Write-Head 'RStudio'
    $prefPath = Join-Path $env:APPDATA 'RStudio/rstudio-prefs.json'
    Backup-One $prefPath 'rstudio-prefs.json'
    $prefs = Read-JsonAsHashtable $prefPath

    # Reproducibility: never carry a hidden .RData from one session into the next.
    $prefs['save_workspace'] = 'never'
    $prefs['load_workspace'] = $false
    $prefs['always_save_history'] = $true
    $prefs['remove_history_duplicates'] = $true

    # Point reticulate and the Python pane at the curated 190-package environment.
    $prefs['python_type'] = 'virtualenv'
    $prefs['python_version'] = '3.13.15'
    $prefs['python_path'] = $PythonEnv

    # Rendering and encoding.
    $prefs['graphics_backend'] = 'ragg'
    $prefs['default_encoding'] = 'UTF-8'

    # Editor hygiene.
    $prefs['auto_detect_indentation'] = $true
    $prefs['highlight_selected_line'] = $true
    $prefs['syntax_color_console'] = $true
    $prefs['full_project_path_in_window_title'] = $true
    $prefs['auto_append_newline'] = $true
    $prefs['strip_trailing_whitespace'] = $true
    $prefs['save_files_before_build'] = $true

    if ($PSCmdlet.ShouldProcess($prefPath, 'write merged preferences')) {
        New-Item -ItemType Directory -Path (Split-Path $prefPath -Parent) -Force | Out-Null
        ($prefs | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $prefPath -Encoding UTF8
        Write-Ok ('wrote ' + $prefPath + ' (' + $prefs.Count + ' keys)')
    }
}

# ------------------------------------------------------------------ Positron
if (-not $SkipPositron) {
    Write-Head 'Positron'
    $setPath = Join-Path $env:APPDATA 'Positron/User/settings.json'
    Backup-One $setPath 'positron-settings.json'
    $set = Read-JsonAsHashtable $setPath

    $set['files.encoding'] = 'utf8'
    $set['files.trimTrailingWhitespace'] = $true
    $set['files.insertFinalNewline'] = $true
    $set['editor.rulers'] = @(80, 120)
    $set['python.defaultInterpreterPath'] = $PythonEnv
    $set['jupyter.askForKernelRestart'] = $false
    $set['notebook.output.textLineLimit'] = 300
    $set['telemetry.telemetryLevel'] = 'off'
    $set['git.autofetch'] = $false
    $set['[python]'] = @{
        'editor.defaultFormatter'  = 'charliermarsh.ruff'
        'editor.formatOnSave'      = $true
        'editor.codeActionsOnSave' = @{ 'source.organizeImports' = 'explicit' }
    }
    $set['[r]'] = @{
        'editor.defaultFormatter' = 'Posit.air-vscode'
        'editor.formatOnSave'     = $true
    }

    if ($PSCmdlet.ShouldProcess($setPath, 'write merged settings')) {
        New-Item -ItemType Directory -Path (Split-Path $setPath -Parent) -Force | Out-Null
        ($set | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $setPath -Encoding UTF8
        Write-Ok ('wrote ' + $setPath + ' (' + $set.Count + ' keys)')
    }
}

# ------------------------------------------------------------------- PyCharm
if (-not $SkipPyCharm) {
    Write-Head 'PyCharm'
    $cfgDir = Get-ChildItem (Join-Path $env:APPDATA 'JetBrains') -Directory -Filter 'PyCharm*' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
    $binDir = Get-ChildItem (Join-Path $env:ProgramFiles 'JetBrains') -Directory -Filter 'PyCharm*' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1

    if (-not $cfgDir -or -not $binDir) {
        Write-Warn 'PyCharm config or install directory not found, skipping.'
    }
    else {
        $src = Join-Path $binDir.FullName 'bin/pycharm64.exe.vmoptions'
        $dst = Join-Path $cfgDir.FullName 'pycharm64.exe.vmoptions'
        Backup-One $dst 'pycharm64.exe.vmoptions'

        # Start from the bundled defaults - exactly what Help | Edit Custom VM Options does -
        # then raise the heap. 2 GB is thin for large notebooks plus indexing on a 32 GB box.
        $lines = Get-Content -LiteralPath $src | ForEach-Object {
            if ($_ -match '^-Xmx') { '-Xmx4096m' }
            elseif ($_ -match '^-Xms') { '-Xms512m' }
            else { $_ }
        }
        if ($PSCmdlet.ShouldProcess($dst, 'write custom VM options')) {
            $lines | Set-Content -LiteralPath $dst -Encoding ASCII
            Write-Ok ('wrote ' + $dst + ' (heap 2048m -> 4096m)')
        }
        Write-Warn 'Interpreter still has to be picked once in the UI: Settings | Project | Python Interpreter'
    }
}

# -------------------------------------------------------------------- TinyTeX
if ($InstallTinyTeX) {
    Write-Head 'TinyTeX (PDF output for Quarto / R Markdown)'
    if (-not (Test-Path $RscriptExe)) {
        Write-Bad 'Rscript not found.'
    }
    elseif ($PSCmdlet.ShouldProcess('TinyTeX', 'install')) {
        & $RscriptExe -e "tinytex::install_tinytex(force = TRUE)"
        & $RscriptExe -e "cat('IS_TINYTEX:', as.character(tinytex::is_tinytex()), ' ROOT:', tinytex::tinytex_root())"
    }
}

# --------------------------------------------------------------- R packages
if ($InstallRPackages) {
    Write-Head 'R packages'
    if ($PSCmdlet.ShouldProcess('tseries, RhpcBLASctl, svglite', 'install')) {
        & $RscriptExe -e "install.packages(c('tseries','RhpcBLASctl','svglite'), repos='https://cloud.r-project.org')"
        & $RscriptExe -e "for (p in c('tseries','RhpcBLASctl','svglite')) cat(p, '=', if (requireNamespace(p, quietly=TRUE)) 'installed' else 'MISSING', ' ')"
    }
}

# ----------------------------------------------------------------- verify
Write-Head 'Verification (read back what is actually on disk)'
$prefPath = Join-Path $env:APPDATA 'RStudio/rstudio-prefs.json'
if (Test-Path $prefPath) {
    $p = Get-Content -LiteralPath $prefPath -Raw | ConvertFrom-Json
    Write-Ok ('RStudio python_path    = ' + $p.python_path)
    Write-Ok ('RStudio save_workspace = ' + $p.save_workspace)
    Write-Ok ('RStudio graphics       = ' + $p.graphics_backend)
}
$setPath = Join-Path $env:APPDATA 'Positron/User/settings.json'
if (Test-Path $setPath) {
    $s = Get-Content -LiteralPath $setPath -Raw | ConvertFrom-Json
    Write-Ok ('Positron interpreter   = ' + $s.'python.defaultInterpreterPath')
}
$vmDir = Get-ChildItem (Join-Path $env:APPDATA 'JetBrains') -Directory -Filter 'PyCharm*' -ErrorAction SilentlyContinue |
Sort-Object Name -Descending | Select-Object -First 1
if ($vmDir) {
    $vmf = Join-Path $vmDir.FullName 'pycharm64.exe.vmoptions'
    if (Test-Path $vmf) {
        Write-Ok ('PyCharm heap           = ' + ((Get-Content $vmf | Where-Object { $_ -match '^-Xmx' }) -join ''))
    }
}
Write-Host ''
Write-Host ('Done. Restore point: ' + $backup) -ForegroundColor Cyan
