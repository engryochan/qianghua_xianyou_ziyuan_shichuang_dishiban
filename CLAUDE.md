# 專案說明（給接手的人與 AI）

## 2026-10-06 更正（優先於以下全部紀錄）

**本機已換成海兰 MiniPC-T1（i5-12400，有內顯），不是下文的華碩原機（i5-12400F，無內顯）。** 下文關於 GT 730 與 Comet 黑屏的整段，是**舊機**的紀錄，不要套到這台。新機目前 Windows 10 Pro 22H2 build 19045.7725。

### 一、`env/python-ds-requirements.lock.txt` 不能用來重建環境

這份鎖版檔**本身無解**，共六處內部矛盾，五處是真互斥：

| 矛盾 | 說明 |
|---|---|
| `boto3==1.43.98` vs `botocore==1.43.75` | boto3 要求 `botocore>=1.43.98` |
| `dalex` vs `evidently` | 前者要 `plotly>=6`，後者所有版本要 `plotly<6` |
| `flair` vs `transformers==5.17.0` | flair 所有版本要 `transformers<5` |
| `gevent==26.9.0` vs `cffi==2.0.0` | gevent 在 win32 要 `cffi>=2.1.1`（`ccxt` 也死釘 2.0.0）。**這兩個釘選單獨放在一起就無解** |
| `gluonts` vs `toolz==1.1.0` | gluonts 所有版本要 `toolz<1` |
| `s3fs==2026.9.0` vs `fsspec==2026.6.0` | s3fs 要 `fsspec>=2026.9.0` |

**根因：pip 安裝時不做全域求解。** 它逐一裝、衝突只印警告然後照裝，所以那個環境裡至少五組套件一直跑在自己不支援的依賴版本上。`pip freeze` 忠實地把這個無解狀態拍成了快照。

**推論：一份從未被真正用來重建過的鎖版檔，不是復原資產，只是一張照片。** 上一輪把它進版控是對的，但少了最後一步——拿它重建一次。等於備份從未做還原測試。

**現在請用這兩份（已實際用來建成環境才宣稱可用）**：

- `env/python-ds-core.in` — 核心環境約束檔（698 個 `==` + 28 個 `>=`）
- `env/python-ds-verified.lock.txt` — 重建後 freeze 的 728 行實況

舊的那份**保留不動，只當歷史證物**。

### 二、單體環境在數學上不可能成立，必須拆

740 套件同時塞 tensorflow + torch + jax + ray + gradio + openbb + ccxt + flair + evidently + dalex，永遠會差一個套件就無解。現行架構是**一個核心 + 五個衛星**：

| 環境 | 內容 | 外移原因（守衛實測值） |
|---|---|---|
| `C:\work\envs\ds` | 核心，728 個發行版 | — |
| `C:\work\envs\fin` | openbb、openbb-platform-api、pyportfolioopt、s3fs | `fsspec>=2026.9.0`（實到 2026.9.0） |
| `C:\work\envs\nlp` | flair、transformer-smaller-training-vocab | `transformers<5`（實到 4.57.6） |
| `C:\work\envs\mlops` | evidently、nannyml、feast | `plotly<6`（實到 5.24.1） |
| `C:\work\envs\xai` | dalex | `plotly>=6`（實到 7.1.0） |
| `C:\work\envs\rl` | tianshou、gluonts、gevent | `cffi>=2.1.1`（實到 2.1.1） |

uv 以硬連結共用快取，多開環境的邊際磁碟成本很小。

### 三、一切放 `C:\work`，絕對不要放 AppData

**Claude 桌面應用跑在 MSIX 容器裡，對 `%APPDATA%` / `%LOCALAPPDATA%` 的寫入會被重導**到 `…\Packages\Claude_pzs8sxrjxfjjc\LocalCache\…`，真實的 R / Python / Jupyter 看不到。探針實證；寫 `C:\work` 不受影響。

連帶後果：

- **本帳戶無法建立符號連結**（`Administrator privilege required`），junction 可以。`uv python install` 用符號連結做次版本連結，在 `%APPDATA%` 下會留壞連結。**設 `UV_PYTHON_INSTALL_DIR=C:\work\pythons`。**
- **`ipykernel install --user` 等於沒註冊**（寫進容器）。要設 `JUPYTER_DATA_DIR=C:\work\jupyter`，並**手寫 `kernel.json`**，`argv[0]` 用絕對路徑——`--prefix` 寫出來的是裸 `"python"`，會走 PATH 指到錯的解譯器。

### 四、驗收用的新腳本

