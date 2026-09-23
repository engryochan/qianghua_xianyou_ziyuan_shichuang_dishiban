#Requires -Version 5.1
# 定义采集参数及边界。
param(
# 定义采集参数及边界。
    [ValidateRange(1,600)][int]$DurationSeconds = 120,
# 定义采集参数及边界。
    [switch]$CompileOnly,
# 定义采集参数及边界。
    [switch]$RecordKeyCodes,
# 定义采集参数及边界。
    [string]$OutDir = "$env:USERPROFILE\Desktop\KbdDiag"
# 执行本地诊断或资源清理，不修改系统配置。
)
# 执行本地诊断或资源清理，不修改系统配置。
$ErrorActionPreference = 'Stop'
# 执行本地诊断或资源清理，不修改系统配置。
$case = Join-Path $OutDir ('rawinput-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fffffff'))
# 执行本地诊断或资源清理，不修改系统配置。
New-Item -ItemType Directory -Path $case -Force | Out-Null

# 执行本地诊断或资源清理，不修改系统配置。
$cs = @'
using System; // 声明或执行键盘诊断逻辑。
using System.IO; // 声明或执行键盘诊断逻辑。
using System.Text; // 声明或执行键盘诊断逻辑。
using System.Runtime.InteropServices; // 声明或执行键盘诊断逻辑。
using System.Windows.Forms; // 声明或执行键盘诊断逻辑。

public static class RawKbd { // 声明或执行键盘诊断逻辑。
    const int  WM_INPUT = 0x00FF; // 声明或执行键盘诊断逻辑。
    const uint RID_INPUT = 0x10000003, RIDI_DEVICENAME = 0x20000007; // 声明或执行键盘诊断逻辑。
    const uint RIM_TYPEKEYBOARD = 1, RIDEV_INPUTSINK = 0x00000100; // 声明或执行键盘诊断逻辑。

    [StructLayout(LayoutKind.Sequential)] struct RAWINPUTDEVICE { public ushort usUsagePage, usUsage; public uint dwFlags; public IntPtr hwndTarget; } // 声明或执行键盘诊断逻辑。
    [StructLayout(LayoutKind.Sequential)] struct RAWINPUTHEADER { public uint dwType, dwSize; public IntPtr hDevice, wParam; } // 声明或执行键盘诊断逻辑。
    [StructLayout(LayoutKind.Sequential)] struct RAWKEYBOARD { public ushort MakeCode, Flags, Reserved, VKey; public uint Message, ExtraInformation; } // 声明或执行键盘诊断逻辑。
    [StructLayout(LayoutKind.Sequential)] struct RAWINPUT { public RAWINPUTHEADER header; public RAWKEYBOARD keyboard; } // 声明或执行键盘诊断逻辑。

