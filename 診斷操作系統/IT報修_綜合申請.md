# IT 申請單（綜合）

**主機**：SHJ-H0647-RYOCH　**使用者**：PPCCpcpc
**主機板**：ASUSTeK PRIME H610M-R D4　**BIOS**：3801（2025-05-14）
**作業系統**：Windows 11 Pro 25H2（Build 26200.9457，2026-09-20 由 Win10 就地升級）
**提報日期**：2026-09-21

---

## 提報緣由

本機用於資料分析（R + Python + Parquet/DuckDB）。近期完成環境整備後，以實測方式盤點全機軟硬體，發現以下五項需要貴部門權限或決策才能處理。

**以下所有數據均為本機實際執行所得，未安裝、未停用、未修改任何資安軟體。** 完整工作紀錄與稽核軌跡見倉庫 `優化並强化現有資源_視窗10版之Claude篇.qmd`（附錄 A～I）。

---

## 申請一：Comet 瀏覽器無法顯示畫面

### 現象

Comet（Perplexity，Chromium 底，152.0.7977.199）可啟動、行程存在、視窗標題正常，但**內容區完全漆黑**，連分頁列與網址列都未繪製。

像素量測（截取視窗、扣除標題列後取樣）：

| 應用程式 | 內容區近黑比例 | 平均亮度 | 相異色數 | 結果 |
|---|---|---|---|---|
| Google Chrome | 0 % | 243.3 | 730 | 正常 |
| Positron（Chromium/Electron） | 1.3 % | 236.4 | 408 | 正常 |
| **Comet** | **97.9 %** | **3.8** | 63 | **全黑** |

同一台機器、同一顆顯示卡、同一版驅動。

### 已排除的原因（皆經實測）

| 假設 | 驗證方式 | 結果 |
|---|---|---|
| 顯示卡驅動過舊 | Chrome 與 Positron 同為 Chromium 底，均正常 | 排除 |
| 使用者設定檔損壞 | 全新 `--user-data-dir` | 仍全黑，排除 |
| 硬體加速問題 | `--disable-gpu` | 仍全黑，排除 |
| 安裝損壞 | 更新程式已由系統層級遷移至使用者層級，重測 | 仍全黑，排除 |

**關鍵線索**：Comet 以無頭模式執行（`--headless=new --disable-gpu --screenshot`）**無法產出任何截圖檔**；Chrome 在完全相同參數下正常產出 800×600 PNG。故障不在螢幕顯示層，而是整個瀏覽器在本機環境無法產生算繪輸出。

### 與管控軟體相關的觀察（供判斷，非結論）

各應用程式行程實際載入的管控模組數：

| 行程 | 模組數 |
|---|---|
| `chrome.exe` | 20 |
| `msedge.exe` | 18 |
| **`comet.exe`** | **13 ～ 15** |

`comet.exe` 缺少的是瀏覽器專用模組：`BrowserGuardx64.dll`、`BrowerInject64.dll`、`LdBrowserMonitor64.dll`、`LdBrowserDataFlow64.dll`、`LdSendFileLimit64.dll`、`EstBrowserUrl64.dll`、`SQLiteDB64.dll`。顯示天锐绿盾（Tipray）的受支援瀏覽器清單中可能沒有 `comet.exe`。

**必須說明**：我們無法證明這是黑屏的原因。反例為 Positron 取得與 Comet **完全相同的 13 個通用模組**（含 `LdWaterMarkHook64.dll`）卻渲染正常。因此模組差異僅供參考。

### 懇請協助

1. 確認 `comet.exe` 是否需加入天锐绿盾的受支援應用程式清單。
2. 若可在**未安裝管控代理**的測試機上啟動同版本 Comet，即可一次判定問題歸屬（管控軟體端或廠商端）。

---

## 申請二：開發目錄掃描排除

### 現況

本機同時常駐三套即時檔案攔截：

