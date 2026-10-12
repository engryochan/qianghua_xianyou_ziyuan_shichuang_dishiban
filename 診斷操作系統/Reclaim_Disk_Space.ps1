<#
    Reclaim_Disk_Space.ps1  —  回收磁碟空間（需管理員）

    產生者：Claude，2026-10-11。交由先生以管理員身分執行。

    嚴格不做的事（依先生 2026-10-11 指示）：
      * 不登錄、不修改、不刪除、不新增任何網管／資安的 IP 設定
      * 不碰網段內任何帳號與設備
      * 不啟停、不卸載、不重裝任何資安軟體（Kaspersky / 亿赛通 CDG / 天锐绿盾 / Defender）
      * 不改 Windows Update 策略
      * 不動磁碟分割

    設計原則：**每一項都要明確指定開關才會動作。** 不帶參數時只做唯讀報告。
    理由：本機可用空間已降至約 12%，而且刪除多為不可復原，寧可多打一次參數。

    用法：
      # 先只看報告（不刪任何東西）
      powershell -ExecutionPolicy Bypass -File C:\work\admin\Reclaim_Disk_Space.ps1

      # 分項執行（建議依此順序，每做一項就看一次可用空間）
      ... -EmptyRecycleBin          # 約 9.55 GB，最安全，且不需要等
      ... -CleanWindowsUpdateCache  # 約 5.08 GB
      ... -RemoveWindowsOld         # 約 40.29 GB，**會摧毀回到 Win10 的唯一路徑**
      ... -DisableHibernation       # 約 12.71 GB，會關閉休眠與快速啟動

    警告（RemoveWindowsOld）：
      C:\Windows.old 是回到 Windows 10 的唯一回滾路徑，而本機升級失敗三次才成功。
      一旦清除即無法回滾。先生已於 2026-10-11 明示要清除，故本腳本提供該選項，
      但仍保留 -Confirm 式的二次確認，除非加上 -Force。
#>

