# OneDrive 重複倉庫查證、WSL2 可行性、HuggingFace 硬體清單與 IDE

日期：2026-10-11（約 12:50–13:20）
全程唯讀。未刪除任何檔案、未安裝任何軟體、未改任何設定。

依先生指示，完全**未**登錄、修改、刪除、新增或試探任何網管／資安的 IP 設定，
**未**碰網段內任何帳號與設備，**未**存取任何博彩網站。

---

## 一、OneDrive 與 Documents 下的 GitHub：**各自獨立，不互相同步**

### 1.1 先確認最關鍵的一件事：`Documents` 沒有被 OneDrive 接管

```
HKCU\...\User Shell Folders\Personal = C:\Users\PPCCpcpc\Documents
[Environment]::GetFolderPath('MyDocuments') = C:\Users\PPCCpcpc\Documents
```

**OneDrive 的「已知資料夾移動」（KFM）沒有啟用**，`Documents` 是真實的本地資料夾。
所以 `OneDrive\文档\GitHub` 與 `Documents\GitHub` 是**兩個獨立的實體位置**，
不是同一個地方的兩個名字。

> 這一步必須先查。如果 KFM 開著，`Documents` 就**是** OneDrive 的一部分，
> 那「兩份」其實是同一份，後面所有比較都沒有意義。

### 1.2 兩份本倉庫是各自獨立的 git clone

| 位置 | HEAD | 分支 | 遠端 | 未提交 |
|---|---|---|---|---|
| `OneDrive\文档\GitHub\qianghua…` | `449059cb` | `世博量化研究院` | `github.com/engryochan/qianghua_xianyou_ziyuan_shichuang_dishiban.git` | 0 |
| `Documents\GitHub\qianghua…` | **`03b6576`** | `世博量化研究院` | **同一個遠端** | 0 |

**結論：同一個 GitHub 遠端、同一分支，但停在不同 commit。**

- **不同步**：兩者之間沒有任何同步機制。git 不會讓兩個工作副本互相更新，
  它們只各自對 GitHub 推拉。
- **重疊**：血緣重疊（同一遠端的歷史），但工作副本已分岔——OneDrive 那份落後。
- **獨立**：是，各自獨立。
- OneDrive 那份會同步到**微軟雲端**；`Documents` 那份不會（只推 GitHub）。

`online-gaming-decision-intelligence-lab` 同樣兩邊各有一份獨立 clone。

### 1.3 **更正我上一輪的數字：「OneDrive 內合計逾 10 GB」已不成立**

上一輪（09:4x）我在最大檔案清單裡找到
`OneDrive\文档\GitHub\basic-data-analytical-lab\.git\objects\pack\pack-a23a…pack`
**7.62 GB**，據此寫下「整機最大的非系統佔用在 OneDrive 裡，合計逾 10 GB」。

**12:5x 複查時那個檔案已不存在。** 現況：

| 位置 | 大小 | 檔案數 |
|---|---|---|
| `OneDrive`（全部） | **3.12 GB** | 2,011 |
| └ `文档\GitHub`（全部） | 3.11 GB | 1,948 |
| &nbsp;&nbsp;├ `qianghua…` | 2.98 GB | 1,378 |
| &nbsp;&nbsp;├ `online-gaming…` | 0.13 GB | 570 |
| &nbsp;&nbsp;└ `basic-data-analytical-lab` | **0.00 GB** | **0**（只剩空目錄） |
| **`Documents\GitHub`（全部）** | **9.98 GB** | 11,573 |
| └ `online-gaming…` | **6.32 GB** | 9,925 |
| └ `qianghua…` | 3.65 GB | 1,444 |

**所以現在佔空間較大的是 `Documents\GitHub`（9.98 GB），不是 OneDrive（3.12 GB）。**

**我無法證明那 7.62 GB 是什麼移除的**——先生在這段期間清了回收桶並做了清理，
也可能是 git 自行重新打包。照實記錄：我當時量到它，現在它不在了，原因不明。

### 1.4 一個會讓測量失準的坑：`-Recurse` 不穿越 ReparsePoint

