# IT 請求：Kaspersky Endpoint Security 主服務在 Windows 11 26H2 上啟動逾時

**主機**：SHJ-H0647-RYOCH（MiniPC T1 / Intel H610I / i5-12400 / 31.77 GB RAM）
**系統**：Windows 11 專業版 26H2，**26300.9550**（10-11 06:52 套用 KB5121794 + KB5124010 後）
**產品**：Kaspersky Endpoint Security for Windows **14.1.0.423**（`avp.exe` 檔案版本 21.3.10.1001）
**管理**：Kaspersky Security Center 網路代理 16.2.0.1023，**`klnagent` 執行中——控制台看得到本機**

**證據**：`reports/2026-10-11/post-reboot/post-reboot-recheck.json`

---

## 一句話

**KES 14.1 的使用者模式主服務 `AVP.KES.14.1` 在這台機器上啟動逾時，跨兩個開機週期共四次，重啟無效；核心驅動層完全正常。公司配發的防毒實質未運作，目前由 Windows Defender 接手。**

## 失敗事實

| 時間 | 事件 ID | 內容 |
|---|---|---|
| 2026-10-10 13:14:56 | 7009 / 7000 | `AVP.KES.14.1` 等待連線逾時 **45,000 ms**，啟動失敗 |
| 2026-10-10 13:17:00 | 7009 / 7000 | `Kaspersky Endpoint Security 服务 (KES.14.1)` 逾時 **30,000 ms**，啟動失敗 |
| 2026-10-11 06:52:03 | 7009 / 7000 | `AVP.KES.14.1` 逾時 **45,000 ms**，啟動失敗 |
| 2026-10-11 06:54:11 | 7009 / 7000 | `Kaspersky Endpoint Security 服务 (KES.14.1)` 逾時 **30,000 ms**，啟動失敗 |

錯誤字串一致：`The service did not respond to the start or control request in a timely fashion.`

**10-11 的那次是在一次乾淨重啟之後**（三項待重啟旗標均已清除），所以**不是升級殘留的暫態**。

## 關鍵區分：驅動層正常，卡的是使用者模式服務

這一點對定位很重要——**不要往驅動簽署或驅動相容性的方向查**。

以 `HKLM\SYSTEM\CurrentControlSet\Services` 列舉，**19 個 Kaspersky 項目全部在冊**，
對應 `.sys` 檔案也都在磁碟上：

| 類型 | 項目 | `Start` |
|---|---|---|
| 檔案系統篩選（`Type=2`） | `KLIF.KES-14-1`、`klbackupflt.KES-14-1`、`klgse.KES-14-1` | 1（系統啟動） |
| 核心驅動（`Type=1`） | `klflt`、`klhk`、`klwtp`、`kneps`、`klpnpflt`、`klbackupdisk`、`klids`、`klim6`、`klelam`、4 × `klupd_*` | 多為 1 |
| **使用者模式服務（`Type=16`）** | **`AVP.KES.14.1`** ← 逾時的是這一個 | 2（自動） |

旁證：

