# Windows 11 資料分析工作站

2026-09-21 已實際盤點本機並補齊 Excel 分析能力。完整本機報告：
[診斷與強化結果](reports/2026-09-21/RESULTS.md)。報告含設備與軟體資訊，不納入 Git。

## 已驗證環境

- R 4.6.1：348 個套件。
- `C:\work\envs\ds`、`C:\work\projects\lab\.venv`：Python 3.13.15，各 182 個套件。
- Excel / Parquet / SQL / 統計 / CPU 建模 / Jupyter 核心 / R–Python 互通已實跑。
- Quarto 請明確使用 `C:\Program Files\Quarto\bin\quarto.exe`；本輪 `.cmd` 包裝器失敗，`.exe` 已成功產出 R＋Python HTML。

## 日常入口

在本倉庫開啟 PowerShell：

```powershell
# 驗證基本分析功能
.\診斷操作系統\Start_Analytics.ps1 -Mode Check

# 啟動 JupyterLab；localhost、保留驗證、使用既有專案環境
.\診斷操作系統\Start_Analytics.ps1 -Mode Jupyter

# CSV / Parquet 直接分組，不必把整張表載入 pandas
.\診斷操作系統\Start_Analytics.ps1 -Mode LargeFile `
  -InputPath C:\work\data\sales.csv -GroupBy category -ValueColumn amount `
  -OutputDirectory C:\work\results\sales-001
```

大型資料請選擇 OneDrive 之外的新輸出目錄。預設 6 執行緒、最多 6 GB DuckDB buffer、20 GB 磁碟暫存；程式會依當時可用 RAM 下修 buffer，並預留磁碟空間。這是資源預算，並非整個程序的記憶體硬上限或所有工作負載的最佳速度保證。

## 復原與驗收

`env/python-ds-requirements.lock.txt` 保存目前 182 個套件的精確版本（無 artifact 雜湊）。本輪新增 6 個套件，未升級原有套件。安裝前後清單保存在本機報告的 `excel-repair` 子目錄。

`Repair_Analytics.py` 預設只預檢，加 `--apply` 才修改指定 venv；使用既有版本約束，所有目標預檢成功才開始安裝。過程不是跨環境交易，若中途失敗請先讀取 status.json 與安裝紀錄。

`Analytics_Model_Check.py` 實跑 CPU 模型、Excel 新引擎及 Notebook；`Analytics_R_Check.R` 驗證 R 資料處理與跨語言 Parquet。

GT 730 的本機 PCI ID 為 `10DE:0F02`，不能套用舊文檔的 Kepler 472.xx 建議。系統驅動、企業防護及待更新應用由 IT 核對；未自動重啟。