| 檔案 | 用途 |
|---|---|
| `診斷操作系統/Accept_Python_Stack.py` | Python 15 項真實計算驗收 |
| `診斷操作系統/Accept_R_Stack.R` | R 10 項，含 `arrow` 缺席守衛與 duckdb→reticulate→pyarrow |
| `診斷操作系統/Accept_Satellites.py` | 衛星環境匯入與約束守衛 |
| `診斷操作系統/Reconcile_PythonLock.py` | 鎖版檔矛盾的可稽核迭代鬆綁器 |
| `診斷操作系統/Build_Satellite_Envs.ps1` | 重建五個衛星環境 |
| `診斷操作系統/Install_R_Stack_v2.R` | R 堆疊逐一安裝（不用 pak） |
| `診斷操作系統/Start_Analytics_v2.ps1` | 工作階段入口（＝`C:\work\Start_Analytics.ps1`） |

### 五、本輪新增的其他地雷

- **缺 `vcomp140.dll`**（Microsoft OpenMP 執行期）。本機有 `vcruntime140` / `msvcp140` / `concrt140`，就是沒有 OpenMP，也查無任何 VC++ Redistributable 安裝紀錄。任何連結 OpenMP 的 wheel 會報 `Could not find module <dll> (or one of its dependencies)`——**那個 DLL 明明在**，缺的是它的依賴。權宜解：環境內 `sklearn\.libs\vcomp140.dll` 自帶一份，複製到 `lightgbm\bin\`。正解請 IT 裝 VC++ Redistributable。
- **`lightgbm==4.5.0` 配不了新版 scikit-learn**：sklearn 把 `force_all_finite` 改名 `ensure_all_finite` 並移除舊名，lightgbm 4.5.0 還在呼叫舊名 → `TypeError`。依賴求解器看不到，**只有真的 fit 一次才會知道**。用 `lightgbm>=4.6.0`。
- **PowerShell 5.1 的 `Set-Content -Encoding utf8` 會寫 BOM**，`json.load` 直接拋 `Unexpected UTF-8 BOM`。用 `[System.IO.File]::WriteAllText($p, $s, (New-Object System.Text.UTF8Encoding($false)))`。
- **PowerShell 5.1 沒有三元運算子**：`(if(…){…}else{…})` 放在運算式位置會丟 `The term 'if' is not recognized`。
- **`uv pip freeze` 的提示訊息會汙染鎖版檔**：用 PowerShell 管線收集會把 `Using Python … environment at: …` 一起寫進去，拿去安裝得到 `Couldn't parse requirement … at position 0`。用 `2>$null` 並過濾。**我在同一輪裡先交付了一份這樣的壞鎖版檔，只有真的拿它建第二個環境時才發現。**
- **Store 版 `python` 代理殼**（`…\WindowsApps\python.exe`）在非互動工作階段會無回應地吊死。一律用絕對解譯器路徑。
- **R 的 `tempdir()` 不等於 Python 的 `tempfile.gettempdir()`**：R 回每個工作階段的 `…\Temp\RtmpXXXX`，Python 回父目錄。`templates/r-python-template.qmd` 早就用 `r.pq` 橋解掉了——**動既有檔案之前先讀它**，不要重新發明倉庫已解的問題。

### 六、Windows 11 升級仍未完成

三次嘗試、兩種來源映像（安裝助理 ESD 26200 / 官網 ISO 26300，SHA256 已核對），失敗簽名完全相同：Pre-Finalize、`0x80070057 - 0x50015`。換映像不影響結果。

**確定的機制**：`RegLoadKeyW` 對所有離線 hive 回傳 Win32 `87`（NewOS `SOFTWARE`、SafeOS `SYSTEM`、本機 `elam`）。`elam` 本身是合法 `regf`、32,768 bytes、一般使用者讀得到，所以不是損壞或權限問題。

本機同時常駐 Kaspersky KES 14.1.0.423（含開機 ELAM `klelam.sys`）、**亿赛通 Cobra DocGuard**（含 `CDGRegedit` 登錄檔元件）、**天锐绿盾 Tipray**。**沒有確定是哪一個驅動**，需管理員列舉 `fltmc filters` 與登錄檔回呼。

**下一步先試**（前三次都沒用過，失敗點正是 Dynamic Update 的 SSU 注入）：

```powershell
F:\setup.exe /auto upgrade /DynamicUpdate disable /eula accept
```

細節與 IT 交接單：`reports/2026-10-06/Win11升級第三次失敗_根因與IT請求_20261006.md`。

## 2026-09-21 更正（優先於下方歷史紀錄）

