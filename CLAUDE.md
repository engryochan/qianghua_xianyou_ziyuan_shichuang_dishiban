# 專案說明（給接手的人與 AI）

## 2026-10-10 Windows 11 升級後實測（目前狀態）

本機為 MiniPC T1 / Intel H610I / i5-12400（6 核心、12 執行緒）/ 約 32 GB RAM / Intel UHD Graphics 730。已確認升級至 Windows 11 專業版 26H2，26300.9457，系統已啟用。SSD 回報 Healthy；4 個在位設備仍為錯誤碼 28（INTC1070、7AA3、INTC1056、7AA4），且有 CBS 待重啟標記。

指定 WIM 與 ISO 已刪除，合計約 14.61 GiB。完整設備、驅動、軟體、防護、事件與診斷界限：[升級後診斷](reports/2026-10-10/Windows11升級後診斷.md)。以下較早記錄為歷史內容，舊華碩 / NVIDIA GT 730 資訊不能套用本機；Python 環境復原以 CLAUDE.md 的 2026-10-06 更正為準。

### 2026-10-11 提權複驗（**優先於本檔以下全部**）

先生以管理員跑了 `診斷操作系統/Elevated_Pending_Tasks.ps1`。證據
`reports/2026-10-11/elevated-run/`，判讀見報告「提權複驗」一節。
**本輪把所有「需提權才能確認」的項目結案，並查出升級失敗調查三次都缺的資料。**

**最重要的一條：`fltmc` 需要提權，所以前三次升級失敗調查從來拿不到篩選器清單。**
非提權下它只回 `0x80070005 Access is denied`（對照證物已存
`elevated-run/non-elevated-contrast/`）。**凡是結論寫著「沒有確定是哪一個驅動」的，
先確認那是真的查不出來，還是你根本沒權限查。**

拿到清單後的發現：**亿赛通 CDG 在本機有三個檔案系統篩選驅動，不是一個**
（先前只盤點到它的 `CDGRegedit` 登錄檔元件）：

| 驅動 | 高度 | Start | 群組 | 模型 |
|---|---|---|---|---|
| Estdlock | **586333（全機最高，在 Defender 328010 與 Kaspersky 320400 之上）** | 1 | Activity Monitor | minifilter |
| FLMonDrv | 370030 | 2 | Activity Monitor | minifilter |
| **Filelock**（SmartSec 7.4.5） | 149998.99 | **0（Boot）** | **Encryption** | **傳統篩選器** |

**`Filelock` 是升級 hive 失敗的最佳候選解釋。** `fltmc` 把它標為 `<过时>`，
且它**沒有 `Instances` 子機碼**——兩項獨立證據確認它不是 minifilter，而是
前 FltMgr 時代的傳統篩選驅動。它同時具備開機啟動 + 傳統模型 + 透明加密 +
2021 年 Win7 DDK 二進位，全部落在「setup 掛載離線 hive」這條路徑上；而失敗碼
Win32 `87` 正是「檔案開得起來但內容不被登錄檔接受」的典型回應（`elam` 是合法
`regf` 且一般使用者可讀，已排除損壞與權限）。**這是假設不是證明**，證實需停用
該驅動再升級一次——違反資安規範，**不做**。已出單：
`reports/2026-10-11/IT請求_篩選驅動堆疊與升級hive失敗_20261011.md`。

**判讀紀律（踩過）：驅動的簽章者不等於開發者。** `LdMFilter` 的簽章者是
`Microsoft Windows Hardware Compatibility Publisher`，那只代表它過了 WHQL
認證簽署；它的 ProductName 是未改的 `Windows (R) Win 7 DDK driver` 預設字串，
憑證查不出真實廠商。判它為天锐绿盾是靠檔名 `Ld` 前綴與既知路徑一致，**屬推定**。

**四項原本「未驗證」全部結案：**

- **BitLocker 權威確認未啟用**：`manage-bde -status C:` → 版本「无」、完全解密、
  已加密 0.0%、保護關閉、找不到密鑰保護器。先前的旁證推定正確。
- **TPM 2.0 就緒，且是 Intel PTT 韌體 TPM**（`ManufacturerIdTxt = INTC`，
  SpecVersion 2.0, 0, 1.38，Owned/Ready 全 True）。**先前只知「TPM 2.0」，
  分不出韌體或離散晶片**——韌體 TPM 的設定在 UEFI 裡。
  另記 `RestartPending = True`，**那是 TPM 子系統自身狀態，與 OS 層那三個已清除的
  待重啟旗標是兩回事，不要混記。**
- **安全啟動 `Confirm-SecureBootUEFI = False`**，與非提權讀到的
  `UEFISecureBootEnabled = 0` 互相印證。
- **WinRE Enabled**，在 `partition3\Recovery\WindowsRE`（住在 `C:` 內，
  **這解釋了為何磁碟 0 沒有獨立修復分割區**），版本 10.0.26100.9545
  落後 OS 的 26300.9550。