| 產品 | 狀態 |
|---|---|
| 亿赛通 Cobra DocGuard Client 5.2.0 | 執行中 |
| 天锐绿盾 Tipray（`C:\Inetpub\ftproot\Tipray\LdTerm\`） | 執行中 |
| Kaspersky Endpoint Security 14.1 + Security Center 網路代理 | 執行中 |
| Microsoft Defender | **Normal 模式**，即時保護開啟 |

安裝 R／Python 套件屬小檔案密集操作（單次安裝可達數千個檔案），每個檔案需通過多層攔截。

### 申請排除路徑

```
C:\work                                        工作區（含 Python 虛擬環境）
C:\Users\PPCCpcpc\AppData\Local\R\win-library   R 套件庫
C:\Users\PPCCpcpc\AppData\Local\uv              套件快取
```

**僅限上述開發用目錄，不含 Downloads、桌面或任何文件目錄。**

### 另請評估

Microsoft Defender 目前為 Normal 模式且即時保護開啟，與 Kaspersky 形成重複掃描。是否轉為 Passive 模式，悉由貴部門依政策決定。

---

## 申請三：四個裝置缺少驅動程式

狀態皆為 `CM_PROB_FAILED_INSTALL`：

| 硬體 ID | 類別碼 | 位置 | 裝置 |
|---|---|---|---|
| `PCI\VEN_8086&DEV_7AA3&SUBSYS_86941043&REV_11` | `CC_0C0500` | 匯流排 0／裝置 31／功能 4 | Intel SMBus 控制器 |
| `PCI\VEN_8086&DEV_7AA4&SUBSYS_86941043&REV_11` | `CC_0C8000` | 匯流排 0／裝置 31／功能 5 | Intel SPI 控制器 |
| `PCI\VEN_8086&DEV_7ACC&SUBSYS_86941043&REV_11` | `CC_0C8000` | 匯流排 0／裝置 21／功能 0 | Intel Serial IO |
| `ACPI\INTC1056` | — | — | Intel 動態調校（DPTF） |

四者皆為 Intel 600 系列晶片組週邊，一般由 **Intel Chipset Device Software（INF Update Utility）** 與 **Intel Dynamic Tuning 驅動**提供，可自 ASUS PRIME H610M-R D4 支援頁或 Intel 官方取得。

**Windows Update 唯讀查詢結果：驅動 0 筆、所有更新 0 筆**——這四項不會由 Windows Update 補上。

**影響評估**：不影響運算功能（CPU、記憶體、磁碟、網路皆正常）。主要影響感測器讀值與電源／散熱調校精細度。**屬「該補但不急」。**

另：Realtek PCIe GBE 網卡驅動為 `10.10.714.2016`（2016-07-14），功能正常但版本老舊，可一併評估。

**我們未自行下載或安裝任何驅動程式**——驅動與韌體屬貴部門管理範圍，且需管理員權限。

---

## 申請四：顯示卡已無驅動可更新（僅告知，非申請）

顯示卡為 NVIDIA GeForce GT 730，PCI ID **`VEN_10DE&DEV_0F02`** = GF108 核心，屬 **Fermi** 世代（GT 730 另有 Kepler GK208 版本，不能依卡名推定）。

NVIDIA 對 Fermi 的支援狀態：

- 2018-03 發布 **391.35**，為 Fermi 最後一版驅動
- 2018-04 轉入 legacy
- 2019-01 支援期滿，此後未再發布任何更新，含安全性修補

**本機驅動版本正是 391.35（2018-03-23）——已是該硬體的最終版本，無更新版可安裝。**

此事僅供資產管理參考。作業上已改為 CPU 運算路線（i5-12400F 6C/12T），不影響分析工作。若貴部門有顯示卡汰換規劃，本機可列入評估。

---

## 申請五：一條名實不符的群組原則

```
HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate
    TargetReleaseProductVersion = "Windows 10"
```

此政策原意為將版本鎖定於 Windows 10，但本機已是 **Windows 11 Build 26200**。政策已名實不符，可能影響後續功能更新的取得。

**我們未自行更動**——屬群組原則層級設定，且可能為公司統一派送。懇請確認是否應清除或更新。

---

## 附記：我們沒有做的事

為避免誤會，一併說明：

1. **未停用、未解除安裝、未修改任何資安軟體。** 四套防護全部維持原狀運作中。
2. **未嘗試規避任何管控。** 曾考慮將 `comet.exe` 改名為 `chrome.exe` 以驗證假設，因屬規避資安管控，明確放棄。
3. **未提權。** 所有作業以一般使用者身分執行。
4. **未下載或執行任何廠商驅動安裝程式。**
5. **未接觸業務資料。** 所有測試資料均為程式即時產生的隨機數。

嘗試讀取 `C:\Inetpub\ftproot\Tipray\LdTerm\BrowserGuard.ini` 一次（為確認 Comet 是否在支援清單內），實際回傳 0 位元組（檔案鎖正常運作），隨即停止，未再以任何方式嘗試。

---

## 可供複驗的資料

| 項目 | 位置 |
|---|---|
| 驅動盤點（唯讀腳本，可重跑） | `診斷操作系統/Driver_Report.ps1` |
| 系統診斷（唯讀腳本，可重跑） | `診斷操作系統/Win10_Diagnose_v2.ps1` |
| 環境驗收（28 項實跑） | `診斷操作系統/Acceptance_Test.ps1` |
| 完整工作紀錄與稽核軌跡 | `優化並强化現有資源_視窗10版之Claude篇.qmd` 附錄 A～I |
| 變更前備份 | `~\PATH_user_backup_*.txt`、`~\gitconfig_backup_*.txt`、`~\R_packages_backup_*.csv` |
| 逐行執行記錄 | `~\Setup_DataStack_*.log`（PowerShell Transcript，可與資安日誌對照） |
