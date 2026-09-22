#Requires -Version 5.1
<#
.SYNOPSIS
  把所有「需要系統管理員」的項目集中在這一支，請以管理員身分執行一次即可。
.DESCRIPTION
  Claude Code 的 session 以一般使用者身分執行，無法提權（起不了 UAC），
  因此下列項目必須由使用者手動以管理員身分跑一次。

  每一項都是獨立開關，全部支援 -WhatIf 預演。不帶開關時只顯示說明。

  建議順序：先 -RestorePoint，再其他。

.EXAMPLE
  # 先預演，確認要做什麼
  .\Run_AsAdmin.ps1 -All -WhatIf
.EXAMPLE
  # 正式執行
  .\Run_AsAdmin.ps1 -All
#>
# 启用 PowerShell 高级脚本参数绑定及所列功能。
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
# 声明脚本或函数接受的参数及默认值。
param(
    [switch]$RestorePoint,          # 建立系統還原點（做其他變更前的退路）
    [switch]$EnableLongPaths,       # 啟用 Windows 長路徑（R 套件深層路徑會用到）
    [switch]$SetPageFile,           # 分頁檔固定為 0.5x ~ 1.0x 實體記憶體，避免大資料被系統終止
    [switch]$DefenderExclusions,    # 對開發目錄加 Defender 掃描排除
    [switch]$UpgradeApps,           # winget 升級需要機器層級權限的軟體
    # 声明参数 $All的类型、默认值或校验规则。
    [switch]$All
# 结束此处的代码块、参数列表或集合定义。
)

# 处理 Set-StrictMode 所指定的操作或当前表达式的后续部分。
Set-StrictMode -Off
# 设置本脚本遇到 PowerShell 错误时的处理方式。
$ErrorActionPreference = 'Continue'
# 开始受异常处理保护的操作。
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# 检查本行条件；满足时执行对应分支。
if ($All) { $RestorePoint = $true; $EnableLongPaths = $true; $SetPageFile = $true; $DefenderExclusions = $true; $UpgradeApps = $true }

# 计算本行表达式并设置 $any，供后续步骤使用。
$any = $RestorePoint -or $EnableLongPaths -or $SetPageFile -or $DefenderExclusions -or $UpgradeApps
# 检查本行条件；满足时执行对应分支。
if (-not $any) {
    # 把结果转换为文本；向终端显示提示或结果。
    Get-Help $MyInvocation.MyCommand.Path -Full | Out-String -Width 200 | Write-Host
    # 向终端显示提示或结果。
    Write-Host '未指定任何開關，未執行任何動作。建議先跑： .\Run_AsAdmin.ps1 -All -WhatIf' -ForegroundColor Yellow
    # 返回本行结果并结束当前函数。
    return
# 结束此处的代码块、参数列表或集合定义。
}

# 构造或计算 $id，保存本行指定的集合或索引结果。
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
# 创建指定类型的对象；检查当前身份是否具有指定权限角色，并保存到 $isAdmin。
$isAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# 检查本行条件；满足时执行对应分支。
if (-not $isAdmin) {
    # 显示警告信息。
    Write-Warning '這支腳本必須以系統管理員身分執行。'
    # 向终端显示提示或结果。
    Write-Host '作法：開始功能表搜尋 PowerShell -> 右鍵「以系統管理員身分執行」-> 再跑這支腳本。' -ForegroundColor Yellow
    # 返回本行结果并结束当前函数。
    return
# 结束此处的代码块、参数列表或集合定义。
}

# 生成当前时间或格式化时间戳，并保存到 $ts。
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
# 组合父目录与子路径，并保存到 $log。
$log = Join-Path $env:USERPROFILE ('Run_AsAdmin_' + $ts + '.log')
# 开始受异常处理保护的操作。
try { Start-Transcript -Path $log -WhatIf:$false | Out-Null } catch { }
# 定义 Step，封装此函数内的操作。
function Step { param([string]$T) Write-Host ''; Write-Host ('>>> ' + $T) -ForegroundColor Cyan }
# 向终端显示提示或结果。
Write-Host ('記錄檔：' + $log)

