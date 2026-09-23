#Requires -Version 5.1
# 执行本地诊断或资源清理，不修改系统配置。
[CmdletBinding()]
# 定义采集参数及边界。
param(
# 定义采集参数及边界。
    [ValidateRange(1,600)][int]$DurationSeconds = 120,
# 定义采集参数及边界。
    [switch]$RecordKeyCodes,                          # 默认只记来源，不记键码；避免沦为内容记录器
# 定义采集参数及边界。
    [switch]$CompileOnly,
# 定义采集参数及边界。
    [string]$OutDir = "$env:USERPROFILE\Desktop\KbdDiag"
# 执行本地诊断或资源清理，不修改系统配置。
)

# 执行本地诊断或资源清理，不修改系统配置。
$ErrorActionPreference = 'Stop'
# 执行本地诊断或资源清理，不修改系统配置。
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fffffff'
# 执行本地诊断或资源清理，不修改系统配置。
$case  = Join-Path $OutDir $stamp
# 执行本地诊断或资源清理，不修改系统配置。
New-Item -ItemType Directory -Path $case -Force | Out-Null

# 执行本地诊断或资源清理，不修改系统配置。
# 独立读取预检项目并记录成功或具体错误。
if (-not $CompileOnly) {
# 独立读取预检项目并记录成功或具体错误。
    $checks = [ordered]@{
# 独立读取预检项目并记录成功或具体错误。
        'hid-devices' = { Get-PnpDevice -PresentOnly -Class Keyboard,HIDClass -ErrorAction Stop | Select-Object Status,Class,FriendlyName,InstanceId,Problem,Manufacturer | Export-Csv (Join-Path $case 'hid-devices.csv') -NoTypeInformation -Encoding UTF8 }
# 独立读取预检项目并记录成功或具体错误。
        'accessibility' = { 'StickyKeys','Keyboard Response','ToggleKeys' | ForEach-Object { Get-ItemProperty "HKCU:\Control Panel\Accessibility\$_" | Out-File (Join-Path $case ("acc-" + ($_ -replace ' ','') + '.txt')) -Encoding UTF8 } }
# 独立读取预检项目并记录成功或具体错误。
        'input-methods' = { Get-WinUserLanguageList | Format-List * | Out-File (Join-Path $case 'input-methods.txt') -Encoding UTF8 }
# 独立读取预检项目并记录成功或具体错误。
        'remote-macro-candidates' = { Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object { $_.Name -match 'teamviewer|anydesk|rustdesk|todesk|sunlogin|splashtop|screenconnect|connectwise|vnc|remoting_host|autohotkey|autoit|powertoys|inputdirector|synergy|barrier' } | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath | Export-Csv (Join-Path $case 'remote-macro-candidates.csv') -NoTypeInformation -Encoding UTF8 }
# 独立读取预检项目并记录成功或具体错误。
    }
# 独立读取预检项目并记录成功或具体错误。
    $status = foreach ($check in $checks.GetEnumerator()) {
# 独立读取预检项目并记录成功或具体错误。
        try { & $check.Value; [pscustomobject]@{Check=$check.Key;Status='OK';Error=$null} }
# 独立读取预检项目并记录成功或具体错误。
        catch { $_ | Out-String | Set-Content (Join-Path $case ($check.Key + '-error.txt')) -Encoding UTF8; Write-Warning $_; [pscustomobject]@{Check=$check.Key;Status='Unavailable';Error=$_.Exception.Message} }
# 独立读取预检项目并记录成功或具体错误。
    }
# 独立读取预检项目并记录成功或具体错误。
    $status | ConvertTo-Json | Set-Content (Join-Path $case 'preflight-status.json') -Encoding UTF8
# 独立读取预检项目并记录成功或具体错误。
}
# 编译低级键盘事件诊断类型。
$cs = @'
using System; // 声明或执行键盘诊断逻辑。
using System.IO; // 声明或执行键盘诊断逻辑。
using System.Text; // 声明或执行键盘诊断逻辑。
using System.Runtime.InteropServices; // 声明或执行键盘诊断逻辑。
using System.Collections.Concurrent; // 声明或执行键盘诊断逻辑。
using System.Threading; // 声明或执行键盘诊断逻辑。

public static class LLKbd { // 声明或执行键盘诊断逻辑。
    const int  WH_KEYBOARD_LL = 13; // 声明或执行键盘诊断逻辑。
    const int  WM_KEYDOWN = 0x0100, WM_SYSKEYDOWN = 0x0104; // 声明或执行键盘诊断逻辑。
    const uint LLKHF_INJECTED = 0x10, LLKHF_LOWER_IL_INJECTED = 0x02, WM_QUIT = 0x0012; // 声明或执行键盘诊断逻辑。

