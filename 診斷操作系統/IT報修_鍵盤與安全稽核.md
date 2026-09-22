# IT 報修單：鍵盤異常與安全稽核

- **機器**：ASUS PRIME H610M-R D4 / i5-12400F / Windows 11 Pro 26200 25H2
- **電腦名**：SHJ-H0647-RYOCH
- **使用者**：PPCCpcpc
- **稽核時間**：2026-09-22
- **稽核方式**：本機唯讀量測，未停用任何管控軟體，未刪除任何檔案

## 一、申報症狀

使用者回報鍵盤異常，並曾看見藍底畫面。

**症狀尚未取得精確描述**——使用者的說法是「幾乎所有鍵盤輸入都被不明人士入侵」，這是判斷而非可觀察現象。下列稽核在症狀未定義的前提下進行，涵蓋硬體、驅動、掛鉤、帳戶、網路、日誌六個面向。

## 二、先排除的兩個誤判

### 1. 那個藍底畫面不是藍屏（BSOD）

| 檢查項 | 結果 |
|---|---|
| `C:\Windows\MEMORY.DMP` | **不存在** |
| `C:\Windows\Minidump` | **空** |
| System 日誌 Event 41（Kernel-Power 意外關機） | **無** |
| 今日三次重開機 07:47 / 08:45 / 14:19 | 全部記錄為 `last shutdown's success status was **true**` |
| 14:16:25 的關機發起者 | `StartMenuExperienceHost`（使用者從開始選單操作） |

畫面內容「選擇一個選項／繼續／疑難排解／關閉電腦」是 **Windows 恢復環境（WinRE）進階啟動選單**。按住 Shift 點「重新啟動」即會進入，屬正常行為。

### 2. 鍵盤硬體與驅動正常

| 檢查項 | 結果 |
|---|---|
| 裝置 | `HID\VID_1A2C&PID_6004&MI_00`（有線 USB 複合裝置） |
| 驅動 | `keyboard.inf`，Microsoft 內建，v10.0.26100.8972 |
| Problem Code | **0** |
| 連接路徑 | HID → USB Input Device → USB Composite → **USB Root Hub (USB 3.0)** → Intel USB 3.20 控制器 → 主機板 |
| KVM／擴充座／USB Hub | **無**，直插主機板 |
| 藍牙硬體 | **本機完全沒有藍牙裝置** |
| 驅動層按鍵重映射 `Scancode Map` | **不存在** |
| 黏滯鍵 / 篩選鍵 / 切換鍵 | Flags = 510 / 126 / 62 → bit0 皆為 0，**全部關閉**（開啟應為 511 / 127） |

### 本機 USB 完整歷史（登錄檔 `Enum\USB`，比 DriverFrameworks 日誌可靠）

```
ROOT_HUB30           USB Root Hub (USB 3.0)
VID_1A2C&PID_6004    鍵盤（複合裝置 MI_00 + MI_01）   ×2 個連接埠
VID_10C4&PID_0005    滑鼠                            ×2 個連接埠
```

**此機自安裝以來只枚舉過這兩個 USB 裝置。** 無隨身碟、無未知 HID、無 BadUSB 類裝置。
（註：`Microsoft-Windows-DriverFrameworks-UserMode/Operational` 日誌在本機為 **停用**狀態，Windows 11 預設如此，故改用登錄檔列舉。）

## 三、確實在攔截鍵盤的三套軟體，全部為公司部署

| 元件 | 廠商 | 簽章 | 角色 |
|---|---|---|---|
| `klfltdev.KES-14-1` | Kaspersky Endpoint Security | Valid | 掛載於**鍵盤類 UpperFilters**：`kbdclass, klfltdev.KES-14-1` |
| `HookDll` / `HookDll64` | 北京億賽通科技發展有限責任公司 | Valid | 注入各行程的掛鉤模組 |
| `LdTerm` / `LdTermDaemon` | 廈門天銳（Tipray） | Valid | 第三套 DLP 終端 |

億賽通另有 5 個核心驅動執行中，**全部簽章有效**：`Estdlock`、`Filelock`、`FLMonDrv`、`maillock`、`NSFFileCtl`。

**非 Microsoft 的執行中核心驅動共 5 個，全部屬億賽通，簽章全部 Valid。無任何未簽章核心驅動。**

## 四、排除入侵的證據

| 檢查項 | 結果 |
|---|---|
| 遠端控制軟體（ToDesk／AnyDesk／TeamViewer／RustDesk／向日葵／VNC／Splashtop 等） | **無行程、無服務** |
| 遠端桌面 | **已停用**（`fDenyTSConnections = 1`）；3389／5900／5938 無監聽 |
| 登入工作階段 | **僅一個**：`ppccpcpc`，console，2026-09-22 14:19 登入 |
| 本機帳戶 | 僅 `PPCCpcpc` 啟用；Administrator／Guest／DefaultAccount／WDAGUtilityAccount 全部停用 |
| 系統管理員群組 | 僅 Administrator 與 PPCCpcpc，**無多餘帳戶** |
| 服務執行於使用者可寫入路徑（AppData／Temp／Downloads／腳本主機） | **無** |
| 開機自啟項 | 7 條，全部可歸屬：Snipaste、Firefox、Chrome、Edge、OneDrive、CometUpdater、SecurityHealth |
| 未簽章的執行中行程 | 僅 `browser-use`、`head`（本次診斷所用的 Git／工具鏈） |
| Defender | AMRunningMode=Normal、即時保護**開啟**、行為監控**開啟**、簽章 1.459.332.0 |
| Security 日誌 4688（行程建立稽核） | **預設未啟用**，故無法回溯過往行程 |

