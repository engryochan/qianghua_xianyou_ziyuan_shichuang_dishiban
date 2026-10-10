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

---

# 增補複檢（2026-10-10 14:10，升級後仍未重啟）

本節為同日稍後的第二輪複檢，**不覆寫上文**。證據：`recheck-1410/recheck.json`。
上文三項記為「未驗證」的項目，其中兩項本輪已取得可驗證結果。

## 一、`D:\` 分割區：不存在，且無空間可生成

| 查證項 | 實測 |
|---|---|
| `Test-Path D:\` | **False** |
| 實體磁碟數 | **1 顆**：`HAILAN 256G`，SN 2601X1226A002104，238.47 GB，GPT，SATA，Healthy / Online |
| 磁碟 0 分割 | P1 `System`(EFI) 0.29 GB 隱藏 / P2 `Reserved`(MSR) 0.02 GB 隱藏 / **P3 `C:` 238.16 GB IsBoot** |
| 未配置空間 | **0 GB**（總 238.47 = 已配置 238.47） |
| 有磁碟機代號的卷 | **只有 `C:`** |
| 光碟機 | **無**（`Win32_CDROMDrive` 回空） |

**結論：`D:\` 不存在，也沒有任何功能。** 本機既無第二顆實體磁碟、無未配置空間、亦無光碟機，
所以不存在任何會自然佔用 `D:` 的裝置。先前 2026-10-05／10-06 看到的 `F:` 是**手動掛載的 Win11 ISO**，
該 ISO 已於本日刪除，所以連 `F:` 也不再存在。

若日後確需 `D:`，只有兩條路，兩者都需要先生決定（本輪未執行任何磁碟變更）：

1. **縮小 `C:` 再新建分割區** —— 可用空間僅約 55 GB，而 `Windows.old` 占其中 40 GB（見第五節），
   實際可縮的量很有限；且縮分割區是破壞性風險操作。
2. **外接／加裝第二顆磁碟** —— 主機板為 Intel H610I（MiniPC T1），實際可用插槽需開機殼或查廠商規格確認，
   本輪無法由軟體判定。

## 二、安全啟動：**未啟用**（上文「未驗證」已可結案）

上文以 `Confirm-SecureBootUEFI` 查詢被拒而記為未驗證。該 Cmdlet 需要提權，
但**同一事實在登錄檔中非提權即可讀**：

```
HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\State
    UEFISecureBootEnabled = 0        → 未啟用
