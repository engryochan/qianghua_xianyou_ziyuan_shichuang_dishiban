#Requires -Version 5.1
[CmdletBinding()]
param(
    [int]$DurationSeconds = 120,
    [switch]$RecordKeyCodes,                          # 默认只记来源，不记键码；避免沦为内容记录器
    [string]$OutDir = "$env:USERPROFILE\Desktop\KbdDiag"
)

$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$case  = Join-Path $OutDir $stamp
New-Item -ItemType Directory -Path $case -Force | Out-Null

# ---------- 只读预检：不改任何系统设置 ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
          ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
Write-Host ("管理员权限：{0}（钩子不需要；读安全日志才需要）" -f $isAdmin) -ForegroundColor Cyan
Write-Host ("CapsLock 当前：{0}" -f [Console]::CapsLock) -ForegroundColor Cyan

# 键盘 / HID 设备清单——看是否多于一把键盘
Get-PnpDevice -Class Keyboard,HIDClass -ErrorAction SilentlyContinue |
    Select-Object Status, Class, FriendlyName, InstanceId, Problem, Manufacturer |
    Export-Csv (Join-Path $case 'hid-devices.csv') -NoTypeInformation -Encoding UTF8

# 无障碍键（粘滞/筛选/切换）——最常见的“假故障”来源
'StickyKeys','Keyboard Response','ToggleKeys' | ForEach-Object {
    $p = "HKCU:\Control Panel\Accessibility\$_"
    if (Test-Path $p) {
        Get-ItemProperty $p | Out-File (Join-Path $case ("acc-" + ($_ -replace ' ','') + ".txt")) -Encoding UTF8
    }
}

# 输入法
Get-WinUserLanguageList | Format-List * | Out-File (Join-Path $case 'input-methods.txt') -Encoding UTF8

# 远控 / 宏 候选（含 Chrome Remote Desktop 真实进程名 remoting_host）
$cand = 'teamviewer','anydesk','rustdesk','todesk','sunlogin','splashtop',
        'screenconnect','connectwise','vnc','winvnc','remoting_host',
        'autohotkey','autoit','powertoys','inputdirector','synergy','barrier'
Get-CimInstance Win32_Process |
    Where-Object {
        $t = "$($_.Name) $($_.ExecutablePath) $($_.CommandLine)".ToLower()
        $cand | Where-Object { $t -like "*$_*" }
    } |
    Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine |
    Export-Csv (Join-Path $case 'remote-macro-candidates.csv') -NoTypeInformation -Encoding UTF8
Write-Host "预检完成，已写入：$case" -ForegroundColor Cyan

# ---------- 低级键盘钩子：逐事件判定 实体 / 注入 ----------
$cs = @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using System.Collections.Concurrent;
using System.Threading;

public static class LLKbd {
    const int  WH_KEYBOARD_LL = 13;
    const int  WM_KEYDOWN = 0x0100, WM_SYSKEYDOWN = 0x0104;
    const uint LLKHF_INJECTED = 0x10, LLKHF_LOWER_IL_INJECTED = 0x02, WM_QUIT = 0x0012;

    [StructLayout(LayoutKind.Sequential)]
    struct KBDLLHOOKSTRUCT { public uint vkCode, scanCode, flags, time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam, lParam; public uint time; public int x, y; }

    delegate IntPtr HookProc(int nCode, IntPtr w, IntPtr l);
    [DllImport("user32.dll", SetLastError=true)] static extern IntPtr SetWindowsHookEx(int id, HookProc fn, IntPtr mod, uint tid);
    [DllImport("user32.dll")] static extern bool   UnhookWindowsHookEx(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int n, IntPtr w, IntPtr l);
    [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string n);
    [DllImport("kernel32.dll")] static extern uint  GetCurrentThreadId();
    [DllImport("user32.dll")] static extern int    GetMessage(out MSG m, IntPtr h, uint a, uint b);
    [DllImport("user32.dll")] static extern bool   PostThreadMessage(uint tid, uint msg, IntPtr w, IntPtr l);

    static IntPtr hookId = IntPtr.Zero;
    static HookProc proc;
    static ConcurrentQueue<string> q = new ConcurrentQueue<string>();
    static string outPath; static bool recVk;
    public static long CountPhysical = 0, CountInjected = 0, CountInjectedLowIL = 0;