### 網路連線

外連全部可歸屬：Chrome／ChatGPT／Claude／Codex／svchost 走 443；本機迴路為 ASUS 自家服務（ROGLiveService、ArmouryCrate、asus_framework）與本次診斷的 python。

**一條內網連線值得記錄**：

```
192.168.103.32:1028  ->  192.168.7.17:20081   LdTermDaemon
```

天銳綠盾終端正在向公司內網伺服器回報，屬預期行為。

## 五、三項需要 IT 判斷的發現

### 發現 1：ChatGPT／Codex 桌面應用曾以 LocalSystem 權限建立服務讀取瀏覽器設定檔

```
2026-09-21 08:52:15  OwlBrowserProfileImport-5f2a7153-...
2026-09-21 08:53:06  OwlBrowserProfileImport-9cc585a1-...

映像路徑：
"C:\Program Files\WindowsApps\OpenAI.Codex_26.915.4065.0_x64__2p2nqsd0c76g0\app\ChatGPT.exe"
  --owl-browser-profile-import-system-service="\\.\pipe\owl-browser-profile-import-..."

服務帳戶：LocalSystem
啟動類型：按需啟動
目前狀態：服務已不存在（一次性，用後自行移除）
```

這是使用者自行安裝的 OpenAI 官方應用（簽章 Valid），用途是匯入瀏覽器設定檔。**但它以 SYSTEM 權限存取瀏覽器設定檔，在受管控的公司資產上可能與資安政策衝突**，請 IT 判斷是否允許。

### 發現 2：ASUS `IOMap64.sys` 每次開機重新安裝，30 天內 9 次

```
服務名：IOMap        檔案：C:\WINDOWS\system32\drivers\IOMap64.sys
簽章：Valid，ASUSTeK COMPUTER INC.     檔案日期：2026-09-20
目前：state=Running，start=Disabled（組合異常）
安裝時間點：09-20 15:48、15:54 / 09-21 07:54、09:20、16:23、18:05 / 09-22 07:48、08:45、14:19
```

此驅動隨 Armoury Crate／ROG Live Service 提供 ring-0 硬體存取。ASUS IOMap／AsIO 系列屬於業界已知的 **BYOVD（自帶易受攻擊驅動）** 風險類別。簽章有效、來源正當，但**它是本機目前最大的核心層攻擊面**。若不使用 Armoury Crate 的燈效與風扇控制，建議評估移除。

### 發現 3：Kaspersky 鍵盤過濾驅動於 2026-09-21 07:56 重新安裝

```
2026-09-21 07:54  IOMap
2026-09-21 07:56  Kaspersky KLFltDev.KES-14-1        <- 鍵盤類過濾驅動
2026-09-21 07:56  Kaspersky Anti-Virus NDIS 6 Filter
2026-09-21 07:56  klpsm
```

**若鍵盤異常始於 2026-09-21 上午，這是時間上最吻合的單一事件。** 此驅動位於鍵盤輸入鏈路上，屬公司管控，使用者無權停用，需 IT 協助驗證。

（附註：2026-09-20 15:28 有大批 7045 事件，那是 Windows 11 就地升級重新註冊既有服務所致，非異常。）

## 六、一項與鍵盤直接相關的設定缺陷

```
語言清單：
  [0] zh-Hans-CN  中文        InputMethodTip: 0804:{81D4E9C9-...}{FA550B04-...}
  [1] ja          日本語      InputMethodTips: (空 —— 未掛載任何輸入法)

鍵盤配置表 HKCU\Keyboard Layout\Preload：
  1 -> 00000804   Chinese (Simplified) - US Keyboard

Win32_Keyboard.Layout: 00000804
```

語言清單有 **2** 個語言，配置表只有 **1** 個。日文項目**既無輸入法、亦無鍵盤配置**。`Win+空白鍵` 切換至該項目時會進入未定義狀態，可導致字元錯位、吞字或按鍵無反應。

**建議修正**（使用者層級，無需管理員）：設定 → 時間與語言 → 語言和地區 → 「日本語」→ `…` → 移除；若確需日文輸入，改為補上 Microsoft IME。

## 七、本次稽核查不到的範圍

- **硬體鍵盤側錄器**（插於鍵盤與主機之間的實體裝置）——需目視檢查
- **韌體／BIOS 層植入**——需 IT 取證
- **2026-09-21 之前的行程建立記錄**——Security 4688 稽核預設未啟用，無法回溯
- **DriverFrameworks USB 插拔日誌**——本機停用，已改用登錄檔列舉替代

## 八、請 IT 協助的事項

1. 驗證 `klfltdev.KES-14-1`（2026-09-21 07:56 安裝）是否為鍵盤異常來源，必要時於管理主控台調整安全鍵盤輸入設定。
2. 裁決 OpenAI Codex／ChatGPT 應用以 LocalSystem 匯入瀏覽器設定檔的行為是否符合資安政策。
3. 評估 ASUS `IOMap64.sys` 的留存必要性（BYOVD 風險類別，每次開機重裝）。
4. 若使用者仍懷疑遭入侵，安排端點取證；**在此之前請勿重灌，以免破壞證據**。

## 九、給使用者的即時建議

- 在確認之前，**不要在本機輸入密碼、銀行資訊或私人憑據**。無論是否遭入侵，三套 DLP 依設計即會記錄輸入，這是公司資產的既定前提。
- 目視檢查鍵盤線與主機介面之間是否有多餘的小型轉接頭。
- **請勿停用任何一套管控代理**，亦不要自行移除——違反資安規範且多半已被策略鎖定。
