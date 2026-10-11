<#
    Elevated_Apply_Updates.ps1  —  套用已查證的更新（需管理員）

    產生者：Claude，2026-10-11。交由先生以管理員終端執行。

    嚴格不做的事（依先生 2026-10-11 指示）：
      * 不爆破、不修改、不新增、不刪除任何網管／資安設定
      * 不碰任何網際協定（IP）位址設定
      * 不碰億賽通（ESafenet／CDG）、天锐绿盾、Kaspersky、Defender 的任何設定
      * 不嘗試登錄任何博彩網站
      * 不改 Windows Update 策略（含那條把本機釘在 Win10 22H2 的 TargetReleaseVersion）
      * 不安裝 Windows Update 提供的那個 Realtek 驅動（它是退版，見下）

    設計原則：每一項都要明確指定開關才會動作。不帶參數只做唯讀檢查。

    用法（建議依序）：
      # 0) 只檢查，不動任何東西
      powershell -ExecutionPolicy Bypass -File C:\work\admin\Elevated_Apply_Updates.ps1

      # 1) Defender 病毒定義（最安全，且本機 Kaspersky 失效期間它是唯一實質防護）
      ... -DefenderSignature

      # 2) 低風險軟件（Git 與 Windows 終端；刻意不含 Edge 與 Teams）
      ... -WingetSafe

      # 3) Intel 無線網卡驅動（風險最低：WLAN 目前未連線）
      ... -IntelWiFi    -InstallerPath 'C:\work\dl\WiFi-24.70.0-Driver64-Win10-Win11.exe'

      # 4) Intel 顯示卡驅動（需先騰出空間，安裝檔 744.7 MB）
      ... -IntelGraphics -InstallerPath 'C:\work\dl\gfx_win_101.7092.exe'

      # 5) 事後複驗版本
      ... -VerifyOnly

    刻意不做的升級，與理由：
      * Realtek 以太網：WU 提供 9.1.409.2015，而本機是 9.1.412.2015。
        版本號 412 > 409，Windows 只因日期較新而誤判。裝過去是退版，
        且這是唯一在用的連線。交 IT，取得整機／板卡廠原廠包。
      * Microsoft Edge 150 -> 155：跨 5 個主版本。本機 DLP 對瀏覽器按支援清單
        注入（Edge 現得 18 個模組），而 Comet 正因不在清單上而整窗黑屏。
        升級前請 IT 確認 DLP 支援該版；若自行升級，升完務必跑
        診斷操作系統\Win11_App_RealTest.ps1 做像素級黑屏判定。
      * Microsoft Teams：同屬受管控應用，風險次之，一併暫緩。
#>

[CmdletBinding()]
param(
    [switch]$DefenderSignature,
    [switch]$WingetSafe,
    [switch]$IntelWiFi,
    [switch]$IntelGraphics,
    [string]$InstallerPath,
    [switch]$VerifyOnly,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Show-Free {
    $v = Get-Volume -DriveLetter C
    '{0,8:N2} GB 可用（{1,5:N1}%）' -f ($v.SizeRemaining/1GB), ($v.SizeRemaining/$v.Size*100)
}

function Get-DriverVersion {
    param([string]$NameLike)
    Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceName -like $NameLike } |
        Select-Object -First 1 -ExpandProperty DriverVersion
}

Write-Host '==== 套用已查證的更新 ====' -ForegroundColor Cyan
$isAdmin = Test-Admin
Write-Host ("管理員身分：{0}" -f $(if ($isAdmin) { '是' } else { '否（多數項目會失敗）' }))
Write-Host ("磁碟：" + (Show-Free))
Write-Host ''

# ---------- 現況檢查（一律執行） ----------
Write-Host '---- 現況 ----' -ForegroundColor Yellow
$gfx  = Get-DriverVersion '*UHD Graphics 730*'
$wifi = Get-DriverVersion '*Wireless-AC 9560*'
$net  = Get-DriverVersion '*Realtek*Ethernet*'
'{0,-28} {1,-20} 目標 {2}' -f 'Intel UHD Graphics 730', $gfx,  '32.0.101.7092'
'{0,-28} {1,-20} 目標 {2}' -f 'Intel Wireless-AC 9560', $wifi, '24.70.0.x'
'{0,-28} {1,-20} {2}'      -f 'Realtek PCIe GbE',       $net,  '** 不升級（WU 那份是退版）**'

$mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
if ($mp) {
    '{0,-28} {1}' -f 'Defender 定義版本', $mp.AntivirusSignatureVersion
    '{0,-28} {1}' -f 'Defender 定義時間', $mp.AntivirusSignatureLastUpdated
}
Write-Host ''

if ($VerifyOnly) {
    Write-Host '（-VerifyOnly：只做上面的檢查。）' -ForegroundColor Cyan
    return
}

$did = $false

# ---------- 1) Defender 病毒定義 ----------
if ($DefenderSignature) {
    $did = $true
    Write-Host '---- 更新 Defender 病毒定義 ----' -ForegroundColor Yellow
    if (-not $isAdmin) {
        Write-Warning '需要管理員，略過。'
    } else {
        # 只更新定義檔，不改任何 Defender 設定
        Update-MpSignature -UpdateSource MicrosoftUpdateServer -ErrorAction Continue
        $m2 = Get-MpComputerStatus -ErrorAction SilentlyContinue
        if ($m2) {
            Write-Host ('  定義版本：{0}' -f $m2.AntivirusSignatureVersion)
            Write-Host ('  定義時間：{0}' -f $m2.AntivirusSignatureLastUpdated)
        }
    }
    Write-Host ''
}

