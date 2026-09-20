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

Comet 少掉的全是**瀏覽器專用**模組：`BrowserGuardx64.dll`、`BrowerInject64.dll`、`LdBrowserMonitor64.dll`、`LdBrowserDataFlow64.dll`、`LdSendFileLimit64.dll`、`EstBrowserUrl64.dll`、`SQLiteDB64.dll`。

**但這不足以解釋黑屏。** 同日稍後的反例推翻了「半套掛鉤 = 黑屏」這個推論：

> **Positron 拿到的 13 個通用模組，與 Comet 的 13 個完全相同**（連攔截繪製路徑的 `LdWaterMarkHook64.dll` 都一樣），**而 Positron 渲染完全正常**（近黑 1.3%、平均亮度 236.4）。

所以模組數落差只是「這支應用不在管控軟體支援清單上」的**線索**，不是黑屏的**原因**。

### Comet 黑屏：已排除的假設（全部實測）

| 假設 | 結果 |
|---|---|
| GT 730 的 391.35 舊驅動 | **排除**——Chrome（近黑 0%）、Positron（1.3%）同為 Chromium 底，都正常 |
| 設定檔損壞 | **排除**——全新 `--user-data-dir` 仍全黑 |
| 硬體加速 | **排除**——`--disable-gpu` 仍全黑 |
| DLP 模組數較少 | **排除**——Positron 同樣 13 個模組卻正常 |
| 系統層級安裝損壞 | **排除**——更新程式遷移到使用者層級後重測，仍全黑 |

關鍵觀察：**Comet 連無頭截圖（`--headless --disable-gpu --screenshot`）都產不出檔案，而 Chrome 在同條件下正常產出 800x600。** 這代表失敗不在螢幕合成層，而是整個瀏覽器在這個環境裡產不出任何輸出。

**目前沒有確立的正因。** 現有結論只到「Comet 在這台機器上無法渲染，且不是上述任何一個原因」。這需要 IT（管控軟體端）或 Perplexity（廠商端）進一步診斷。不要嘗試把 `comet.exe` 改名成 `chrome.exe` 去騙過掛鉤——那是規避資安管控。

