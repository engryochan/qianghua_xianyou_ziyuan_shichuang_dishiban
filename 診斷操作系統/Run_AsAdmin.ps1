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
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [switch]$RestorePoint,          # 建立系統還原點（做其他變更前的退路）
    [switch]$EnableLongPaths,       # 啟用 Windows 長路徑（R 套件深層路徑會用到）
    [switch]$SetPageFile,           # 分頁檔固定為 0.5x ~ 1.0x 實體記憶體，避免大資料被系統終止
    [switch]$DefenderExclusions,    # 對開發目錄加 Defender 掃描排除
    [switch]$UpgradeApps,           # winget 升級需要機器層級權限的軟體
    [switch]$All
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

if ($All) { $RestorePoint = $true; $EnableLongPaths = $true; $SetPageFile = $true; $DefenderExclusions = $true; $UpgradeApps = $true }

$any = $RestorePoint -or $EnableLongPaths -or $SetPageFile -or $DefenderExclusions -or $UpgradeApps
if (-not $any) {
    Get-Help $MyInvocation.MyCommand.Path -Full | Out-String -Width 200 | Write-Host
    Write-Host '未指定任何開關，未執行任何動作。建議先跑： .\Run_AsAdmin.ps1 -All -WhatIf' -ForegroundColor Yellow
    return
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning '這支腳本必須以系統管理員身分執行。'
    Write-Host '作法：開始功能表搜尋 PowerShell -> 右鍵「以系統管理員身分執行」-> 再跑這支腳本。' -ForegroundColor Yellow
    return
}

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$log = Join-Path $env:USERPROFILE ('Run_AsAdmin_' + $ts + '.log')
try { Start-Transcript -Path $log -WhatIf:$false | Out-Null } catch { }
function Step { param([string]$T) Write-Host ''; Write-Host ('>>> ' + $T) -ForegroundColor Cyan }
Write-Host ('記錄檔：' + $log)

# ---------------------------------------------------------------- 1. 還原點
if ($RestorePoint) {
    Step '建立系統還原點（其他變更的退路）'
    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, '建立還原點 DataStack_' + $ts)) {
        try {
            Enable-ComputerRestore -Drive 'C:\' -ErrorAction SilentlyContinue
            # 關鍵：Checkpoint-Computer 在「24 小時內已建立過」時發的是【警告】，
            # 不是終止性錯誤，try/catch 接不到。舊版因此印出假的「已建立」。
            # 2026-09-21 實測：警告照發，還原點數量 1 -> 1，根本沒建成。
            # 所以一律用「數量有沒有增加」來判定，不相信「沒擲出例外 = 成功」。
            $before = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
            $wv = $null
            Checkpoint-Computer -Description ('DataStack_' + $ts) -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop -WarningVariable wv
            $after = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
            if ($after -gt $before) {
                Write-Host ('  已建立（還原點 ' + $before + ' -> ' + $after + '）。')
            } else {
                Write-Warning ('  未建立：還原點數量仍為 ' + $after + '。' + $(if ($wv) { '系統訊息：' + ($wv -join ' ') } else { '' }))
                $latest = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object CreationTime -Descending)[0]
                if ($latest) {
                    Write-Host ('  現有最近的還原點：#' + $latest.SequenceNumber + '  ' +
                        $latest.ConvertToDateTime($latest.CreationTime).ToString('yyyy-MM-dd HH:mm:ss') + '  ' + $latest.Description) -ForegroundColor Yellow
                    Write-Host '  ↑ 這個仍可作為退路，但它不是本次建立的，請確認其時間早於你即將做的變更。' -ForegroundColor Yellow
                } else {
                    Write-Warning '  ★ 系統上沒有任何還原點，後續變更將沒有系統層級的退路。'
                }
            }
        } catch {
            Write-Warning ('  未能建立（系統保護可能未啟用，或權限不足）：' + $_.Exception.Message)
        }
    }
}

# ---------------------------------------------------------------- 2. 長路徑
if ($EnableLongPaths) {
    Step '啟用 Windows 長路徑'
    $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    $cur = $null
    try { $cur = (Get-ItemProperty -Path $k -Name LongPathsEnabled -ErrorAction Stop).LongPathsEnabled } catch { }
    if ($cur -eq 1) { Write-Host '  已是啟用狀態。' }
    elseif ($PSCmdlet.ShouldProcess($k, 'LongPathsEnabled = 1')) {
        New-ItemProperty -Path $k -Name LongPathsEnabled -Value 1 -PropertyType DWord -Force | Out-Null
        Write-Host '  已啟用（需重新開機生效）。'
    }
}