**`vmcompute` 查明了，而且不必修。** 所有 Hyper-V 與 Containers 功能皆
`Disabled`，只有 `Microsoft-Windows-Subsystem-Linux` 與 `VirtualMachinePlatform`
是 `Enabled`，且**無一卡在 `EnablePending`**。`Hyper-V-Compute-Admin` 與
`-Operational` **完全沒有事件**，而 `Hypervisor-Admin` 每次開機正常初始化——
**服務在寫出第一條日誌前就死了**。`hypervisorlaunchtype = Auto`，BCD 無問題。
結論是「半配置」：WSL2 開著、Hyper-V 關著，而 HCS 橫跨兩邊。
**不宣稱已證明因果**，但本機 WSL 無任何發行版，**功能影響為零，建議什麼都不做**。

**`powershell -File` 吃得下中文絕對路徑**（先生實測）。先生第一次失敗是因為
**我給了相對路徑**，而提權視窗的工作目錄是 `C:\WINDOWS\system32`。
**所以本檔「Rscript 吃中文絕對路徑會亂碼」那條不能外推到 `powershell.exe`。**

**仍未取得（收斂，不是結案）**：登錄檔篩選回呼清單（`CDGRegedit` 等）需核心
除錯器，不在使用者端腳本能力內。原先那句「需管理員列舉 `fltmc filters`
**與登錄檔回呼**」，前半做完了，後半沒做。

### 2026-10-11 重啟後複驗（優先於以下兩段，**但次於上段提權複驗**）

已於 10-11 06:51:52 正常重啟。詳見報告「重啟後複驗」各節。

**重啟修好的：** 三項待重啟旗標全部清除；UBR **26300.9457 → 26300.9550**（KB5121794 + KB5124010 於 06:52:07 套用）。天锐绿盾 `LeaderTerm` 的 7030 互動式服務警告、以及 `Microsoft Defender Core` 啟動失敗，本次開機都未再出現。本次開機無任何非 SCM 的系統層級錯誤。

**重啟修不好的——Kaspersky，而且定位更銳利了：**

| 時間 | 事件 |
|---|---|
| 06:52:03 | `AVP.KES.14.1` 逾時 45,000 ms 啟動失敗（7000 + 7009） |
| 06:54:11 | `Kaspersky Endpoint Security 服务 (KES.14.1)` 逾時 30,000 ms 啟動失敗 |

**累計兩個開機週期四次失敗，已是可重現的穩定狀態，不是升級後暫態。**

以登錄檔列舉確認 **19 個 Kaspersky 服務／驅動項全部在冊**、`.sys` 全在磁碟：`KLIF`／`klflt`／`klhk`／`klwtp`／`kneps`／`klpnpflt` 等核心與檔案系統篩選驅動皆 `Start=1`（系統啟動），`klim6` 實測 Running（`klelam` Stopped 屬 ELAM 開機後卸載的正常設計）。**只有 Type=16 的使用者模式服務 `AVP.KES.14.1` 逾時。** `avp.exe` 存在（21.3.10.1001）；`klupd_*` 定義檔 10-08 還在更新（`avpsus` 在跑）；**Kaspersky 自有事件記錄 `RecordCount = 0`**，產品從未啟動到能寫一條日誌。

> **所以問題不在驅動簽署或載入期相容性，而在產品本體於本 OS 組建上的使用者模式初始化卡死（>45 秒）。** 這比「服務起不來」對 IT 有用得多。
>
> **一處自我更正**：我一度以為驅動在重啟時被移除——那是查詢寫法造成的誤判（真實服務名帶 `.KES-14-1` 後綴，且 `Get-Service` 不可靠列出核心驅動）。改用登錄檔列舉後證實驅動完整無缺。

三層防護中**目前只有 Kaspersky 一層實質未運作**；亿赛通 CDG 與天锐绿盾行程皆齊，Defender 持續接手（簽章 10-11 00:34:06）。

**仍失敗：** `vmcompute`（Hyper-V 主机计算服务）兩度逾時——與 VBS 在跑但無安全服務執行相關，容器／WSL2 類功能會受影響，目前工作流程不依賴它。`edgeupdate` 找不到檔案（殘留）。

**重啟本來就不會改變的三類，複驗一致：** 四個錯誤碼 28 設備完全未變（需驅動）、安全啟動仍 `0`（需韌體設定）、HVCI 仍未啟用（需策略）。設備統計仍 OK 128 / Error 4 / Unknown 1。

