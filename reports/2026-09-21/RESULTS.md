# Windows 11 診斷與資料分析強化結果

日期：2026-09-21。以下區分實測、已修改與尚未處理項目；沒有宣稱完成所有系統升級或達到硬體無法提供的「最強」。

## 現有資源

| 項目 | 本機實讀 |
|---|---|
| 作業系統 | Windows 11 Pro 25H2，Build 26200.9457，64-bit |
| CPU | Intel Core i5-12400F，6 核心／12 邏輯處理器 |
| RAM | 31.82 GiB；首次盤點可用 14.8 GiB，屬瞬時值 |
| 磁碟 | BORY R500 256G SATA SSD，儲存 API 回報 Healthy；不等同完整 SMART／壽命檢測 |
| C 槽 | 237.21 GiB，盤點時剩約 60 GiB／25.3% |
| GPU | NVIDIA GT 730，2 GiB；硬體 ID 10DE:0F02，驅動 391.35（2018） |
| 分頁檔／電源 | 系統自動管理；已是高效能電源計畫，未再更動 |
| 防護 | Defender 即時保護／防竄改啟用，三個 Windows 防火牆設定檔均啟用；另有 Kaspersky 相關安裝及服務 |
| 長路徑 | LongPathsEnabled=0；使用 C:\work 短路徑避免常見問題，未修改 HKLM |
| VBS | 盤點回報未運作；未更動，應由 IT 評估企業基線 |
| 重啟 | CBS／Windows Update 重啟旗標均 false；只有 PendingFileRename=true，不能視為必須立即重啟 |

已盤點 **85 筆桌面軟體登錄、154 筆目前使用者 Appx**。包含元件、框架及重複登錄，不能當作 239 個獨立應用。未全面掃描其他使用者、可攜軟體、WSL、容器或所有私人專案。

主要分析與開發工具：

| 工具 | 版本／狀態 |
|---|---|
| R | 4.6.1，348 個套件（含系統與使用者套件）；同一 R 的兩個啟動器盤點須去重 |
| RStudio | 2026.09.0+174 |
| Positron | 2026.09.1 |
| Python 全域 | 3.14.7，僅基礎套件；日常分析請選下方 3.13 環境 |
| Python 分析 | 3.13.15；共用與 lab 專案環境各 182 個套件 |
| DuckDB CLI／Python | 1.5.5 |
| Quarto | 1.10.18；exe 實測成功，cmd 包裝器本輪啟動失敗 |
| uv | 0.12.17 |
| Git | PATH 版本 2.55.0.windows.5；另有 2.53.0 安裝，不宜任意刪除其他軟體依賴 |
| PowerShell | 發現 7.6.5 與 7.6.6 執行檔 |
| Office／WPS | Office 專業增強版 2016 登錄名，16.0.19127.20800；WPS 11.8.2.12330。登錄名不代表已核實授權／支援期限 |
| Rtools | 發現 GCC 14.3.0；本輪未重跑原生擴充編譯 |
| ODBC | 有 32-bit Access／Excel 驅動；64-bit 只盤點到舊 SQL Server 驅動，pyodbc 已安裝不代表已有現代 SQL Server ODBC 驅動 |

完整清單：[桌面軟體](11_software.csv)、[Appx](12_appx_current_user.csv)、[執行環境](35_runtimes.csv)、[Python 套件](37_python_packages.csv)、[R 套件](39_r_packages.csv)、[啟動項](13_startup.csv)、[ODBC](29_odbc.csv)。

## 已實際修改

1. **修復 Excel 功能缺口**。修改前兩個環境的真實 Excel 匯出均因 `ModuleNotFoundError: openpyxl` 失敗；依賴相容性檢查原本通過，所以只查版本或套件數會漏掉問題。
2. 兩個 venv 各新增 openpyxl 3.1.5、XlsxWriter 3.2.9、python-calamine 0.8.2、fastexcel 0.21.0、pywin32 312，以及依賴 et-xmlfile 2.0.0。**原有 176 個版本均保留，現為 182 個**。PyPI 二進位 wheel 安裝；兩個環境預檢均成功後才套用。
3. 更新版本快照 `env/python-ds-requirements.lock.txt`，保存安裝前後清單、預檢與驗證紀錄。未改全域 Python 或 R 套件。
4. 新增 `Start_Analytics.ps1` 入口，直接選取已驗證的 lab 環境。CPU 執行緒設定只作用於工作階段，結束後恢復呼叫端環境變數；大型 CSV／Parquet 使用 DuckDB 及明確資源預算。
5. 修正 `Analyze_LargeFile.ps1` 未搜尋安裝器實際建立的 `python-env` 目錄問題。
6. 修復唯讀診斷腳本兩處缺少括號、R 中文路徑參數亂碼，以及從 PowerShell 7 啟動 Windows PowerShell 時模組搜尋路徑不相容問題。先前 R 清單為空是探測失敗，非未安裝。
7. 修正 GT 730 架構／驅動建議；新增 GPU 硬體 ID 盤點欄位。原始本機報告排除於 Git，避免把設備清單跟程式一起提交。

