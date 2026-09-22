# Save as: RawInputKeyLogger.ps1
# Run as Administrator
Add-Type -Language CSharp -Namespace RawInputDemo -Name RawLogger -MemberDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public class RawLogger {
    const int RIDEV_INPUTSINK = 0x00000100;
    const int RID_INPUT = 0x10000003;
    const int RIM_TYPEKEYBOARD = 1;
    const int WM_INPUT = 0x00FF;

    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTDEVICE {
        public ushort usUsagePage;
        public ushort usUsage;
        public uint dwFlags;
        public IntPtr hwndTarget;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTHEADER {
        public uint dwType;
        public uint dwSize;
        public IntPtr hDevice;
        public IntPtr wParam;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct RAWKEYBOARD {
        public ushort MakeCode;
        public ushort Flags;
        public ushort Reserved;
        public ushort VKey;
        public uint Message;
        public uint ExtraInformation;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUT {
        public RAWINPUTHEADER header;
        public RAWKEYBOARD keyboard;
    }

    [DllImport("User32.dll")]
    static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] pRawInputDevices, uint uiNumDevices, uint cbSize);

    [DllImport("User32.dll")]
    static extern uint GetRawInputData(IntPtr hRawInput, uint uiCommand, IntPtr pData, ref uint pcbSize, uint cbSizeHeader);

    [DllImport("User32.dll", CharSet=CharSet.Auto)]
    static extern int GetRawInputDeviceInfo(IntPtr hDevice, uint uiCommand, StringBuilder pData, ref uint pcbSize);

    const uint RIDI_DEVICENAME = 0x20000007;

    public static void Run(string outPath) {
        var form = new System.Windows.Forms.Form();
        form.Text = "RawInputLogger";
        form.Width = 300;
        form.Height = 100;
        form.Load += (s,e) => {
            RAWINPUTDEVICE[] rid = new RAWINPUTDEVICE[1];
            rid[0].usUsagePage = 0x01;
            rid[0].usUsage = 0x06; // keyboard
            rid[0].dwFlags = RIDEV_INPUTSINK;
            rid[0].hwndTarget = form.Handle;
            if (!RegisterRawInputDevices(rid, (uint)rid.Length, (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(RAWINPUTDEVICE)))) {
                System.Windows.Forms.MessageBox.Show("RegisterRawInputDevices failed");
            }
        };

        form.FormClosing += (s,e) => { System.Windows.Forms.Application.ExitThread(); };

        form.HandleCreated += (s,e) => {
            System.Windows.Forms.Application.AddMessageFilter(new MsgFilter(outPath));
        };

        System.Windows.Forms.Application.Run(form);
    }

    class MsgFilter : System.Windows.Forms.IMessageFilter {
        string outPath;
        public MsgFilter(string p) { outPath = p; }
        public bool PreFilterMessage(ref System.Windows.Forms.Message m) {
            if (m.Msg == WM_INPUT) {
                uint dwSize = 0;
                GetRawInputData(m.LParam, RID_INPUT, IntPtr.Zero, ref dwSize, (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(RAWINPUTHEADER)));
                IntPtr buffer = System.Runtime.InteropServices.Marshal.AllocHGlobal((int)dwSize);
                try {
                    if (GetRawInputData(m.LParam, RID_INPUT, buffer, ref dwSize, (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(RAWINPUTHEADER))) == dwSize) {
                        RAWINPUT raw = (RAWINPUT)System.Runtime.InteropServices.Marshal.PtrToStructure(buffer, typeof(RAWINPUT));
                        if (raw.header.dwType == RIM_TYPEKEYBOARD) {
                            IntPtr hDev = raw.header.hDevice;
                            uint pcbSize = 0;
                            GetRawInputDeviceInfo(hDev, RIDI_DEVICENAME, null, ref pcbSize);
                            StringBuilder sb = new StringBuilder((int)pcbSize);
                            GetRawInputDeviceInfo(hDev, RIDI_DEVICENAME, sb, ref pcbSize);
                            string devName = sb.ToString();
                            string line = string.Format("{0:o},{1},{2},{3}", DateTime.UtcNow, raw.keyboard.VKey, raw.keyboard.Message, devName);
                            System.IO.File.AppendAllText(outPath, line + Environment.NewLine);
                        }
                    }
                } finally {
                    System.Runtime.InteropServices.Marshal.FreeHGlobal(buffer);
                }
            }
            return false;
        }
    }
}
"@

# Prepare output
$OutDir = "C:\Forensic\RawInputLogs"
New-Item -Path $OutDir -ItemType Directory -Force | Out-Null
$log = Join-Path $OutDir ("rawinput_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".csv")
"Timestamp,VKey,Message,DeviceName" | Out-File -FilePath $log -Encoding UTF8

# Run the RawInput logger in a new thread so PowerShell remains interactive
[RawInputDemo.RawLogger]::Run($log)