[CmdletBinding()]
param(
    [switch]$EmptyRecycleBin,
    [switch]$CleanWindowsUpdateCache,
    [switch]$RemoveWindowsOld,
    [switch]$DisableHibernation,
    [switch]$ClearOneDriveGitHub,
    [switch]$RemoveSupersededVersions,
    [int]$SetPagefileFixed = 0,
    [switch]$RemoveOptionalCaches,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'

function Show-Free {
    param([string]$Label)
    $v = Get-Volume -DriveLetter C
    '{0,-28} 可用 {1,8:N2} GB （{2,5:N1}%）' -f $Label, ($v.SizeRemaining/1GB), ($v.SizeRemaining/$v.Size*100)
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

Write-Host '==== 回收磁碟空間 ====' -ForegroundColor Cyan
Write-Host (Show-Free '開始前')
Write-Host ''

$isAdmin = Test-Admin
if (-not $isAdmin) {
    Write-Warning '未以管理員身分執行。除了回收桶，其餘項目都會失敗。'
    Write-Warning '請以管理員開啟 PowerShell 後重跑。'
    Write-Host ''
}

# ---------- 唯讀報告 ----------
Write-Host '---- 現況（唯讀） ----' -ForegroundColor Yellow
$items = [ordered]@{
    'C:\Windows.old'                           = '舊系統（回滾路徑）'
    'C:\Windows\SoftwareDistribution\Download' = 'WU 下載快取'
    'C:\$Recycle.Bin'                          = '回收桶'
    $(Join-Path $env:USERPROFILE 'OneDrive\文档\GitHub') = 'OneDrive 內的 GitHub（使用者資料）'
    'C:\hiberfil.sys'                          = '休眠檔'
    'C:\pagefile.sys'                          = '分頁檔（自動管理，勿手動刪）'
}
# 根目錄的系統檔（pagefile/hiberfil/swapfile）在非提權下 Test-Path 與
# Get-Item -Force 都會回 False／失敗——它們的 ACL 連中繼資料開啟都擋。
# 但**列舉 C:\ 目錄**讀得到大小。實測踩過：初版用 Test-Path，把 19 GB 的
# pagefile 與 12.7 GB 的 hiberfil 都報成「不存在」，報告看起來乾淨卻是錯的。
$rootFiles = @{}
Get-ChildItem 'C:\' -Force -File -ErrorAction SilentlyContinue |
    ForEach-Object { $rootFiles[$_.Name] = $_.Length }

foreach ($k in $items.Keys) {
    $leaf = Split-Path $k -Leaf
    if ($rootFiles.ContainsKey($leaf)) {
        '{0,8:N2} GB  {1,-44} {2}' -f ($rootFiles[$leaf]/1GB), $k, $items[$k]
        continue
    }
    if (Test-Path $k) {
        $m = Get-ChildItem $k -Recurse -Force -File -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum
        '{0,8:N2} GB  {1,-44} {2}' -f ($m.Sum/1GB), $k, $items[$k]
    } else {
        '{0,8}     {1,-44} {2}' -f '不存在', $k, $items[$k]
    }
}
Write-Host ''

$didSomething = $false

# ---------- 1) 回收桶 ----------
if ($EmptyRecycleBin) {
    $didSomething = $true
    Write-Host '---- 清空回收桶 ----' -ForegroundColor Yellow
    Write-Host '注意：這是永久刪除，無法復原。'
    try {
        Clear-RecycleBin -DriveLetter C -Force -ErrorAction Stop
        Write-Host '回收桶已清空。'
    } catch {
        Write-Warning "清空回收桶失敗: $($_.Exception.Message)"
    }
    Write-Host (Show-Free '清空回收桶後')
    Write-Host ''
}

# ---------- 2) Windows Update 下載快取 ----------
if ($CleanWindowsUpdateCache) {
    $didSomething = $true
    Write-Host '---- 清 Windows Update 下載快取 ----' -ForegroundColor Yellow
    if (-not $isAdmin) {
        Write-Warning '需要管理員，略過。'
    } else {
        # 注意：這裡停的是 Windows Update 服務本身，不是任何資安軟體。
        # 偵測到有更新正在暫存時先警告——本機 2026-10-11 09:22 仍在寫入。
        $dl = 'C:\Windows\SoftwareDistribution\Download'
        $recent = Get-ChildItem $dl -Recurse -Force -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-30) }
        if ($recent -and -not $Force) {
            Write-Warning "近 30 分鐘內仍有 $($recent.Count) 個檔案被寫入，可能正在下載更新。"
            Write-Warning '清掉會讓該更新重新下載。要照做請加 -Force。已略過。'
        } else {
            Write-Host '停止 wuauserv / bits …'
            Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            Write-Host '刪除下載快取內容（保留目錄本身）…'
            Get-ChildItem $dl -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host '重新啟動 wuauserv / bits …'
            Start-Service wuauserv, bits -ErrorAction SilentlyContinue
            Write-Host '完成。'
        }
    }
    Write-Host (Show-Free '清 WU 快取後')
    Write-Host ''
}

