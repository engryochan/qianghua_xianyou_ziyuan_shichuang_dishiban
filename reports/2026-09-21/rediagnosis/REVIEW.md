# 再次診斷與不退化驗證

2026-09-21。使用者已確認另有人員／工具正在調整本機，並指示「先完成診斷與驗證」。因此本階段只盤點、執行合成資料驗證及寫報告；未執行已準備的驅動安裝器，未更改分頁檔、安全防護、BIOS、電源計畫或更新政策。

## 結論

**已測的資料分析功能未發現退化；不能據此保證全作業系統、全部應用或所有工作負載都無退化。** 仍有 4 個在線裝置缺少驅動，Edge 更新未完成；目前不是全機升級竣工狀態。另一方完成調整後應重建基線，再由單一操作者繼續安裝與驗收。

## 與第一輪的差異

| 項目 | 第一輪 | 本次複查 |
|---|---|---|
| Windows | Pro 25H2，26200.9457 | 相同；期間已重啟 |
| Python 兩個分析環境 | 各 182 套件 | 各 190；原有版本未變，新增 8 套件 |
| R | 348 筆安裝記錄 | 444 筆、434 個不同套件名稱；10 個套件同時存在於使用者與系統庫 |
| 長路徑 | LongPathsEnabled=0 | 1 |
| 分頁檔 | 自動管理，當時配置 5,120 MB | 非自動，初始 16,290 MB、上限 32,581 MB |
| 分頁檔使用 | 初次瞬時 12 MB | 本次瞬時 156 MB、峰值 161 MB；不代表長期 commit 峰值 |
| C 槽剩餘 | 約 60 GiB／25.3% | 約 45.46 GiB／19.2% |
| Defender | Normal，保護執行中 | Not running，WinDefend Stopped |
| Kaspersky KES.14.1 | 先前服務啟動失敗／Stopped | 本次 Running、Auto；網路代理亦 Running |
| Windows 防火牆 | 三設定檔開啟 | 仍全部開啟 |
| 電源 | 高效能 | 相同 |
| 磁碟健康 API | Healthy | Healthy（不是完整 SMART 或壽命測試） |

上述設定變化不是本輪由我執行。分頁檔配置增加約 10.9 GiB，可解釋磁碟剩餘減少的一部分；其餘不能僅憑兩個快照歸因。固定較大分頁檔不等同運算加速，目前不再更改。

Kaspersky 已執行，因此不能單凭 Defender 停止判定沒有防護；但服務 Running 也不能替代端點管理主控台對病毒碼、政策與保護模組健康的核實。今日 07:59 曾出現 Kaspersky 啟動逾時事件，目前服務已運作，未將舊事件誤報為仍故障。

證據：[目前狀態](../update-round2/current-state.json)、[安全服務](security-services.json)、[服務事件](service-errors.json)、[完整盤點摘要](00_summary.md)。

## 已完成應用更新（在停止新變更的指示之前）

| 應用 | 之前 | 目前驗證 |
|---|---|---|
| Kimi | 3.1.4 | 3.2.11 |
| Teams | 26183.1903.4892.4448 | 26198.304.4946.9672；Appx 實讀 |
| PyCharm | 2026.1.5 | 登錄名稱 2026.2.3、版本 262.10968.92；安裝資料夾仍名 2026.2.2，記錄兩者差異 |
| Adobe Acrobat | 26.001.21691 | 26.002.21931 |
| VC++ x64 | 14.42.34438 | 14.51.36247 |
| VC++ x86 | 14.42.34438 | 14.51.36247；x64 更新後再查 x86 已無升級候選，現由登錄核實 |
| Edge | 150.0.4078.105 | 仍 150.0.4078.105，**未完成更新** |

Edge：WinGet 拒絕跨安裝技術升級。未按錯誤訊息卸載瀏覽器。已安裝、Microsoft 簽章有效的更新器執行後，其日誌回報 `0x80070002`，未得到成功更新證據；後續須先修復官方更新通道與確認安裝來源。WebView2 也仍為 150.0.4078.105，未宣稱最新。

安裝紀錄：[逐項結果](../update-round2/apps-install-results.json)、[更新後候選](../update-round2/winget-after.txt)。本輪驗證了版本與資料分析能力，沒有逐一登入、開啟或驗證全部第三方應用 GUI。

## 資料分析功能驗證