    static IntPtr CB(int nCode, IntPtr w, IntPtr l) {
        if (nCode >= 0) {
            KBDLLHOOKSTRUCT kb = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(l, typeof(KBDLLHOOKSTRUCT));
            int wm = w.ToInt32();
            string ev  = (wm == WM_KEYDOWN || wm == WM_SYSKEYDOWN) ? "Down" : "Up";
            bool inj = (kb.flags & LLKHF_INJECTED) != 0;
            bool low = (kb.flags & LLKHF_LOWER_IL_INJECTED) != 0;
            string src = inj ? (low ? "INJECTED_LOWIL" : "INJECTED") : "PHYSICAL";
            if (inj) { Interlocked.Increment(ref CountInjected); if (low) Interlocked.Increment(ref CountInjectedLowIL); }
            else Interlocked.Increment(ref CountPhysical);
            string vk = recVk ? kb.vkCode.ToString() : "-";
            string sc = recVk ? kb.scanCode.ToString() : "-";
            q.Enqueue(string.Format("{0:o},{1},{2},{3},{4},0x{5:X}", DateTime.Now, ev, src, vk, sc, kb.flags));
        }
        return CallNextHookEx(hookId, nCode, w, l);
    }
    static void Flush() {
        StringBuilder sb = new StringBuilder(); string ln;
        while (q.TryDequeue(out ln)) sb.AppendLine(ln);
        if (sb.Length > 0) { try { File.AppendAllText(outPath, sb.ToString(), Encoding.UTF8); } catch {} }
    }
    public static void Start(string path, bool includeVk, int durationSec) {
        outPath = path; recVk = includeVk; proc = CB;
        hookId = SetWindowsHookEx(WH_KEYBOARD_LL, proc, GetModuleHandle(null), 0);
        if (hookId == IntPtr.Zero) throw new Exception("SetWindowsHookEx failed, err " + Marshal.GetLastWin32Error());
        uint tid = GetCurrentThreadId();
        Timer quit  = (durationSec > 0)
            ? new Timer(delegate { PostThreadMessage(tid, WM_QUIT, IntPtr.Zero, IntPtr.Zero); }, null, durationSec*1000, Timeout.Infinite)
            : null;
        Timer flush = new Timer(delegate { Flush(); }, null, 500, 500);
        MSG m; while (GetMessage(out m, IntPtr.Zero, 0, 0) > 0) { }
        if (quit != null) quit.Dispose(); flush.Dispose();
        UnhookWindowsHookEx(hookId); Flush();
    }
}
'@
if (-not ('LLKbd' -as [type])) { Add-Type -TypeDefinition $cs -Language CSharp }

$log = Join-Path $case 'key-source-log.csv'
'Timestamp,Event,Source,VKey,ScanCode,Flags' | Out-File $log -Encoding UTF8

Write-Host ("开始监测 {0} 秒。请在记事本里复现故障，切勿在密码框操作。" -f $DurationSeconds) -ForegroundColor Yellow
[LLKbd]::Start($log, [bool]$RecordKeyCodes, $DurationSeconds)

# ---------- 收尾统计 ----------
$phys = [LLKbd]::CountPhysical; $inj = [LLKbd]::CountInjected; $low = [LLKbd]::CountInjectedLowIL
Write-Host "`n===== 结果 =====" -ForegroundColor Green
Write-Host ("实体按键 PHYSICAL     : {0}" -f $phys)
Write-Host ("注入按键 INJECTED     : {0}（其中来自更低完整性级别 {1}）" -f $inj, $low)
if ($inj -gt 0) {
    Write-Host "检测到注入事件。分时段分布（每秒计数）：" -ForegroundColor Yellow
    Import-Csv $log | Where-Object { $_.Source -like 'INJECTED*' } |
        Group-Object { ([datetime]$_.Timestamp).ToString('HH:mm:ss') } |
        Sort-Object Name | Select-Object @{N='时刻';E={$_.Name}}, @{N='注入次数';E={$_.Count}} | Format-Table -AutoSize
    Write-Host "提醒：屏幕键盘 / AutoHotkey / 部分输入法本身就产生 INJECTED，先确认 remote-macro-candidates.csv 为空再判读。" -ForegroundColor Yellow
} else {
    Write-Host "监测窗口内无软件注入按键。" -ForegroundColor Green
}
Write-Host ("完整日志：{0}" -f $log) -ForegroundColor Cyan