`C:` 可用 52.51 GB；`Windows.old` 仍在（刻意保留）；`D:\` 仍不存在。

**堆疊重啟後再驗一次，仍 `REGRESSION FAILURES: 0`**（Python 15/15、R 10/10、5×ALL PASS、5×OK、flair NER PASS、CmdStan PASS、Quarto Output created、`kernels bad: 0`）。CmdStan 的輸出與 10-10 **逐字一致**（`mu 3.5128` / `sigma 1.1557` / `rhat 1.0032`），正好證明那支驗收是確定性的。**升級與重啟兩道關卡都沒動到 `C:\work`——這是「一切放 `C:\work`、不放 AppData」的第二次獨立驗證。**

**目前唯一的開放阻塞項是 Kaspersky**，已備可直接交 IT 的單子：`reports/2026-10-11/IT請求_Kaspersky主服務在Win11_26H2啟動逾時.md`。

#### 驅動更新：**「一律交給 Windows Update 更新」在這台機器上是錯的**

詳見 `reports/2026-10-11/驅動更新評估與待定清單.md`。

**WU 總共只提供一個驅動，而它是沒有價值的平移**：

| | 版本 | 日期 | 供應商 |
|---|---|---|---|
| 已安裝 | **9.1.412.2015** | 2015-03-31 | **Microsoft 內建** |
| WU 提供 | 9.1.409.2015 | 2015-04-09 | Realtek |

版本號 412 > 409，但 WU 的日期較新——**Windows 的驅動排序先比日期再比版本**，所以 WU 才認為自己那份較新並提供它。兩者都是 2015 年的驅動，換過去版本號反而退了。**而 WU 完全沒有那四個錯誤碼 28 設備的驅動。**

逐項判定：

| 驅動 | 已安裝 | 判定 |
|---|---|---|
| Intel UHD Graphics 730 / Graphics Software | 32.0.101.7088 | **已是最新**（Intel 官方頁面，列示日期 2026-06-22） |
| **Realtek PCIe GbE（唯一在用的網路連線）** | **9.1.412.2015（2015）** | **落後數世代**；第三方彙整指向 10.79.x/10.80.x（2026），但**無法從原廠直接確認版號** |
| 4 × Intel 晶片組設備 | 無驅動 | `pnputil /scan-devices` 重掃**仍 4 個 Error**；確定需板卡廠／Intel 平台包 |

> **Realtek 那一項建議交 IT**：它是目前唯一在用的連線（`以太网 2` Up 1 Gbps，WLAN 為 Disconnected），換驅動期間會斷線，不相容則可能完全失去連線，而這是受管理的公司資產。硬體 ID 為 `PCI\VEN_10EC&DEV_8168&SUBSYS_012310EC&REV_2B`，取得順序應為「整機／板卡廠 OEM 包 → Realtek 通用包」。

**另查到一條過時策略（未修改，屬 IT 範圍）**：

```
HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate
    TargetReleaseVersion = 1 / TargetReleaseVersionInfo = 22H2
    TargetReleaseProductVersion = Windows 10
