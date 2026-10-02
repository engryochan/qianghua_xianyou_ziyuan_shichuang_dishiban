# 系統升級與驗收紀錄

更新日期：2026-09-22。依使用者最新指示，以已驗證的 lab 分析環境為主，先完成系統升級；保留 ds 的新增套件，不降版、不清除。

## 已完成

- Windows 11 Pro 25H2，26200.9457。2026-09-22 08:14 的 Windows Update 掃描成功（ResultCode 2），目前配置的來源提供 0 個待裝項目。
- 10 個 ASUS 官方硬體匹配 INF 已逐項交給 PnPUtil 安裝，均返回 0；36 個原有第三方驅動包已完整匯出。2026-09-22 重啟後再次檢查，原先 4 個缺驅動裝置均正常，現有異常裝置為 0。
- Intel SMBus/SPI/晶片組 10.1.37.5、主機橋/PEG 10.1.45.10；Serial IO GPIO/I2C 30.100.2531.31；Realtek 1168.27.50.919，網路 Up、1 Gbps；ME 2552.8.10.0、WMI 2544.8.3.0、DAL 1.46.2024.221。
- Edge 150.0.4078.105 → 153.0.4234.48。官方 MSI SHA256 與 Microsoft 簽章核對通過，MSI 結束碼 0。使用安裝器自行註冊的 rename-msedge-exe 命令完成主程式切換。獨立配置的 headless 測試成功執行 JavaScript 並產生 DOM，主程式完整版本 153.0.4234.48、UA 為簡化的 Edg/153.0.0.0。
- EdgeUpdate 主程式與 edgeupdate/edgeupdatem 服務已恢復。手動 /ua 執行記錄顯示 user-context 0x80070002，不能據此宣稱整個自動更新排程已驗收成功；正式 Edge 安裝與新版渲染均另有成功證據。
- 高效能計畫、LongPathsEnabled=1 保持；Kaspersky 服務運行、三個防火牆設定檔開啟。未更改安全排除、分頁檔、BIOS、企業更新政策，未自動重啟。

## 分析驗收與性能

- lab：190 個套件，uv pip check 通過；12 類基本測試、7 類模型/Notebook 測試全過。XGBoost 0.8884、LightGBM 0.8928、因果 ATE 2.02943285，與上次一致。
- R：444 筆安裝記錄，5 類驗收全過；10 萬行 Parquet、data.table、XGBoost 0.9886、reticulate/pyarrow 通過。啟動有 locale 警告，未造成這些測試失敗。
- ds：12 類基本測試通過，但從原 190 個套件增至 742 個，uv pip check 發現 15 項衝突。不是本輪驅動/瀏覽器作業的套件變更；按使用者選擇保留，不能稱為完整健康環境。建議使用既有 Start_Analytics.ps1（預設 lab）。
- 合成基準：DuckDB 7.605 → 7.198 ms、Polars 7.320 → 6.199 ms、NumPy 4.335 → 4.308 ms（預熱後各 5 次中位數）。這些測試未見變慢；跨日系統負載不同，不能把差異直接歸因於驅動，也不能推論全部工作負載永不退化。

## 邊界與恢復依據

- NVIDIA GT 730 硬體 ID 0F02 為 Fermi，保留 391.35；未混裝其他架構驅動。RST/VMD 已為核對的官方版本，未強制覆蓋。
- 不能把「系統優化完成」解讀為所有第三方軟體最新、全部 GUI 功能完成測試或 BIOS 必須刷新。
- 驅動安裝腳本的末尾驗收原遇非數字版本字串而報 Stopped；原日誌保留。其 10 項安裝已成功，後續版本比較修正後對共同裝置未發現降版，並另以重啟後零異常裝置驗證。重啟前後消失的 USB/虛擬裝置 ID 單獨記錄，不直接當作降版。
- 本次未建立新系統還原點（Windows 頻率限制）；原驅動備份位於 ../update-round2/drivers/installation-20260921-135922/driver-backup。Git 只保存脚本，不是作業系統還原。

## 證據

system-after.json、drivers-after.csv、driver-changes.json、driver-version-validation.json、windows-update-scan.json、edge-install.log、edge-finalize.json、edge-final-validation.json、performance-comparison.json、smoke-lab/smoke-result.json、models-lab/models-result.json、r-validation/r-result.json、ds-dependency-check.txt。

官方資料：
- https://www.asus.com/sg/supportonly/prime%20h610m-r%20d4/helpdesk_download/
- https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/msiexec
- https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution

## WebView2 收尾

已使用 Microsoft 官方 Evergreen 安裝器將 WebView2 150.0.4078.105 更新為 153.0.4234.48；登錄版本、執行檔版本與簽章已核實，證據 webview-validation.json。已運行的舊 Edge/WebView2 程序未被強制關閉，正常重新開啟應用後使用新版。此項驗證為安裝狀態，不等同每個使用 WebView2 的第三方應用 GUI 都已驗收。