# ---------- 3) Windows.old ----------
if ($RemoveWindowsOld) {
    $didSomething = $true
    Write-Host '---- 清除 C:\Windows.old ----' -ForegroundColor Yellow
    if (-not (Test-Path 'C:\Windows.old')) {
        Write-Host 'C:\Windows.old 不存在，無需動作。'
    } elseif (-not $isAdmin) {
        Write-Warning '需要管理員，略過。'
    } else {
        Write-Host ''
        Write-Host '*** 這會摧毀回到 Windows 10 的唯一回滾路徑。***' -ForegroundColor Red
        Write-Host '*** 本機升級失敗三次才成功，清除後無法回頭。***' -ForegroundColor Red
        Write-Host ''
        $go = $Force
        if (-not $go) {
            $ans = Read-Host '確定要清除嗎？請輸入大寫 YES'
            $go = ($ans -ceq 'YES')
        }
        if (-not $go) {
            Write-Host '已取消，未做任何變更。'
        } else {
            # 用受支援的機制：cleanmgr 的「以前的 Windows 安裝」處理常式。
            # 不手動 Remove-Item——該目錄屬 TrustedInstaller，強刪會留下
            # 刪一半且無法移除的殘骸。
            $vc = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
            $handlers = @(
                'Previous Installations',
                'Windows Upgrade Log Files',
                'Update Cleanup',
                'Temporary Setup Files',
                'Setup Log Files'
            )
            $tag = 77
            $sf  = 'StateFlags{0:0000}' -f $tag

            Write-Host "設定 cleanmgr 設定檔 /sageset:$tag（只開啟升級殘留相關處理常式）…"
            # 先把所有處理常式設為 0，避免誤清其他東西
            Get-ChildItem $vc -ErrorAction SilentlyContinue | ForEach-Object {
                New-ItemProperty -Path $_.PSPath -Name $sf -Value 0 `
                    -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
            }
            foreach ($h in $handlers) {
                $p = Join-Path $vc $h
                if (Test-Path $p) {
                    New-ItemProperty -Path $p -Name $sf -Value 2 `
                        -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
                    Write-Host "  啟用: $h"
                } else {
                    Write-Host "  （本機無此處理常式: $h）"
                }
            }

            Write-Host ''
            Write-Host "執行 cleanmgr /sagerun:$tag —— 這會跑一段時間（40 GB / 40 萬檔），請耐心等它結束。"
            $p = Start-Process -FilePath 'cleanmgr.exe' `
                               -ArgumentList "/sagerun:$tag" -PassThru -Wait
            Write-Host "cleanmgr 結束，離開碼 $($p.ExitCode)。"

            if (Test-Path 'C:\Windows.old') {
                $m = Get-ChildItem 'C:\Windows.old' -Recurse -Force -File `
                        -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
                Write-Warning ('C:\Windows.old 仍存在，剩 {0:N2} GB。' -f ($m.Sum/1GB))
                Write-Warning 'cleanmgr 有時需要重啟後才完成，或該處理常式未出現。'
                Write-Warning '若重啟後仍在，請改用「設定 > 系統 > 儲存空間 > 清理建議」勾選「以前的 Windows 安裝」。'
            } else {
                Write-Host 'C:\Windows.old 已清除。' -ForegroundColor Green
            }
        }
    }
    Write-Host (Show-Free '處理 Windows.old 後')
    Write-Host ''
}

# ---------- 4) 休眠檔 ----------
if ($DisableHibernation) {
    $didSomething = $true
    Write-Host '---- 關閉休眠以移除 hiberfil.sys ----' -ForegroundColor Yellow
    Write-Host '副作用：休眠與「快速啟動」都會停用。開機會略慢，但不影響任何功能。'
    Write-Host '要復原：powercfg /h on'
    if (-not $isAdmin) {
        Write-Warning '需要管理員，略過。'
    } else {
        & powercfg.exe /h off
        if (Test-Path 'C:\hiberfil.sys') {
            Write-Warning 'hiberfil.sys 仍存在（可能需重啟才會釋放）。'
        } else {
            Write-Host 'hiberfil.sys 已移除。' -ForegroundColor Green
        }
    }
    Write-Host (Show-Free '關閉休眠後')
    Write-Host ''
}