```

機器已是 Windows 11 26H2，這條仍釘在 Win10 22H2，狀態矛盾，會影響日後功能更新投放。

#### 需管理員的事項已做成一支腳本

`診斷操作系統/Elevated_Pending_Tasks.ps1`（**含 BOM，必須保留**；已過語法檢查並在非提權下完整試跑）。

- **A 段全唯讀**：`manage-bde -status`、`Get-Tpm`、`Confirm-SecureBootUEFI`、`reagentc /info`、**`fltmc filters`／`instances`**（三次升級失敗時 `RegLoadKeyW` 回傳 87，當時就是缺這份清單）、`Dism /CheckHealth`、`driverquery /v`
- **B 段預設只列出與掃描**，`-InstallDrivers` 加 `-DriverPackagePath` 才會安裝自備驅動包。**刻意不自動安裝 WU 那個 2015 年的驅動。**

腳本開頭明寫它不做的事：不碰網管／資安 IP 設定、不碰網段帳號與設備、不啟停或重裝任何資安軟體、不改 Windows Update 策略。

#### `vmcompute` 根因：已排除三項，目前無功能影響

- **不是升級留下舊版執行檔。** `System32\vmcompute.exe` 的 `VersionInfo.FileVersion` 寫著 `10.0.19041.4522`（Win10 基底），看起來正是「系統跳了元件沒跳」。但它與 WinSxS 的 `26100.9549` 份**SHA256 相同（`AEAFAC80…9388`）、大小相同、`fsutil hardlink list` 確認互為硬連結，是同一個檔案**；而 `FileVersionRaw` 是 **`10.0.26100.9549`**。
  > **`VersionInfo.FileVersion` 是自由文字資源，可以與真實版本欄位不一致**（這裡來自 `vmcompute.exe.mui`）。判版本要用 `FileVersionRaw`，更可靠的是雜湊與硬連結身分。**只看 `FileVersion` 字串會得出「檔案是舊的」這個錯誤結論——我就先得出過。**
- **不是依賴失敗**：`rpcss` / `wcifs` / `condrv` / `hvsocketcontrol` 全部 Running。
- **不是 hypervisor 未載入**：`HypervisorPresent = True`、VBS 狀態 2。
  （`VirtualizationFirmwareEnabled = False` **不代表韌體虛擬化未啟用**——hypervisor 既已執行就接管了 VT-x，該欄位自然是 False。）
- **請求者是 `WSLService`**（Running/Automatic，`wsl.exe` 存在；無 `vmms`／Sandbox，即只裝了 WSL2／容器那一組）。實測 `wsl --version` 為 **3.0.1.0**、預設 WSL2，但**「适用于 Linux 的 Windows 子系统没有已安装的分发」**。
  **所以目前沒有功能影響；一旦裝了發行版就會卡住 WSL2。**
  > `wsl.exe` 的輸出是 **UTF-16LE**，用單位元組編碼讀會得到字元間夾空白的亂碼，要用 `[System.Text.Encoding]::Unicode` 解碼。

#### 四個缺驅動設備：本機完全沒有 INF 宣告

除「WU 沒有」與「`pnputil /scan-devices` 重掃仍 4 個 Error」之外，再加驗一項：掃 `C:\Windows\INF` 與 `DriverStore\FileRepository`，搜 `DEV_7AA3`／`DEV_7AA4`／`INTC1070`／`INTC1056`，**四個 ID 零宣告**。所以**沒有任何本機手段可補，必須外部廠商包**。候選為 Intel 下載 ID 19347（Chipset Device Software），但**該包是否涵蓋 `7AA3` 無法從公開資料確認**，取得順序仍應整機／板卡廠 OEM 包優先。

### 14:10 複檢增補（優先於上段）

同日第二輪複檢，證據 `reports/2026-10-10/recheck-1410/recheck.json`，詳述見上列報告的「增補複檢」各節。

**要先處理的一件事：Kaspersky 主服務在本 OS 上起不來。**

| 項目 | 狀態 |
|---|---|
| `AVP.KES.14.1` | **Stopped**，啟動類型 Automatic；`avp.exe` / `avpui.exe` 未執行 |
| 事件日誌 | 13:14:56 與 13:17:00 各一次 **7009 + 7000**，逾時 45,000 / 30,000 ms 後啟動失敗 |
| 仍在跑的 | `avpsus`、`klnagent`（IT 控制台看得到本機）、`klim6` |
| Defender | **已接手**：即時防護／行為監控／防篡改皆 True，引擎 1.1.26080.3 |

**本機並非無防護，但公司配發的 Kaspersky 實質未運作。** 這印證了 2026-10-06 對升級失敗的既有假設——**KES 14.1.0.423 與這個 OS 組建不相容**。請 IT 由 Security Center 處置並核對版本支援清單；**不要自行啟停或變更它**。

另有 `LeaderTerm` / `LeaderTermDaemon`（天锐绿盾）被標為互動式服務而系統不允許，事件 7030 明寫「这项服务可能无法正常操作」——**第二層 DLP 也可能未正常運作**。`Hyper-V 主机计算服务` 與 `Microsoft Defender Core 服务` 亦各自逾時啟動失敗。

**上段三項「未驗證」中，兩項已結案：**

- **安全啟動 = 未啟用。** `Confirm-SecureBootUEFI` 需提權，但 `HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\State\UEFISecureBootEnabled = 0` **非提權即可讀**。開機方式為 UEFI（磁碟 0 為 GPT + EFI System 分割區）。
- **TPM = 存在且正常，TPM 2.0。** `Win32_Tpm` 仍需提權，但設備層已確認：`受信任的平台模块 2.0`、`ACPI\MSFT0101\1`、Status OK、ErrorCode 0、`TPM` 服務 Running。僅 SpecVersion 等細項仍未驗證。
- **BitLocker 仍未權威確認**（`Get-BitLockerVolume` 需提權）。旁證一致指向未啟用：`BDESVC` Stopped、僅 `C:` 且為純 NTFS、`bitlocker.json` 僅 6 bytes。權威確認需 `manage-bde -status C:`。

**連帶的資安落差**：VBS 本身在跑（`VirtualizationBasedSecurityStatus = 2`），但 `SecurityServicesRunning = {0}` 且 HVCI 機碼不存在 → **記憶體完整性未啟用**，而硬體能力具備。與安全啟動關閉相呼應。

**`D:\` 不存在，也沒有任何功能。** 全機只有一顆 `HAILAN 256G`（238.47 GB、GPT、SATA、Healthy），**未配置空間 0**，有代號的卷只有 `C:`，且**無光碟機**。先前的 `F:` 是手動掛載的 Win11 ISO，該 ISO 已刪，`F:` 也不存在了。要生成 `D:` 只能縮 `C:`（可用僅約 55 GB，其中 40 GB 是 `Windows.old`）或加裝第二顆磁碟。

**`C:\Windows.old` 占 40.29 GB（409,445 檔）**，是目前最大可回收項，但**它是回到 Windows 10 的唯一回滾路徑**。本機失敗三次才升級成功，故刻意不刪；Windows 約 10 天後（約 2026-10-20）自動清除。確認不需回滾再用 `cleanmgr` 處理，**不要手動刪該目錄**。

**待重啟旗標已擴大**：CBS `RebootPending` 仍 True，Windows Update `RebootRequired` **由 false 變 True**，而 `LastBootUpTime` 仍是 13:14:37——**升級後尚未重啟過**。上述服務逾時失敗都在這唯一一次開機之後，**一次正常重啟是應優先做的下一步**，重啟後再複驗。

**四個錯誤碼 28 設備全屬 Intel 晶片組側**，由硬體自報的 class code 可判功能：`DEV_7AA3` 為 `CC_0C0500`（SMBus 控制器）、`DEV_7AA4` 為 `CC_0C8000`（序列匯流排／其他）、`INTC1070` 與 `INTC1056` 為 Intel 平台 ACPI 設備且無 CompatibleIds。四者皆 `VEN_8086` / `VEN_INTC`，**應由同一套 Intel 平台／晶片組驅動覆蓋**，不是四個獨立來源。全機設備：OK 128 / Error 4 / Unknown 1。

**資料分析堆疊完整存活：`Run_Full_Regression.ps1` 八節 0 失敗**（Python 15/15、R 10/10、五衛星、flair NER、CmdStan 編譯擬合、Quarto render、六 kernel）。**上次升級摧毀的是 `%APPDATA%\uv\python`；這次全部資產都在 `C:\work`，一件未失——那個架構決定得到了驗證。**


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

  目前 `C:\work\jupyter\kernels` 下有六個，核心加五個衛星：`ds`、`fin`、`mlops`、`nlp`、`rl`、`xai`。重建用 `診斷操作系統/Register_Kernels_And_Runtime.ps1`。

  **`jupyter kernelspec list` 只列舉目錄，不解析 `kernel.json`。** 一份 JSON 壞掉的 kernel 它照樣列出來，看起來一切正常。實際踩過：用字串拼接產生 `kernel.json` 時 Windows 路徑的反斜線少轉義一層，寫出 `"argv": ["C:\work\envs\fin\..."]`，`json.load` 拋 `Invalid \escape`，而 `kernelspec list` 六個全列、毫無異狀。

  所以 kernel.json 一律用 `ConvertTo-Json` 產生（它會正確轉義路徑），而且驗收要**真的 `json.load` 一次**並確認 `argv[0]` 指到存在的解譯器——見 `診斷操作系統/Accept_Jupyter_Kernels.py`。

### 三之二、兩個 IDE 也在 `C:\work`，但啟動捷徑不能放開始選單

| 項目 | 版本 | 位置 |
|---|---|---|
| Positron | 裝入時 2026.09.1 build 2（Code OSS 1.130.0）；**它會自動更新**，2026-10-10 已自行升到 2026.10.0 | `C:\work\Positron`（官方 `UserSetup`，`/SILENT /DIR=`） |
| RStudio | 2026.09.0+174 | `C:\work\RStudio`（官方 **ZIP** 解壓，免安裝器） |

**開始選單在 `%APPDATA%` 底下，所以我建的捷徑會被 MSIX 容器吃掉**——實測確認
Positron 安裝器建的選單項與我手建的 RStudio 捷徑都只存在於
`…\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\…`，真實桌面看不到。
程式本體在 `C:\work` 不受影響，被困住的只有捷徑。

所以捷徑放 **`C:\work\Launch\{Positron,RStudio}.lnk`**（已驗證不被重導）。
要進開始選單請在**自己的終端**執行：

```powershell
Copy-Item 'C:\work\Launch\*.lnk' "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\" -Force
```

接線方式同理：**Positron 的設定寫工作區**
`C:\work\projects\lab\.vscode\settings.json`，不要寫 `%APPDATA%\Positron\User\`。
RStudio 靠 `HKCU\SOFTWARE\R-core\R64`（`/CURRENTUSER` 安裝寫 HKCU，不是 HKLM）自動
找到 R，另已明確釘 `RSTUDIO_WHICH_R`。

**兩者都通過像素級算繪驗證**（`Win11_App_RealTest.ps1`，七種渲染旗標全部
`Rendered=True`；Positron 內容區亮度 ~244.4、RStudio ~247）。與 Comet 不同，
預設啟動即正常，不需任何旗標或白名單。

### 三之三、本機顯卡是 Intel UHD Graphics 730，**沒有 NVIDIA 卡**

```
Intel(R) UHD Graphics 730
PCI\VEN_8086&DEV_4692&SUBSYS_22128086&REV_0C
驅動 32.0.101.7088（2026-06-17）
```

下文所有關於 NVIDIA GT 730 / `10DE:0F02` / Fermi / 472.xx 的段落，都是**舊機**
（華碩原機）的紀錄。**「UHD Graphics 730」與「GT 730」名字極像但完全無關**，
一個是 Intel 內顯、一個是 NVIDIA 獨顯。

`Win11_App_RealTest.ps1` 原本**無條件**印出「本机 10DE:0F02 为旧型 Fermi」，
而那份報告是要交給 IT 的——等於叫 IT 去查一張不存在的顯卡。
已改為在產生報告時實讀所有適配器，不再寫死任何型號。

### 三之四、大型壓縮檔不要用 `Expand-Archive`

解 735 MB 的 RStudio ZIP，`Expand-Archive` **近半小時未完成**並隨工作階段中斷
死掉，留下半成品（381 檔 / 0.53 GB，主程式還沒出來）。改用 Windows 內建 bsdtar：

```powershell
tar -xf 'C:\work\dl\RStudio-2026.09.0-174.zip' -C 'C:\work\RStudio'
```

**34.9 秒**完成，4,931 檔 / 2.1 GB。`C:\Windows\System32\tar.exe` 自 Win10 1803
內建且認得 zip。

### 四、驗收用的新腳本

| 檔案 | 用途 |
|---|---|
| `診斷操作系統/Accept_Python_Stack.py` | Python 15 項真實計算驗收 |
| `診斷操作系統/Accept_R_Stack.R` | R 10 項，含 `arrow` 缺席守衛與 duckdb→reticulate→pyarrow |
| `診斷操作系統/Accept_Satellites.py` | 衛星環境匯入與約束守衛 |
| `診斷操作系統/Accept_Satellites_Domain.py` | 衛星環境領域計算驗收（需網路的標 SKIP，不混進 PASS） |
| `診斷操作系統/Accept_CmdStan.R` | 編譯並擬合真實 Stan 模型，檢查參數回收與 rhat |
| `診斷操作系統/Accept_Flair_NER.py` | flair 實跑 NER（會下載模型到 `~\.flair`） |
| `診斷操作系統/Accept_Jupyter_Kernels.py` | 真的 `json.load` 每份 kernel.json 並探測其解譯器 |
| `診斷操作系統/Register_Kernels_And_Runtime.ps1` | 重建六個 kernel 與 OpenMP `.pth`（冪等） |
| `診斷操作系統/Run_Full_Regression.ps1` | **一次跑完 8 節全套回歸**（含 BOM，必須保留） |
| `診斷操作系統/Reconcile_PythonLock.py` | 鎖版檔矛盾的可稽核迭代鬆綁器 |
| `診斷操作系統/Build_Satellite_Envs.ps1` | 重建五個衛星環境 |
| `診斷操作系統/Install_R_Stack_v2.R` | R 堆疊逐一安裝（不用 pak） |
| `診斷操作系統/Install_CmdStan.R` | 從 Stan r-universe 裝 cmdstanr 並編譯 CmdStan |
| `診斷操作系統/Start_Analytics_v2.ps1` | 工作階段入口（＝`C:\work\Start_Analytics.ps1`），`-WithToolchain` 開啟編譯鏈 |

### 四之二、編譯鏈（Rtools45 + CmdStan，皆使用者層級）

| 項目 | 位置 |
|---|---|
| Rtools45 | `C:\work\rtools45`（`/CURRENTUSER /MERGETASKS=!addtopath`，**沒有**污染 PATH） |
| gcc | `C:\work\rtools45\x86_64-w64-mingw32.static.posix\bin\gcc.exe`（14.3.0） |
| make | `C:\work\rtools45\usr\bin\make.exe` |
| CmdStan | `C:\work\cmdstan\cmdstan-2.40.0`（cmdstanr 0.9.0，來自 Stan r-universe，不在 CRAN） |

要編譯時用 `Start_Analytics_v2.ps1 -WithToolchain`；平時**不要**開，因為
`usr\bin` 會蓋掉 Windows 內建的 `sh` / `find` / `sort`。詳細機制見本檔
「幾個容易誤判的事實」裡的 Rtools 更正。

### 五、本輪新增的其他地雷

- **缺 `vcomp140.dll`**（Microsoft OpenMP 執行期）。本機有 `vcruntime140` / `msvcp140` / `concrt140`，就是沒有 OpenMP，也查無任何 VC++ Redistributable 安裝紀錄。任何連結 OpenMP 的 wheel 會報 `Could not find module <dll> (or one of its dependencies)`——**那個 DLL 明明在**，缺的是它的依賴。

  **Python 3.8 以後，Windows 的 DLL 搜尋不再看 `PATH`**（改用 `LOAD_LIBRARY_SEARCH_DEFAULT_DIRS`），只找 DLL 自身目錄、`System32`、以及 `os.add_dll_directory()` 註冊的目錄。所以「把 DLL 放某處再加進 PATH」**沒有用**，這點已實測否證。

  現行做法：`C:\work\runtime\vcomp140.dll`（取自環境內 `sklearn\.libs`），六個環境的 `site-packages` 各放一份 `zz_work_runtime_dlls.pth`：

  ```python
  import os; os.path.isdir(r"C:\work\runtime") and os.add_dll_directory(r"C:\work\runtime")
  ```

  `isdir()` 守衛不可省——`.pth` 每次解譯器啟動都執行，對不存在的路徑呼叫 `add_dll_directory` 會拋例外並弄壞整個環境。

  **根本解仍是請 IT 裝 VC++ Redistributable**（進 `System32` 就不需要任何環境層補丁）。
- **`lightgbm==4.5.0` 配不了新版 scikit-learn**：sklearn 把 `force_all_finite` 改名 `ensure_all_finite` 並移除舊名，lightgbm 4.5.0 還在呼叫舊名 → `TypeError`。依賴求解器看不到，**只有真的 fit 一次才會知道**。用 `lightgbm>=4.6.0`。
- **BOM 的方向在兩種檔案上剛好相反，兩邊都踩過：**

  | 檔案 | BOM | 踩到的症狀 |
  |---|---|---|
  | 資料檔（`kernel.json` 等） | **不可有** | `Set-Content -Encoding utf8` 會寫 BOM，`json.load` 直接拋 `Unexpected UTF-8 BOM` |
  | **含非 ASCII 的 `.ps1`** | **必須有** | 沒有 BOM 時 PS 5.1 當 ANSI(GBK) 解碼，腳本裡的 `診斷操作系統` 變成 `瑷烘柗鎿嶄綔绯荤当`，路徑全失效 |

  寫資料檔：`[System.IO.File]::WriteAllText($p, $s, (New-Object System.Text.UTF8Encoding($false)))`
  寫 `.ps1`：同一行但用 `UTF8Encoding($true)`。

  **後者的症狀特別會騙人**：我用 Bash heredoc 寫了一支回歸測試腳本（無 BOM），跑出「14 個失敗、而且完全沒有輸出」。看起來像整個環境崩了，其實腳本連檔案都沒找到。改成有 BOM 後同一支腳本是 **0 失敗**。
  **凡是「全部都失敗」又「沒有任何輸出」，先懷疑你的 runner，不要懷疑被測物。**
- **PowerShell 5.1 沒有三元運算子**：`(if(…){…}else{…})` 放在運算式位置會丟 `The term 'if' is not recognized`。
- **本環境的 Bash heredoc 會把 `\\` 塌成 `\`，即使寫成 `<<'EOF'`。** 這是本輪三次反斜線錯誤的共同真因，而三次的症狀完全不同、都很難看出來：

  | 現場 | 實際寫出 | 症狀 |
  |---|---|---|
  | `kernel.json` 的 `argv[0]` | `"C:\work\envs\fin\..."` | `json.load` 拋 `Invalid \escape`，而 `kernelspec list` 照樣列出 |
  | `Start_Analytics.ps1` 的 gcc 路徑 | `C:\worktools45聠_64-...in\gcc.exe` | 路徑變亂碼（`\t`→tab、`\x`→hex、`\b`→退格） |
  | `Win11_App_RealTest.ps1` 的 `-split '\'` | 單一反斜線 | `-split` 吃 **regex**，孤立 `\` 是不完整轉義，切不開，欄位**靜默變空** |

  對策：產生 JSON 用 `ConvertTo-Json`；切字串用 `.Split([char]0x5C)` 而非 `-split` 配反斜線；heredoc 內需要反斜線時用 `chr(92)` 組出；**最重要的是產生完就真的解析／執行一次**——這三個錯誤沒有一個能靠讀程式碼發現。