- 本機 GT 730 的 PCI ID 已實讀為 `VEN_10DE&DEV_0F02`，屬 Fermi 舊型版本；不能按「GT 730」名稱推定 Kepler，也不能套用下文 472.xx 驅動建議。NVIDIA 官方支援討論：https://forums.developer.nvidia.com/t/450-57-driver-version-for-geforce-gt-730/144948 。目前保持 CPU 分析，驅動與硬體更新交由 IT 核對。
- 兩個 Python 3.13.15 環境原有 176 套件，但缺 openpyxl/XlsxWriter，真實 Excel round-trip 失敗。本輪補入 openpyxl、xlsxwriter、python-calamine、fastexcel、pywin32 及 et-xmlfile，現各 182 套件，既有版本未變。版本快照已更新至 env/python-ds-requirements.lock.txt（不含雜湊）。
- R 有 348 套件；Win10_Diagnose_v3.ps1 原有兩處缺括號，且 Rscript 絕對中文路徑參數會亂碼，已改用子行程工作目錄下的 ASCII 相對路徑。Windows PowerShell 子程序另隔離 PS7 模組搜尋路徑。
- 本機報告在 reports/2026-09-21；未納入版控。新增 Start_Analytics.ps1 作為已驗證環境入口，CPU 設定僅作用於此工作階段；模型與 Notebook 驗收使用 Analytics_Model_Check.py。
- 歷史 Acceptance_Test.ps1 會終止所有 comet 行程，且部分檢查永遠 PASS；本輪未執行該腳本，不將它的舊 28/28 當作當前驗收。

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
- **Rtools 不該**永久**加進 PATH**，因為 `rtools\usr\bin` 的 `sh` / `find` / `sort` 會蓋掉 Windows 內建同名指令。

  > **2026-10-06 更正：「R 靠登錄機碼 `HKLM\SOFTWARE\R-core\Rtools` 尋找」這句不完整，照它做會失敗。**
  >
  > 實測：Rtools45 以 `/CURRENTUSER` 安裝後，登錄機碼確實寫在 `HKCU\SOFTWARE\R-core\Rtools\4.5.6768`（不是 HKLM），但 `R CMD SHLIB` 仍然報 **`'make' not found`**。
  >
  > R 4.5／4.6 的真正機制是 `etc\x64\Makeconf` 讀 **`RTOOLS45_HOME`** 去定位編譯器（`LOCAL_SOFT = $(RTOOLS45_HOME)/x86_64-w64-mingw32.static.posix`）；安裝器會把這個變數設成使用者層級。但 **`make.exe` 本身在 `rtools45\usr\bin`，必須在 PATH 上**，建置才啟動得起來。
  >
  > 所以正確做法是**只在建置的那個工作階段**設這兩樣：
  >
  > ```powershell
  > $env:RTOOLS45_HOME = 'C:\work\rtools45'
  > $env:Path = "C:\work\rtools45\usr\bin;$env:Path"
  > ```
  >
  > 或用 `診斷操作系統\Start_Analytics_v2.ps1 -WithToolchain`。
  >
  > 另外要記得：改完使用者層級環境變數後，**既有行程看不到**（`$env:` 是行程啟動時的快照，同本檔第 4 條教訓）。我第一次測失敗就是這個原因，不是 Rtools 裝壞。
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

升級 Windows 11 時 `%APPDATA%\uv\python` 整個目錄消失，`C:\work\envs\ds` 的套件還在但底層直譯器沒了。

> **下面這份是 2026-10-06 實測可行的版本。舊版的三個問題：`uv python install` 會把 Python 裝到會被 MSIX 重導的 `%APPDATA%`、`-r env/python-ds-requirements.lock.txt` 根本無解、`ipykernel install --user` 等於沒註冊。詳見本檔開頭的 2026-10-06 更正。**

```powershell
# 1) Python 與快取都放 C:\work，不要放 AppData（MSIX 重導 + 無法建符號連結）
$env:UV_PYTHON_INSTALL_DIR = 'C:\work\pythons'
$env:UV_CACHE_DIR          = 'C:\work\uv-cache'
uv python install 3.13

# 2) 核心環境：用「已驗證」的那份，不是 python-ds-requirements.lock.txt
uv venv --python 3.13 C:\work\envs\ds
uv pip install --python C:\work\envs\ds\Scripts\python.exe -r env/python-ds-core.in

# 3) 五個衛星環境（互斥套件）
.\診斷操作系統\Build_Satellite_Envs.ps1

# 4) Jupyter kernel：手寫 kernel.json，argv[0] 用絕對路徑
#    （--user 會寫進 Claude 容器；--prefix 會寫出裸 "python"）
$env:JUPYTER_DATA_DIR = 'C:\work\jupyter'
New-Item -ItemType Directory 'C:\work\jupyter\kernels\ds' -Force | Out-Null
$spec = '{
  "argv": ["C:\\work\\envs\\ds\\Scripts\\python.exe", "-m", "ipykernel_launcher", "-f", "{connection_file}"],
  "display_name": "Python 3.13 (ds)", "language": "python", "metadata": {"debugger": true}
}'
# 不可用 Set-Content -Encoding utf8：PS 5.1 會寫 BOM，json.load 直接拒收
[System.IO.File]::WriteAllText('C:\work\jupyter\kernels\ds\kernel.json', $spec,
  (New-Object System.Text.UTF8Encoding($false)))

# 5) 驗收——標準是「跑出結果」，不是「裝成功」
C:\work\envs\ds\Scripts\python.exe .\診斷操作系統\Accept_Python_Stack.py   # 期望 15/15
C:\work\R\R-4.6.1\bin\x64\Rscript.exe .\診斷操作系統\Accept_R_Stack.R      # 期望 10/10
```