# ---------- 5) 清空 OneDrive\文档\GitHub ----------
if ($ClearOneDriveGitHub) {
    $didSomething = $true
    Write-Host '---- 清空 OneDrive\文档\GitHub ----' -ForegroundColor Yellow
    $odg = Join-Path $env:USERPROFILE 'OneDrive\文档\GitHub'
    if (-not (Test-Path -LiteralPath $odg)) {
        Write-Host "$odg 不存在，無需動作。"
    } else {
        # 先保全兩個「OneDrive 版與 Documents 版位元組不同」的舊草稿。
        # 兩者都比 Documents 版舊且小，但既然不同就不是重複檔，先留底再刪。
        $backup = 'C:\work\backup\onedrive-github-salvage'
        $salvage = @(
            'online-gaming-decision-intelligence-lab\_大秦赋算筹_v1_3_8.qmd',
            'online-gaming-decision-intelligence-lab\Reference\Aerospace_Ecosystem_Report.qmd'
        )
        New-Item -ItemType Directory $backup -Force | Out-Null
        Write-Host "先備份舊草稿到 $backup …"
        $backupOk = $true
        foreach ($rel in $salvage) {
            $src = Join-Path $odg $rel
            if (Test-Path -LiteralPath $src) {
                $dst = Join-Path $backup (Split-Path $rel -Leaf)
                Copy-Item -LiteralPath $src -Destination $dst -Force
                if (Test-Path -LiteralPath $dst) {
                    Write-Host ('  已備份 {0}  ({1:N1} KB)' -f (Split-Path $rel -Leaf), ((Get-Item -LiteralPath $dst).Length / 1KB))
                } else {
                    Write-Warning "  備份失敗：$rel"
                    $backupOk = $false
                }
            } else {
                Write-Host "  （找不到 $rel，略過）"
            }
        }

        if (-not $backupOk) {
            Write-Warning '有檔案備份失敗，為安全起見不進行刪除。'
        } else {
            Write-Host ''
            Write-Host '*** 注意：這是永久刪除（permanent deletion）。***' -ForegroundColor Red
            Write-Host '*** OneDrive 會把刪除同步到雲端；雲端回收桶約保留 30 天可復原。***' -ForegroundColor Red
            Write-Host '*** 已核實三個倉庫均無獨有提交；qianghua 那份本已損壞。***'
            Write-Host ''
            $go = $Force
            if (-not $go) {
                $ans = Read-Host '確定要清空嗎？請輸入大寫 YES'
                $go = ($ans -ceq 'YES')
            }
            if (-not $go) {
                Write-Host '已取消，未做任何變更。（備份已留存）'
            } else {
                Write-Host '刪除中（約 1,948 個檔案、3.11 GB）…'
                $items = @(Get-ChildItem -LiteralPath $odg -Force -ErrorAction SilentlyContinue)
                foreach ($it in $items) {
                    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $it.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
                $left = @(Get-ChildItem -LiteralPath $odg -Recurse -Force -File -ErrorAction SilentlyContinue).Count
                if ($left -eq 0) {
                    Write-Host 'OneDrive\文档\GitHub 已清空。' -ForegroundColor Green
                } else {
                    Write-Warning "仍剩 $left 個檔案（可能被 OneDrive 鎖定；可暫停同步後重試）。"
                }
            }
        }
    }
    Write-Host (Show-Free '清空 OneDrive\GitHub 後')
    Write-Host ''
}

# ---------- 6) 移除已被取代的舊版與安裝檔 ----------
if ($RemoveSupersededVersions) {
    $didSomething = $true
    Write-Host '---- 移除已被取代的舊版與安裝檔 ----' -ForegroundColor Yellow

    # 清單是 2026-10-11 實測確認的：每一項都已安裝完成或已被新版取代。
    # 刻意不含 C:\work\backup（那裡有先生的著作與 R 套件清單還原依據）。
    $items = @(
        @{ Path = 'C:\work\tools.bak.1.10.18';                       Note = '舊版 Quarto 1.10.18（1.10.19 已通過八節回歸）' },
        @{ Path = 'C:\work\dl\quarto-1.10.18-win.zip';               Note = '舊版 Quarto 安裝檔' },
        @{ Path = 'C:\work\dl\quarto-1.10.19-win.zip';               Note = '現版 Quarto 安裝檔（已解壓安裝，不再需要）' },
        @{ Path = 'C:\work\dl\RStudio-2026.09.0-174.zip';            Note = 'RStudio 安裝檔（已安裝）' },
        @{ Path = 'C:\work\dl\Positron-2026.09.1-2-UserSetup-x64.exe'; Note = 'Positron 舊版安裝檔（已自動更新至 2026.10.0）' },
        @{ Path = 'C:\work\dl\rtools45-6768-6492.exe';               Note = 'Rtools45 安裝檔（已安裝）' },
        @{ Path = 'C:\work\dl\R-4.6.1-win.exe';                      Note = 'R 安裝檔（已安裝）' }
    )

    Write-Host '將移除以下項目：'
    $total = 0
    foreach ($it in $items) {
        if (Test-Path -LiteralPath $it.Path) {
            $o = Get-Item -LiteralPath $it.Path -Force
            if ($o.PSIsContainer) {
                $sz = (Get-ChildItem -LiteralPath $it.Path -Recurse -Force -File -ErrorAction SilentlyContinue |
                       Measure-Object -Property Length -Sum).Sum
            } else { $sz = $o.Length }
            $total += $sz
            Write-Host ('  {0,8:N1} MB  {1}' -f ($sz/1MB), $it.Path)
            Write-Host ('            {0}' -f $it.Note)
        } else {
            Write-Host ('  {0,8}     {1}  （不存在，略過）' -f '-', $it.Path)
        }
    }
    Write-Host ('合計可回收約 {0:N2} GB' -f ($total/1GB))
    Write-Host ''
    Write-Host '*** 這是永久刪除。***' -ForegroundColor Red
    Write-Host '*** 不含 C:\work\backup —— 那裡存著先生的著作與 R 套件還原依據。***'
    Write-Host ''

    $go = $Force
    if (-not $go) {
        $ans = Read-Host '確定要移除嗎？請輸入大寫 YES'
        $go = ($ans -ceq 'YES')
    }
    if (-not $go) {
        Write-Host '已取消，未做任何變更。'
    } else {
        foreach ($it in $items) {
            if (Test-Path -LiteralPath $it.Path) {
                Microsoft.PowerShell.Management\Remove-Item -LiteralPath $it.Path -Recurse -Force -ErrorAction SilentlyContinue
                if (Test-Path -LiteralPath $it.Path) {
                    Write-Warning ('  仍存在：{0}' -f $it.Path)
                } else {
                    Write-Host ('  已移除：{0}' -f $it.Path)
                }
            }
        }
    }

    # uv 快取修剪：這是 uv 自己的維護指令，只清掉不再被任何環境引用的項目，
    # 不會動到已安裝的套件。重建環境時會重新下載，故只是速度代價。
    Write-Host ''
    Write-Host '修剪 uv 快取（只清無人引用者）…'
    $env:UV_CACHE_DIR = 'C:\work\uv-cache'
    & uv cache prune 2>&1 | ForEach-Object { Write-Host ('    ' + $_) }

    Write-Host (Show-Free '移除舊版後')
    Write-Host ''
}

# ---------- 7) 分頁檔改為固定大小 ----------
if ($SetPagefileFixed -gt 0) {
    $didSomething = $true
    Write-Host '---- 分頁檔改為固定大小 ----' -ForegroundColor Yellow

    $pf = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    if ($pf) {
        Write-Host ('  目前配置 {0} MB；目前用量 {1} MB；峰值用量 {2} MB' -f `
            $pf.AllocatedBaseSize, $pf.CurrentUsage, $pf.PeakUsage)
    }
    Write-Host ('  實體記憶體 {0:N2} GB；自動管理 = {1}' -f `
        ($cs.TotalPhysicalMemory/1GB), $cs.AutomaticManagedPagefile)
    Write-Host ('  目標固定大小 {0} MB（{1:N1} GB）' -f $SetPagefileFixed, ($SetPagefileFixed/1024))

    # 缺陷修正（2026-10-12）：Win32_PageFileUsage.PeakUsage 是「本次開機」的峰值，
    # 重啟就歸零。2026-10-12 剛開機時它只有 142 MB，拿它當守衛等於形同失效——
    # 會放行一個危險地小的分頁檔。所以改用「本次峰值 x1.3」與「絕對下限 8192 MB」
    # 取大者。8192 的依據是 2026-10-11 實測到的跨工作階段峰值 5,498 MB。
    $floorFromPeak = if ($pf) { [int]($pf.PeakUsage * 1.3) } else { 0 }
    $floorAbsolute = 8192
    $floor = [Math]::Max($floorFromPeak, $floorAbsolute)
    Write-Host ('  守衛下限 {0} MB（本次峰值x1.3 = {1}；絕對下限 {2}）' -f $floor, $floorFromPeak, $floorAbsolute)

    if ($SetPagefileFixed -lt $floor) {
        Write-Warning ('目標值 {0} MB 低於守衛下限 {1} MB。' -f $SetPagefileFixed, $floor)
        Write-Warning '本機跑 tensorflow／torch／ray 等大記憶體工作，餘裕不足有風險。'
        if (-not $Force) {
            Write-Warning '已略過。確認要照做請加 -Force。'
            Write-Host (Show-Free '未變更')
            Write-Host ''
            return
        }
    }

    if (-not $isAdmin) {
        Write-Warning '需要管理員，略過。'
    } else {
        Write-Host ''
        Write-Host '副作用：' -ForegroundColor Red
        Write-Host '  * 分頁檔小於實體記憶體時，無法產生「完整記憶體傾印」（核心傾印仍可）。'
        Write-Host '  * 若日後記憶體吃緊，可能出現分頁檔不足的警告。'
        Write-Host '  * 復原方式：把自動管理改回開啟（指令見結尾）。'
        Write-Host ''
        $go = $Force
        if (-not $go) {
            $ans = Read-Host ('確定把分頁檔固定為 {0} MB 嗎？請輸入大寫 YES' -f $SetPagefileFixed)
            $go = ($ans -ceq 'YES')
        }
        if (-not $go) {
            Write-Host '已取消，未做任何變更。'
        } else {
            # 先關閉自動管理，否則固定值設不進去
            $csw = Get-CimInstance Win32_ComputerSystem
            Set-CimInstance -InputObject $csw -Property @{ AutomaticManagedPagefile = $false } -ErrorAction Continue

            $ps = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue
            if (-not $ps) {
                # 自動管理關掉後若無設定物件，建一個
                New-CimInstance -ClassName Win32_PageFileSetting -Property @{
                    Name        = 'C:\pagefile.sys'
                    InitialSize = [uint32]$SetPagefileFixed
                    MaximumSize = [uint32]$SetPagefileFixed
                } -ErrorAction Continue | Out-Null
            } else {
                Set-CimInstance -InputObject $ps -Property @{
                    InitialSize = [uint32]$SetPagefileFixed
                    MaximumSize = [uint32]$SetPagefileFixed
                } -ErrorAction Continue
            }

            $ps2 = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue
            if ($ps2) {
                Write-Host ('  設定後：Initial {0} MB / Maximum {1} MB' -f $ps2.InitialSize, $ps2.MaximumSize)
            }
            Write-Host '  **必須重啟才會實際縮小 pagefile.sys 並釋放空間。**' -ForegroundColor Yellow
            Write-Host ''
            Write-Host '  要復原為自動管理，以管理員執行：'
            Write-Host '    $cs = Get-CimInstance Win32_ComputerSystem'
            Write-Host '    Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true }'
        }
    }
    Write-Host (Show-Free '設定分頁檔後（重啟前不會變）')
    Write-Host ''
}

# ---------- 8) 其他可選快取（皆不需提權，皆不影響 OS） ----------
if ($RemoveOptionalCaches) {
    $didSomething = $true
    Write-Host '---- 其他可選快取 ----' -ForegroundColor Yellow

    # 8a) Chrome 裝置端 AI 模型權重
    #     這是 Chrome 的「最佳化指南裝置端模型」，刪掉 Chrome 照常運作，
    #     該功能會改用雲端或自行重抓。屬快取性質，非使用者資料。
    $chromeModel = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\OptGuideOnDeviceModel'
    if (Test-Path -LiteralPath $chromeModel) {
        $sz = (Get-ChildItem -LiteralPath $chromeModel -Recurse -Force -File -ErrorAction SilentlyContinue |
               Measure-Object -Property Length -Sum).Sum
        Write-Host ('  Chrome 裝置端 AI 模型：{0:N2} GB' -f ($sz/1GB))
        Write-Host '    刪掉 Chrome 照常運作；該功能會改用雲端或自行重抓。'
        $chromeRunning = @(Get-Process -Name chrome -ErrorAction SilentlyContinue).Count
        if ($chromeRunning -gt 0) {
            Write-Warning ('    Chrome 正在執行（{0} 個行程），檔案可能被鎖定。建議先關閉 Chrome。' -f $chromeRunning)
        }
        $go = $Force
        if (-not $go) {
            $ans = Read-Host '  要刪除 Chrome 裝置端 AI 模型嗎？請輸入大寫 YES'
            $go = ($ans -ceq 'YES')
        }
        if ($go) {
            Microsoft.PowerShell.Management\Remove-Item -LiteralPath $chromeModel -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $chromeModel) {
                Write-Warning '    仍存在（可能被 Chrome 鎖定）。關閉 Chrome 後重試。'
            } else {
                Write-Host '    已刪除。' -ForegroundColor Green
            }
        } else {
            Write-Host '    已略過。'
        }
    } else {
        Write-Host '  Chrome 裝置端 AI 模型：不存在。'
    }

    # 8b) uv 快取修剪
    #     2026-10-11 與 10-12 兩度實測：Claude 桌面應用會啟動
    #     `uvx --python 3.12 browser-use@latest --cli-mcp` 作為 MCP 伺服器
    #     （父行程 claude.exe），它們長駐並持有快取鎖，所以 prune 拿不到獨佔鎖。
    #     **這一項必須在 Claude 關閉後才做得動。**
    #     不要用 --force 去搶鎖：其他 uv 行程存活時搶鎖可能損壞快取。
    Write-Host ''
    $env:UV_CACHE_DIR = 'C:\work\uv-cache'
    $uvProcs = @(Get-Process -Name 'uv', 'uvx' -ErrorAction SilentlyContinue)
    $cacheSz = 0
    if (Test-Path 'C:\work\uv-cache') {
        $cacheSz = (Get-ChildItem 'C:\work\uv-cache' -Recurse -Force -File -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
    }
    Write-Host ('  uv 快取：{0:N2} GB' -f ($cacheSz/1GB))
    if ($uvProcs.Count -gt 0) {
        Write-Warning ('    有 {0} 個 uv／uvx 行程在執行。' -f $uvProcs.Count)
        Write-Warning '    若其父行程是 claude.exe，那是 Claude 的 MCP 伺服器，**不要終止**。'
        Write-Warning '    請改為關閉 Claude 桌面應用後，再單獨執行： uv cache prune'
        Write-Warning '    不要加 --force 搶鎖——其他 uv 行程存活時搶鎖可能損壞快取。'
    } else {
        Write-Host '    無 uv 行程，可以修剪。'
        & uv cache prune 2>&1 | ForEach-Object { Write-Host ('    ' + $_) }
        $after = (Get-ChildItem 'C:\work\uv-cache' -Recurse -Force -File -ErrorAction SilentlyContinue |
                  Measure-Object -Property Length -Sum).Sum
        Write-Host ('    修剪後 {0:N2} GB（回收 {1:N2} GB）' -f ($after/1GB), (($cacheSz-$after)/1GB))
    }

    Write-Host (Show-Free '可選快取處理後')
    Write-Host ''
}

if (-not $didSomething) {
    Write-Host '（未指定任何開關，只做了唯讀報告。）' -ForegroundColor Cyan
    Write-Host '建議順序：-RemoveSupersededVersions → -DisableHibernation → -RemoveWindowsOld → -CleanWindowsUpdateCache'
}

Write-Host (Show-Free '結束時')