    [StructLayout(LayoutKind.Sequential)] // 声明或执行键盘诊断逻辑。
    struct KBDLLHOOKSTRUCT { public uint vkCode, scanCode, flags, time; public IntPtr dwExtraInfo; } // 声明或执行键盘诊断逻辑。
    [StructLayout(LayoutKind.Sequential)] // 声明或执行键盘诊断逻辑。
    struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam, lParam; public uint time; public int x, y; } // 声明或执行键盘诊断逻辑。

    delegate IntPtr HookProc(int nCode, IntPtr w, IntPtr l); // 声明或执行键盘诊断逻辑。
    [DllImport("user32.dll", SetLastError=true)] static extern IntPtr SetWindowsHookEx(int id, HookProc fn, IntPtr mod, uint tid); // 声明或执行键盘诊断逻辑。
    [DllImport("user32.dll")] static extern bool   UnhookWindowsHookEx(IntPtr h); // 声明或执行键盘诊断逻辑。
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int n, IntPtr w, IntPtr l); // 声明或执行键盘诊断逻辑。
    [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string n); // 声明或执行键盘诊断逻辑。
    [DllImport("kernel32.dll")] static extern uint  GetCurrentThreadId(); // 声明或执行键盘诊断逻辑。
    [DllImport("user32.dll")] static extern int    GetMessage(out MSG m, IntPtr h, uint a, uint b); // 声明或执行键盘诊断逻辑。
    [DllImport("user32.dll")] static extern bool   PostThreadMessage(uint tid, uint msg, IntPtr w, IntPtr l); // 声明或执行键盘诊断逻辑。

    static IntPtr hookId = IntPtr.Zero; // 声明或执行键盘诊断逻辑。
    static HookProc proc; // 声明或执行键盘诊断逻辑。
    static ConcurrentQueue<string> q = new ConcurrentQueue<string>(); // 声明或执行键盘诊断逻辑。
    static string outPath; static bool recVk; static readonly object writeLock = new object(); static Exception writeError; // 声明或执行键盘诊断逻辑。
    public static long CountPhysical = 0, CountInjected = 0, CountInjectedLowIL = 0; // 声明或执行键盘诊断逻辑。

    static IntPtr CB(int nCode, IntPtr w, IntPtr l) { // 声明或执行键盘诊断逻辑。
        if (nCode >= 0) { // 声明或执行键盘诊断逻辑。
            KBDLLHOOKSTRUCT kb = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(l, typeof(KBDLLHOOKSTRUCT)); // 声明或执行键盘诊断逻辑。
            int wm = w.ToInt32(); // 声明或执行键盘诊断逻辑。
            string ev  = (wm == WM_KEYDOWN || wm == WM_SYSKEYDOWN) ? "Down" : "Up"; // 声明或执行键盘诊断逻辑。
            bool inj = (kb.flags & LLKHF_INJECTED) != 0; // 声明或执行键盘诊断逻辑。
            bool low = (kb.flags & LLKHF_LOWER_IL_INJECTED) != 0; // 声明或执行键盘诊断逻辑。
            string src = inj ? (low ? "INJECTED_LOWIL" : "INJECTED") : "NOT_FLAGGED_INJECTED"; // 声明或执行键盘诊断逻辑。
            if (inj) { Interlocked.Increment(ref CountInjected); if (low) Interlocked.Increment(ref CountInjectedLowIL); } // 声明或执行键盘诊断逻辑。
            else Interlocked.Increment(ref CountPhysical); // 声明或执行键盘诊断逻辑。
            string vk = recVk ? kb.vkCode.ToString() : "-"; // 声明或执行键盘诊断逻辑。
            string sc = recVk ? kb.scanCode.ToString() : "-"; // 声明或执行键盘诊断逻辑。
            q.Enqueue(string.Format("{0:o},{1},{2},{3},{4},0x{5:X}", DateTime.Now, ev, src, vk, sc, kb.flags)); // 声明或执行键盘诊断逻辑。
        } // 声明或执行键盘诊断逻辑。
        return CallNextHookEx(hookId, nCode, w, l); // 声明或执行键盘诊断逻辑。
    } // 声明或执行键盘诊断逻辑。
    static void Flush() { // 声明或执行键盘诊断逻辑。
        lock (writeLock) { StringBuilder sb = new StringBuilder(); string ln; // 声明或执行键盘诊断逻辑。
        while (q.TryDequeue(out ln)) sb.AppendLine(ln); // 声明或执行键盘诊断逻辑。
        if (sb.Length > 0) { try { File.AppendAllText(outPath, sb.ToString(), Encoding.UTF8); } catch (Exception ex) { writeError = ex; } } } // 声明或执行键盘诊断逻辑。
    } // 声明或执行键盘诊断逻辑。
    public static void Start(string path, bool includeVk, int durationSec) { // 声明或执行键盘诊断逻辑。
        CountPhysical = CountInjected = CountInjectedLowIL = 0; writeError = null; q = new ConcurrentQueue<string>(); outPath = path; recVk = includeVk; proc = CB; // 声明或执行键盘诊断逻辑。
        hookId = SetWindowsHookEx(WH_KEYBOARD_LL, proc, GetModuleHandle(null), 0); // 声明或执行键盘诊断逻辑。
        if (hookId == IntPtr.Zero) throw new Exception("SetWindowsHookEx failed, err " + Marshal.GetLastWin32Error()); // 声明或执行键盘诊断逻辑。
        uint tid = GetCurrentThreadId(); // 声明或执行键盘诊断逻辑。
        Timer quit  = (durationSec > 0) // 声明或执行键盘诊断逻辑。
            ? new Timer(delegate { PostThreadMessage(tid, WM_QUIT, IntPtr.Zero, IntPtr.Zero); }, null, durationSec*1000, Timeout.Infinite) // 声明或执行键盘诊断逻辑。
            : null; // 声明或执行键盘诊断逻辑。
        Timer flush = new Timer(delegate { Flush(); }, null, 500, 500); // 声明或执行键盘诊断逻辑。
        try { MSG m; int result; while ((result = GetMessage(out m, IntPtr.Zero, 0, 0)) > 0) { } if (result < 0) throw new System.ComponentModel.Win32Exception(); } // 声明或执行键盘诊断逻辑。
        finally { if (quit != null) quit.Dispose(); using (var done = new ManualResetEvent(false)) { flush.Dispose(done); done.WaitOne(); } UnhookWindowsHookEx(hookId); hookId = IntPtr.Zero; Flush(); } // 声明或执行键盘诊断逻辑。
        if (writeError != null) throw new IOException("Failed to write keyboard diagnostic log", writeError); // 声明或执行键盘诊断逻辑。
    } // 声明或执行键盘诊断逻辑。
} // 声明或执行键盘诊断逻辑。
'@
# 执行本地诊断或资源清理，不修改系统配置。
if (-not ('LLKbd' -as [type])) { Add-Type -TypeDefinition $cs -Language CSharp }

