# RStudio 與 Positron：安裝於 `C:\work` 並像素級驗證算繪

2026-10-06。全程**一般使用者權限，未提權**。

## 一、裝了什麼

| 項目 | 版本 | 位置 | 方式 |
|---|---|---|---|
| **Positron** | 2026.09.1 build 2（Code OSS 1.130.0） | `C:\work\Positron` | 官方 `UserSetup-x64.exe`，`/SILENT /DIR=C:\work\Positron /MERGETASKS=!runcode` |
| **RStudio** | 2026.09.0+174 | `C:\work\RStudio` | 官方 **ZIP** 解壓（免安裝器、免登錄） |

兩者的完整性驗證：

| 檔案 | Authenticode |
|---|---|
| `Positron-2026.09.1-2-UserSetup-x64.exe` | **Valid** — `CN="Posit Software, PBC"` |
| `C:\work\Positron\Positron.exe` | **Valid** — 同上 |
| `C:\work\RStudio\rstudio.exe` | **Valid** — 同上 |

> RStudio 的 ZIP 在 `download1.rstudio.org` 與 docs 站都**查不到官方 SHA256**
> （`.zip.sha256` 回 404）。所以改為驗證解壓後 `rstudio.exe` 的 Authenticode——
> 對「內容是否來自 Posit」而言，這比容器雜湊更直接。

## 二、解壓踩到的坑：`Expand-Archive` 對大壓縮檔不堪用

第一次用 `Expand-Archive` 解 735.5 MB 的 RStudio ZIP，**跑了近半小時仍未完成**，
而且隨工作階段中斷而死，留下半成品：381 個檔案 / 0.53 GB，`rstudio.exe` 還沒出來
（它按字母序排在 `resources.pak` 之後，正好卡在那裡）。

改用 Windows 內建的 bsdtar：

```powershell
tar -xf 'C:\work\dl\RStudio-2026.09.0-174.zip' -C 'C:\work\RStudio'
```

**34.9 秒**完成，4,931 個檔案 / 2.1 GB。

> `C:\Windows\System32\tar.exe`（bsdtar）自 Windows 10 1803 起內建，認得 zip。
> **大型壓縮檔一律用它，不要用 `Expand-Archive`。**

## 三、啟動捷徑被 MSIX 容器吃掉了

這是本輪最需要注意的一項。

開始選單在 `%APPDATA%\Microsoft\Windows\Start Menu\Programs` 底下，而
**Claude 桌面應用對 `%APPDATA%` 的寫入會被重導進它的 MSIX 容器**。

後果是：**我啟動的 Positron 安裝器所建立的開始選單項，以及我手動建立的 RStudio
捷徑，兩者都只存在於容器內**，先生的真實開始選單看不到。實測確認：

```
<CONTAINER>\Positron\Positron.lnk              True
<CONTAINER>\Posit\RStudio (C-work).lnk         True
```

並以哨兵檔決定性驗證：寫入 `%APPDATA%\...\Programs\probe.txt`，該檔同時出現在
`...\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\...`。

**程式本體不受影響**（在 `C:\work`，已驗證不被重導）。被困住的只有捷徑。

### 解法：捷徑放 `C:\work\Launch`

```
C:\work\Launch\Positron.lnk   -> C:\work\Positron\Positron.exe
C:\work\Launch\RStudio.lnk    -> C:\work\RStudio\rstudio.exe
```

兩者工作目錄都設為 `C:\work\projects\lab`。已驗證目標可解析、且該目錄**不被重導**
（`C:\work\Launch\_redirect_probe.txt` 在容器內不存在）。

先生可以直接在該資料夾雙擊，或釘到工作列。若要進開始選單，請在**自己的終端**
（不在容器內）執行：

```powershell
Copy-Item 'C:\work\Launch\*.lnk' "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\" -Force
```

## 四、接線：兩個 IDE 都指向既有堆疊

### RStudio 找 R

R 以 `/CURRENTUSER` 安裝，所以登錄機碼落在 **HKCU**（不是 HKLM）：

```
HKCU:\SOFTWARE\R-core\R     InstallPath=C:\work\R\R-4.6.1  Current=4.6.1
HKCU:\SOFTWARE\R-core\R64   InstallPath=C:\work\R\R-4.6.1  Current=4.6.1
HKLM:\SOFTWARE\R-core\R     absent
```

RStudio 兩邊都讀，所以自動找得到。為求確定性另外明確釘住：

```
RSTUDIO_WHICH_R = C:\work\R\R-4.6.1\bin\x64\R.exe   （使用者層級）
```

### Positron 的設定放工作區，不放 `%APPDATA%`

Positron 的使用者設定在 `%APPDATA%\Positron\User\settings.json`——**我寫進去會被
重導**，先生啟動的 Positron 讀不到。所以改用工作區設定
`C:\work\projects\lab\.vscode\settings.json`（在 `C:\work` 底下，不受影響）：

```json
{
  "python.defaultInterpreterPath": "C:\\work\\projects\\lab\\.venv\\Scripts\\python.exe",
  "positron.r.customRootFolders": ["C:\\work\\R\\R-4.6.1"],
  "positron.r.interpreters.default": "C:\\work\\R\\R-4.6.1\\bin\\x64\\R.exe",
  "quarto.path": "C:\\work\\tools\\bin\\quarto.cmd",
  "r.rterm.windows": "C:\\work\\R\\R-4.6.1\\bin\\x64\\Rterm.exe",
  "r.libPaths": ["C:\\work\\R\\R-4.6.1\\library"]
}
```

已用 `json.load` 實際解析過，不只是寫出來。

### 入口腳本

