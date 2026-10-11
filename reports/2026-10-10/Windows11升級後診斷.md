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

---

# 重啟後複驗（2026-10-11 07:30，開機於 06:51:52）

上節把「一次正常重啟」列為應優先做的下一步。先生已重啟，本節逐項複驗。

## 一、待重啟旗標：**全部清除**，且套用了兩個更新

| 旗標 | 10-10 14:10 | **10-11 07:30** |
|---|---|---|
| CBS `RebootPending` | True | **False** |
| Windows Update `RebootRequired` | True | **False** |
| `PendingFileRenameOperations` | False | **False** |

UBR 隨之推進：**26300.9457 → 26300.9550**。

`Setup` 記錄顯示這兩個套件在 10-10 15:55 已暫存並標記「需重啟」，於本次開機
**06:52:07** 完成安裝：

- **KB5121794**
- **KB5124010**
- `Microsoft-Windows-FodMetadataServicing-Desktop-Metadata`

## 二、Kaspersky：**重啟不是解法**，本次開機又失敗兩次

| 項目 | 狀態 |
|---|---|
| `AVP.KES.14.1` | **仍 Stopped**，啟動類型 Automatic |
| `avp.exe` / `avpui.exe` | **仍未執行** |
| `avpsus`、`klnagent` | Running |

本次開機的失敗事件：

| 時間 | ID | 內容 |
|---|---|---|
| 06:52:03 | 7000 / 7009 | `AVP.KES.14.1` 逾時 **45,000 ms**，啟動失敗 |
| 06:54:11 | 7000 / 7009 | `Kaspersky Endpoint Security 服务 (KES.14.1)` 逾時 **30,000 ms**，啟動失敗 |

**累計兩個開機週期、四次失敗（10-10 兩次 + 10-11 兩次）。
這已是可重現的穩定狀態，不是升級後的暫態。**

### 更銳利的定位：驅動層正常，卡的是使用者模式服務

以登錄檔列舉 `HKLM\SYSTEM\CurrentControlSet\Services`，**19 個 Kaspersky 項目全部在冊**，
`.sys` 檔也都在磁碟上：

| 類型 | 項目 | Start |
|---|---|---|
| 檔案系統篩選（Type=2） | `KLIF.KES-14-1`、`klbackupflt.KES-14-1`、`klgse.KES-14-1` | 1 / 1 / 1 |
| 核心驅動（Type=1） | `klflt`、`klhk`、`klwtp`、`kneps`、`klpnpflt`、`klbackupdisk`、`klids`、`klim6`、`klelam`、4× `klupd_*` | 多為 1（系統啟動） |
| **使用者模式服務（Type=16）** | **`AVP.KES.14.1`** ← 逾時的就是這一個 | 2（自動） |

旁證：