# ---------------------------------------------------------------- 3. 分頁檔
if ($SetPageFile) {
    Step '固定分頁檔大小（避免大資料運算被系統直接終止）'
    $ramMB = [int]((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)
    $initMB = [int]($ramMB * 0.5)
    $maxMB = [int]($ramMB * 1.0)
    $freeMB = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1MB
    Write-Host ('  實體記憶體 ' + $ramMB + ' MB；擬設定初始 ' + $initMB + ' MB / 最大 ' + $maxMB + ' MB')
    Write-Host ('  C: 目前可用 ' + [int]$freeMB + ' MB')
    if ($freeMB -lt ($maxMB + 20480)) {
        Write-Warning '  可用空間不足（需大於最大值再加 20 GB 餘裕），已略過。請先清出空間。'
    } elseif ($PSCmdlet.ShouldProcess('C:\pagefile.sys', "初始 $initMB MB / 最大 $maxMB MB")) {
        $bk = Join-Path $env:USERPROFILE ('pagefile_backup_' + $ts + '.txt')
        (Get-WmiObject Win32_PageFileSetting | Out-String) | Set-Content -Path $bk -Encoding UTF8 -WhatIf:$false
        Add-Content -Path $bk -Value ('AutomaticManagedPagefile=' + (Get-WmiObject Win32_ComputerSystem).AutomaticManagedPagefile) -WhatIf:$false
        Write-Host ('  已備份原設定：' + $bk)
        $csw = Get-WmiObject Win32_ComputerSystem -EnableAllPrivileges
        if ($csw.AutomaticManagedPagefile) { $csw.AutomaticManagedPagefile = $false; [void]$csw.Put() }
        $pfs = Get-WmiObject Win32_PageFileSetting | Where-Object { $_.Name -like 'C:*' }
        if ($pfs) { $pfs.InitialSize = $initMB; $pfs.MaximumSize = $maxMB; [void]$pfs.Put() }
        else { $null = Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{ Name = 'C:\pagefile.sys'; InitialSize = $initMB; MaximumSize = $maxMB } }
        Write-Host '  已設定，需重新開機生效。還原：系統內容 > 進階 > 效能 > 虛擬記憶體 > 自動管理。'
    }
}

# ---------------------------------------------------------------- 4. Defender 排除
if ($DefenderExclusions) {
    Step '對開發目錄加入 Microsoft Defender 掃描排除'
    Write-Host '  只排除「你自己的程式碼與套件庫」，絕不排除 Downloads、桌面或整顆 C:。' -ForegroundColor Yellow
    $paths = @(
        'C:\work',
        (Join-Path $env:LOCALAPPDATA 'R\win-library'),
        (Join-Path $env:LOCALAPPDATA 'uv'),
        (Join-Path $env:USERPROFILE '.cache\uv')
    ) | Where-Object { $_ } | Select-Object -Unique
    foreach ($p in $paths) {
        if (-not (Test-Path -LiteralPath $p)) { Write-Host ('  路徑不存在，略過：' + $p); continue }
        if ($PSCmdlet.ShouldProcess($p, 'Add-MpPreference -ExclusionPath')) {
            try { Add-MpPreference -ExclusionPath $p -ErrorAction Stop; Write-Host ('  已排除：' + $p) }
            catch { Write-Warning ('  失敗（可能被群組原則鎖定）：' + $_.Exception.Message) }
        }
    }
    Write-Host ''
    Write-Host '  重要：這只對 Microsoft Defender 有效。亿赛通 CDG、Kaspersky、天锐绿盾' -ForegroundColor Yellow
    Write-Host '  不受這裡影響，必須由 IT 在他們的管理主控台加白名單。' -ForegroundColor Yellow
}

# ---------------------------------------------------------------- 5. winget 升級
if ($UpgradeApps) {
    Step '升級需要機器層級權限的軟體'
    $wg = Get-Command winget -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
    if (-not $wg) { Write-Warning '找不到 winget。' }
    else {
        foreach ($idp in @('Microsoft.Edge', 'Microsoft.Teams', 'Microsoft.VCRedist.2015+.x64', 'Microsoft.VCRedist.2015+.x86')) {
            $listed = & $wg.Source list --id $idp --exact --accept-source-agreements 2>$null | Out-String
            if ($listed -notmatch [regex]::Escape($idp)) { Write-Host ('  未安裝，略過：' + $idp); continue }
            if ($PSCmdlet.ShouldProcess($idp, 'winget upgrade')) {
                & $wg.Source upgrade --id $idp --exact --silent --accept-source-agreements --accept-package-agreements
                Write-Host ('  ' + $idp + ' -> ExitCode ' + $LASTEXITCODE + '（無可用更新時也可能非 0）')
            }
        }
        Write-Host '  註：VCRedist 升級後建議重新開機，部分原生擴充（Python C 擴充）才會使用新版執行期。'
    }
}

Write-Host ''
Write-Host '完成。建議重新開機，然後以一般使用者身分重跑：' -ForegroundColor Green
Write-Host '  .\Win10_Diagnose_v2.ps1' -ForegroundColor Green
try { Stop-Transcript | Out-Null } catch { }