# ---------------------------------------------------------------- 1. 還原點
# 检查本行条件；满足时执行对应分支。
if ($RestorePoint) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '建立系統還原點（其他變更的退路）'
    # 检查本行条件；满足时执行对应分支。
    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, '建立還原點 DataStack_' + $ts)) {
        # 开始受异常处理保护的操作。
        try {
            # 启用指定磁盘的系统还原保护。
            Enable-ComputerRestore -Drive 'C:\' -ErrorAction SilentlyContinue
            # 關鍵：Checkpoint-Computer 在「24 小時內已建立過」時發的是【警告】，
            # 不是終止性錯誤，try/catch 接不到。舊版因此印出假的「已建立」。
            # 2026-09-21 實測：警告照發，還原點數量 1 -> 1，根本沒建成。
            # 所以一律用「數量有沒有增加」來判定，不相信「沒擲出例外 = 成功」。
            # 读取现有系统还原点，并保存到 $before。
            $before = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
            # 计算本行表达式并设置 $wv，供后续步骤使用。
            $wv = $null
            # 请求建立系统还原点。
            Checkpoint-Computer -Description ('DataStack_' + $ts) -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop -WarningVariable wv
            # 读取现有系统还原点，并保存到 $after。
            $after = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
            # 检查本行条件；满足时执行对应分支。
            if ($after -gt $before) {
                # 向终端显示提示或结果。
                Write-Host ('  已建立（還原點 ' + $before + ' -> ' + $after + '）。')
            # 结束上一代码块并进入另一条件分支。
            } else {
                # 显示警告信息。
                Write-Warning ('  未建立：還原點數量仍為 ' + $after + '。' + $(if ($wv) { '系統訊息：' + ($wv -join ' ') } else { '' }))
                # 读取现有系统还原点；按指定属性排序输入记录，并保存到 $latest。
                $latest = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object CreationTime -Descending)[0]
                # 检查本行条件；满足时执行对应分支。
                if ($latest) {
                    # 向终端显示提示或结果。
                    Write-Host ('  現有最近的還原點：#' + $latest.SequenceNumber + '  ' +
                        # 调用 $latest.ConvertToDateTime，使用本行列出的输入完成对应操作。
                        $latest.ConvertToDateTime($latest.CreationTime).ToString('yyyy-MM-dd HH:mm:ss') + '  ' + $latest.Description) -ForegroundColor Yellow
                    # 向终端显示提示或结果。
                    Write-Host '  ↑ 這個仍可作為退路，但它不是本次建立的，請確認其時間早於你即將做的變更。' -ForegroundColor Yellow
                # 结束上一代码块并进入另一条件分支。
                } else {
                    # 显示警告信息。
                    Write-Warning '  ★ 系統上沒有任何還原點，後續變更將沒有系統層級的退路。'
                # 结束此处的代码块、参数列表或集合定义。
                }
            # 结束此处的代码块、参数列表或集合定义。
            }
        # 结束上一代码块并进入异常处理。
        } catch {
            # 显示警告信息。
            Write-Warning ('  未能建立（系統保護可能未啟用，或權限不足）：' + $_.Exception.Message)
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ---------------------------------------------------------------- 2. 長路徑
# 检查本行条件；满足时执行对应分支。
if ($EnableLongPaths) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '啟用 Windows 長路徑'
    # 计算本行表达式并设置 $k，供后续步骤使用。
    $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    # 计算本行表达式并设置 $cur，供后续步骤使用。
    $cur = $null
    # 开始受异常处理保护的操作。
    try { $cur = (Get-ItemProperty -Path $k -Name LongPathsEnabled -ErrorAction Stop).LongPathsEnabled } catch { }
    # 检查本行条件；满足时执行对应分支。
    if ($cur -eq 1) { Write-Host '  已是啟用狀態。' }
    # 检查本行条件；满足时执行对应分支。
    elseif ($PSCmdlet.ShouldProcess($k, 'LongPathsEnabled = 1')) {
        # 创建或写入指定注册表属性；创建指定目录、文件或配置项；丢弃不需要显示的输出。
        New-ItemProperty -Path $k -Name LongPathsEnabled -Value 1 -PropertyType DWord -Force | Out-Null
        # 向终端显示提示或结果。
        Write-Host '  已啟用（需重新開機生效）。'
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ---------------------------------------------------------------- 3. 分頁檔
# 检查本行条件；满足时执行对应分支。
if ($SetPageFile) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '固定分頁檔大小（避免大資料運算被系統直接終止）'
    # 查询 Windows 管理接口中的设备或系统信息，并保存到 $ramMB。
    $ramMB = [int]((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)
    # 构造或计算 $initMB，保存本行指定的集合或索引结果。
    $initMB = [int]($ramMB * 0.5)
    # 构造或计算 $maxMB，保存本行指定的集合或索引结果。
    $maxMB = [int]($ramMB * 1.0)
    # 查询 Windows 管理接口中的设备或系统信息，并保存到 $freeMB。
    $freeMB = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1MB
    # 向终端显示提示或结果。
    Write-Host ('  實體記憶體 ' + $ramMB + ' MB；擬設定初始 ' + $initMB + ' MB / 最大 ' + $maxMB + ' MB')
    # 向终端显示提示或结果。
    Write-Host ('  C: 目前可用 ' + [int]$freeMB + ' MB')
    # 检查本行条件；满足时执行对应分支。
    if ($freeMB -lt ($maxMB + 20480)) {
        # 显示警告信息。
        Write-Warning '  可用空間不足（需大於最大值再加 20 GB 餘裕），已略過。請先清出空間。'
    # 结束上一代码块并进入另一条件分支。
    } elseif ($PSCmdlet.ShouldProcess('C:\pagefile.sys', "初始 $initMB MB / 最大 $maxMB MB")) {
        # 组合父目录与子路径，并保存到 $bk。
        $bk = Join-Path $env:USERPROFILE ('pagefile_backup_' + $ts + '.txt')
        # 通过 WMI 查询系统配置；将内容写入目标文件；把结果转换为文本。
        (Get-WmiObject Win32_PageFileSetting | Out-String) | Set-Content -Path $bk -Encoding UTF8 -WhatIf:$false
        # 通过 WMI 查询系统配置；向目标文件追加内容。
        Add-Content -Path $bk -Value ('AutomaticManagedPagefile=' + (Get-WmiObject Win32_ComputerSystem).AutomaticManagedPagefile) -WhatIf:$false
        # 向终端显示提示或结果。
        Write-Host ('  已備份原設定：' + $bk)
        # 通过 WMI 查询系统配置，并保存到 $csw。
        $csw = Get-WmiObject Win32_ComputerSystem -EnableAllPrivileges
        # 检查本行条件；满足时执行对应分支。
        if ($csw.AutomaticManagedPagefile) { $csw.AutomaticManagedPagefile = $false; [void]$csw.Put() }
        # 通过 WMI 查询系统配置；按条件筛选输入记录，并保存到 $pfs。
        $pfs = Get-WmiObject Win32_PageFileSetting | Where-Object { $_.Name -like 'C:*' }
        # 检查本行条件；满足时执行对应分支。
        if ($pfs) { $pfs.InitialSize = $initMB; $pfs.MaximumSize = $maxMB; [void]$pfs.Put() }
        # 当前述条件不成立时执行此分支。
        else { $null = Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{ Name = 'C:\pagefile.sys'; InitialSize = $initMB; MaximumSize = $maxMB } }
        # 向终端显示提示或结果。
        Write-Host '  已設定，需重新開機生效。還原：系統內容 > 進階 > 效能 > 虛擬記憶體 > 自動管理。'
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ---------------------------------------------------------------- 4. Defender 排除
# 检查本行条件；满足时执行对应分支。
if ($DefenderExclusions) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '對開發目錄加入 Microsoft Defender 掃描排除'
    # 向终端显示提示或结果。
    Write-Host '  只排除「你自己的程式碼與套件庫」，絕不排除 Downloads、桌面或整顆 C:。' -ForegroundColor Yellow
    # 构造或计算 $paths，保存本行指定的集合或索引结果。
    $paths = @(
        # 提供当前表达式所需的文本、字段名称或列表元素。
        'C:\work',
        # 组合父目录与子路径。
        (Join-Path $env:LOCALAPPDATA 'R\win-library'),
        # 组合父目录与子路径。
        (Join-Path $env:LOCALAPPDATA 'uv'),
        # 组合父目录与子路径。
        (Join-Path $env:USERPROFILE '.cache\uv')
    # 选取记录中的指定字段或条目；按条件筛选输入记录。
    ) | Where-Object { $_ } | Select-Object -Unique
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($p in $paths) {
        # 检查本行条件；满足时执行对应分支。
        if (-not (Test-Path -LiteralPath $p)) { Write-Host ('  路徑不存在，略過：' + $p); continue }
        # 检查本行条件；满足时执行对应分支。
        if ($PSCmdlet.ShouldProcess($p, 'Add-MpPreference -ExclusionPath')) {
            # 开始受异常处理保护的操作。
            try { Add-MpPreference -ExclusionPath $p -ErrorAction Stop; Write-Host ('  已排除：' + $p) }
            # 捕获并处理前述操作抛出的异常。
            catch { Write-Warning ('  失敗（可能被群組原則鎖定）：' + $_.Exception.Message) }
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 向终端显示提示或结果。
    Write-Host ''
    # 向终端显示提示或结果。
    Write-Host '  重要：這只對 Microsoft Defender 有效。亿赛通 CDG、Kaspersky、天锐绿盾' -ForegroundColor Yellow
    # 向终端显示提示或结果。
    Write-Host '  不受這裡影響，必須由 IT 在他們的管理主控台加白名單。' -ForegroundColor Yellow
# 结束此处的代码块、参数列表或集合定义。
}

# ---------------------------------------------------------------- 5. winget 升級
# 检查本行条件；满足时执行对应分支。
if ($UpgradeApps) {
    # 处理 Step 所指定的操作或当前表达式的后续部分。
    Step '升級需要機器層級權限的軟體'
    # 查找当前环境可用的命令及其位置；选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $wg。
    $wg = Get-Command winget -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
    # 检查本行条件；满足时执行对应分支。
    if (-not $wg) { Write-Warning '找不到 winget。' }
    # 当前述条件不成立时执行此分支。
    else {
        # 按本行的迭代范围或条件重复执行循环体。
        foreach ($idp in @('Microsoft.Edge', 'Microsoft.Teams', 'Microsoft.VCRedist.2015+.x64', 'Microsoft.VCRedist.2015+.x86')) {
            # 把结果转换为文本，并保存到 $listed。
            $listed = & $wg.Source list --id $idp --exact --accept-source-agreements 2>$null | Out-String
            # 检查本行条件；满足时执行对应分支。
            if ($listed -notmatch [regex]::Escape($idp)) { Write-Host ('  未安裝，略過：' + $idp); continue }
            # 检查本行条件；满足时执行对应分支。
            if ($PSCmdlet.ShouldProcess($idp, 'winget upgrade')) {
                # 调用本行指定的程序或脚本，并传入列出的参数。
                & $wg.Source upgrade --id $idp --exact --silent --accept-source-agreements --accept-package-agreements
                # 向终端显示提示或结果。
                Write-Host ('  ' + $idp + ' -> ExitCode ' + $LASTEXITCODE + '（無可用更新時也可能非 0）')
            # 结束此处的代码块、参数列表或集合定义。
            }
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 向终端显示提示或结果。
        Write-Host '  註：VCRedist 升級後建議重新開機，部分原生擴充（Python C 擴充）才會使用新版執行期。'
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# 向终端显示提示或结果。
Write-Host ''
# 向终端显示提示或结果。
Write-Host '完成。建議重新開機，然後以一般使用者身分重跑：' -ForegroundColor Green
# 向终端显示提示或结果。
Write-Host '  .\Win10_Diagnose_v2.ps1' -ForegroundColor Green
# 开始受异常处理保护的操作。
try { Stop-Transcript | Out-Null } catch { }
