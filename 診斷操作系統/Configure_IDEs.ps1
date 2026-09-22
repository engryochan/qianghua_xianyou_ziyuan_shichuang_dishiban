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
# 启用 PowerShell 高级脚本参数绑定及所列功能。
[CmdletBinding(SupportsShouldProcess)]
# 声明脚本或函数接受的参数及默认值。
param(
    # 声明参数 $SkipRStudio的类型、默认值或校验规则。
    [switch]$SkipRStudio,
    # 声明参数 $SkipPositron的类型、默认值或校验规则。
    [switch]$SkipPositron,
    # 声明参数 $SkipPyCharm的类型、默认值或校验规则。
    [switch]$SkipPyCharm,
    # 声明参数 $InstallTinyTeX的类型、默认值或校验规则。
    [switch]$InstallTinyTeX,
    # 声明参数 $InstallRPackages的类型、默认值或校验规则。
    [switch]$InstallRPackages
# 结束此处的代码块、参数列表或集合定义。
)

# 设置本脚本遇到 PowerShell 错误时的处理方式。
$ErrorActionPreference = 'Stop'
# 继续当前表达式，补充参数、类型转换或结果处理。
[Console]::OutputEncoding = [Text.Encoding]::UTF8

# 计算本行表达式并设置 $PythonEnv，供后续步骤使用。
$PythonEnv = 'C:/work/envs/ds/Scripts/python.exe'
# 计算本行表达式并设置 $RscriptExe，供后续步骤使用。
$RscriptExe = 'C:/Program Files/R/R-4.6.1/bin/x64/Rscript.exe'

# 定义 Write-Head，封装此函数内的操作。
function Write-Head($t) { Write-Host ''; Write-Host ('=== ' + $t + ' ===') -ForegroundColor Cyan }
# 定义 Write-Ok，封装此函数内的操作。
function Write-Ok  ($t) { Write-Host ('  [OK]   ' + $t) -ForegroundColor Green }
# 定义 Write-Warn，封装此函数内的操作。
function Write-Warn($t) { Write-Host ('  [WARN] ' + $t) -ForegroundColor Yellow }
# 定义 Write-Bad，封装此函数内的操作。
function Write-Bad ($t) { Write-Host ('  [FAIL] ' + $t) -ForegroundColor Red }

# ---------------------------------------------------------------- guard rails
# 处理 Write-Head 所指定的操作或当前表达式的后续部分。
Write-Head 'Pre-flight'

