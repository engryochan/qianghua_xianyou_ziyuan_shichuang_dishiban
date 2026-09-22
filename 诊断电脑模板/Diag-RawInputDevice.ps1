#Requires -Version 5.1
param(
    [int]$DurationSeconds = 120,
    [string]$OutDir = "$env:USERPROFILE\Desktop\KbdDiag"
)
$case = Join-Path $OutDir ('rawinput-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $case -Force | Out-Null

$cs = @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class RawKbd {
    const int  WM_INPUT = 0x00FF;
    const uint RID_INPUT = 0x10000003, RIDI_DEVICENAME = 0x20000007;
    const uint RIM_TYPEKEYBOARD = 1, RIDEV_INPUTSINK = 0x00000100;

    [StructLayout(LayoutKind.Sequential)] struct RAWINPUTDEVICE { public ushort usUsagePage, usUsage; public uint dwFlags; public IntPtr hwndTarget; }
    [StructLayout(LayoutKind.Sequential)] struct RAWINPUTHEADER { public uint dwType, dwSize; public IntPtr hDevice, wParam; }
    [StructLayout(LayoutKind.Sequential)] struct RAWKEYBOARD { public ushort MakeCode, Flags, Reserved, VKey; public uint Message, ExtraInformation; }
    [StructLayout(LayoutKind.Sequential)] struct RAWINPUT { public RAWINPUTHEADER header; public RAWKEYBOARD keyboard; }

    [DllImport("user32.dll", SetLastError=true)] static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] p, uint n, uint cb);
    [DllImport("user32.dll")] static extern uint GetRawInputData(IntPtr h, uint cmd, IntPtr data, ref uint size, uint hdr);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern uint GetRawInputDeviceInfoW(IntPtr h, uint cmd, IntPtr data, ref uint size);

    static string outPath;
    class Sink : NativeWindow {
        public Sink() {
            CreateParams cp = new CreateParams(); cp.Parent = (IntPtr)(-3); // HWND_MESSAGE
            CreateHandle(cp);
            RAWINPUTDEVICE[] rid = new RAWINPUTDEVICE[1];
            rid[0].usUsagePage = 0x01; rid[0].usUsage = 0x06; rid[0].dwFlags = RIDEV_INPUTSINK; rid[0].hwndTarget = this.Handle;
            if (!RegisterRawInputDevices(rid, 1, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE))))
                throw new Exception("RegisterRawInputDevices failed, err " + Marshal.GetLastWin32Error());
        }
        protected override void WndProc(ref Message m) { if (m.Msg == WM_INPUT) Handle(m.LParam); base.WndProc(ref m); }
        void Handle(IntPtr hRaw) {
            uint size = 0, hdr = (uint)Marshal.SizeOf(typeof(RAWINPUTHEADER));
            if (GetRawInputData(hRaw, RID_INPUT, IntPtr.Zero, ref size, hdr) != 0) return;
            IntPtr buf = Marshal.AllocHGlobal((int)size);
            try {
                if (GetRawInputData(hRaw, RID_INPUT, buf, ref size, hdr) != size) return;
                RAWINPUT raw = (RAWINPUT)Marshal.PtrToStructure(buf, typeof(RAWINPUT));
                if (raw.header.dwType != RIM_TYPEKEYBOARD) return;
                string dev, src;
                if (raw.header.hDevice == IntPtr.Zero) { dev = "(null)"; src = "INJECTED"; }
                else { dev = DevName(raw.header.hDevice); src = "PHYSICAL"; }
                string ev = ((raw.keyboard.Flags & 0x01) == 0) ? "Down" : "Up";
                try { File.AppendAllText(outPath, string.Format("{0:o},{1},{2},{3}\r\n", DateTime.Now, ev, src, dev), Encoding.UTF8); } catch {}
            } finally { Marshal.FreeHGlobal(buf); }
        }
        string DevName(IntPtr hDev) {
            uint size = 0; GetRawInputDeviceInfoW(hDev, RIDI_DEVICENAME, IntPtr.Zero, ref size);
            if (size == 0) return "(unknown)";
            IntPtr p = Marshal.AllocHGlobal((int)(size * 2 + 2));
            try {
                uint r = GetRawInputDeviceInfoW(hDev, RIDI_DEVICENAME, p, ref size);
                if (r == 0 || r == unchecked((uint)-1)) return "(err)";
                string s = Marshal.PtrToStringUni(p); return (s == null) ? "(null-str)" : s;
            } finally { Marshal.FreeHGlobal(p); }
        }
    }
    static Sink sink;
    public static void Start(string path, int durationSec) {
        outPath = path; sink = new Sink();
        if (durationSec > 0) {
            System.Windows.Forms.Timer t = new System.Windows.Forms.Timer();
            t.Interval = durationSec * 1000; t.Tick += delegate { t.Stop(); Application.ExitThread(); }; t.Start();
        }
        Application.Run();
    }
}
'@
if (-not ('RawKbd' -as [type])) { Add-Type -TypeDefinition $cs -ReferencedAssemblies System.Windows.Forms -Language CSharp }

$log = Join-Path $case 'raw-device-log.csv'
'Timestamp,Event,Source,Device' | Out-File $log -Encoding UTF8
Write-Host ("Raw Input 监测 {0} 秒，请复现故障……" -f $DurationSeconds) -ForegroundColor Yellow
[RawKbd]::Start($log, $DurationSeconds)

Write-Host "`n===== 按设备汇总 =====" -ForegroundColor Green
Import-Csv $log | Group-Object Device |
    Select-Object @{N='设备/来源';E={$_.Name}}, @{N='事件数';E={$_.Count}} | Sort-Object 事件数 -Descending | Format-Table -AutoSize
Write-Host ("完整日志：{0}" -f $log) -ForegroundColor Cyan
Write-Host "把带 VID/PID 的设备路径与预检里的 hid-devices.csv 对号入座；(null) 即软件注入。" -ForegroundColor Cyan