```

開機方式為 **UEFI**（磁碟 0 為 GPT 且具 EFI System 分割區；Windows 的 GPT 開機必經 UEFI）。

> **這是一項需要留意的資安落差**：Windows 11 的設計前提是安全啟動開啟。
> 目前韌體層關閉，等於沒有量測開機鏈保護，並連帶使記憶體完整性（HVCI）無法啟用（見第四節）。
> 是否開啟屬韌體設定與公司資安策略範圍，本輪未修改任何韌體或策略設定。

## 三、TPM：**存在且正常**，TPM 2.0（上文「未驗證」已可結案）

`Win32_Tpm` 仍需提權，但設備層與服務層非提權即可確認：

| 項目 | 實測 |
|---|---|
| 設備 | `受信任的平台模块 2.0` |
| InstanceId | `ACPI\MSFT0101\1` |
| Status / ConfigManagerErrorCode | **OK / 0** |
| `TPM` 服務 | **Running** |

所以「TPM 是否存在、是否正常」已有答案：**是**。
僅 SpecVersion、製造商、擁有權狀態等細項仍需提權才能讀，那部分保留為未驗證。

## 四、BitLocker 與 VBS

**BitLocker：仍未取得權威結論，但旁證一致指向未啟用。**

| 旁證 | 實測 |
|---|---|
| `Get-BitLockerVolume` | 拒絕存取（需提權） |
| `BDESVC`（BitLocker 管理服務） | **Stopped** |
| `fvevol`（加密磁碟區驅動） | Running（驅動常駐屬正常，不代表已加密） |
| 有代號的卷 | 僅 `C:`，`Get-Volume` 回報純 NTFS |
| 上文 `bitlocker.json` | 僅 6 bytes（查詢無結果） |

權威確認需提權執行 `manage-bde -status C:`。**在那之前不應宣稱已加密或未加密。**

**VBS 在跑，但記憶體完整性未啟用：**

```
VirtualizationBasedSecurityStatus : 2      → VBS 已啟用並執行
SecurityServicesConfigured        : {0}    → 未設定任何安全服務
SecurityServicesRunning           : {0}    → 未執行任何安全服務
AvailableSecurityProperties       : {1,3,5,6…}  → 硬體能力具備
HKLM\…\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity  → 機碼不存在
```

即 **HVCI（記憶體完整性）未設定、未執行**，而硬體是支援的。與第二節的安全啟動關閉相呼應。

## 五、磁碟空間：`Windows.old` 佔 40.29 GB，是回滾路徑

| 項目 | 實測 |
|---|---|
| `C:` 可用 | 約 **54.97 GB** / 238.16 GB |
| `C:\Windows.old` | **40.29 GB，409,445 個檔案**，建立 2026-10-10 09:12:12 |

這是目前最大的可回收項，但**它同時是回到 Windows 10 的唯一回滾路徑**。
本機在 10-05／10-06 共失敗三次才升級成功，**本輪刻意不刪**。

Windows 通常在升級後約 10 天自動清除（即約 2026-10-20）。若先生確認不再需要回滾，
請以管理員身分用磁碟清理處理，**不要手動刪除該目錄**：

```powershell
cleanmgr /sageset:65535    # 勾選「以前的 Windows 安裝」
cleanmgr /sagerun:65535
```

## 六、**Kaspersky 主服務啟動失敗**（本輪最要緊的發現）

| 項目 | 實測 |
|---|---|
| `AVP.KES.14.1`（主服務） | **Stopped**，啟動類型 **Automatic** |
| `avp.exe` / `avpui.exe` | **未執行**（2026-10-06 時為 `avp`×2 + `avpui`） |
| `avpsus`（更新服務） | Running |
| `klnagent`（Security Center 代理） | Running —— IT 控制台仍看得到本機 |
| `klim6`（NDIS 篩選驅動） | Running |
| 已安裝版本 | KES 14.1.0.423 仍在（未被升級移除） |

事件日誌直接指名，且**兩次嘗試、兩次逾時失敗**：

| 時間 | ID | 內容 |
|---|---|---|
| 13:14:56 | 7009 / 7000 | 等待 `AVP.KES.14.1` 連線逾時 **45,000 ms**；服務啟動失敗 |
| 13:17:00 | 7009 / 7000 | 等待 `Kaspersky Endpoint Security 服务 (KES.14.1)` 逾時 **30,000 ms**；啟動失敗 |

**Defender 已接手即時防護**（權威來源 `Get-MpComputerStatus`）：

```
AMServiceEnabled / AntivirusEnabled / RealTimeProtectionEnabled / BehaviorMonitorEnabled : True
IsTamperProtected : True
AMEngineVersion   : 1.1.26080.3
簽章更新          : 2026-10-10 01:05:09
```

所以**本機並非無防護**，但**公司配發的 Kaspersky 實質未運作**。

> 這與 2026-10-06 對升級失敗的既有假設互相印證：
> **KES 14.1.0.423 與這個 OS 組建不相容。** 當時的推測是它參與了安裝程式的離線 hive 遷移；
> 如今升級完成後，其使用者模式服務在本 OS 上直接逾時起不來。
>
> **本輪未嘗試啟動、停用或變更任何資安軟體**（符合本倉庫硬性要求）。
> 該服務受 Kaspersky Security Center 策略管理，而 `klnagent` 仍在線，
> **請 IT 由控制台處置，並核對 KES 版本對 Windows 11 26H2（26300）的支援清單。**

## 七、另外三個服務啟動失敗

| 時間 | 服務 | 現象 |
|---|---|---|
| 13:14:10 | `LeaderTerm` / `LeaderTermDaemon`（天锐绿盾 Tipray） | 7030：標為互動式服務，但系統不允許互動式服務，**「这项服务可能无法正常操作」** |
| 13:17:07 | `Microsoft Defender Core 服务` | 7009 / 7000 逾時啟動失敗（但 Defender 主防毒服務本身在跑） |
| 13:18:18、13:23:18 | `Hyper-V 主机计算服务` | 7009 / 7000 兩度逾時啟動失敗 |
| 13:14:49 | `edgeupdate` | 7000：找不到指定檔案（屬殘留，影響小） |

第一項是**第二層 DLP 也可能未正常運作**，同樣請 IT 一併核對。

## 八、四個錯誤碼 28 設備：由 class code 判定其功能

上文已列識別碼，本輪補上**硬體自報的 class code**，可據此判斷缺的是哪類驅動：

| 設備 | 硬體識別碼 | Class Code | 功能 |
|---|---|---|---|
| SM 总线控制器 | `PCI\VEN_8086&DEV_7AA3&SUBSYS_72708086&REV_11` | **`CC_0C0500`** | 0C05 = **SMBus 控制器** |
| PCI 设备 | `PCI\VEN_8086&DEV_7AA4&SUBSYS_72708086&REV_11` | **`CC_0C8000`** | 0C80 = **序列匯流排控制器（其他）** |
| 未命名 ACPI 設備 | `ACPI\VEN_INTC&DEV_1070`（無 CompatibleIds） | — | Intel 平台 ACPI 設備 |
| 未命名 ACPI 設備 | `ACPI\VEN_INTC&DEV_1056`（無 CompatibleIds） | — | Intel 平台 ACPI 設備 |

**四者全為 `VEN_8086` / `VEN_INTC`，即全部屬 Intel 晶片組側設備**，
因此應由 Intel 平台／晶片組驅動套件一併覆蓋，而非四個獨立來源。

全機設備狀態統計：**OK 128、Error 4、Unknown 1**。

> 具體驅動套件名稱與版本，請由 IT 按主機板型號（Intel H610I / MiniPC T1）與上列硬體 ID
> 向廠商支援清單核對。**本輪未安裝任何驅動**，也不以舊華碩主機的安裝包推定適用。

## 九、待重啟狀態已擴大，且升級後尚未重啟

| 旗標 | 上文（13:38） | 本輪（14:10） |
|---|---|---|
| CBS `RebootPending` | True | **True** |
| Windows Update `RebootRequired` | **false** | **True（已變化）** |
| `PendingFileRenameOperations` | — | False |
| `LastBootUpTime` | 13:14:37 | **13:14:37（未變，即升級後未重啟過）** |

兩個旗標現在同時成立。第六、七節那些服務逾時失敗，都發生在這唯一一次開機之後；
**一次正常重啟是合理且應優先做的下一步**，重啟後再複驗服務狀態與設備錯誤碼。

## 十、資料分析堆疊：完整存活，0 失敗

這是本輪特意加驗的一項，因為**上一次 Windows 11 升級曾把 `%APPDATA%\uv\python` 整個目錄弄消失**。

執行 `診斷操作系統/Run_Full_Regression.ps1` 全套八節：

| # | 項目 | 結果 |
|---|---|---|
| 1 | Python 核心真實計算 | **15 / 15** |
| 2 | R 核心真實計算 | **10 / 10** |
| 3 | 五個衛星：匯入 + 約束守衛 | 全部 ALL PASS |
| 4 | 五個衛星：領域計算 | 全部 OK |
| 5 | flair NER（真實模型） | PASS |
| 6 | CmdStan 編譯 + 擬合 | PASS（mu 3.5128 / sigma 1.1557 / rhat 1.0032） |
| 7 | Quarto render 倉庫原版範本 | Output created |
| 8 | 六個 Jupyter kernel | 全 PASS，`kernels bad: 0` |

```
################ REGRESSION FAILURES: 0 ################
```

連需要 Rtools 工具鏈的 CmdStan 編譯都照樣通過。

> **這驗證了「一切放 `C:\work`，不放 AppData」那個架構決定。**
> 上次升級摧毀的是 `%APPDATA%` 下的東西；這次全部資產都在 `C:\work`，升級後一件未失。

## 十一、本輪界限

- **未重啟、未安裝任何驅動、未變更韌體或資安策略、未啟停任何服務、未改磁碟分割、未刪除 `Windows.old`。**
- BitLocker 權威狀態、TPM 細項屬性、`reagentc /info`（WinRE 位置）仍需提權，保留為未驗證。
- Kaspersky 與 Tipray 的**功能**驗收不在本輪範圍；本節只陳述服務與行程狀態及事件日誌所載。
- 未執行壓力測試、SFC/DISM、線上更新搜尋。