**另一套先前沒被盤點到的 DLP：天锐绿盾**，裝在 `C:\Inetpub\ftproot\Tipray\LdTerm\`（行程 `LdTerm.exe`、`LdApproval.exe`），沒有標準解除安裝登錄項，所以只比對「已安裝程式」清單會**完全漏掉**。偵測管控代理必須同時列舉**行程載入的模組**，不能只看已安裝程式。

**黑屏必須量測，不能用看的。** 判據：截取視窗 → 縮放取樣 → 內容區平均亮度 < 12 且相異色數 <= 3 即為黑屏。扣掉頂端瀏覽器外框再量，才分得出「整窗黑」與「只有內容黑」——後者才是算繪問題。

**找修法的順序**（逐一實測，第一個畫得出來的就是答案）：預設 → `--disable-gpu-sandbox`（測 DLP/防毒挂鉤）→ `--disable-gpu-compositing` → `--disable-gpu` → `--use-angle=swiftshader` → `--use-angle=d3d9` → `--disable-features=DirectComposition`。若只有關掉 GPU 沙箱才正常，指向亿赛通 CDG 或防毒注入，**正解是請 IT 加白名單，不是停用資安軟體**。

## 幾個容易誤判的事實（皆已實測）

- **Rtools 版本號不等於 R 次版本。** R 4.6 用的就是 Rtools45，CRAN 並未發行 rtools46。能否編譯請用 `R CMD SHLIB` 實測。
- **Rtools 不該加進 PATH。** R 靠登錄機碼 `HKLM\SOFTWARE\R-core\Rtools` 尋找；而 `rtools\usr\bin` 的 `sh` / `find` / `sort` 會蓋掉 Windows 內建同名指令。
- **Rtools 的 gcc 只服務 R，不服務 Python。** Python 的 C 擴充需要 MSVC Build Tools，兩條編譯鏈完全獨立（`scikit-survival` 因此裝不起來）。
- **Windows PowerShell 5.1 傳參數給原生程式會吃掉內嵌引號。** `python -c "...d.metadata[\"Name\"]..."` 會變成 `d.metadata[Name]` 而拋 `NameError`。用不需引號的寫法。

## 腳本

**全部位於 `診斷操作系統/` 子目錄**（2026-09-20 重整過，別再用倉庫根目錄的舊路徑）。

| 檔案 | 用途 |
|---|---|
| `診斷操作系統/Win10_Diagnose_v2.ps1` | 唯讀診斷，產出 `00_摘要.txt` 與 `99_建議指令.txt` |
| `診斷操作系統/Setup_DataStack.ps1` | 補齊工具鏈與 R/Python 堆疊，全部開關獨立、支援 `-WhatIf` |
| `診斷操作系統/Win10_Optimize.ps1` | 只負責「更新已安裝的東西」 |
| `診斷操作系統/Win10_Diagnose_v3.ps1` / `Setup_DataStack_v2.ps1` / `Win10_Optimize_v2.ps1` | 另一輪作者的版本，設計更保守（不改全域 `.Rprofile`、不動 PATH） |
| `診斷操作系統/Win11_App_RealTest.ps1` | **驗證應用是否真的畫得出畫面**（不是「有沒有裝」）。像素級黑屏判定 + 渲染旗標逐一實測 |
| `env/python-ds-requirements.lock.txt` | Python 工作環境的鎖版檔，**重建環境的唯一依據** |

流程：先 `Win10_Diagnose_v2.ps1`，再照 `99_建議指令.txt` 選 `Setup_DataStack.ps1` 的開關，第一次一律加 `-WhatIf`。

## 環境重建

升級 Windows 11 時 `%APPDATA%\uv\python` 整個目錄消失，`C:\work\envs\ds` 的套件還在但底層直譯器沒了。重建：

```powershell
uv python install 3.13
uv venv --python 3.13 C:\work\envs\ds
uv pip install --python C:\work\envs\ds\Scripts\python.exe -r env/python-ds-requirements.lock.txt
C:\work\envs\ds\Scripts\python.exe -m ipykernel install --user --name ds --display-name "Python 3.13 (ds)"
```

**教訓：復原用的鎖版檔本身也要進版控。** 它原本只躺在 `C:\work` 裡，等於復原能力沒有備份。

## 日常工作專案：`C:\work\projects\lab`

不在 OneDrive、純 ASCII 路徑，附帶專屬 `.venv`（Python 3.13.15、176 套件，版本與 `env/python-ds-requirements.lock.txt` 一致）。`templates/r-python-template.qmd` 是已實測 render 成功的 R+Python 混用範本。

**uv 以硬連結共用快取**：再建一份 176 套件的環境，磁碟實際只多佔約 **24 MB**，不是再複製一份 1 GB。所以「每個專案一個 `.venv`」在這台機器上是負擔得起的。

### Positron 的「A dedicated Python environment is available ❌」不是錯誤

它是設定檢查清單，字面意思就是「沒有開啟任何資料夾，所以找不到專屬環境」。實測確認：`storage.json` 的 `backupWorkspaces` 顯示 `"workspaces":[]`、`"folders":[]`，只有 `emptyWindows`——Positron 從未開過資料夾。

開啟一個含 `.venv` 的資料夾即可滿足。**但開啟後會遇到第二關：Restricted Mode。**

### Restricted Mode 會停用 Python／R 擴充

Positron 沿用 VS Code 的工作區信任機制。未信任的資料夾會顯示：

```
The Python extension is not available.
The R extension is not available.
Cannot start consoles in Restricted Mode.
```

看起來像環境壞掉，其實只是沒按信任。點橫幅的 **Manage → Trust**。

**這是安全決定，AI 不該代按。** 工作區信任的用途正是防止開啟他人來源的資料夾時自動執行其中的設定。

## 地雷：R 的 `arrow` 與 Python 的 `pyarrow` 不能在同一個行程裡共存

2026-09-20 實測隔離：

| 先載入的 R 套件 | 之後 `reticulate::import("pyarrow")` |
|---|---|
| 無 | OK |
| `duckdb` | OK |
| **`arrow`** | **FAIL: ImportError: DLL load failed while importing lib** |

兩者都夾帶各自的 Arrow C++ 二進位，先載入的會讓後載入的找不到符號。

**在 `.qmd` 裡混用 R 與 Python chunk 時，knitr 走 reticulate，兩者同行程，必炸。**

可行寫法（已實測 `quarto render` 成功產出 HTML）：**R 端改用 `duckdb` 讀寫 Parquet，不要 `library(arrow)`**：

```r
con <- dbConnect(duckdb()); duckdb_register(con, "dt", dt)
dbExecute(con, sprintf("copy dt to '%s' (format parquet)", pq))
```

其他相關事項：

- **reticulate 不認 `QUARTO_PYTHON`，只認 `RETICULATE_PYTHON`。** 沒設的話它會自己臨時下載一個乾淨的 Python（實測看到它抓 cpython-3.12.14 + numpy），於是你的套件全都不在，錯誤訊息是 `ModuleNotFoundError`，很容易誤判成環境壞掉。
- 正確設定：`Sys.setenv(RETICULATE_PYTHON = "C:/work/envs/ds/Scripts/python.exe")`
- 單獨用 `Rscript` + reticulate 時，12 個常用 Python 套件（含 polars、pyarrow）全部載入正常——**衝突只在載入 R `arrow` 之後才出現**。

## 比對式診斷（本倉庫最有效的一招）

單看一個應用「不正常」，很難知道原因。**找一個同類但正常的應用當對照組**，比對兩者的差異，答案通常立刻浮現：

- Comet 黑屏 vs Chrome 正常 → 比對注入模組 → 15 vs 20 → DLP 支援清單問題。
- 比對時務必抓**有主視窗的那個行程**。Chromium 的 renderer 子行程在沙箱裡本來就不被注入，抓錯行程會量到 0 而誤判。
- 不同類的應用不能互比（`explorer` 被注入的模組本來就比瀏覽器多）。

## 工作方式的硬性要求

- **變更系統之前先 commit 並 push**，留下可回溯的基線。
- 但要講清楚：**git 保護的是倉庫，不是作業系統**。PATH、電源計畫、套件庫都不在版控裡，其還原依據是腳本產生的備份檔（`~\PATH_user_backup_*.txt`、`~\gitconfig_backup_*.txt`、`~\R_packages_backup_*.csv`）與系統還原點。
- 這台是**公司資產**：亿赛通 CDG（透明加密/DLP）、Kaspersky Endpoint Security、Defender 三層常駐。**不要建議停用任何一個**——違反資安規範且多半被策略鎖定，正解是請 IT 加白名單。
- session 以一般使用者身分執行，**無法提權**。需要管理員的項目請產出指令交給使用者手動執行。