- **`uv pip freeze` 的提示訊息會汙染鎖版檔**：用 PowerShell 管線收集會把 `Using Python … environment at: …` 一起寫進去，拿去安裝得到 `Couldn't parse requirement … at position 0`。用 `2>$null` 並過濾。**我在同一輪裡先交付了一份這樣的壞鎖版檔，只有真的拿它建第二個環境時才發現。**
- **Store 版 `python` 代理殼**（`…\WindowsApps\python.exe`）在非互動工作階段會無回應地吊死。一律用絕對解譯器路徑。
- **R 的 `tempdir()` 不等於 Python 的 `tempfile.gettempdir()`**：R 回每個工作階段的 `…\Temp\RtmpXXXX`，Python 回父目錄。`templates/r-python-template.qmd` 早就用 `r.pq` 橋解掉了——**動既有檔案之前先讀它**，不要重新發明倉庫已解的問題。

### 六、Windows 11 升級（**已於 2026-10-10 成功，本節轉為歷史**）

> **狀態更新：升級已完成**，現為 Windows 11 專業版 26H2 / 26300.9457。
> 本節保留的是失敗那三次的診斷過程，仍有參考價值——**其中對 Kaspersky KES 14.1
> 與本 OS 組建不相容的推測，在升級後得到印證**（主服務逾時起不來，見本檔開頭
> 「14:10 複檢增補」）。下文的「下一步先試」與 IT 請求已無須執行。

