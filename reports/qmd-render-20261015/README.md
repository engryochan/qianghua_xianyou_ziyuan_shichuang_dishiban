# QMD 檢查與渲染紀錄（2026-10-15）

本次遞迴處理專案全部 25 份 `.qmd`，包括根目錄歷史版本、`reports` 的 baseline 與 `templates` 範本。輸出格式為 HTML，保留原有 PDF 設定；本次沒有產生 PDF。

## 修復內容

- Cosmo 主題加入共用 `styles/offline.scss`，使用本機字型，避免渲染時下載 Google Fonts。
- HTML 公式改為 MathML，避免 MathJax 及 polyfill 的外部腳本下載；公式由支援 MathML 的現代瀏覽器顯示。
- `templates/r-python-template.qmd` 優先沿用 `RETICULATE_PYTHON`，其次搜尋專案環境及本機既有分析環境；驗證路徑存在後才使用。移除原先無條件指定不存在 `.venv` 的行為，並在 R 寫出 Parquet 後關閉 DuckDB 連線。
- 宇航報告的 Mermaid 區塊改為 Quarto 圖表語法，使流程圖參與渲染。
- Windows 11 文件「提問十四」的引用重新命名為 `rebate-1` 至 `rebate-10`，解決跨章節重複 `[1]`、`[2]`、`[3]` 導致來源連結混用的問題。
- 批次程序清除本次子行程繼承的 POSIX `C.UTF-8` 語系環境值，避免 Windows R 啟動及中文檔名警告。沒有修改系統永久環境設定。

既有未提交的 Windows 11 文件修改予以保留。

## 驗收資料

- [HTML 結果索引](index.html)：逐份開啟輸出。
- `final-results.json`：每份文件的實際渲染退出碼、輸出與紀錄路徑。
- `final-*.log`：最後一輪的完整 Quarto 輸出。
- `retry-v1_3_0.log`、`retry-windows11.log`：個別文件最後重試成功的紀錄，具體採用哪份紀錄以 `final-results.json` 為準。
- `verification.json`：原始檔／HTML SHA-256、輸出時效、標題／程式碼／公式數量、圍欄平衡及本機資源檢查。
- `structure-before.json`：修復前的全檔案結構盤點。
- `render-*.log`、`render-results.json`：前期排查紀錄，包含已解決的外部下載問題；最終結果應以 `final-results.json` 與 `verification.json` 為準。

依各文件既有 `execute` 設定渲染，沒有用全域 `--no-execute` 或容忍執行錯誤的方式跳過失敗。兩份 R／Python 範本均需真正執行；原已設定 `eval: false` 的歷史文件保留原設定。文件內的普通 PowerShell／Python 示例程式碼仍以程式碼展示。

## 重跑

在 PowerShell 執行：

```powershell
.\reports\qmd-render-20261015\render-all.ps1
```

需有 Quarto、R 及相應套件。程序優先使用 `RETICULATE_PYTHON`，未設定時使用本機既有 `C:/work/envs/ds/Scripts/python.exe`；不安裝套件、不升級解譯器。Python 批次工具亦支援 `--retry-failed`，只重試上輪失敗項目。

## 核實範圍與限制

本次核實涵蓋全部 QMD 的文件結構、Quarto 解析與實際 HTML 產出、依設定執行的程式區塊及輸出資源完整性。沒有逐條查證數十萬行歷史對話中的硬體敘述、日期／農曆、法規、金融、科學及外部引用，也沒有把歷史敘述改寫成目前事實。渲染成功不代表這些主張已獲事實背書。

目前所用 Quarto 1.10.19／Pandoc 對 `zh-CN`、`zh-TW` 會回報缺少 `translations/zh.yaml` 及 Abstract 翻譯警告；這是工具翻譯資料警告，保留文件原有中文語系與自訂標籤。其餘發現及驗收結果見 `verification.json`。

發現 318 個無法由專案資料還原來源的 ChatGPT 引用標記：電競平台文件 308 個、Windows 11 文件 10 個。原標記保留，不臆造來源；這些引用仍待補上原始 URL 或文獻資料。HTML 產出不受阻，但引用本身尚未通過核實。

最終 Quarto 渲染退出碼：**25／25 成功**。輸出與原始檔同目錄。全部 HTML 的結構、輸出時效、本機腳本／樣式／圖片資源及內部片段連結另由 `verify.py` 檢查。
