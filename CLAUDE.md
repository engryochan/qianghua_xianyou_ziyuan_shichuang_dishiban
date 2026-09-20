# 專案說明（給接手的人與 AI）

本倉庫是一場**多模型對照實驗**：同一個問題（「診斷 Windows 10 並強化資料分析環境」）交給 Claude、ChatGPT、Perplexity、Grok、深度求索回答，答案全部收在 `優化並强化現有資源_視窗10版.qmd`（約 4,000 行）。

## 最重要的一課

那 4,000 行 PowerShell **讀起來全都是對的**——語法正確、邏輯通順、註解完整。2026-09-20 真的拿去跑，五個 bug 才現形，沒有一個能靠讀程式碼發現：

1. `qs` / `fastshap` / `vip` 已遭 CRAN 封存 → **pak 的求解器是全域的**，一個套件找不到就把整批 74 個標成 `dependency conflict`。錯誤訊息長得像「R 版本太新」或「鏡像壞了」。
2. `.Rprofile` 寫入 `OMP_NUM_THREADS` / `TZ` 會改變 R 的**執行行為** → 同一份腳本在不同機器跑出不同結果。`.Rprofile` 只該管「套件怎麼裝」。
3. Rtools 的 gcc 在 `x86_64-w64-mingw32.static.posix\bin`，**不在** `usr\bin` → 偵測寫錯路徑會把「已安裝」誤報成「沒安裝」。
4. PATH 判定查 `$env:PATH` 是**行程啟動時的快照** → 剛改過 PATH 的機器會把已修好的項目報成沒修。要讀登錄檔的持久化 PATH。
5. **uv 建立的 venv 刻意不安裝 pip** → `python -m pip list` 回空清單，把 149 個套件的環境誤報成空環境。改用 `importlib.metadata`。

**推論**：驗收標準是「跑出結果」，不是「安裝成功」。

## 2026-09-20 第二輪：升上 Windows 11 之後

升級大版本會**留下升級前的驅動**。系統版本跳了，驅動沒跳，於是出現「昨天好好的，今天黑屏」。

- **判斷 OS 版本一律用 `CurrentBuild >= 22000`，不要用字串比對。** Win10 就地升級到 Win11 之後，註冊表 `ProductName` 仍寫著 `Windows 10`（微軟的已知行為），只有 `CurrentBuild` 誠實。`Win32_OperatingSystem.Caption` 會正確更新，但兩個來源不一致這件事本身就會誤導人。
- **NVIDIA 驅動的真實版本要從 Windows 版本字串反解**：取末 5 碼重組。`23.21.13.9135` → `391.35`（2018-03-23）。直接看 `23.21.13.9135` 會以為很新。
- **GT 730（Kepler）配 391.35 驅動確實過舊**（Kepler 最後支援的分支是 R470 / 472.12），這點成立。但**「Chrome / Edge 也會失敗」這句話經實測不成立，已推翻**（見下）。
- **i5-12400F 沒有內顯**，獨顯是唯一的顯示裝置，沒有任何 fallback。

### 黑屏的真正根因：DLP 只認得它名單上的瀏覽器（2026-09-20 實測）

同一台機器、同一顆 GT 730、同一個 391.35 驅動，用**同一套像素判據**量測：

| 瀏覽器 | 內容區近黑比例 | 平均亮度 | 相異色 | 結果 |
|---|---|---|---|---|
| Chrome | **0%** | 243.3 | 730 | 正常 |
| Comet | **97.8%** | — | 160 | **黑屏** |

所以顯示路徑本身是好的，驅動不是黑屏的原因。真正的差別在**注入的 DLP 模組**：

| 行程 | 被注入的 DLP 模組數 |
|---|---|
| `chrome.exe` | **18** |
| `msedge.exe` | **18** |
| `comet.exe` | **13** |

Comet 少掉的全是**瀏覽器專用**模組：`BrowserGuardx64.dll`、`BrowerInject64.dll`、`LdBrowserMonitor64.dll`、`LdBrowserDataFlow64.dll`、`LdSendFileLimit64.dll`、`EstBrowserUrl64.dll`、`SQLiteDB64.dll`。但通用掛鉤照樣注入，其中包含攔截繪製路徑的 **`LdWaterMarkHook64.dll`**。

**結論：天锐绿盾（Tipray）認得 `chrome.exe` / `msedge.exe`，不認得 `comet.exe`，於是只套了半套掛鉤——浮水印掛鉤進去了，讓它正常運作的配套模組沒進去，合成器輸出因此全黑。**