三次嘗試、兩種來源映像（安裝助理 ESD 26200 / 官網 ISO 26300，SHA256 已核對），失敗簽名完全相同：Pre-Finalize、`0x80070057 - 0x50015`。換映像不影響結果。

**確定的機制**：`RegLoadKeyW` 對所有離線 hive 回傳 Win32 `87`（NewOS `SOFTWARE`、SafeOS `SYSTEM`、本機 `elam`）。`elam` 本身是合法 `regf`、32,768 bytes、一般使用者讀得到，所以不是損壞或權限問題。

本機同時常駐 Kaspersky KES 14.1.0.423（含開機 ELAM `klelam.sys`）、**亿赛通 Cobra DocGuard**（含 `CDGRegedit` 登錄檔元件）、**天锐绿盾 Tipray**。~~**沒有確定是哪一個驅動**，需管理員列舉 `fltmc filters` 與登錄檔回呼。~~ **2026-10-11 提權後已收斂**：`fltmc` 列出來了，候選縮到**亿赛通的 `Filelock`**（開機啟動的傳統加密篩選器，SmartSec 7.4.5），見本檔開頭「提權複驗」。登錄檔回呼那半句仍未做（需核心除錯器）。

**下一步先試**（前三次都沒用過，失敗點正是 Dynamic Update 的 SSU 注入）：