`OneDrive\文档\GitHub` 帶 `ReparsePoint` 屬性（OneDrive 以雲端篩選驅動
`CldFlt` 實作，該驅動在 `fltmc` 清單高度 180451）。

**PowerShell 的 `Get-ChildItem -Recurse` 預設不穿越 reparse point**，
所以從父目錄遞迴測量 OneDrive 子樹會**低估甚至得到 0**：

| 方法 | `basic-data-analytical-lab` |
|---|---|
| `Get-ChildItem -Force`（直接列舉） | **18 個子項**（`.git`、`.claude`、`.posit`…） |
| `Get-ChildItem -Recurse -Force -File` | **0 個檔案** |
| `cmd /c dir /s /a` | **0 檔 / 0 bytes**（權威：目錄在，但真的沒有檔案） |

**三者不一致，只有交叉比對才看得出來。** 量 OneDrive 這類含 reparse point
的樹，要用 `cmd dir /s` 或其他會穿越的工具。

### 1.5 檔案是否「僅線上」（不佔本機空間）？——**否，全部在本機**

OneDrive Files On-Demand 會把雲端檔案標成 `Offline` / `RecallOnDataAccess`，
那種檔案有邏輯大小但**不佔本機空間**。實查結果：

```
OneDrive 全部 2,011 檔；邏輯合計 3.12 GB；其中僅線上 0.00 GB
→ 實際佔本機約 3.12 GB
```

**沒有任何檔案是僅線上的**，那 3.12 GB 確實佔用本機磁碟。
（注意：`ReparsePoint` 屬性**所有** OneDrive 檔案都有，不論是否已下載；
真正判斷「僅線上」要看 `Offline` / `RecallOn*`。只看 `ReparsePoint` 會誤判。）

### 1.6 一個實質風險：git 倉庫不該放在 OneDrive 裡

OneDrive 會同步 `.git` 目錄，而它對 `index`、`objects`、`refs` 的**併發寫入
可能損壞倉庫**（git 假設自己獨佔這些檔案）。本倉庫既有規定「日常工作專案放
`C:\work\projects\lab`，純 ASCII、不在 OneDrive」正是這個道理。

**OneDrive 那兩份是否還需要，屬先生決定，我不動使用者資料。**
若確定不需要，刪除可回收約 3.11 GB；但那是使用者資料，請先生自行處置。

---

## 二、WSL2：**先騰空間再裝，且有一個已知阻塞**

### 2.1 WSL2 不會節省空間，它會消耗空間

先生提到「節省空間安裝 WSL2」，這裡要講清楚方向：

| 項目 | 現況 |
|---|---|
| WSL 本體已裝 | `C:\Program Files\WSL` **1.14 GB** |
| 已安裝發行版 | **無** |
| 裝一個發行版要多少 | 約 1–3 GB，`ext4.vhdx` 之後**只會長大不會自動縮** |
| 目前 `C:` 可用 | **33.69 GB（14.1%）** |

**所以順序應該是：先跑 `Reclaim_Disk_Space.ps1` 騰出空間，再裝 WSL2。**
執行休眠檔（12.71 GB）與 `Windows.old`（40.29 GB）兩項後約有 86 GB 可用，
屆時裝 WSL2 很寬裕。

### 2.2 WSL 控制層正常，但 `vmcompute` 仍是未解的阻塞

```
WSL 版本      : 3.0.1.0
核心版本      : 6.18.40.1-1
預設版本      : 2
已安裝發行版  : 無
wsl --list --online : 正常（24 個發行版可選）
```

控制層沒問題。**但：**

| 服務 | 狀態 |
|---|---|
| `WSLService` | Running / Automatic |
| `hns` | Running / Manual |
| **`vmcompute`** | **Stopped / Manual** |

`vmcompute`（Host Compute Service）在本次開機時**兩度逾時失敗**
（06:52:07 逾時 45,000 ms、06:57:07 逾時 30,000 ms），而所有 Hyper-V 與
Containers 選用功能都是 `Disabled`，只有 WSL 與 `VirtualMachinePlatform` 是
`Enabled`（見 `Windows11升級後診斷.md` 的「提權複驗」一節）。