    [DllImport("user32.dll", SetLastError=true)] static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] p, uint n, uint cb); // 声明或执行键盘诊断逻辑。
    [DllImport("user32.dll")] static extern uint GetRawInputData(IntPtr h, uint cmd, IntPtr data, ref uint size, uint hdr); // 声明或执行键盘诊断逻辑。
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern uint GetRawInputDeviceInfoW(IntPtr h, uint cmd, IntPtr data, ref uint size); // 声明或执行键盘诊断逻辑。

    static string outPath; static bool recordKeys; static Exception failure; // 声明或执行键盘诊断逻辑。
    class Sink : NativeWindow { // 声明或执行键盘诊断逻辑。
        public Sink() { // 声明或执行键盘诊断逻辑。
            CreateParams cp = new CreateParams(); cp.Parent = (IntPtr)(-3); // HWND_MESSAGE // 声明或执行键盘诊断逻辑。
            CreateHandle(cp); // 声明或执行键盘诊断逻辑。
            RAWINPUTDEVICE[] rid = new RAWINPUTDEVICE[1]; // 声明或执行键盘诊断逻辑。
            rid[0].usUsagePage = 0x01; rid[0].usUsage = 0x06; rid[0].dwFlags = RIDEV_INPUTSINK; rid[0].hwndTarget = this.Handle; // 声明或执行键盘诊断逻辑。
            if (!RegisterRawInputDevices(rid, 1, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE)))) // 声明或执行键盘诊断逻辑。
                throw new Exception("RegisterRawInputDevices failed, err " + Marshal.GetLastWin32Error()); // 声明或执行键盘诊断逻辑。
        } // 声明或执行键盘诊断逻辑。
        protected override void WndProc(ref Message m) { if (m.Msg == WM_INPUT) { try { ReadInput(m.LParam); } catch (Exception ex) { failure = ex; Application.ExitThread(); } } base.WndProc(ref m); } // 声明或执行键盘诊断逻辑。
        void ReadInput(IntPtr hRaw) { // 声明或执行键盘诊断逻辑。
            uint size = 0, hdr = (uint)Marshal.SizeOf(typeof(RAWINPUTHEADER)); // 声明或执行键盘诊断逻辑。
            if (GetRawInputData(hRaw, RID_INPUT, IntPtr.Zero, ref size, hdr) != 0) throw new System.ComponentModel.Win32Exception(); if (size < Marshal.SizeOf(typeof(RAWINPUT))) return; // 声明或执行键盘诊断逻辑。
            IntPtr buf = Marshal.AllocHGlobal((int)size); // 声明或执行键盘诊断逻辑。
            try { // 声明或执行键盘诊断逻辑。
                if (GetRawInputData(hRaw, RID_INPUT, buf, ref size, hdr) != size) return; // 声明或执行键盘诊断逻辑。
                RAWINPUT raw = (RAWINPUT)Marshal.PtrToStructure(buf, typeof(RAWINPUT)); // 声明或执行键盘诊断逻辑。
                if (raw.header.dwType != RIM_TYPEKEYBOARD) return; // 声明或执行键盘诊断逻辑。
                string dev, src; // 声明或执行键盘诊断逻辑。
                if (raw.header.hDevice == IntPtr.Zero) { dev = "(null)"; src = "NO_DEVICE_HANDLE"; } // 声明或执行键盘诊断逻辑。
                else { dev = DevName(raw.header.hDevice); src = "DEVICE_ASSOCIATED"; } // 声明或执行键盘诊断逻辑。
                string ev = ((raw.keyboard.Flags & 0x01) == 0) ? "Down" : "Up"; // 声明或执行键盘诊断逻辑。
                try { File.AppendAllText(outPath, string.Format("{0:o},{1},{2},{3},{4}\r\n", DateTime.Now, ev, src, dev, recordKeys ? raw.keyboard.VKey.ToString() : "-"), Encoding.UTF8); } catch (Exception ex) { failure = ex; Application.ExitThread(); } // 声明或执行键盘诊断逻辑。
            } finally { Marshal.FreeHGlobal(buf); } // 声明或执行键盘诊断逻辑。
        } // 声明或执行键盘诊断逻辑。
        string DevName(IntPtr hDev) { // 声明或执行键盘诊断逻辑。
            uint size = 0; GetRawInputDeviceInfoW(hDev, RIDI_DEVICENAME, IntPtr.Zero, ref size); // 声明或执行键盘诊断逻辑。
            if (size == 0) return "(unknown)"; // 声明或执行键盘诊断逻辑。
            IntPtr p = Marshal.AllocHGlobal((int)(size * 2 + 2)); // 声明或执行键盘诊断逻辑。
            try { // 声明或执行键盘诊断逻辑。
                uint r = GetRawInputDeviceInfoW(hDev, RIDI_DEVICENAME, p, ref size); // 声明或执行键盘诊断逻辑。
                if (r == 0 || r == unchecked((uint)-1)) return "(err)"; // 声明或执行键盘诊断逻辑。
                string s = Marshal.PtrToStringUni(p); return (s == null) ? "(null-str)" : s; // 声明或执行键盘诊断逻辑。
            } finally { Marshal.FreeHGlobal(p); } // 声明或执行键盘诊断逻辑。
        } // 声明或执行键盘诊断逻辑。
    } // 声明或执行键盘诊断逻辑。
    static Sink sink; // 声明或执行键盘诊断逻辑。
    public static void Start(string path, int durationSec, bool includeKeys) { // 声明或执行键盘诊断逻辑。
        outPath = path; recordKeys = includeKeys; failure = null; sink = new Sink(); // 声明或执行键盘诊断逻辑。
        using (var timer = new System.Windows.Forms.Timer()) { // 声明或执行键盘诊断逻辑。
            try { timer.Interval = durationSec * 1000; timer.Tick += delegate { Application.ExitThread(); }; timer.Start(); Application.Run(); } // 声明或执行键盘诊断逻辑。
            finally { timer.Stop(); RAWINPUTDEVICE[] remove = new RAWINPUTDEVICE[1]; remove[0].usUsagePage=1; remove[0].usUsage=6; remove[0].dwFlags=1; RegisterRawInputDevices(remove,1,(uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE))); sink.DestroyHandle(); sink=null; } // 声明或执行键盘诊断逻辑。
        } // 声明或执行键盘诊断逻辑。
        if (failure != null) throw new System.IO.IOException("Raw Input diagnostic failed", failure); // 声明或执行键盘诊断逻辑。
    } // 声明或执行键盘诊断逻辑。
} // 声明或执行键盘诊断逻辑。
'@
# 执行本地诊断或资源清理，不修改系统配置。
# 根据运行时加载WinForms编译引用，兼容Windows PowerShell和PowerShell7。
$refs = @('System.Windows.Forms')
# PowerShell7需要显式引用WinForms拆分程序集及.NET参考程序集。
if ($PSVersionTable.PSEdition -eq 'Core') { $refs = @((Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll').FullName) + @((Join-Path $PSHOME 'System.Windows.Forms.dll'),(Join-Path $PSHOME 'System.Windows.Forms.Primitives.dll')) }
# 仅在本会话未编译时创建原生输入类型。
if (-not ('RawKbd' -as [type])) { Add-Type -TypeDefinition $cs -ReferencedAssemblies $refs -Language CSharp }

# 执行本地诊断或资源清理，不修改系统配置。
if ($CompileOnly) { Write-Output "COMPILE_OK"; return }
# 执行本地诊断或资源清理，不修改系统配置。
$log = Join-Path $case 'raw-device-log.csv'
# 执行本地诊断或资源清理，不修改系统配置。
'Timestamp,Event,Source,Device,VKey' | Out-File $log -Encoding UTF8
# 执行本地诊断或资源清理，不修改系统配置。
Write-Host ("Raw Input 监测 {0} 秒，请复现故障……" -f $DurationSeconds) -ForegroundColor Yellow
# 执行本地诊断或资源清理，不修改系统配置。
[RawKbd]::Start($log, $DurationSeconds, [bool]$RecordKeyCodes)

# 执行本地诊断或资源清理，不修改系统配置。
Write-Host "`n===== 按设备汇总 =====" -ForegroundColor Green
# 执行本地诊断或资源清理，不修改系统配置。
Import-Csv $log | Group-Object Device |
# 执行本地诊断或资源清理，不修改系统配置。
    Select-Object @{N='设备/来源';E={$_.Name}}, @{N='事件数';E={$_.Count}} | Sort-Object 事件数 -Descending | Format-Table -AutoSize
# 执行本地诊断或资源清理，不修改系统配置。
Write-Host ("完整日志：{0}" -f $log) -ForegroundColor Cyan
# 执行本地诊断或资源清理，不修改系统配置。
Write-Host "把带 VID/PID 的设备路径与预检里的 hid-devices.csv 对号入座；(null) 表示未提供设备句柄，不能据此认定软件注入或入侵。" -ForegroundColor Cyan