```powershell
F:\setup.exe /auto upgrade /DynamicUpdate disable /eula accept
```

細節與 IT 交接單：`reports/2026-10-06/Win11升級第三次失敗_根因與IT請求_20261006.md`。

#### 2026-10-10 補：相容性掃描結論乾淨，阻擋項只有 hive 那一個

10-10 跑了兩次 `setup.exe /auto upgrade /compat scanonly /noreboot`（11:20 與 11:30）。
**這是掃描模式，本來就不升級**，所以系統仍是 19045.7725 不是失敗；
`setuperr.log` 裡的 `0x800705BB` / `CheckUserInterrupt` 就是 scanonly 的正常收尾。
**`/DynamicUpdate disable` 至今仍未試過。**

`ScanResult.xml` 的結論：

- 硬體檢查全部 `BlockingType="None"`（BitLocker、Secure Boot、授權、語言包、FoD、flight signing、non-staged build）
- `<Devices/>` 與 `<Programs/>` 皆空；`diagwrn.xml` / `diagerr.xml` 無任何非 None 的 BlockingType、無硬阻擋標記
- 唯一被標記的是 `oem0.inf` / `oem1.inf`（`BlockMigration="True"`、未簽署）——實查為 **Microsoft Print To PDF** 與 **Microsoft XPS Document Writer v4**，Windows 自家內建虛擬印表機。這是常見無害產物（新系統會自行重建），**不是**升級阻擋項

