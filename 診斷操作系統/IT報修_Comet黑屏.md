# IT 報修單：Comet 瀏覽器視窗全黑

**主機**：SHJ-H0647-RYOCH　**使用者**：PPCCpcpc
**作業系統**：Windows 11 Pro 25H2（Build 26200.9457，2026-09-20 由 Win10 就地升級）
**應用程式**：Comet 152.0.7977.199（Perplexity，Chromium 底）
**提報日期**：2026-09-20

---

## 一、現象

Comet 可以啟動，行程正常存在、視窗標題列正常顯示「Comet」，但**視窗內容區完全漆黑**——連分頁列與網址列都沒有繪製出來。

像素量測（截取視窗後取樣，扣除標題列）：

| 應用程式 | 內容區近黑比例 | 平均亮度 | 相異色數 | 結果 |
|---|---|---|---|---|
| Google Chrome | 0 % | 243.3 | 730 | 正常 |
| Positron（Chromium/Electron） | 1.3 % | 236.4 | 408 | 正常 |
| **Comet** | **97.9 %** | **3.8** | 63 | **全黑** |

同一台機器、同一顆顯示卡、同一個驅動版本。

## 二、已排除的原因（皆經實測，非推測）

| 假設 | 驗證方式 | 結果 |
|---|---|---|
| 顯示卡驅動過舊 | Chrome 與 Positron 同為 Chromium 底，均正常渲染 | **排除** |
| 使用者設定檔損壞 | 以全新 `--user-data-dir` 啟動 | 仍全黑，**排除** |
| 硬體加速問題 | 以 `--disable-gpu` 啟動 | 仍全黑，**排除** |
| 安裝損壞 | 更新程式已將安裝由系統層級遷移至使用者層級，重測 | 仍全黑，**排除** |

**關鍵線索**：Comet 以無頭模式執行（`--headless=new --disable-gpu --screenshot`）**無法產出任何截圖檔**；Chrome 在完全相同的參數下正常產出 800×600 的 PNG。這表示故障**不在螢幕顯示層**，而是整個瀏覽器在本機環境下無法產生任何算繪輸出。

## 三、與管控軟體相關的觀察（供貴部門判斷，非結論）

列舉各應用程式行程實際載入的管控模組：

| 行程 | 被注入的管控模組數 |
|---|---|
| `chrome.exe` | 20 |
| `msedge.exe` | 18 |
| **`comet.exe`** | **13 ～ 15** |

`comet.exe` 缺少的是**瀏覽器專用模組**：`BrowserGuardx64.dll`、`BrowerInject64.dll`、`LdBrowserMonitor64.dll`、`LdBrowserDataFlow64.dll`、`LdSendFileLimit64.dll`、`EstBrowserUrl64.dll`、`SQLiteDB64.dll`。

這顯示**天锐绿盾（Tipray）的受支援瀏覽器清單中沒有 `comet.exe`**。

**必須說明**：我們無法證明這就是黑屏的原因。反例是 Positron 取得與 Comet **完全相同的 13 個通用模組**（含 `LdWaterMarkHook64.dll`），卻渲染正常。因此模組差異僅供參考。

## 四、懇請協助事項

1. 確認 `comet.exe` 是否需要加入天锐绿盾的受支援應用程式清單。
2. 若貴部門能在**未安裝管控代理**的測試機上啟動同版本 Comet，即可一次判定問題歸屬（管控軟體端或廠商端）。
3. 一併申請開發目錄的掃描排除（見下），以改善套件安裝效能。

## 五、附帶申請：開發目錄掃描排除

本機同時常駐三套即時檔案攔截（亿赛通 CDG、Kaspersky Endpoint Security、Microsoft Defender 且為 Normal 模式）。安裝 R／Python 套件屬於小檔案密集操作，每個檔案需通過三層攔截。

建議排除路徑：

```
C:\work                                          （工作區，含 Python 虛擬環境）
C:\Users\PPCCpcpc\AppData\Local\R\win-library     （R 套件庫）
C:\Users\PPCCpcpc\AppData\Local\uv                （套件快取）
```

另建議評估是否將 Microsoft Defender 轉為 Passive 模式，避免與 Kaspersky 重複掃描。

**我們沒有、也不會自行停用或規避任何資安軟體。** 以上僅為申請，悉由貴部門依公司政策決定。

---

*本報修單所有數據均為本機實測結果，測試方式見 `診斷操作系統/Win11_App_RealTest.ps1` 與 `Win10_Diagnose_v2.ps1`。*