`C:\work\Start_Analytics.ps1`（＝`診斷操作系統/Start_Analytics_v2.ps1`）現在會回報：

```
analytics environment ready
  python  : 3.13.16
  R       : R version 4.6.1 (2026-06-24 ucrt)
  quarto  : 1.10.18
  uv      : uv 0.12.23
  satellites: fin, nlp, mlops, xai, rl
  Positron : 2026.09.1
  RStudio  : 2026.09.0+174
  launchers : C:\work\Launch\{Positron,RStudio}.lnk
```

## 五、驗收：不只能報版本，還要畫得出畫面

### CLI 層

```
positron --version        -> Positron 2026.09.1 build 2 / Code OSS 1.130.0 / x64
positron --list-extensions -> ruff 2026.84.0, pyrefly 1.3.1, jupyter 2025.9.1,
                              debugpy 2026.6.0, jupyter-renderers 1.3.0 …
rstudio --version         -> 2026.09.0+174
```

### 像素層（用倉庫自己的 `Win11_App_RealTest.ps1`）

這一步是必要的，因為本倉庫最硬的教訓正是：**Comet 裝好了、能報版本、視窗全黑。**
所以兩個 IDE 都跑一遍七種渲染旗標組合：

| Profile | Positron | RStudio |
|---|---|---|
| A 預設 | **True**　內容區亮度 244.40 / 相異色 75 | **True**　247.15 / 67 |
| B `--disable-gpu-sandbox` | True　244.87 / 54 | True　246.57 / 67 |
| C `--disable-gpu-compositing` | True　244.40 / 74 | True　247.05 / 67 |
| D `--disable-gpu` | True　244.40 / 74 | True　247.04 / 68 |
| E `--use-angle=swiftshader` | True　244.76 / 56 | True　247.04 / 67 |
| F `--use-angle=d3d9` | True　244.40 / 74 | True　246.43 / 68 |
| G `--disable-features=DirectComposition` | True　244.40 / 75 | True　246.43 / 68 |

**兩者預設啟動即正常算繪，七種組合全部 `Rendered=True`。** 與 Comet 不同，
不需要任何旗標、也不需要請 IT 加白名單。

## 六、順手更正：這台機器沒有 NVIDIA 顯卡

`Win11_App_RealTest.ps1` 的報告原本**無條件**印出：

```
本机 10DE:0F02 为旧型 Fermi；不要强装其他架构驱动。
```

那是**舊機**（華碩原機 + NVIDIA GT 730）的寫死文案。本機實讀：

```
Intel(R) UHD Graphics 730
PCI\VEN_8086&DEV_4692&SUBSYS_22128086&REV_0C
驅動 32.0.101.7088（2026-06-17）  共享 2 GB  1920x1080
```

**完全沒有 NVIDIA 卡。** 而這份報告是要交給 IT 的——它會讓 IT 去查一張不存在的
顯卡。該腳本自己的 `01_GPU.csv` 其實已正確記下 Intel UHD 730，只有結論段落寫死。

> 「UHD Graphics 730」與「GT 730」名字極像，一個是 Intel 內顯、一個是 NVIDIA 獨顯，
> 很容易混。本機是前者。

已改為在產生報告時實讀所有顯示適配器：

```
实读适配器：Intel(R) UHD Graphics 730  |  PCI VEN_8086&DEV_4692&SUBSYS_22128086&REV_0C  |  驱动 32.0.101.7088
```

改動後以 `Parser::ParseFile` 確認語法無誤、BOM 保留，並重跑確認輸出正確。

## 七、本輪三次反斜線錯誤的共同真因

本輪我在三個地方把反斜線弄錯：`kernel.json` 的 `argv[0]`、`Start_Analytics.ps1`
的 gcc 路徑、以及這支腳本的 `-split`。一開始以為是各自的疏忽，追到最後是**同一個**
原因：

> **本環境的 Bash heredoc（即使寫成 `<<'EOF'`）會把 `\\` 塌成 `\`。**

所以任何「用 heredoc 產生含 Windows 路徑的程式碼」都會靜默少掉一層轉義。症狀各異
但都很難看出來：

| 現場 | 寫出的東西 | 症狀 |
|---|---|---|
| `kernel.json` | `"argv": ["C:\work\envs\fin\..."]` | `json.load` 拋 `Invalid \escape`，而 `kernelspec list` 照樣列出 |
| `Start_Analytics.ps1` | `C:\worktools45聠_64-...in\gcc.exe` | 路徑變亂碼（`\t`→tab、`\x`→hex、`\b`→退格） |
| `Win11_App_RealTest.ps1` | `-split '\'` | regex 不完整轉義，切不開，PCI 欄位靜默變空 |

**對策**（本輪已全部採用）：

1. **產生 JSON 用 `ConvertTo-Json`**，不要字串拼接。
2. **切字串用 `.Split([char]0x5C)`**，不要 `-split` 搭反斜線 regex（`-split` 吃 regex）。
3. **在 heredoc 裡需要反斜線時用 `chr(92)` 程式化組出**，不要寫字面值。
4. 最重要：**產生完就真的解析／執行一次**。這三個錯誤沒有一個能靠讀程式碼發現。

## 八、仍需先生自己動手的兩件事

1. **把捷徑放進開始選單**（上面第三節那行 `Copy-Item`）——我的寫入會被容器吃掉。
2. **Positron 的工作區信任**。第一次用 Positron 開 `C:\work\projects\lab` 會進
   Restricted Mode，顯示「The Python extension is not available / Cannot start
   consoles in Restricted Mode」。那不是環境壞掉，點橫幅 **Manage → Trust** 即可。
   **這是安全決定，我不代按**——工作區信任的用途正是防止自動執行來源不明的資料夾設定。
