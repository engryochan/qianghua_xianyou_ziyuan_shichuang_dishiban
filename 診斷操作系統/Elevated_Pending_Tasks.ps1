<#
  Elevated_Pending_Tasks.ps1
  以「管理員身分」執行。本腳本分兩部分：
    A 段 = 唯讀診斷，補齊一般使用者查不到的項目（BitLocker / TPM 細項 / WinRE /
           篩選驅動清單）。完全不做任何變更。
    B 段 = 驅動處置，預設只「列出與掃描」，實際安裝要自己加 -InstallDrivers
           並自備驅動包路徑。

  嚴格不做的事（依先生 2026-10-11 指示）：
    * 不登錄、不修改、不刪除、不新增任何網管／資安的 IP 設定
    * 不碰網段內任何帳號與設備
    * 不啟停、不卸載、不重裝任何資安軟體（Kaspersky / 亿赛通 CDG / 天锐绿盾 / Defender）
    * 不改 Windows Update 策略（含那條把本機釘在 Win10 22H2 的 TargetReleaseVersion）

  本檔含非 ASCII，必須保留 UTF-8 BOM，否則 PowerShell 5.1 會當 ANSI 解碼而路徑全壞。
#>

param(
    [switch]$InstallDrivers,
    [string]$DriverPackagePath
)

$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out   = "C:\work\logs\elevated_$stamp"
New-Item -ItemType Directory -Path $out -Force | Out-Null

function Section { param([string]$T) Write-Host ''; Write-Host ("=== $T ===") -ForegroundColor Cyan }

# ---- 提權確認 -------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host ("Elevated = " + $isAdmin) -ForegroundColor $(if($isAdmin){'Green'}else{'Red'})
if (-not $isAdmin) {
    Write-Warning '未以管理員身分執行。請在提升權限的 PowerShell 重跑，否則 A 段多數項目仍會拒絕存取。'
}

# ==========================================================================
# A 段：唯讀診斷（補齊一般使用者查不到的項目）
# ==========================================================================

Section 'A1 BitLocker 權威狀態'
# 之前一般使用者查詢被拒，旁證指向未啟用，但未經權威確認。
& manage-bde -status C: 2>&1 | Tee-Object -FilePath "$out\A1_bitlocker.txt"

Section 'A2 TPM 細項屬性'
try {
    Get-Tpm | Format-List | Tee-Object -FilePath "$out\A2_tpm.txt"
} catch { "Get-Tpm 失敗: $($_.Exception.Message)" | Tee-Object -FilePath "$out\A2_tpm.txt" }
try {
    Get-CimInstance -Namespace root\cimv2\security\microsofttpm -Class Win32_Tpm |
      Select-Object SpecVersion, ManufacturerIdTxt, ManufacturerVersion,
                    IsEnabled_InitialValue, IsActivated_InitialValue, IsOwned_InitialValue |
      Format-List | Tee-Object -Append -FilePath "$out\A2_tpm.txt"
} catch { "Win32_Tpm 失敗: $($_.Exception.Message)" | Tee-Object -Append -FilePath "$out\A2_tpm.txt" }

Section 'A3 安全啟動（權威介面）'
& {
    try   { "Confirm-SecureBootUEFI = " + (Confirm-SecureBootUEFI) }
    catch { "Confirm-SecureBootUEFI 失敗: $($_.Exception.Message)" }
} | Tee-Object -FilePath "$out\A3_secureboot.txt"

Section 'A4 WinRE 位置與狀態'
& reagentc /info 2>&1 | Tee-Object -FilePath "$out\A4_winre.txt"

Section 'A5 篩選驅動清單（升級期 hive 載入失敗調查的關鍵一項）'
# 2026-10-05/06 三次升級失敗時，RegLoadKeyW 對所有離線 hive 回傳 Win32 87。
# 當時無法列舉篩選驅動，這是補上那一項。唯讀。
& fltmc filters  2>&1 | Tee-Object -FilePath "$out\A5_fltmc_filters.txt"
& fltmc instances 2>&1 | Tee-Object -FilePath "$out\A5_fltmc_instances.txt"

Section 'A6 元件存放區健康（唯讀，不修復）'
& Dism /Online /Cleanup-Image /CheckHealth 2>&1 | Tee-Object -FilePath "$out\A6_dism_checkhealth.txt"

Section 'A7 已載入的核心驅動（供與 Kaspersky 註冊項對照）'
& driverquery /v /fo csv 2>&1 | Out-File "$out\A7_driverquery.csv" -Encoding utf8
"已寫出 A7_driverquery.csv"