**我先前預判「一旦裝了發行版就會卡住」，這一點仍未被推翻也未被證實**——
`vmcompute` 是 Manual 啟動，沒有 VM 要跑時 Stopped 是正常的；它能否**按需
啟動成功**，只有真的裝一個發行版開機才知道。

### 2.3 建議的做法

1. **先騰空間**（`Reclaim_Disk_Space.ps1`，需提權）。
2. 裝一個**最精簡**的發行版先試水溫。清單裡最輕的是 `Debian`
   （`wsl --install Debian`）。Ubuntu 完整版較大。
3. 若 `vmcompute` 按需啟動失敗，才需要處理那個阻塞——可能要啟用
   `Microsoft-Hyper-V-Services`，**那是系統變更且本機受管理，應先問 IT。**

**安裝發行版需要下載（約 1 GB）且屬系統變更，我未執行。**
請先生在自己的提權終端執行，或明示要我代為下載。

---

## 三、HuggingFace 硬體清單

### 3.1 `huggingface.co/settings/hardware` 要填什麼

依 HF Hub 官方文件，該頁用來申報你擁有的運算硬體，Hub 會據此推薦跑得動的模型；
填寫方式是選**類型（GPU／CPU／Apple Silicon）→ 供應商與型號 → 記憶體 → 數量**，
可標一個為 primary，預設公開但可關閉 `Publicly Visible`。
在提供 GGUF／MLX 的模型頁上會出現「Hardware compatibility」面板，
估算各量化版本能否跑得動；個人頁則會有 TFLOPS 徽章。

### 3.2 本機實測硬體（可直接照填）

**CPU**

| 欄位 | 值 |
|---|---|
| 型號 | **12th Gen Intel Core i5-12400** |
| 核心／執行緒 | 6 核 / 12 執行緒 |
| 基準時脈 | 2500 MHz |
| 插槽 | 1 |

**記憶體**

| 欄位 | 值 |
|---|---|
| 總容量 | **31.77 GB**（申報填 **32 GB**） |
| 模組 | 2 × 16 GB @ 2667 MHz |
| 位置 | Controller0-ChannelA-DIMM0、Controller1-ChannelA-DIMM0 |

**GPU**

| 欄位 | 值 |
|---|---|
| 名稱 | **Intel UHD Graphics 730**（內顯） |
| PNP ID | `PCI\VEN_8086&DEV_4692&SUBSYS_22128086&REV_0C` |
| 驅動 | 32.0.101.7088（**原廠已有 32.0.101.7092**） |
| `AdapterRAM` 回報 | 2.00 GB |
| **CUDA / ROCm** | **無**（無 NVIDIA、無 AMD 獨顯） |

> **那個「2.00 GB VRAM」要小心。** `Win32_VideoController.AdapterRAM` 對內顯
> 回報的是一個配置值，不是獨立顯示記憶體——UHD 730 **沒有獨立 VRAM**，
> 它共用系統記憶體。**填 HF 時不要當成 2 GB 的獨立顯卡。**

**系統與儲存**

| 欄位 | 值 |
|---|---|
| 機器 | MiniPC **T1** |
| 主機板 | Intel **H610I** Chipset |
| BIOS | 5.27（2025-07-29） |
| 磁碟 | **HAILAN 256G**，238.47 GB，SSD，SATA（單一磁碟） |

### 3.3 實話：這台機器在 HF 上申報的意義有限

**本機沒有任何可用的推論加速器。** HF 的 GPU 清單以 NVIDIA／AMD／Apple
Silicon 為主，Intel 內顯即使能填也沒有 CUDA／ROCm 可用。

**所以建議只申報 CPU（i5-12400）+ 32 GB RAM。** 預期結果：

- TFLOPS 徽章會很低。
- Hardware compatibility 面板會建議**小型 GGUF 量化模型**。
- 以 32 GB RAM 做 CPU 推論，實務上 **7–8B 參數模型 Q4 量化**是舒適區，
  13B Q4 勉強可行但慢。**這台機器的定位是統計與資料分析，不是 LLM 推論。**