**所以相容性層面沒有障礙，唯一真正的阻擋仍是 Pre-Finalize 的 hive 載入失敗。**

> **陷阱：`HKLM\SYSTEM\Setup\SetupDiag\Results` 不是原子性的，它會混不同次執行。**
> 10-10 查到的內容是 `ProfileName=CompatScanOnly` + `UpgradeStartTime 10/10 11:30`，
> 卻同時帶著 `FailureDetails = 0x80070057 … SafeOS.Mount`、`LastSetupPhase=Pre-Finalize`、
> 而那兩個時間戳是 **10/06**——是上一次失敗升級的殘留欄位。
> 只讀這個機碼會以為「相容性掃描死在 hive bug」。
> **要信同時間寫出的 `C:\Windows\logs\SetupDiag\SetupDiagResults.xml`**，
> 它的 `<FailureDetails />` 是空的。

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
| `診斷操作系統/Elevated_Pending_Tasks.ps1` | **需管理員才查得到的項目**（`manage-bde`、`Get-Tpm`、`Confirm-SecureBootUEFI`、`reagentc`、**`fltmc filters` / `instances`**、`Dism /CheckHealth`、Hyper-V 事件與選用功能、`bcdedit`）。**含 BOM，必須保留。** A 段全唯讀；B 段僅在明確加 `-InstallDrivers` 並提供存在的 `-DriverPackagePath` 時才安裝自備驅動包 |
| `env/python-ds-core.in` | **重建核心環境的依據**（698 個 `==` + 28 個 `>=`，已實測可建成） |
| `env/python-ds-verified.lock.txt` | 重建後 freeze 的 728 行實況，已通過 15/15 驗收 |
| `env/python-ds-requirements.lock.txt` | ~~重建環境的唯一依據~~ **這份本身無解，不要用**。只留作歷史證物，見本檔開頭 2026-10-06 更正第一節 |

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

