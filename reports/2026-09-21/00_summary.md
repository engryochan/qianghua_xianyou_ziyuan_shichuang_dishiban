# Windows 資料分析工作站診斷 v3

時間：2026-09-21 08:13:27 +04:00；系統管理員：False。所有探測離線唯讀，僅寫入本報告資料夾。

系統：Microsoft Windows 11 Pro 25H2 / Professional / Build 26200.9457；RAM 31.82 GB，當下可用 15.29 GB。

桌面軟體登錄筆數：86；目前使用者 Appx：154；Python 已盤點環境：7；R 套件筆數（含不同直譯器）：696。

- **注意 / 重啟**：偵測到待重啟標記；PendingFileRename 單獨出現未必代表 Windows 更新需要重啟。
- **建議 / 路徑**：LongPathsEnabled 未啟用。啟用可改善支援 longPathAware 的程式；並非所有舊程式都能突破長路徑限制。
- **說明 / GPU**：GPU 名稱/驅動僅供盤點；CUDA、PyTorch 支援與 Windows 11 CPU/TPM/Secure Boot/WDDM 資格須依廠商當前要求另外核實。
- **說明 / 套件**：未安装選用分析套件不等於故障。依工作負載建立獨立 Python/R 專案環境與鎖檔；不建議全域一次升級所有套件。
- **說明 / 範圍**：本次不連網檢查可升級版本；Windows 更新清單不代表完整更新歷史。未搜尋其他使用者、所有可攜程式、每個專案環境、Conda/WSL 容器內部。

## 工具鏈

| 工具 | 發現 | 版本 |
|---|---|---|
| Python | True | Python 3.14.7 |
| Python | True | Python 3.12.14 |
| Python | True | Python 3.12.14 |
| Python | True | Python 3.13.15 |
| Python | True | Python 3.13.15 |
| Python | True | Python 3.13.15 |
| Python | True | Python 3.13.15 |
| Rscript | True | Rscript (R) version 4.6.1 (2026-06-24) |
| Rscript | True | Rscript (R) version 4.6.1 (2026-06-24) |
| uv | True | uv 0.12.17 (635500036 2026-09-18 x86_64-pc-windows-msvc) |
| Git | True | git version 2.55.0.windows.5 |
| Git | True | git version 2.53.0.windows.3 |
| Quarto | True | 1.10.18 |
| Quarto | True | 1.10.18 #< CLIXML |
| Pandoc | False |  |
| PowerShell7 | True | PowerShell 7.6.5 |
| PowerShell7 | True | PowerShell 7.6.6 |
| Node | True | v24.19.0 |
| Java | False |  |
| DuckDB | True | v1.5.5 (Variegata) d8cdaa33fd |
| PostgreSQL | False |  |
| Docker | False |  |
| Julia | False |  |
| Winget | True | v1.29.380 |
| RtoolsCompiler | True | gcc.exe (GCC) 14.3.0 |

## 未完成或不可用的探測

- 19_secure_boot：Unavailable — 无法设置正确的权限。访问被拒绝。
- 21_tpm_specification：Unavailable — 拒绝访问 
- 22_bitlocker：Unavailable — 拒绝访问 
- 25_optional_features：Unavailable — The requested operation requires elevation.

- Runtime/Pandoc：Unavailable — 限定的安裝位置未發現；可能是可攜版或另一使用者安裝。
- Runtime/Java：Unavailable — 限定的安裝位置未發現；可能是可攜版或另一使用者安裝。
- Runtime/PostgreSQL：Unavailable — 限定的安裝位置未發現；可能是可攜版或另一使用者安裝。
- Runtime/Docker：Unavailable — 限定的安裝位置未發現；可能是可攜版或另一使用者安裝。
- Runtime/Julia：Unavailable — 限定的安裝位置未發現；可能是可攜版或另一使用者安裝。

完整資料：inventory.json；逐項 CSV/JSON；91_probe_status.csv 保存每項結果與耗時。空資料不等於健康，先查探測狀態。探測用 _probe_* 檔案保留以便稽核。報告含軟體與本機路徑，分享前請檢視。