R 與 Quarto 都可以**使用者層級**安裝，不需管理員：

```powershell
# R 4.6.1（安裝檔簽章 CN=Martyn Plummer）
.\R-4.6.1-win.exe /CURRENTUSER /SILENT /DIR=C:\work\R\R-4.6.1 /NOICONS /COMPONENTS=main,x64
.\診斷操作系統\Install_R_Stack_v2.R   # 逐一安裝，不用 pak
# Quarto：zip 解壓到 C:\work\tools 即可，不需安裝器
```

**教訓一：復原用的鎖版檔本身也要進版控。** 它原本只躺在 `C:\work` 裡，等於復原能力沒有備份。

**教訓二（2026-10-06 補）：進版控還不夠，必須拿它真的重建一次。** 那份鎖版檔進版控整整兩週，沒人用過，而它從第一行就無解。**備份沒做還原測試，等於沒有備份。**

## 日常工作專案：`C:\work\projects\lab`

不在 OneDrive、純 ASCII 路徑，附帶專屬 `.venv`。`templates/r-python-template.qmd` 是已實測 render 成功的 R+Python 混用範本——它用 `getwd()/.venv` 綁定專案內解譯器，所以要**在這個專案目錄裡** render。

> 2026-10-06 更正：此處原寫「Python 3.13.15、176 套件，版本與 `env/python-ds-requirements.lock.txt` 一致」。新機上重建後是 **Python 3.13.16、728 個發行版**，依據改為 `env/python-ds-verified.lock.txt`。

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

## 竣工驗收：`診斷操作系統/Acceptance_Test.ps1`

28 項實跑驗收，任一項 FAIL 即以非零離開碼結束，可直接接排程或 CI。驗收標準是「跑出結果」而非「有沒有裝」——不查版本號，而是真的算一遍再比對輸出。

```powershell
.\診斷操作系統\Acceptance_Test.ps1            # 完整
.\診斷操作系統\Acceptance_Test.ps1 -SkipRender # 略過最耗時的 quarto render
```

### 寫這支腳本踩到的五個坑（都讓它謊報過）

第一次跑出 FAIL 10、第二次 FAIL 1，**十一個紅字沒有一個是機器的毛病，全是腳本自身的缺陷**：

| 症狀 | 真正原因 |
|---|---|
| Python 八項全部「未取得輸出」 | DuckDB 的 `+` **不能串接字串**（要用 `\|\|`）。而且程式是寫進 `.py` 檔再執行的，本來就能用引號——把「`python -c` 會被吃掉引號」的教訓套用到不適用的地方 |
| R「關鍵套件缺 DTSUM: 5000050000」 | **.NET 的 `\s` 包含換行**。`'KEYMISS:\s*(.*)'` 在標籤後為空行時會跨行抓到下一行。一律改用 `[ \t]*` 與 `[^\r\n]*` |
| R「Parquet 只有 1 列」 | R 的 `cat()` 把 100000 印成 `1e+05`，`(\d+)` 只抓到開頭的 `1`。輸出數字給機器解析時一律 `format(x, scientific = FALSE)` |
| 整份腳本卡住 11.5 分鐘 | Comet 無頭模式在本機不會自己結束，而我用了 `Start-Process -Wait` 沒設逾時。改用 `WaitForExit(ms)` 並強制收尾 |
| econml ATE 時好時壞（1.846 vs 2.028） | `LinearDML` 內部交叉擬合有隨機性。未鎖種子實測連跑五次得 2.0307 / **1.8229** / 2.0295 / 2.03 / 2.0312；鎖 `random_state=0` 後三次都是 2.0294 |

**推論：驗收工具本身也必須被驗收。** 一份會謊報的驗收比沒有驗收更危險——它讓人以為查過了，然後去修四個根本沒壞的東西。

**驗收測試必須是確定性的。** 會飄的測試等同雜訊，久了就會被無視，那時真正的紅字也一起被無視了。

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