- 兩個 Python 3.13.15 環境的 `uv pip check`：各 190 套件，全數依賴相容。
- 兩個環境各 12 類基本驗證通過：Excel 雙引擎、Parquet、Polars lazy、DuckDB、迴歸、SciPy、statsmodels、SQLite、Matplotlib、Plotly、Jupyter import。
- lab 模型與 Notebook 7 類通過；XGBoost 0.8884、LightGBM 0.8928、因果 ATE 2.02943285，與前次確定性測試結果相同。
- R：關鍵套件齊全；分組總和正確、100,000 列 Parquet 寫讀正確、XGBoost 訓練準確率 0.9886、reticulate→pyarrow 成功。
- Python 新增 arch、linearmodels、optuna 及其依賴共 8 個；未覆盖原 182 個版本。R 另有使用者庫的新版本及系統庫舊版本並存，詳見版本變動檔；未自行整理或刪除。

證據：[lab 基本](analytics-smoke/smoke-result.json)、[共用基本](analytics-smoke-ds/smoke-result.json)、[模型](models-lab/models-result.json)、[R](r-validation/r-result.json)、[Python 差異](package-diff.json)、[R 差異](r-version-changes.json)。

## 目前效能基線

合成 1,000,000 列 Parquet，暖機後執行 5 次，6 執行緒；每次均驗證分組總和。DuckDB 中位約 7.60 ms，Polars 約 7.32 ms；512×512 NumPy 矩陣乘法含結果比對約 4.34 ms。測試資料高度可壓縮、檔案約 1 MB，不能代表真實大型資料或磁碟吞吐。

這是**當前基線**，沒有同条件的更新前時間，所以不能宣稱已加速，也無法證明所有效能都不退化。同時存在其他調整與背景工作，後續比較需在穩定、相似負載下重跑。原始時間及資源數據：[performance-baseline.json](performance-baseline.json)。

## 驅動候選已查證，但未安裝

4 個在線裝置仍為 Code 28：`PCI 8086:7AA3`、`PCI 8086:7AA4`、`PCI 8086:7ACC`、`ACPI INTC1056`。

**更正：INTC1056 匹配 Serial IO 套件的 iaLPSS2_GPIO2_ADL.inf，不能再直接判為缺 DTT。**

ASUS PRIME H610M-R D4 官方 Windows 11 頁面已核實以下套件，下載檔 SHA-256 與官方值一致；候選 INF 的 catalog 簽章有效，並有本機在線硬體 ID 匹配：

| 類別 | 套件／INF 版本 |
|---|---|
| Chipset | 10.1.37.5；Alder Lake 部分 INF 10.1.45.10 |
| Serial IO | 30.100.2531.31 |
| Realtek LAN | 1168.27.50.919；目前 10.10.714.2016 |
| Intel ME Interface | 2552.8.10.0；目前 2406.5.5.0 |
| Intel DAL | 1.46.2024.0221；目前 1.44.2023.710 |
| Intel ME WMI | 2544.8.3.0；目前 2408.5.4.0 |

來源：[ASUS 官方支援頁](https://www.asus.com/sg/supportonly/prime%20h610m-r%20d4/helpdesk_download/)。清單含 10 個 INF 候選，不等同 10 個獨立裝置，亦不代表全部有必要覆蓋目前可用的 Microsoft 內建驅動。版本數字不能取代硬體適用性、驅動排名及實測。

`Install_Verified_Drivers.ps1` 尚未執行。腳本設有型號、現行版本未改變、檔案雜湊、有效簽章、管理員權限、磁碟空間及驅動備份檢查；使用 PnPUtil 正常排名，不強制低排名、不自動重啟。必須在另一方停止變更後重新產生計畫，並完成安裝後裝置、網路、分析及重啟驗收，才可結案。驅動備份／還原點也不能保證任意硬體與應用都零風險。

NVIDIA GT 730 的 PCI ID 10DE:0F02 仍受舊硬體支援限制；未強裝 Kepler 驅動。RST/VMD 目前 20.2.6.1025 與 ASUS 頁面版本相同，未碰啟動儲存驅動。未更新 BIOS／韌體。

## 尚不能判定的項目

Secure Boot、TPM 規格、BitLocker 及 Windows Optional Features 讀取仍需管理員，未以空值宣稱健康。Windows Update 會沿本機既有來源與政策查詢，不繞過企業政策；掃描結果另存 windows-update-scan.json。未測業務資料、外部資料庫、完整 GUI 工作流程、電池／睡眠、全磁碟壓力或長時間穩定性。

13:47（UTC+04:00）重啟後再次 Windows Update 掃描：ResultCode=2（成功），0 個可見、未安裝更新。此結論只限當時設定來源提供的項目，不代表所有廠商驅動皆最新；4 個缺驅動裝置仍需分別處理。安裝目錄核實沒有任何 `installation-*` 執行記錄，本輪驅動仍未安裝。