- `klim6` 實測 **Running**（`klelam` 為 Stopped，屬 ELAM 驅動開機後卸載的正常設計）
- `avp.exe` 存在於 `C:\Program Files (x86)\Kaspersky Lab\KES.14.1.0\`，`StartName = LocalSystem`
- `klupd_*` 定義檔時間戳為 **2026-10-08**——`avpsus.KES.14.1`（更新服務）一直在正常下載病毒庫
- **`Kaspersky Endpoint Security` 事件記錄存在，但 `RecordCount = 0`**
  ——產品從未啟動到能寫出任何一條自有日誌

**推論：驅動載入成功，是產品本體在本 OS 組建上的使用者模式初始化階段卡死（逾 45 秒無回應）。**

## 目前的防護狀態

| 層 | 狀態 |
|---|---|
| **Kaspersky Endpoint Security** | **主服務未運作**（`avpsus`、`klnagent` 仍在） |
| 亿赛通 Cobra DocGuard | 行程齊全：`CdgTwin32`×2、`CdgTwin64`×2、`CDGRegedit`、`CdgUpGrade` |
| 天锐绿盾 Tipray | 行程齊全：`LdTerm`、`LdTermDaemon`×2、`LdTermPlug`、`LdTermPlug64`。10-10 曾有事件 7030「标记为交互服务但系统配置成不允许」，**重啟後未再出現** |
| Windows Defender | **已接手即時防護**：`AntivirusEnabled` / `RealTimeProtectionEnabled` / `BehaviorMonitorEnabled` / `IsTamperProtected` 皆 True，引擎 1.1.26080.3，簽章 2026-10-11 00:34:06 |

**本機並非無防護**，但三層中 Kaspersky 這一層實質失效。

## 請 IT 處置的事項

1. **核對 KES 14.1.0.423 對 Windows 11 26H2（組建 26300）的支援狀態。**
   這台機器在 10-05／10-06 共三次升級失敗，當時的失敗點是安裝程式在 Pre-Finalize
   階段 `RegLoadKeyW` 對離線 hive 回傳 Win32 87（`0x80070057 - 0x50015`），
   而本機常駐 KES（含開機 ELAM `klelam.sys`）、亿赛通 CDG、天锐绿盾三層。
   **當時「KES 與目標 OS 組建不相容」只是推測；現在升級完成後主服務直接起不來，
   該推測獲得獨立印證。**

2. **若 KES 14.1 不支援此組建，請經 Security Center 推送受支援的版本。**
   `klnagent` 在線，可直接管理，不需本機操作。

3. **若需現場日誌**，請提供取得方式：產品自有事件記錄為空，
   其餘需 `%ProgramData%\Kaspersky Lab\` 下的追蹤檔或 Kaspersky 的 GetSystemInfo 工具，
   兩者都需要管理員權限，本機工作階段無法提權。

4. **順帶一併核對**：`vmcompute`（Hyper-V 主机计算服务）同樣兩度逾時啟動失敗
   （10-11 06:52:07、06:57:07）。與 Kaspersky 是否同源未知，但症狀形態相同。

## 本機未做的事

**未啟動、未停用、未重新安裝、未修改任何資安軟體或其策略。**
未提權，未改韌體設定，未安裝驅動。本文件只陳述服務／行程狀態與事件日誌所載事實。

## 附帶的兩項資安設定落差（與本案獨立，但建議同時決定）

| 項目 | 實測 | 影響 |
|---|---|---|
| 安全啟動 | `HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\State\UEFISecureBootEnabled = 0`，**未啟用** | 無量測開機鏈保護；Windows 11 的設計前提是開啟 |
| 記憶體完整性（HVCI） | VBS 本身在跑（`VirtualizationBasedSecurityStatus = 2`），但 `SecurityServicesRunning = {0}`，HVCI 機碼不存在 | 未啟用，而硬體能力具備 |

TPM 已確認存在且正常（`受信任的平台模块 2.0`、`ACPI\MSFT0101\1`、Status OK、ErrorCode 0）。
BitLocker 狀態需提權執行 `manage-bde -status C:` 才能定論，旁證指向未啟用。

## 另有四個設備缺驅動（需要廠商驅動包，與本案無關）

四者全為 Intel 晶片組側，應由同一套 Intel 平台／晶片組驅動覆蓋：

| 設備 | 硬體識別碼 | Class Code | 功能 |
|---|---|---|---|
| SM 总线控制器 | `PCI\VEN_8086&DEV_7AA3&SUBSYS_72708086&REV_11` | `CC_0C0500` | SMBus 控制器 |
| PCI 设备 | `PCI\VEN_8086&DEV_7AA4&SUBSYS_72708086&REV_11` | `CC_0C8000` | 序列匯流排（其他） |
| （未命名） | `ACPI\VEN_INTC&DEV_1070` | — | Intel 平台 ACPI 設備 |
| （未命名） | `ACPI\VEN_INTC&DEV_1056` | — | Intel 平台 ACPI 設備 |

設備統計：OK 128 / Error 4 / Unknown 1。四者狀態在重啟前後完全一致。