佐證（皆已實測）：`--disable-gpu` 無效、全新 `--user-data-dir` 無效、連分頁列與網址列都沒畫出來（代表黑在 UI 層而非網頁層）。

**這不是使用者能修的，正解是請 IT 在綠盾主控台把 `comet.exe` 加入受支援瀏覽器清單。** 不要嘗試把 `comet.exe` 改名成 `chrome.exe` 去騙過掛鉤——那是規避資安管控。

**另一套先前沒被盤點到的 DLP：天锐绿盾**，裝在 `C:\Inetpub\ftproot\Tipray\LdTerm\`（行程 `LdTerm.exe`、`LdApproval.exe`），沒有標準解除安裝登錄項，所以只比對「已安裝程式」清單會**完全漏掉**。偵測管控代理必須同時列舉**行程載入的模組**，不能只看已安裝程式。

**黑屏必須量測，不能用看的。** 判據：截取視窗 → 縮放取樣 → 內容區平均亮度 < 12 且相異色數 <= 3 即為黑屏。扣掉頂端瀏覽器外框再量，才分得出「整窗黑」與「只有內容黑」——後者才是算繪問題。

**找修法的順序**（逐一實測，第一個畫得出來的就是答案）：預設 → `--disable-gpu-sandbox`（測 DLP/防毒挂鉤）→ `--disable-gpu-compositing` → `--disable-gpu` → `--use-angle=swiftshader` → `--use-angle=d3d9` → `--disable-features=DirectComposition`。若只有關掉 GPU 沙箱才正常，指向亿赛通 CDG 或防毒注入，**正解是請 IT 加白名單，不是停用資安軟體**。

## 幾個容易誤判的事實（皆已實測）

- **Rtools 版本號不等於 R 次版本。** R 4.6 用的就是 Rtools45，CRAN 並未發行 rtools46。能否編譯請用 `R CMD SHLIB` 實測。
- **Rtools 不該加進 PATH。** R 靠登錄機碼 `HKLM\SOFTWARE\R-core\Rtools` 尋找；而 `rtools\usr\bin` 的 `sh` / `find` / `sort` 會蓋掉 Windows 內建同名指令。
- **Rtools 的 gcc 只服務 R，不服務 Python。** Python 的 C 擴充需要 MSVC Build Tools，兩條編譯鏈完全獨立（`scikit-survival` 因此裝不起來）。
- **Windows PowerShell 5.1 傳參數給原生程式會吃掉內嵌引號。** `python -c "...d.metadata[\"Name\"]..."` 會變成 `d.metadata[Name]` 而拋 `NameError`。用不需引號的寫法。

## 腳本

| 檔案 | 用途 |
|---|---|
| `Win10_Diagnose_v2.ps1` | 唯讀診斷，產出 `00_摘要.txt` 與 `99_建議指令.txt` |
| `Setup_DataStack.ps1` | 補齊工具鏈與 R/Python 堆疊，全部開關獨立、支援 `-WhatIf` |
| `Win10_Optimize.ps1` | 只負責「更新已安裝的東西」 |
| `Win10_Diagnose_v3.ps1` / `Setup_DataStack_v2.ps1` / `Win10_Optimize_v2.ps1` | 另一輪作者的版本，設計更保守（不改全域 `.Rprofile`、不動 PATH） |
| `Win11_App_RealTest.ps1` | **驗證應用是否真的畫得出畫面**（不是「有沒有裝」）。像素級黑屏判定 + 渲染旗標逐一實測 + winget 版本落差 |

流程：先 `Win10_Diagnose_v2.ps1`，再照 `99_建議指令.txt` 選 `Setup_DataStack.ps1` 的開關，第一次一律加 `-WhatIf`。

## 工作方式的硬性要求

- **變更系統之前先 commit 並 push**，留下可回溯的基線。
- 但要講清楚：**git 保護的是倉庫，不是作業系統**。PATH、電源計畫、套件庫都不在版控裡，其還原依據是腳本產生的備份檔（`~\PATH_user_backup_*.txt`、`~\gitconfig_backup_*.txt`、`~\R_packages_backup_*.csv`）與系統還原點。
- 這台是**公司資產**：亿赛通 CDG（透明加密/DLP）、Kaspersky Endpoint Security、Defender 三層常駐。**不要建議停用任何一個**——違反資安規範且多半被策略鎖定，正解是請 IT 加白名單。
- session 以一般使用者身分執行，**無法提權**。需要管理員的項目請產出指令交給使用者手動執行。
