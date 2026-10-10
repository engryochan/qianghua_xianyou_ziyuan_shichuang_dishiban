# Windows 11 升級後設備與系統實測

採集日期：2026-10-10（Europe/Paris）；精確 UTC 時間見 metadata.json。此次僅查詢本機狀態與刪除使用者指定的兩個映像檔。

## 系統與設備

| 項目 | 本次實測 |
|---|---|
| 主機 | MiniPC T1；Intel H610I Chipset 主機板 |
| 系統 | Microsoft Windows 11 專業版，64 位元，26H2，26300.9457 |
| 啟用 | Professional、VOLUME_KMSCLIENT，LicenseStatus=1（已授權） |
| 安裝日期 / 最近開機 | 2026-10-10 13:17:16 / 13:14:37（Europe/Paris；系統回報值） |
| CPU | Intel Core i5-12400，6 核心 / 12 邏輯處理器 |
| 記憶體 | 約 31.77 GiB 實體記憶體（34,117,074,944 bytes）；模組資料見 memory.json |
| GPU | Intel UHD Graphics 730；32.0.101.7088，2026-06-17；1920×1080，Status=OK |
| BIOS | AMI 5.27，2025-07-29 |
| SSD | HAILAN 256G，256,060,514,304 bytes；HealthStatus=Healthy、OperationalStatus=OK |
| C 槽 | NTFS，約 238.16 GiB；刪檔後採集時可用約 57.96 GiB |
| 虛擬化 | HypervisorPresent=true；CPU 探針 VirtualizationFirmwareEnabled=false，不能僅由此欄位判定韌體虛擬化未啟用 |

登錄 ProductName 仍為 Windows 10 Pro；以 Win32_OperatingSystem 的 Windows 11 Caption 與組建實測確認系統，不能用該殘留名稱判斷升級失敗。相較 2026-10-05 的新機快照，系統已從 Windows 10 22H2 19045.7725 升至上述版本；CPU 與 Intel 內顯型號相符。早期 ASUS / i5-12400F / NVIDIA GT 730 紀錄屬舊機。

## 需跟進事項

目前在位設備有 **4 個錯誤碼 28（未安裝驅動）**：

| 設備 | 識別碼 |
|---|---|
| 未命名 ACPI 設備 | ACPI\INTC1070 |
| SM 匯流排控制器 | PCI\VEN_8086&DEV_7AA3 |
| 未命名 ACPI 設備 | ACPI\INTC1056 |
| PCI 設備 | PCI\VEN_8086&DEV_7AA4 |

應依本機主機板與硬體 ID 核對廠商驅動；本輪未安裝驅動，也未將舊華碩主機的安裝包判定為適用。

CBS RebootPending=true，Windows Update RebootRequired=false。尚有元件維護待重新開機標記，宜保存工作後安排正常重啟，再複驗；本次未重啟。

近 3 天 System 記錄取得 19 筆錯誤：WindowsUpdateClient 20 一筆，以及 Service Control Manager 7000/7009/7023/7030 共 18 筆。完整時間、服務與訊息見 recent-system-errors.json；時間窗涵蓋升級前後，不能將全部事件歸因於 Windows 11 升級。

## 網路與防護

目前乙太網路為 Private 類別，IPv4 顯示 Internet 連通；此為系統狀態，未另實測外部端點。Domain / Private / Public 防火牆設定檔均啟用。SecurityCenter2 登錄 Windows Defender 與 Kaspersky Endpoint Security；Defender 回報服務、防毒與即時防護為 true，簽章更新時間為 2026-10-10 01:05:09（Europe/Paris）。產品登錄與服务狀態不能代替 Kaspersky / DLP 的功能驗收。

TPM 查詢出現拒絕存取且欄位為 null；Secure Boot 查詢拒絕存取；BitLocker 未取得可驗證的磁碟區結果。這三項記為 **未驗證**，不能據此宣稱未啟用。未修改網路、資安策略或服務。

## 指定檔案刪除

- reports/2026-10-05/Win11源映像只读核验/professional-integrity-test.wim：6,571,929,515 bytes。
- reports/2026-10-05/Windows11_Client_x64_zh-cn_26300_9457.iso：9,112,440,832 bytes。

兩檔均已確認不存在，合计 15,684,370,347 bytes（約 14.61 GiB）。刪除明細見 deleted-media.json。並未移除 Windows.old 或系統回復檔。

## 證據與範圍

本目錄 JSON 分別保存系統、CPU、RAM、主機板、BIOS、GPU、磁碟、在位設備、簽署驅動、網卡、網路類別、已安裝修補、授權、防護、防火牆、服務、卸載登錄軟體與近期事件。採集腳本為 Collect-PostUpgrade.ps1；probe-status.json 明確區分成功與未驗證項目。

此次未執行壓力測試、SFC/DISM 修復、線上更新搜尋、每項應用或周邊實際操作測試；設備 Status=OK 與 SSD Healthy 不是完整硬體功能保證。未測通的項目保留界限，歷史快照不覆寫。