Section 'A8 Hyper-V / 容器事件通道（一般使用者讀取被拒，這是補上那一項）'
# 2026-10-11 實測：vmcompute（Hyper-V 主机计算服务）每次開機逾時啟動失敗兩次
# （45,000 ms 與 30,000 ms）。已排除的：執行檔並非舊版遺留（System32 的
# vmcompute.exe 與 WinSxS 的 26100.9549 份 SHA256 相同且互為硬連結，只是版本
# 字串資源寫著 19041.4522），四個依賴 rpcss / wcifs / condrv / hvsocketcontrol
# 全部 Running。下一個決定性線索就在這些通道裡，而它們需要提權。
& {
    foreach ($log in @(
        'Microsoft-Windows-Hyper-V-Compute-Admin',
        'Microsoft-Windows-Hyper-V-Compute-Operational',
        'Microsoft-Windows-Hyper-V-Hypervisor-Admin',
        'Microsoft-Windows-Hyper-V-Worker-Admin',
        'Microsoft-Windows-Containers-Wcifs/Operational')) {
        "--- $log ---"
        try {
            Get-WinEvent -LogName $log -MaxEvents 15 -ErrorAction Stop |
              Select-Object TimeCreated, Id, LevelDisplayName, Message | Format-List
        } catch { "  讀取失敗: $($_.Exception.Message)" }
    }
} 2>&1 | Tee-Object -FilePath "$out\A8_hyperv_events.txt"

Section 'A9 虛擬化相關選用功能狀態'
& {
    try {
        Get-WindowsOptionalFeature -Online -ErrorAction Stop |
          Where-Object { $_.FeatureName -match 'Hyper-V|VirtualMachinePlatform|Windows-Subsystem|Containers|HypervisorPlatform' } |
          Select-Object FeatureName, State | Sort-Object FeatureName | Format-Table -AutoSize
    } catch { "Get-WindowsOptionalFeature 失敗: $($_.Exception.Message)" }
} | Tee-Object -FilePath "$out\A9_optional_features.txt"

Section 'A10 開機設定裡的 hypervisorlaunchtype'
& bcdedit /enum '{current}' 2>&1 | Tee-Object -FilePath "$out\A10_bcdedit.txt"

# ==========================================================================
# B 段：驅動處置
# ==========================================================================

Section 'B1 Windows Update 提供的驅動（唯讀列出，不安裝）'
# 實測 2026-10-11：WU 只提供 Realtek 9.1.409.2015，比已安裝的 9.1.412.2015
# 版本號更低（僅日期較新）。兩者都是 2015 年的驅動。
# 所以這裡只「列出」，刻意不自動安裝，避免把網卡驅動換成同代甚至更舊的版本。
& {
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $res = $session.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Driver'")
        "WU 提供的驅動數 = " + $res.Updates.Count
        foreach ($u in $res.Updates) {
            "  - {0}  (DriverVerDate {1})" -f $u.Title, $u.DriverVerDate
        }
        if ($res.Updates.Count -eq 0) { "  （無）" }
    } catch { "WU 查詢失敗: $($_.Exception.Message)" }
} | Tee-Object -FilePath "$out\B1_wu_drivers.txt"

Section 'B2 目前缺驅動的設備（錯誤碼 28）'
Get-PnpDevice -Status Error -ErrorAction SilentlyContinue | ForEach-Object {
    $hw = (Get-PnpDeviceProperty -InstanceId $_.InstanceId `
            -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction SilentlyContinue).Data
    [pscustomobject]@{
        Name        = if ($_.FriendlyName) { $_.FriendlyName } else { '(未命名)' }
        InstanceId  = $_.InstanceId
        HardwareIds = ($hw -join ' ; ')
    }
} | Format-List | Tee-Object -FilePath "$out\B2_missing_drivers.txt"

Section 'B3 重新掃描硬體變更（安全，不下載任何東西）'
& pnputil /scan-devices 2>&1 | Tee-Object -FilePath "$out\B3_scan.txt"
Start-Sleep -Seconds 3
"重新掃描後仍為 Error 的設備數 = " + (Get-PnpDevice -Status Error -ErrorAction SilentlyContinue | Measure-Object).Count

if ($InstallDrivers) {
    Section 'B4 安裝自備驅動包'
    if (-not $DriverPackagePath) {
        Write-Warning '要安裝請同時給 -DriverPackagePath，指向解壓後含 .inf 的資料夾。未提供，略過。'
    } elseif (-not (Test-Path $DriverPackagePath)) {
        Write-Warning "路徑不存在：$DriverPackagePath。略過。"
    } else {
        "來源：$DriverPackagePath"
        # /subdirs 遞迴；/install 立即套用到相符設備
        & pnputil /add-driver (Join-Path $DriverPackagePath '*.inf') /subdirs /install 2>&1 |
            Tee-Object -FilePath "$out\B4_pnputil_add.txt"
        Start-Sleep -Seconds 3
        "安裝後仍為 Error 的設備：" 
        Get-PnpDevice -Status Error -ErrorAction SilentlyContinue |
            Select-Object FriendlyName, InstanceId | Format-Table -AutoSize
    }
} else {
    Section 'B4 已略過（未指定 -InstallDrivers）'
    Write-Host '要安裝自備驅動包時：' -ForegroundColor Yellow
    Write-Host '  .\Elevated_Pending_Tasks.ps1 -InstallDrivers -DriverPackagePath "D:\chipset\extracted"' -ForegroundColor Yellow
}

Section '完成'
"產出目錄：$out"
Get-ChildItem $out | Select-Object Name, Length | Format-Table -AutoSize