# The probe deliberately uses [System.IO.File] rather than Set-Content: this check
# must still run under -WhatIf, otherwise the very run that is meant to be a dry run
# is the one that silently skips the sandbox detection.
# 构造或计算 $probeName，保存本行指定的集合或索引结果。
$probeName = '_redir_probe_' + [guid]::NewGuid().ToString('N') + '.tmp'
# 组合父目录与子路径，并保存到 $probe。
$probe = Join-Path $env:APPDATA $probeName
# 将文本写入指定文件。
[System.IO.File]::WriteAllText($probe, 'probe')
# 计算本行表达式并设置 $redirected，供后续步骤使用。
$redirected = $false
# 按本行的迭代范围或条件重复执行循环体。
foreach ($pkg in (Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -ErrorAction SilentlyContinue)) {
    # 组合父目录与子路径，并保存到 $shadow。
    $shadow = Join-Path $pkg.FullName ('LocalCache/Roaming/' + $probeName)
    # 检查本行条件；满足时执行对应分支。
    if ([System.IO.File]::Exists($shadow)) {
        # 计算本行表达式并设置 $redirected，供后续步骤使用。
        $redirected = $true
        # 处理 Write-Bad 所指定的操作或当前表达式的后续部分。
        Write-Bad ('%APPDATA% writes are being redirected into ' + $pkg.Name)
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if ([System.IO.File]::Exists($probe)) { [System.IO.File]::Delete($probe) }
# 检查本行条件；满足时执行对应分支。
if ($redirected) {
    # 处理 Write-Bad 所指定的操作或当前表达式的后续部分。
    Write-Bad 'Run this script from a normal PowerShell window instead. Aborting.'
    # 以指定状态结束当前脚本或进程。
    exit 2
# 结束此处的代码块、参数列表或集合定义。
}
# 处理 Write-Ok 所指定的操作或当前表达式的后续部分。
Write-Ok 'Writes to %APPDATA% are real (not sandboxed).'

# 读取正在运行的进程信息，并保存到 $busy。
$busy = Get-Process -Name 'rstudio', 'rsession', 'Positron', 'pycharm64', 'Rgui', 'Rterm' -ErrorAction SilentlyContinue
# 检查本行条件；满足时执行对应分支。
if ($busy) {
    # 按指定属性排序输入记录。
    Write-Bad ('Close these first, they rewrite their settings on exit: ' + (($busy.Name | Sort-Object -Unique) -join ', '))
    # 以指定状态结束当前脚本或进程。
    exit 3
# 结束此处的代码块、参数列表或集合定义。
}
# 处理 Write-Ok 所指定的操作或当前表达式的后续部分。
Write-Ok 'No RStudio / Positron / PyCharm / R process is running.'

# 生成当前时间或格式化时间戳，并保存到 $stamp。
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
# 组合父目录与子路径，并保存到 $backup。
$backup = Join-Path $env:USERPROFILE ('ide_config_backup_' + $stamp)
# 检查本行条件；满足时执行对应分支。
if ($PSCmdlet.ShouldProcess($backup, 'create backup folder')) {
    # 创建指定目录、文件或配置项；丢弃不需要显示的输出。
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
# 结束此处的代码块、参数列表或集合定义。
}
# 处理 Write-Ok 所指定的操作或当前表达式的后续部分。
Write-Ok ('Backups -> ' + $backup)

# 定义 Backup-One，封装此函数内的操作。
function Backup-One($path, $asName) {
    # 检查本行条件；满足时执行对应分支。
    if (Test-Path $path) {
        # 组合父目录与子路径；复制文件或目录到目标位置。
        Copy-Item -LiteralPath $path -Destination (Join-Path $backup $asName) -Force
        # 处理 Write-Ok 所指定的操作或当前表达式的后续部分。
        Write-Ok ('backed up ' + $path)
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 当前述条件不成立时执行此分支。
    else {
        # 处理 Write-Warn 所指定的操作或当前表达式的后续部分。
        Write-Warn ('not present yet, will be created: ' + $path)
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# 定义 Read-JsonAsHashtable，封装此函数内的操作。
function Read-JsonAsHashtable($path) {
    # 计算本行表达式并设置 $h，供后续步骤使用。
    $h = @{}
    # 检查本行条件；满足时执行对应分支。
    if (Test-Path $path) {
        # 读取文件内容供后续处理，并保存到 $raw。
        $raw = Get-Content -LiteralPath $path -Raw
        # 检查本行条件；满足时执行对应分支。
        if ($raw -and $raw.Trim()) {
            # 把 JSON 文本解析为对象；逐项处理管道传入的记录。
            ($raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 返回本行结果并结束当前函数。
    return $h
# 结束此处的代码块、参数列表或集合定义。
}

# ------------------------------------------------------------------- RStudio
# 检查本行条件；满足时执行对应分支。
if (-not $SkipRStudio) {
    # 处理 Write-Head 所指定的操作或当前表达式的后续部分。
    Write-Head 'RStudio'
    # 组合父目录与子路径，并保存到 $prefPath。
    $prefPath = Join-Path $env:APPDATA 'RStudio/rstudio-prefs.json'
    # 处理 Backup-One 所指定的操作或当前表达式的后续部分。
    Backup-One $prefPath 'rstudio-prefs.json'
    # 计算本行表达式并设置 $prefs，供后续步骤使用。
    $prefs = Read-JsonAsHashtable $prefPath

    # Reproducibility: never carry a hidden .RData from one session into the next.
    # 构造或计算 $prefs['save_workspace']，保存本行指定的集合或索引结果。
    $prefs['save_workspace'] = 'never'
    # 构造或计算 $prefs['load_workspace']，保存本行指定的集合或索引结果。
    $prefs['load_workspace'] = $false
    # 构造或计算 $prefs['always_save_history']，保存本行指定的集合或索引结果。
    $prefs['always_save_history'] = $true
    # 构造或计算 $prefs['remove_history_duplicates']，保存本行指定的集合或索引结果。
    $prefs['remove_history_duplicates'] = $true

    # Point reticulate and the Python pane at the curated 190-package environment.
    # 构造或计算 $prefs['python_type']，保存本行指定的集合或索引结果。
    $prefs['python_type'] = 'virtualenv'
    # 构造或计算 $prefs['python_version']，保存本行指定的集合或索引结果。
    $prefs['python_version'] = '3.13.15'
    # 构造或计算 $prefs['python_path']，保存本行指定的集合或索引结果。
    $prefs['python_path'] = $PythonEnv

    # Rendering and encoding.
    # 构造或计算 $prefs['graphics_backend']，保存本行指定的集合或索引结果。
    $prefs['graphics_backend'] = 'ragg'
    # 构造或计算 $prefs['default_encoding']，保存本行指定的集合或索引结果。
    $prefs['default_encoding'] = 'UTF-8'

    # Editor hygiene.
    # 构造或计算 $prefs['auto_detect_indentation']，保存本行指定的集合或索引结果。
    $prefs['auto_detect_indentation'] = $true
    # 构造或计算 $prefs['highlight_selected_line']，保存本行指定的集合或索引结果。
    $prefs['highlight_selected_line'] = $true
    # 构造或计算 $prefs['syntax_color_console']，保存本行指定的集合或索引结果。
    $prefs['syntax_color_console'] = $true
    # 构造或计算 $prefs['full_project_path_in_window_title']，保存本行指定的集合或索引结果。
    $prefs['full_project_path_in_window_title'] = $true
    # 构造或计算 $prefs['auto_append_newline']，保存本行指定的集合或索引结果。
    $prefs['auto_append_newline'] = $true
    # 构造或计算 $prefs['strip_trailing_whitespace']，保存本行指定的集合或索引结果。
    $prefs['strip_trailing_whitespace'] = $true
    # 构造或计算 $prefs['save_files_before_build']，保存本行指定的集合或索引结果。
    $prefs['save_files_before_build'] = $true

    # 检查本行条件；满足时执行对应分支。
    if ($PSCmdlet.ShouldProcess($prefPath, 'write merged preferences')) {
        # 提取路径中的指定部分；创建指定目录、文件或配置项；丢弃不需要显示的输出。
        New-Item -ItemType Directory -Path (Split-Path $prefPath -Parent) -Force | Out-Null
        # 将内容写入目标文件；把对象序列化为 JSON。
        ($prefs | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $prefPath -Encoding UTF8
        # 处理 Write-Ok 所指定的操作或当前表达式的后续部分。
        Write-Ok ('wrote ' + $prefPath + ' (' + $prefs.Count + ' keys)')
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ------------------------------------------------------------------ Positron
# 检查本行条件；满足时执行对应分支。
if (-not $SkipPositron) {
    # 处理 Write-Head 所指定的操作或当前表达式的后续部分。
    Write-Head 'Positron'
    # 组合父目录与子路径，并保存到 $setPath。
    $setPath = Join-Path $env:APPDATA 'Positron/User/settings.json'
    # 处理 Backup-One 所指定的操作或当前表达式的后续部分。
    Backup-One $setPath 'positron-settings.json'
    # 计算本行表达式并设置 $set，供后续步骤使用。
    $set = Read-JsonAsHashtable $setPath

    # 构造或计算 $set['files.encoding']，保存本行指定的集合或索引结果。
    $set['files.encoding'] = 'utf8'
    # 构造或计算 $set['files.trimTrailingWhitespace']，保存本行指定的集合或索引结果。
    $set['files.trimTrailingWhitespace'] = $true
    # 构造或计算 $set['files.insertFinalNewline']，保存本行指定的集合或索引结果。
    $set['files.insertFinalNewline'] = $true
    # 构造或计算 $set['editor.rulers']，保存本行指定的集合或索引结果。
    $set['editor.rulers'] = @(80, 120)
    # 构造或计算 $set['python.defaultInterpreterPath']，保存本行指定的集合或索引结果。
    $set['python.defaultInterpreterPath'] = $PythonEnv
    # 构造或计算 $set['jupyter.askForKernelRestart']，保存本行指定的集合或索引结果。
    $set['jupyter.askForKernelRestart'] = $false
    # 构造或计算 $set['notebook.output.textLineLimit']，保存本行指定的集合或索引结果。
    $set['notebook.output.textLineLimit'] = 300
    # 构造或计算 $set['telemetry.telemetryLevel']，保存本行指定的集合或索引结果。
    $set['telemetry.telemetryLevel'] = 'off'
    # 构造或计算 $set['git.autofetch']，保存本行指定的集合或索引结果。
    $set['git.autofetch'] = $false
    # 处理 $set['[python]'] 所指定的操作或当前表达式的后续部分。
    $set['[python]'] = @{
        # 提供当前表达式所需的文本、字段名称或列表元素。
        'editor.defaultFormatter'  = 'charliermarsh.ruff'
        # 提供当前表达式所需的文本、字段名称或列表元素。
        'editor.formatOnSave'      = $true
        # 提供当前表达式所需的文本、字段名称或列表元素。
        'editor.codeActionsOnSave' = @{ 'source.organizeImports' = 'explicit' }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 处理 $set['[r]'] 所指定的操作或当前表达式的后续部分。
    $set['[r]'] = @{
        # 提供当前表达式所需的文本、字段名称或列表元素。
        'editor.defaultFormatter' = 'Posit.air-vscode'
        # 提供当前表达式所需的文本、字段名称或列表元素。
        'editor.formatOnSave'     = $true
    # 结束此处的代码块、参数列表或集合定义。
    }

    # 检查本行条件；满足时执行对应分支。
    if ($PSCmdlet.ShouldProcess($setPath, 'write merged settings')) {
        # 提取路径中的指定部分；创建指定目录、文件或配置项；丢弃不需要显示的输出。
        New-Item -ItemType Directory -Path (Split-Path $setPath -Parent) -Force | Out-Null
        # 将内容写入目标文件；把对象序列化为 JSON。
        ($set | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $setPath -Encoding UTF8
        # 处理 Write-Ok 所指定的操作或当前表达式的后续部分。
        Write-Ok ('wrote ' + $setPath + ' (' + $set.Count + ' keys)')
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ------------------------------------------------------------------- PyCharm
# 检查本行条件；满足时执行对应分支。
if (-not $SkipPyCharm) {
    # 处理 Write-Head 所指定的操作或当前表达式的后续部分。
    Write-Head 'PyCharm'
    # 枚举指定位置的文件、目录或注册表项；组合父目录与子路径，并保存到 $cfgDir。
    $cfgDir = Get-ChildItem (Join-Path $env:APPDATA 'JetBrains') -Directory -Filter 'PyCharm*' -ErrorAction SilentlyContinue |
    # 选取记录中的指定字段或条目；按指定属性排序输入记录。
    Sort-Object Name -Descending | Select-Object -First 1
    # 枚举指定位置的文件、目录或注册表项；组合父目录与子路径，并保存到 $binDir。
    $binDir = Get-ChildItem (Join-Path $env:ProgramFiles 'JetBrains') -Directory -Filter 'PyCharm*' -ErrorAction SilentlyContinue |
    # 选取记录中的指定字段或条目；按指定属性排序输入记录。
    Sort-Object Name -Descending | Select-Object -First 1

    # 检查本行条件；满足时执行对应分支。
    if (-not $cfgDir -or -not $binDir) {
        # 处理 Write-Warn 所指定的操作或当前表达式的后续部分。
        Write-Warn 'PyCharm config or install directory not found, skipping.'
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 当前述条件不成立时执行此分支。
    else {
        # 组合父目录与子路径，并保存到 $src。
        $src = Join-Path $binDir.FullName 'bin/pycharm64.exe.vmoptions'
        # 组合父目录与子路径，并保存到 $dst。
        $dst = Join-Path $cfgDir.FullName 'pycharm64.exe.vmoptions'
        # 处理 Backup-One 所指定的操作或当前表达式的后续部分。
        Backup-One $dst 'pycharm64.exe.vmoptions'

        # Start from the bundled defaults - exactly what Help | Edit Custom VM Options does -
        # then raise the heap. 2 GB is thin for large notebooks plus indexing on a 32 GB box.
        # 读取文件内容供后续处理；逐项处理管道传入的记录，并保存到 $lines。
        $lines = Get-Content -LiteralPath $src | ForEach-Object {
            # 检查本行条件；满足时执行对应分支。
            if ($_ -match '^-Xmx') { '-Xmx4096m' }
            # 检查本行条件；满足时执行对应分支。
            elseif ($_ -match '^-Xms') { '-Xms512m' }
            # 当前述条件不成立时执行此分支。
            else { $_ }
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 检查本行条件；满足时执行对应分支。
        if ($PSCmdlet.ShouldProcess($dst, 'write custom VM options')) {
            # 将内容写入目标文件。
            $lines | Set-Content -LiteralPath $dst -Encoding ASCII
            # 处理 Write-Ok 所指定的操作或当前表达式的后续部分。
            Write-Ok ('wrote ' + $dst + ' (heap 2048m -> 4096m)')
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 处理 Write-Warn 所指定的操作或当前表达式的后续部分。
        Write-Warn 'Interpreter still has to be picked once in the UI: Settings | Project | Python Interpreter'
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# -------------------------------------------------------------------- TinyTeX
# 检查本行条件；满足时执行对应分支。
if ($InstallTinyTeX) {
    # 处理 Write-Head 所指定的操作或当前表达式的后续部分。
    Write-Head 'TinyTeX (PDF output for Quarto / R Markdown)'
    # 检查本行条件；满足时执行对应分支。
    if (-not (Test-Path $RscriptExe)) {
        # 处理 Write-Bad 所指定的操作或当前表达式的后续部分。
        Write-Bad 'Rscript not found.'
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 检查本行条件；满足时执行对应分支。
    elseif ($PSCmdlet.ShouldProcess('TinyTeX', 'install')) {
        # 调用本行指定的程序或脚本，并传入列出的参数。
        & $RscriptExe -e "tinytex::install_tinytex(force = TRUE)"
        # 调用本行指定的程序或脚本，并传入列出的参数。
        & $RscriptExe -e "cat('IS_TINYTEX:', as.character(tinytex::is_tinytex()), ' ROOT:', tinytex::tinytex_root())"
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# --------------------------------------------------------------- R packages
# 检查本行条件；满足时执行对应分支。
if ($InstallRPackages) {
    # 处理 Write-Head 所指定的操作或当前表达式的后续部分。
    Write-Head 'R packages'
    # 检查本行条件；满足时执行对应分支。
    if ($PSCmdlet.ShouldProcess('tseries, RhpcBLASctl, svglite', 'install')) {
        # 安装本行指定的 R 套件。
        & $RscriptExe -e "install.packages(c('tseries','RhpcBLASctl','svglite'), repos='https://cloud.r-project.org')"
        # 检查指定 R 套件是否可用。
        & $RscriptExe -e "for (p in c('tseries','RhpcBLASctl','svglite')) cat(p, '=', if (requireNamespace(p, quietly=TRUE)) 'installed' else 'MISSING', ' ')"
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ----------------------------------------------------------------- verify
# 处理 Write-Head 所指定的操作或当前表达式的后续部分。
Write-Head 'Verification (read back what is actually on disk)'
# 组合父目录与子路径，并保存到 $prefPath。
$prefPath = Join-Path $env:APPDATA 'RStudio/rstudio-prefs.json'
# 检查本行条件；满足时执行对应分支。
if (Test-Path $prefPath) {
    # 读取文件内容供后续处理；把 JSON 文本解析为对象，并保存到 $p。
    $p = Get-Content -LiteralPath $prefPath -Raw | ConvertFrom-Json
    # 处理 Write-Ok 所指定的操作或当前表达式的后续部分。
    Write-Ok ('RStudio python_path    = ' + $p.python_path)
    # 处理 Write-Ok 所指定的操作或当前表达式的后续部分。
    Write-Ok ('RStudio save_workspace = ' + $p.save_workspace)
    # 处理 Write-Ok 所指定的操作或当前表达式的后续部分。
    Write-Ok ('RStudio graphics       = ' + $p.graphics_backend)
# 结束此处的代码块、参数列表或集合定义。
}
# 组合父目录与子路径，并保存到 $setPath。
$setPath = Join-Path $env:APPDATA 'Positron/User/settings.json'
# 检查本行条件；满足时执行对应分支。
if (Test-Path $setPath) {
    # 读取文件内容供后续处理；把 JSON 文本解析为对象，并保存到 $s。
    $s = Get-Content -LiteralPath $setPath -Raw | ConvertFrom-Json
    # 处理 Write-Ok 所指定的操作或当前表达式的后续部分。
    Write-Ok ('Positron interpreter   = ' + $s.'python.defaultInterpreterPath')
# 结束此处的代码块、参数列表或集合定义。
}
# 枚举指定位置的文件、目录或注册表项；组合父目录与子路径，并保存到 $vmDir。
$vmDir = Get-ChildItem (Join-Path $env:APPDATA 'JetBrains') -Directory -Filter 'PyCharm*' -ErrorAction SilentlyContinue |
# 选取记录中的指定字段或条目；按指定属性排序输入记录。
Sort-Object Name -Descending | Select-Object -First 1
# 检查本行条件；满足时执行对应分支。
if ($vmDir) {
    # 组合父目录与子路径，并保存到 $vmf。
    $vmf = Join-Path $vmDir.FullName 'pycharm64.exe.vmoptions'
    # 检查本行条件；满足时执行对应分支。
    if (Test-Path $vmf) {
        # 读取文件内容供后续处理；按条件筛选输入记录。
        Write-Ok ('PyCharm heap           = ' + ((Get-Content $vmf | Where-Object { $_ -match '^-Xmx' }) -join ''))
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 向终端显示提示或结果。
Write-Host ''
# 向终端显示提示或结果。
Write-Host ('Done. Restore point: ' + $backup) -ForegroundColor Cyan