這些修改提高功能完整性、可重現性與資源可控性；**未量測業務資料的前後速度，不能宣稱加速百分比**。DuckDB 的 buffer limit 不是程序全部記憶體的硬上限；資源設定依[官方效能文件](https://duckdb.org/docs/current/guides/performance/how_to_tune_workloads)採工作負載調整。

## 實跑驗收

| 驗收 | 結果 |
|---|---|
| 兩個 venv 的 uv pip check | 各 182 套件，相容性通過 |
| 兩個 venv 基本端到端測試 | 各 12 類通過：Excel 兩引擎、Parquet、Polars lazy、DuckDB SQL、sklearn、SciPy、statsmodels、SQLite、Matplotlib、Plotly、Jupyter import |
| 兩個 venv 擴充測試 | 各 7 類通過：XGBoost、LightGBM、econml、pandas calamine、Polars fastexcel、win32com import、真正 Notebook 核心執行 |
| Python 模型 | XGBoost 測試準確率 0.8884；LightGBM 0.8928；合成因果資料 ATE 2.0294（真值 2） |
| R 實跑 | 10 個關鍵套件齊全；data.table 合計 5,000,050,000；DuckDB 寫讀 100,000 列 Parquet；XGBoost 訓練集準確率 0.9886；reticulate→pyarrow 讀回同一檔案 |
| 大型檔案入口 | 小型合成 Parquet 分組成功，6 執行緒／6 GB buffer／20 GB 暫存上限；驗證流程，並未進行大於記憶體的壓力測試 |
| Quarto | 原生 quarto.exe 成功渲染 R＋Python 範本為 HTML |
| 腳本語法 | 所有現存 PowerShell 腳本通過解析；不代表全部舊腳本已執行或適合直接套用 |

測試使用合成資料；Office COM 僅驗證模組可載入，未操作 Excel 視窗；沒有測外部資料庫登入或真實業務模型。scikit-learn 的未來版本棄用警告仍存在，目前測試通過，升級前應重新驗收。

證據：[共用環境](smoke-ds/smoke-result.json)、[專案環境](smoke-lab/smoke-result.json)、[Python 模型](models-lab/models-result.json)、[已執行 Notebook](models-lab/executed.ipynb)、[R 結果](r-result.json)、[Quarto HTML](quarto-verified.html)、[Quarto 紀錄](quarto-check.log)。

## 尚未完成的系統項目

- **GPU 支援是硬體限制**：本機 PCI ID `0F02` 與 NVIDIA 官方討論中只支援 legacy 分支的型號一致，不能用同名 Kepler 版本的驅動。NVIDIA 已結束 Fermi 的功能及安全更新；請 IT 評估受支援顯示卡／工作站，不能靠強裝 CUDA 或 472.xx 變成現代 GPU。依據：[NVIDIA 型號討論](https://forums.developer.nvidia.com/t/450-57-driver-version-for-geforce-gt-730/144948)、[Fermi 支援計畫](https://nvidia.custhelp.com/app/answers/detail/a_id/4654)。未採購、未換驅動。
- **7 項應用更新尚未安裝**：Acrobat、Kimi、Edge、Teams、VC++ x64／x86、PyCharm。完整現行與候選版本見 [WinGet 清單](winget-upgrades.txt)。列出的更新不是「全部已更新」；涉及企業軟體、共用 runtime 或應用關閉，交由 IT 統一部署。WinGet 的候選比對亦不能涵蓋所有廠商通道。
- **管理員項目未核實**：Secure Boot、TPM 規格、BitLocker、Windows Optional Features，讀取被拒絕；不能報為已開啟或健康。Get-Tpm 另回傳空值，不能据此判斷沒有 TPM。VBS、長路徑及企業端點保護狀態由 IT 確認。
- **Comet 黑屏**：本輪未重新測試，不沿用「驅動／DLP 已證實為根因」的舊斷言。未停用任何防護或終止既有使用者應用。
- **容量**：256 GB SATA SSD 限制大型資料、暫存與多模型快取的擴充空間。先保留約 60 GB 可用量；硬體擴充需依資料規模、主板與預算確認，未自行採購。

## 使用與復原

從倉庫執行 `診斷操作系統/Start_Analytics.ps1 -Mode Jupyter` 可使用 lab 分析環境；大型資料請加 `-Mode LargeFile`、欄位參數及 OneDrive 外的新輸出目錄，詳見根目錄 README。

本輪安裝記錄位於 `excel-repair/20260921-081209-334613/`。`0-before.txt`／`1-before.txt` 是兩個環境原始版本，`0-after.txt`／`1-after.txt` 為安裝後版本。初次預檢因日誌格式問題停止，未改套件；成功執行記錄在上述時間子目錄。

若要復原，優先在另一個 Python 3.13 venv 依 before 清單重建並驗收，再切換專案；不要對仍在使用的環境直接執行破壞性同步。快照未含雜湊，未另外保存離線 wheel，未來重建仍依賴套件來源可用。Git 僅保護程式碼，不替代 Windows 還原或使用者資料備份。
