# UAC 選用功能截圖核驗

2026-10-10，根據使用者提供的截圖與唯讀本機查詢。

截圖顯示「設定」在選用功能頁面要求 UAC 提升權限，已驗證發行者 Microsoft Windows，CLSID {B247D87F-C30D-4075-A324-3BB02C917EE9}。

本機 HKCR 對應 CLSID 名稱為 Optional Features Admin Helper；InProcServer32 指向 C:\Windows\System32\SettingsHandlers_OptionalFeatures.dll，Elevation Enabled=1。該 DLL Authenticode Status=Valid，簽署者 Microsoft Windows。截圖與本機官方元件一致；靜態圖片無法證明當時實際程序或其後的操作。

按「是」授權這次元件提升權限；不等於開啟所有選用功能。按「否」取消此次提升。截圖未列出待安裝或移除功能，不能判斷後續會變更哪個功能。

UAC 本機設定：EnableLUA=1、ConsentPromptBehaviorAdmin=5、ConsentPromptBehaviorUser=3、PromptOnSecureDesktop=0。安全桌面未啟用，建議由管理者評估恢復預設的安全桌面提示；本次不修改策略。管理員群組在目前權杖為 deny-only，因此帳戶具管理員群組成員資格，但目前診斷程序未提升；前次 metadata IsAdministrator=false 僅表示當時程序沒有有效管理員權杖，不能推定帳戶不是管理員。

DISM /Online /Get-Features /Format:Table 唯讀查詢回報 740（需要提升權限），未取得完整功能清單。WSL 實測預設版本 2，但沒有安裝的 Linux 發行版。WslService Running；vmcompute Stopped（Manual）；先前採集有主機計算服務啟動超時。停止狀態本身不能證明服務故障，但既有超時事件值得在需要 WSL2/容器時複驗。

功能與可能影響（條件性，不表示本機均已啟用）：語言/OCR/手寫能力影響相應輸入與辨識；OpenSSH 影響 ssh/scp 及遠端服務；.NET Framework 3.5 影響指定舊式程式；WSL/Virtual Machine Platform/Hyper-V 影響 Linux、虛擬機與使用其後端的容器；媒體元件影響依賴 Windows 媒體 API 的程式；列印/XPS 影響對應文件輸出。這些跨越「選用功能」與「更多 Windows 功能」兩套管理入口，不能把全部項目視為截圖這次準備操作的項目。

單純核准本次 UAC 不會使 R、Python、Positron、RStudio、Office 或瀏覽器全部變更；實際影響取決於之後增刪的元件及程式依賴。沒有需求不必全選安裝；保留 UAC，按具體用途選功能，避免盲目啟用 SSH Server、IIS 等服務。

證據：optional-helper-signature.json、uac-policy.json、optional-package-evidence.json（後者僅登錄套件旁證，不作為已啟用狀態判定）、本次命令輸出及 recent-system-errors.json。未核准 UAC，未增刪功能，未修改防護或網路。

官方資料：[UAC 運作與安全桌面](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/user-account-control/how-it-works)、[增刪 Windows 功能](https://learn.microsoft.com/en-us/windows/client-management/client-tools/add-remove-hide-features)。