# 执行本地诊断或资源清理，不修改系统配置。
if ($CompileOnly) { Write-Output "COMPILE_OK"; return }
# 执行本地诊断或资源清理，不修改系统配置。
$log = Join-Path $case 'key-source-log.csv'
# 执行本地诊断或资源清理，不修改系统配置。
'Timestamp,Event,Source,VKey,ScanCode,Flags' | Out-File $log -Encoding UTF8

# 执行本地诊断或资源清理，不修改系统配置。
Write-Host ("开始监测 {0} 秒。请在记事本里复现故障，切勿在密码框操作。" -f $DurationSeconds) -ForegroundColor Yellow
# 执行本地诊断或资源清理，不修改系统配置。
[LLKbd]::Start($log, [bool]$RecordKeyCodes, $DurationSeconds)

# ---------- 收尾统计 ----------
# 执行本地诊断或资源清理，不修改系统配置。
$phys = [LLKbd]::CountPhysical; $inj = [LLKbd]::CountInjected; $low = [LLKbd]::CountInjectedLowIL
# 执行本地诊断或资源清理，不修改系统配置。
Write-Host "`n===== 结果 =====" -ForegroundColor Green
# 执行本地诊断或资源清理，不修改系统配置。
Write-Host ("未标记注入事件     : {0}" -f $phys)
# 执行本地诊断或资源清理，不修改系统配置。
Write-Host ("注入按键 INJECTED     : {0}（其中来自更低完整性级别 {1}）" -f $inj, $low)
# 执行本地诊断或资源清理，不修改系统配置。
if ($inj -gt 0) {
# 执行本地诊断或资源清理，不修改系统配置。
    Write-Host "检测到注入事件。分时段分布（每秒计数）：" -ForegroundColor Yellow
# 执行本地诊断或资源清理，不修改系统配置。
    Import-Csv $log | Where-Object { $_.Source -like 'INJECTED*' } |
# 执行本地诊断或资源清理，不修改系统配置。
        Group-Object { ([datetime]$_.Timestamp).ToString('HH:mm:ss') } |
# 执行本地诊断或资源清理，不修改系统配置。
        Sort-Object Name | Select-Object @{N='时刻';E={$_.Name}}, @{N='注入次数';E={$_.Count}} | Format-Table -AutoSize
# 执行本地诊断或资源清理，不修改系统配置。
    Write-Host "提醒：屏幕键盘 / AutoHotkey / 部分输入法本身就产生 INJECTED，候选进程清单为空也不能排除其他来源；注入标志不能识别操作者或证明入侵。" -ForegroundColor Yellow
# 执行本地诊断或资源清理，不修改系统配置。
} else {
# 执行本地诊断或资源清理，不修改系统配置。
    Write-Host "监测窗口内无软件注入按键。" -ForegroundColor Green
# 执行本地诊断或资源清理，不修改系统配置。
}
# 执行本地诊断或资源清理，不修改系统配置。
Write-Host ("完整日志：{0}" -f $log) -ForegroundColor Cyan