> 若 HF 的清單裡找不到某個裝置，社群討論指出該清單維護在 `huggingface.js`
> 的程式碼裡，缺項要去該 repo 開 issue 或 PR。

---

## 四、HuggingFace 有沒有可以連線實測的 IDE？——**有，但有三個條件**

### 4.1 HF Spaces Dev Mode

HF 的方案是 **Spaces Dev Mode**：在執行中的 Space 裡同時啟動一個 SSH 伺服器
與一個 VS Code server，所以可以

- 直接用**瀏覽器內的 VS Code Web**（不需本機裝任何 IDE）；
- 或從**本機編輯器透過 SSH 連進去**（`ssh <space-subdomain>@ssh.hf.space`，
  或用 HF CLI 的 `hf spaces ssh`，需先把本機 SSH 公鑰加進帳戶）。

**三個條件／限制必須先知道：**

1. **要付費方案。** 官方文件寫明 Dev Mode 屬 **PRO 或 Team & Enterprise**，
   且仍標示 **beta**。
2. **程式碼不會自動生效**——改完要按 `Refresh` 重啟 app；**依賴也不會自動裝**，
   要自己 `pip install`。
3. **對 Space 有要求**：映像需含 `bash`、`curl`、`wget`、`procps`、`git`、
   `git-lfs`；程式碼必須放在 `/app`；Dockerfile 需有 `CMD`；
   **建議 Debian 系基底**（Alpine 等未測試、不保證可用）。
   社群另有 VS Code 連線逾時的回報。

### 4.2 本機這邊的現實

| 項目 | 狀態 |
|---|---|
| **VS Code** | **未安裝**（系統與使用者層都沒有） |
| Positron | 已安裝 **2026.10.0** |
| RStudio | 已安裝 2026.09.0+174 |
| `ssh.exe` | **可用**（`C:\WINDOWS\System32\OpenSSH\ssh.exe`） |

**我原本以為 Positron 不能做 Remote SSH（因為微軟的 Remote-SSH 擴充只授權給
官方 VS Code 版本，而 Positron 走 Open VSX）——這個假設是錯的，已查證推翻。**

**Positron 有自己內建的 Remote SSH**（官方文件標示為 experimental），
前端在本機、後端在遠端處理檔案與 Python／R 工作階段，走標準 SSH。但限制是：

- **遠端主機必須是 Linux**（文件舉 Ubuntu 22+／RedHat 9+，x86；
  不支援 arm64，也不支援 Windows／macOS 遠端主機）。
- **明確列為已知缺口：連線到 WSL 後端**，以及 Dev Container 工作流。
- **擴充不會跟著過去**，首次連上遠端時遠端是沒有擴充的。

### 4.3 結論與建議路徑

**HF Spaces 跑的是 Linux，所以理論上 Positron 的 Remote SSH 可以連**——
但 HF Dev Mode 是以 VS Code 為設計目標，**Positron 連 HF Space 這條路我未實測，
不宣稱可行。**

三條路，風險由低到高：

1. **瀏覽器內的 VS Code Web**（HF 自己提供）——不需本機裝任何東西，
   最省事，但需付費方案。
2. **純 SSH 終端**（`ssh.exe` 已有）——`hf spaces ssh`，最輕量，同樣需付費方案。
3. **Positron Remote SSH 連 HF Space**——理論可行，未實測。

> **另有一個與本機 WSL2 計畫直接相關的重點：Positron 的 Remote SSH
> 明確不支援 WSL 後端。** 若先生打算用 Positron 搭 WSL2，這條路目前是堵的；
> Windows 原生的 Positron 與 WSL 要各自獨立使用。

---

## 五、本輪界限

**未做**：未刪除任何檔案（含 OneDrive 內的使用者資料）、未安裝 WSL 發行版、
未安裝任何驅動、未註冊任何 HF 帳戶資料、未改任何系統設定。

**未實測**：Positron Remote SSH 連 HF Space 是否真的可行（需付費方案）；
`vmcompute` 能否按需啟動（需真的裝一個發行版才知道）。

**無法證明**：那 7.62 GB 的 pack 是什麼移除的。