- `avp.exe` 存在於 `C:\Program Files (x86)\Kaspersky Lab\KES.14.1.0\`，版本 **21.3.10.1001**，`StartName = LocalSystem`
- `klim6` 實測 **Running**；`klelam` Stopped（ELAM 驅動在開機後卸載屬正常設計）
- `klupd_*` 定義檔 **2026-10-08** 還在更新 —— `avpsus` 一直在下載病毒庫
- **Kaspersky 自有事件記錄存在，但 `RecordCount = 0`** —— 產品從未啟動到能寫一條日誌

**結論：核心驅動載得起來，是使用者模式主服務初始化卡死（>45 秒無回應）。**
這對 IT 有用——問題不在驅動簽署或載入期相容性，而在產品本體在本 OS 組建上的初始化。

> **我要更正自己一處。** 我一度以為驅動在重啟時被移除，那是我查詢寫法造成的誤判：
> 真實服務名帶 `.KES-14-1` 後綴，而 `Get-Service` 並不可靠地列出所有核心驅動。
> 改用登錄檔列舉後證實**驅動完整無缺**。

Defender 持續接手，簽章已更新至 **2026-10-11 00:34:06**，即時防護／行為監控／防篡改皆 True。

## 三、兩項重啟後自行消失

| 項目 | 10-10 | 10-11 |
|---|---|---|
| `LeaderTerm` / `LeaderTermDaemon`（天锐绿盾）事件 7030「可能无法正常操作」 | 有 | **本次開機未再出現** |
| `Microsoft Defender Core 服务` 逾時啟動失敗 | 有 | **本次開機未再出現** |

天锐绿盾行程仍齊（`LdTerm`、`LdTermDaemon`×2、`LdTermPlug`、`LdTermPlug64`），
亿赛通 Cobra DocGuard 亦齊（`CdgTwin32`×2、`CdgTwin64`×2、`CDGRegedit`、`CdgUpGrade`）。
**所以三層防護中，目前只有 Kaspersky 一層實質未運作。**

## 四、仍失敗的其他服務

| 時間 | 服務 | 現象 |
|---|---|---|
| 06:52:07、06:57:07 | `vmcompute`（Hyper-V 主机计算服务） | 7009 / 7000 逾時啟動失敗，兩次 |
| 06:52:02 | `edgeupdate` | 7000 找不到指定檔案（殘留，影響小） |

`vmcompute` 失敗與第二節的 VBS 情況相關：VBS 本身在跑，但宿主計算服務起不來，
容器／WSL2 類功能會受影響。目前工作流程不依賴它。

**本次開機沒有任何非 Service Control Manager 的系統層級錯誤。**

## 五、重啟不會改變的三類項目（複驗結果一致）

| 項目 | 狀態 |
|---|---|
| 四個錯誤碼 28 設備 | **完全未變**（`INTC1070`、`7AA3`、`INTC1056`、`7AA4`，皆 `CM_PROB_FAILED_INSTALL`）；設備統計仍 **OK 128 / Error 4 / Unknown 1** |
| 安全啟動 | `UEFISecureBootEnabled = 0`，**仍未啟用**（屬韌體設定） |
| TPM | `受信任的平台模块 2.0`，Status OK、ErrorCode 0 |
| VBS / HVCI | `VirtualizationBasedSecurityStatus = 2`，但 `SecurityServicesRunning = {0}`，**記憶體完整性仍未啟用** |

設備錯誤需要驅動、安全啟動需要韌體設定、HVCI 需要策略——**這三類本來就不會被重啟修好**。

## 六、硬體與磁碟覆核

| 項目 | 實測 |
|---|---|
| CPU | 12th Gen Intel Core i5-12400，**6 核心 / 12 邏輯處理器** |
| 記憶體 | **31.77 GB** |
| GPU | Intel UHD Graphics 730，驅動 32.0.101.7088，1920×1080，Status **OK** |
| `C:` 可用 | **52.51 GB**（10-10 為 54.97 GB） |
| `C:\Windows.old` | **仍存在**（回滾路徑，刻意保留） |
| `D:\` | **仍不存在**（單一磁碟、未配置空間 0、無光碟機，同上節） |

## 七、資料分析堆疊：重啟後再驗一次，仍 0 失敗

`診斷操作系統/Run_Full_Regression.ps1` 全套八節（log：`../2026-10-11/post-reboot/regression_after_reboot.log`）：

| # | 項目 | 結果 |
|---|---|---|
| 1 | Python 核心真實計算 | **PASS 15 / 15** |
| 2 | R 核心真實計算 | **PASS 10 / 10** |
| 3 | 五個衛星：匯入 + 約束守衛 | **5 × ALL PASS** |
| 4 | 五個衛星：領域計算 | **5 × OK** |
| 5 | flair NER（真實模型） | **PASS** |
| 6 | CmdStan 編譯 + 擬合 | **PASS** |
| 7 | Quarto render 倉庫原版範本 | **Output created**（`python 3.13.16 \| polars`） |
| 8 | 六個 Jupyter kernel（真的 `json.load`） | **`kernels bad: 0`** |

```
################ REGRESSION FAILURES: 0 ################
```

CmdStan 這次的輸出與 10-10 完全相同——`mu 3.5128`、`sigma 1.1557`、`max rhat 1.0032`。
**數值逐字一致，正好證明那支驗收是確定性的**（種子已鎖），不是靠運氣過關。

> 所以升級與重啟兩道關卡都沒有動到 `C:\work`。
> **跨 OS 大版本升級 + 一次重啟，整套堆疊零損失——這是「一切放 `C:\work`、不放 AppData」
> 這個決定的第二次獨立驗證。**

## 八、本節界限

- **未啟動／停用／重裝任何資安軟體，未提權，未改韌體設定，未安裝驅動，未動磁碟分割，未刪 `Windows.old`。**
- BitLocker 權威狀態（`manage-bde -status`）、TPM 細項屬性、`reagentc /info` 仍需提權，保留為未驗證。
- Kaspersky 與天锐绿盾的**功能**驗收不在範圍；本節只陳述服務／行程狀態與事件日誌所載。
- `vmcompute` 失敗的根因未查（與 Kaspersky 是否同源未知）。
- 未執行壓力測試、SFC/DISM、線上更新搜尋。

---

# 提權複驗（2026-10-11 08:35，先生以管理員身分執行）

先生以管理員跑了 `診斷操作系統/Elevated_Pending_Tasks.ps1` 三次。證據：
`reports/2026-10-11/elevated-run/`（最後一次 08:35:01 的完整輸出），另附
`non-elevated-contrast/` 三份同腳本在非提權下的輸出作對照。

**這一輪把上文所有「仍需提權才能權威確認」的項目全部結案，並且查出了升級失敗
調查三次都缺的那份資料。**

## 一、BitLocker：**權威確認未啟用**

`manage-bde -status C:` 的輸出：

| 欄位 | 值 |
|---|---|
| BitLocker 版本 | 无 |
| 转换状态 | 完全解密 |
| 已加密百分比 | 0.0% |
| 加密方法 | 无 |
| 保护状态 | 保护关闭 |
| 密钥保护器 | 找不到 |

上文（14:10 複檢）由旁證推出的「未啟用」成立。**但要記得那只是旁證**——
`BDESVC` Stopped、僅 `C:` 且純 NTFS、`bitlocker.json` 僅 6 bytes，三項都只是
一致，不是證明。現在是 `manage-bde` 自己說的。

## 二、TPM：補齊全部屬性，且發現一個新欄位

`Get-Tpm` 與 `Win32_Tpm` 的完整結果：

| 欄位 | 值 |
|---|---|
| TpmPresent / TpmReady / TpmEnabled / TpmActivated / TpmOwned | 全部 True |
| ManufacturerIdTxt | `INTC` |
| ManufacturerVersion | 600.18.30.2264 |
| SpecVersion | 2.0, 0, 1.38 |
| PpiVersion | 1.3 |
| ManagedAuthLevel | Full |
| AutoProvisioning | Enabled |
| LockedOut / LockoutCount / LockoutMax | False / 0 / 31 |
| **RestartPending** | **True** |

兩點值得記：

- **`ManufacturerIdTxt = INTC` 表示這是 Intel PTT（韌體 TPM），不是獨立 TPM 晶片。**
  上文只說「受信任的平台模块 2.0、ACPI\MSFT0101」，沒分辨是韌體還是離散晶片。
  這對 IT 有差別：韌體 TPM 的設定在 UEFI 裡，不是一張可插拔的卡。
- **`RestartPending = True`**，而本機 06:51:52 才開過機、CBS 與 Windows Update
  的待重啟旗標在 07:30 複驗時都已清除。所以這是 TPM 子系統自己的待重啟狀態，
  與 OS 層的旗標是兩回事，**不要把它和上文「旗標已全部清除」混為一談**。

## 三、安全啟動：權威介面與登錄檔**互相印證**

`Confirm-SecureBootUEFI = False`。

上文是讀 `HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\State\UEFISecureBootEnabled = 0`
（非提權可讀）推出同一結論。**兩個獨立來源一致**，這一項可以完全放下了。
要啟用仍須進 UEFI，屬 IT／先生的決定。

## 四、WinRE：Enabled，且位置解釋了「沒有獨立修復分割區」

```
Windows RE 状态:  Enabled
位置:             \\?\GLOBALROOT\device\harddisk0\partition3\Recovery\WindowsRE
BCD 识别符:       fa1e68ae-8bf9-11f1-9fc7-ac45e65e54e9
WinRE 版本:       10.0.26100.9545
```

- **WinRE 在 partition3 的 `\Recovery\WindowsRE` 子目錄裡**，不是獨立分割區。
  這正好補上 14:10 查 `D:\` 時「磁碟 0 只有 EFI + MSR + C:，未配置空間 0」
  的那個缺口——修復環境一直都在，只是住在 `C:` 裡面。
- **WinRE 版本 10.0.26100.9545 落後於 OS 的 26300.9550。** 這在就地升級後很常見
  （WinRE 映像不隨每次更新同步），但要記下來：真要用修復環境時，它是 26100 代的。
- 這個 BCD 識別符與下節 A10 的 `recoverysequence` 完全相同，兩處自洽。

## 五、`fltmc`：**三次升級失敗時缺的就是這份清單**

先看對照——同一支腳本在非提權下跑，`A5_fltmc_filters.txt` 的內容只有：

```
Filter listing failed with error: 0x80070005
Access is denied.
```

**所以這份資料在前三次升級失敗的調查裡從來拿不到，不是漏查。**

提權後的篩選器高度表（由高到低）：

| 高度 | 篩選器 | 歸屬 | 群組 |
|---|---|---|---|
| **586333** | **Estdlock** | **亿赛通 ESafenet** | FSFilter Activity Monitor |
| 409800 | bindflt | Microsoft | — |
| 385250.5 | UCPD | Microsoft | — |
| **370030** | **FLMonDrv** | **亿赛通 ESafenet** | FSFilter Activity Monitor |
| 328010 | WdFilter | Microsoft（Defender） | FSFilter Anti-Virus |
| **320400.17836798641** | **KLIF.KES-14-1** | **Kaspersky** | FSFilter Anti-Virus |
| **300030** | **LdMFilter** | **天锐绿盾（推定）** | FSFilter Activity Monitor |
| 244000 | storqosflt | Microsoft | — |
| 189900 | wcifs | Microsoft | — |
| 180451 | CldFlt | Microsoft | — |
| 150000 | bfs | Microsoft | — |
| **149998.99** | **Filelock `<过时>`** | **亿赛通 ESafenet** | FSFilter Encryption |
| 141100 | FileCrypt | Microsoft | FSFilter Encryption |
| 135000 | luafv | Microsoft | — |
| 130850 | UnionFS | Microsoft | FSFilter HSM |
| 100800.x | klbackupflt.KES-14-1 | Kaspersky | — |
| 46000 | npsvctrig | Microsoft | — |
| 40700 | Wof | Microsoft | — |
| 40500 | FileInfo | Microsoft | — |

實例（`fltmc instances`）：Estdlock / FLMonDrv / LdMFilter / KLIF 四者都掛在
`C:` 與 `\Device\Mup`，KLIF 另外還掛 `\Device\NamedPipe`。

### 歸屬是實查簽章得到的，不是照名字猜的

| 驅動 | ProductName | 版本 | 修改日期 | 簽章者 |
|---|---|---|---|---|
| estdlock.sys | Data Security Container | 2.0.0.46 | 2021-04-19 | **北京亿赛通科技发展有限责任公司** |
| FLMonDrv.sys | Windows (R) Win 7 DDK driver | 6.1.7600.16385 | 2021-02-26 | **北京亿赛通科技发展有限责任公司** |
| FILELOCK.SYS | **SmartSec for Windows** | **7.4.5** | 2021-04-19 | **北京亿赛通科技发展有限责任公司** |
| LdMFilter.sys | Windows (R) Win 7 DDK driver | 6.0.6000.16384 | 2025-06-26 | Microsoft Windows Hardware Compatibility Publisher |

兩個要點：

- **亿赛通 CDG 貢獻了三個篩選驅動，不是一個。** 上文只盤點到「亿赛通含
  `CDGRegedit` 登錄檔元件」，低估了它在檔案系統路徑上的佔位。而且它佔住了
  **全機最高的高度 586333**，在 Defender 的 WdFilter（328010）與 Kaspersky 的
  KLIF（320400）之上。
- **`LdMFilter` 的簽章者是 Microsoft WHCP，那只代表它過了 WHQL 認證簽署，
  不代表微軟寫的。** ProductName 是未改的 DDK 預設字串，所以憑證查不出廠商。
  判為天锐绿盾是依據檔名 `Ld` 前綴與既知的 `C:\Inetpub\ftproot\Tipray\LdTerm\`
  一致——**這一項是推定，不是證實**，照實標註。

### `Filelock` 是**傳統篩選器**，而且是開機啟動的加密篩選器

這是本輪最值得交給 IT 的一條。查登錄檔載入設定：

| 驅動 | Start | 群組 | 有 `Instances` 子機碼？ | 模型 |
|---|---|---|---|---|
| **Filelock** | **0（Boot）** | **FSFilter Encryption** | **否** | **傳統篩選器，直接掛 device stack** |
| Estdlock | 1（System） | FSFilter Activity Monitor | 是 | minifilter（走 FltMgr） |
| FLMonDrv | 2（Auto） | FSFilter Activity Monitor | 是 | minifilter |
| LdMFilter | 0（Boot） | FSFilter Activity Monitor | 是 | minifilter |
| KLIF.KES-14-1 | 1（System） | FSFilter Anti-Virus | 是 | minifilter |

`fltmc` 自己把 `Filelock` 標成 `<过时>`（英文版 `<Legacy>`），而它沒有
`Instances` 子機碼——**這證實它不是 minifilter，是前 FltMgr 時代的傳統檔案系統
篩選驅動**，靠 `IoAttachDeviceToDeviceStack` 直接掛進裝置堆疊。

**這對升級失敗的 hive 載入問題是目前支持度最高的候選解釋。** 回想既有事證：

- 失敗簽名是 `RegLoadKeyW` 對**所有**離線 hive 回傳 Win32 `87`
  （`ERROR_INVALID_PARAMETER`），跨 NewOS `SOFTWARE`、SafeOS `SYSTEM`、
  本機 `elam` 三者皆然，換映像也不變。
- **關鍵反證是 `elam`：它本身是合法 `regf`、32,768 bytes、一般使用者讀得到。**
  所以不是檔案損壞，也不是權限不足。
- 而 Win32 87 正是「檔案開得起來、但內容不被登錄檔子系統接受」的典型回應。

`Filelock` 同時具備四個條件，剛好落在這條路徑上：**開機啟動**（所以在 setup
掛載離線 hive 的每個階段都在場）、**傳統篩選器**（不走 FltMgr 契約，對現代
檔案操作的相容性最差）、**加密群組**（透明加解密會改寫讀回的內容）、
**2021 年的 Win7 DDK 二進位**（比本 OS 組建早四年以上）。

**但必須講清楚界限：這是假設，不是證明。** 要證實只能做對照實驗——停掉它再
升級一次——而那既違反資安規範、也不是我能做的決定。**正解是把這份清單交給 IT
與亿赛通原廠，由他們判斷 SmartSec 7.4.5 是否支援 Windows 11 26H2。**
已另出單子：`reports/2026-10-11/IT請求_篩選驅動堆疊與升級hive失敗_20261011.md`。

> 附帶更正一條推論習慣：上文說「**沒有確定**是哪一個驅動，需管理員列舉
> `fltmc filters` 與登錄檔回呼」。現在 `fltmc` 列出來了，候選從「三套管控軟體
> 任一」收斂到「亿赛通的 Filelock 最可疑」，**但『需要列舉登錄檔回呼』那半句仍
> 未做**——`CDGRegedit` 這類登錄檔篩選元件要用核心除錯器才列得出來，不在本腳本
> 能力內。所以這一項是**收斂，不是結案**。

## 六、元件存放區：健康

`Dism /Online /Cleanup-Image /CheckHealth` → 「未检测到组件存储损坏」，
映像版本 10.0.26300.9550。所以升級後的系統映像本身沒有殘留損傷。

## 七、`vmcompute`：根因查明

A8/A9/A10 三項合起來給出了答案。

### A9：**所有 Hyper-V 功能都是 Disabled，只有 WSL 那兩個是 Enabled**

| 功能 | 狀態 |
|---|---|
| Microsoft-Hyper-V | Disabled |
| Microsoft-Hyper-V-Hypervisor | Disabled |
| **Microsoft-Hyper-V-Services** | **Disabled** |
| Microsoft-Hyper-V-All | Disabled |
| HypervisorPlatform | Disabled |
| Containers、Containers-HNS、Containers-SDN、Containers-DisposableClientVM、Containers-Server-For-Application-Guard | Disabled |
| **Microsoft-Windows-Subsystem-Linux** | **Enabled** |
| **VirtualMachinePlatform** | **Enabled** |

**沒有任何一項卡在 `EnablePending`**——這排除了「功能安裝到一半」的假設。

### A8：`vmcompute` 的事件通道**完全是空的**

| 通道 | 內容 |
|---|---|
| Hyper-V-Compute-Admin | 「找不到任何与指定的选择条件匹配的事件」 |
| Hyper-V-Compute-Operational | 同上，空 |
| Hyper-V-Worker-Admin | 同上，空 |
| Hyper-V-Hypervisor-Admin | **正常**：Id 155 主機處理器功能遮罩 `0x4058381F`、Id 156 NUMA 政策、Id 39 `IGNOREMEMPART=1` |
| Containers-Wcifs/Operational | 反覆「WCIFS filter registration succeeded」 |

**對比極清楚：hypervisor 每次開機都正常初始化並寫事件，而 `vmcompute` 一條都沒寫。**
服務在能寫出第一條日誌之前就死了——這與上文「兩度逾時」的現象一致，也解釋了
為什麼翻「服務自有日誌」在這裡找不到東西。

### A10：BCD 沒問題

`hypervisorlaunchtype = Auto`、`isolatedcontext = Yes`、`nx = OptIn`，
`recoverysequence` 與 A4 的 WinRE 識別符相同。**所以不是 BCD 把 hypervisor
關掉造成的。**

### 結論與誠實界限

**狀態是「半配置」：WSL2 那一組功能開著，Hyper-V 與 Containers 整組關著，
而 `vmcompute`（Host Compute Service）正好橫跨兩邊——它的服務註冊存在、
`WSLService` 會在開機時拉它，但它所屬的 Hyper-V-Services 功能並未安裝。**

這是目前證據所能支持的最強敘述。**我不宣稱已證明因果**：`vmcompute.exe` 在
Win10/11 上同時服務 WSL2、Windows Sandbox 與容器，它究竟是「因為功能未安裝而
缺元件」還是「別的原因初始化失敗」，用唯讀手段分不出來。

**但實務上這一項可以放下，理由是功能影響為零**：上文已實測 `wsl --version`
為 3.0.1.0、預設 WSL2，**但沒有任何已安裝的發行版**，所以沒有任何東西真的需要
HCS。每次開機兩條逾時事件是噪音，不是故障。

三條路，都該由先生或 IT 決定，我不逕行：

1. **什麼都不做**（建議）。沒有發行版，沒有影響。
2. **要用 WSL2 跑發行版**：屆時才需要處理，可先試
   `dism /online /enable-feature /featurename:Microsoft-Hyper-V-Services`
   ——**這是系統變更，需提權，且本機受管理，應先問 IT。**
3. **確定永不用 WSL**：把 `WSLService` 的啟動類型改為手動，可消掉那兩條事件。
   同樣是系統變更，且可逆。

## 八、B 段：驅動部分與先前一致，且安全閘門運作正常

- **B1**：WU 仍然只提供一個驅動，就是那個 2015 年的 Realtek 9.1.409.2015。
  與上文判定一致——**不該裝**，裝了版本號反而退（本機是 9.1.412.2015）。
- **B2**：同樣四個設備，這次拿到完整硬體 ID 清單（已存檔）。
- **B3**：`pnputil /scan-devices` 重掃後**仍是 4 個 Error**。第三次複驗，一致。
- **B4**：第三次執行帶了 `-InstallDrivers` 與一個不存在的 `-DriverPackagePath`，
  腳本正確拒絕：「警告: 路徑不存在：C:\work\dl\chipset\extracted。略過。」
  **閘門按設計運作**——沒有下載任何晶片組包，所以它什麼都沒裝。

## 九、順帶證實一件事：`powershell -File` 吃得下中文絕對路徑

先生第一次用相對路徑失敗（提權視窗的工作目錄是 `C:\WINDOWS\system32`，
那是我給錯路徑），改用倉庫的中文絕對路徑後正常執行。

**所以本倉庫既有的「Rscript 吃中文絕對路徑會亂碼」那條教訓不能外推到
`powershell.exe`。** 兩者的參數編碼處理不同。我仍保留 `C:\work\admin\` 下那份
ASCII 路徑副本，但那是便利，不是必要。

## 十、本節界限

全程唯讀（B4 未觸發，故未安裝任何驅動）。未登錄、未修改、未刪除、未新增任何
網管／資安的 IP 設定，未碰網段內任何帳號與設備，未存取任何博彩網站。未啟停、
未卸載、未重裝任何資安軟體，未改韌體，未改 Windows Update 策略，未動磁碟分割，
未刪 `Windows.old`。

**仍未驗證**：登錄檔回呼清單（`CDGRegedit` 等需核心除錯器）；
`Filelock` 是否確為 hive 載入失敗的成因（需對照實驗，不做）。

---

# 登錄檔回呼靜態查證（2026-10-11 09:30，非提權，唯讀）

上一節把「列舉登錄檔篩選回呼」列為**唯一仍然缺失的資料**，理由是「需核心除錯器
（`!reg querycallbacks`），不在使用者端腳本能力內」。

**那個結論下得太早。** 活躍回呼的列舉確實需要除錯器，但「**哪些驅動具備註冊
登錄檔回呼的能力**」可以靜態查出來，而且不需提權。

證據：`reports/2026-10-11/registry-callbacks/`
（`scan_cm_callbacks.py`、`scan_output.txt`、`drivers_attribution.txt`）

## 一、方法：PE 匯入名稱表是明文

Windows 核心驅動呼叫 `CmRegisterCallbackEx` 之類的 API，是透過 PE 的
**Import Name Table**，而被匯入的函式名以 **ASCII 明文**存在檔案裡。
所以直接搜位元組就能判斷某個 `.sys` 有沒有連結這些 API——**純讀檔，
不載入、不執行任何驅動，也不需要管理員**。

掃 `C:\Windows\System32\drivers`（含子目錄）全部 **476 個 `.sys`**，
搜六個登錄檔回呼 API，另搜七個對照 API（檔案系統篩選、行程／執行緒／映像通知）
以分辨各驅動的管控面向。**14 個命中。**

## 二、結果：載入中的第三方驅動裡，只有兩個碰登錄檔

| 驅動（服務名） | 歸屬 | 載入狀態 | 登錄檔回呼 API | 其他關鍵 API |
|---|---|---|---|---|
| **`Filelock`** | **亿赛通 SmartSec 7.4.5** | **Running / Boot** | `CmRegisterCallback`、`CmUnRegisterCallback` | **`IoAttachDeviceToDeviceStack`**、`ObRegisterCallbacks`、`PsSetCreateProcessNotifyRoutine`、`PsSetLoadImageNotifyRoutine` |
| **`KLIF.KES-14-1`** | **Kaspersky** | **Running / System** | `CmRegisterCallback`、`CmUnRegisterCallback` | `FltRegisterFilter`、`IoAttachDeviceToDeviceStack`、`PsSetLoadImageNotifyRoutine` |
| `klupd_KES-14-1_klbg` | Kaspersky Boot Guard | Running / Boot | `CmRegisterCallback`、`CmUnRegisterCallback` | — |
| `klupd_KES-14-1_arkmon` | Kaspersky Anti-Rootkit Monitor | Running / Boot | 僅 `CmUnRegisterCallback` | 行程／執行緒／映像通知 |
| `RegLock` | **亿赛通 AniSec 1.2.4** | **未註冊、未載入** | `CmRegisterCallback` | — |
| `klupd_*_klark` / `_mark` | Kaspersky | Stopped / Manual | 僅 `CmUnRegisterCallback` | — |
| `bfs`、`UCPD`、`WdFilter`、`applockerfltr`、`mssecflt`、`VerifierExt` | Microsoft | 見存檔 | 各自不同 | — |

### 兩個關鍵的否證

**`Estdlock`、`FLMonDrv`、`LdMFilter` 三者完全沒有匯入任何 `Cm*` API。**
它們雖然都在跑（且 `Estdlock` 高度全機最高），**但不是登錄檔篩選器**。
這把候選範圍大幅縮小——先前只能說「三套管控軟體裡某一個」。

**亿赛通自己那支專職的登錄檔鎖定驅動 `RegLock.sys` 並未載入。**
它在磁碟上（`AniSec for Windows` 1.2.4，2021-02-26，簽章者
`E=liangjq@esafenet.com, CN="Beijing Yisaitong..."`），**但沒有任何服務的
`ImagePath` 指向它**，所以 SCM 無從載入，`Win32_SystemDriver` 也查不到。
本檔開頭提到的 `CDGRegedit` 登錄檔元件屬同一家族，目前是**休眠**的。

## 三、這讓 `Filelock` 的嫌疑從「最可疑」變成「唯一同時落在兩條路上」

升級失敗是 `RegLoadKeyW` 對所有離線 hive 回傳 Win32 `87`。要讓這件事發生，
攔截點只有兩種可能：**檔案內容被改寫**（hive 必須逐位元組原樣讀取），
或**登錄檔操作本身被攔**。

**`Filelock` 是目前載入中的第三方驅動裡，唯一同時站在這兩條路上的：**

| 路徑 | `Filelock` 的身分 |
|---|---|
| **檔案** | 開機啟動（`Start=0`）的**傳統**篩選器（`IoAttachDeviceToDeviceStack`、無 `Instances` 子機碼、`fltmc` 標 `<过时>`），且屬 **FSFilter Encryption** 群組——透明加解密會改寫讀回的內容 |
| **登錄檔** | 匯入 `CmRegisterCallback` / `CmUnRegisterCallback` |

Kaspersky 的 `KLIF` 雖然也兩者皆具，但它是**正規 minifilter**
（有 `FltRegisterFilter` 與 `Instances`，高度 320400），而 `Filelock` 是
2021 年 Win7 DDK 的傳統驅動。**兩者都該請原廠確認，但 `Filelock` 的風險面
明顯更大。**

## 四、界限（這點必須講清楚）

**匯入某個 API 只證明「具備能力並已連結」，不證明此刻真的有活躍的回呼。**
一支驅動可以連結 `CmRegisterCallback` 卻在特定條件下才註冊，也可能註冊後
又註銷。**要列舉當下活躍的回呼，仍然只能用核心除錯器的 `!reg querycallbacks`。**

所以 #14 的狀態是**從「完全沒有資料」變成「候選已收斂到兩個具名驅動」**，
**不是結案**。但對 IT 與原廠來說，這已經足以指名問誰。

## 五、過程中的一次自我檢出

產生歸屬存檔時，我用**檔名的 basename 去查服務機碼**，於是 `klif.sys`
被報成「服務機碼不存在 → 無法被 SCM 載入、未載入」。

**那是假陰性，而且是本倉庫早已記載過的同一個坑**——Kaspersky 的真實服務名帶
`.KES-14-1` 後綴（`KLIF.KES-14-1`），上一輪我就因為 `Get-Service` 的查詢寫法
誤判過「驅動被移除」。

改用**以 `ImagePath` 反查服務名**（不猜檔名對應）後，`klif` 正確顯示
`KLIF.KES-14-1 / Start=1 / Running`，並與提權那輪 `fltmc` 實測的
高度 320400 相互印證。`RegLock` 經同一套方法複驗，確實**沒有**任何服務指向它。

**存檔檔案已重寫，並在檔頭留下修正紀錄。** 教訓重述一次：
**在 Windows 上不要用檔名推服務名，要用 `ImagePath` 反查。**