# ---------- 2) 低風險軟件 ----------
if ($WingetSafe) {
    $did = $true
    Write-Host '---- 升級低風險軟件（Git、Windows 終端）----' -ForegroundColor Yellow
    Write-Host '刻意不含 Edge 與 Teams——見本檔開頭的理由。'
    $ids = @('Microsoft.WindowsTerminal')
    foreach ($id in $ids) {
        Write-Host ("  升級 {0} …" -f $id)
        & winget upgrade --id $id --accept-source-agreements --accept-package-agreements --silent
        Write-Host ("  離開碼 {0}" -f $LASTEXITCODE)
    }
    # Git 來自 msstore，用名稱較穩
    Write-Host '  升級 Git（msstore 來源）…'
    & winget upgrade --id XPDFF77QZ71XD0 --source msstore --accept-source-agreements --accept-package-agreements
    Write-Host ("  離開碼 {0}" -f $LASTEXITCODE)
    Write-Host ''
    Write-Host '剩餘未升者可用此指令查看：winget upgrade --include-unknown'
    Write-Host ''
}

# ---------- 3) Intel 無線網卡 ----------
if ($IntelWiFi) {
    $did = $true
    Write-Host '---- 安裝 Intel 無線網卡驅動 ----' -ForegroundColor Yellow
    Write-Host '風險最低：WLAN 目前未連線，本機走 Realtek 有線，不會中斷連線。'
    if (-not $InstallerPath) {
        Write-Warning '請以 -InstallerPath 指定安裝檔路徑。略過。'
    } elseif (-not (Test-Path -LiteralPath $InstallerPath)) {
        Write-Warning ("路徑不存在：{0}。略過。" -f $InstallerPath)
    } elseif (-not $isAdmin) {
        Write-Warning '需要管理員，略過。'
    } else {
        $sig = Get-AuthenticodeSignature -LiteralPath $InstallerPath
        Write-Host ('  簽章狀態：{0}' -f $sig.Status)
        Write-Host ('  簽章者　：{0}' -f $(if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { '(無)' }))
        if ($sig.Status -ne 'Valid' -and -not $Force) {
            Write-Warning '簽章非 Valid，為安全起見中止。確認無誤要照做請加 -Force。'
        } else {
            Write-Host '  執行安裝器（Intel 安裝器會自行顯示介面）…'
            Start-Process -FilePath $InstallerPath -Wait
            Write-Host ('  安裝後版本：{0}' -f (Get-DriverVersion '*Wireless-AC 9560*'))
            Write-Host '  注意：無線驅動更新後建議重啟，裝置管理員才會反映最終狀態。'
        }
    }
    Write-Host ''
}

# ---------- 4) Intel 顯示卡 ----------
if ($IntelGraphics) {
    $did = $true
    Write-Host '---- 安裝 Intel 顯示卡驅動 ----' -ForegroundColor Yellow
    $v = Get-Volume -DriveLetter C
    $freeGB = $v.SizeRemaining/1GB
    Write-Host ('  目前可用 {0:N2} GB' -f $freeGB)
    if ($freeGB -lt 12 -and -not $Force) {
        Write-Warning '可用空間低於 12 GB。安裝檔 744.7 MB，解壓與暫存需更多空間。'
        Write-Warning '請先跑 Reclaim_Disk_Space.ps1 騰出空間。要照做請加 -Force。已略過。'
    } elseif (-not $InstallerPath) {
        Write-Warning '請以 -InstallerPath 指定安裝檔路徑。略過。'
    } elseif (-not (Test-Path -LiteralPath $InstallerPath)) {
        Write-Warning ("路徑不存在：{0}。略過。" -f $InstallerPath)
    } elseif (-not $isAdmin) {
        Write-Warning '需要管理員，略過。'
    } else {
        $sig = Get-AuthenticodeSignature -LiteralPath $InstallerPath
        Write-Host ('  簽章狀態：{0}' -f $sig.Status)
        Write-Host ('  簽章者　：{0}' -f $(if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { '(無)' }))
        if ($sig.Status -ne 'Valid' -and -not $Force) {
            Write-Warning '簽章非 Valid，為安全起見中止。要照做請加 -Force。'
        } else {
            Write-Host '  安裝期間畫面會閃黑數次，屬正常（顯示驅動重載）。'
            Write-Host '  執行安裝器…'
            Start-Process -FilePath $InstallerPath -Wait
            Write-Host ('  安裝後版本：{0}' -f (Get-DriverVersion '*UHD Graphics 730*'))
            Write-Host '  裝完請重啟，然後跑像素級算繪驗證：'
            Write-Host '    powershell -ExecutionPolicy Bypass -File ' -NoNewline
            Write-Host 'C:\Users\PPCCpcpc\Documents\GitHub\qianghua_xianyou_ziyuan_shichuang_dishiban\診斷操作系統\Win11_App_RealTest.ps1'
        }
    }
    Write-Host ''
}

if (-not $did) {
    Write-Host '（未指定任何開關，只做了現況檢查。）' -ForegroundColor Cyan
    Write-Host '建議順序：-DefenderSignature → -WingetSafe → -IntelWiFi → （騰空間）→ -IntelGraphics'
}

Write-Host ('磁碟：' + (Show-Free))
