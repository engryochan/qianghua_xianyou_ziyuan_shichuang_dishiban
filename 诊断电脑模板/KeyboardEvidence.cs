using System; // 使用基础类型。
using System.Collections.Generic; // 使用有界事件队列。
using System.Runtime.InteropServices; // 调用Windows只读输入接口。
using System.Windows.Forms; // 显示可关闭的诊断窗口。
namespace KeyboardEvidence { // 避免与既有脚本类型冲突。
public sealed class Panel : Form { // 在同一UI线程接收两种输入证据。
    [StructLayout(LayoutKind.Sequential)] struct HookData { public uint Key,Scan,Flags,Time; public IntPtr Extra; } // 匹配低级键盘事件结构。
    [StructLayout(LayoutKind.Sequential)] struct Device { public ushort Page,Usage; public uint Flags; public IntPtr Window; } // 匹配RawInput注册结构。
    [StructLayout(LayoutKind.Sequential)] struct Header { public uint Type,Size; public IntPtr Device,Param; } // 保持指针宽度兼容。
    [StructLayout(LayoutKind.Sequential)] struct Keyboard { public ushort Scan,Flags,Reserved,Key; public uint Message,Extra; } // 匹配原始键盘字段。
    [StructLayout(LayoutKind.Sequential)] struct Raw { public Header Header; public Keyboard Keyboard; } // 匹配键盘RawInput布局。
    delegate IntPtr HookProc(int code,IntPtr message,IntPtr data); // 保留原生回调类型。
    [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SetWindowsHookEx(int id,HookProc proc,IntPtr module,uint thread); // 安装只观察的键盘钩子。
    [DllImport("user32.dll",SetLastError=true)] static extern bool UnhookWindowsHookEx(IntPtr hook); // 结束时移除钩子。
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook,int code,IntPtr message,IntPtr data); // 原样转交所有输入。
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name); // 取得当前进程模块句柄。
    [DllImport("user32.dll",SetLastError=true)] static extern bool RegisterRawInputDevices(Device[] devices,uint count,uint size); // 注册或注销设备证据接收。
    [DllImport("user32.dll",SetLastError=true)] static extern uint GetRawInputData(IntPtr input,uint command,IntPtr buffer,ref uint size,uint header); // 读取当前原始事件。
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetRawInputDeviceInfoW(IntPtr device,uint command,IntPtr data,ref uint size); // 查询设备路径。
    readonly Queue<string[]> pending=new Queue<string[]>(); // 回调只入队，避免界面操作拖慢输入。
    readonly ListView events=new ListView(); // 显示最近事件而非无限追加。
    readonly Label status=new Label(); // 展示计数、丢弃与采集状态。
    readonly ComboBox annotation=new ComboBox(); // 用户声明测试方式，不当作自动判定。
    readonly Timer timer=new Timer(); // 批量刷新减少UI开销。
    readonly bool showKeys; readonly int duration; readonly System.Diagnostics.Stopwatch elapsed=new System.Diagnostics.Stopwatch(); // 保存显示选项与单调计时。
    HookProc callback; IntPtr hook; bool rawRegistered; string failure; long dropped,hookCount,rawCount; // 跟踪清理、失败和两路独立计数。
    public static string Classify(uint flags) { return (flags&0x10)!=0 ? "系统标记软件注入；具体软件未知" : "未标记注入；不证明实体按键"; } // 只解释Windows标志，不推断操作者。
    public static string RawClass(bool hasDevice) { return hasDevice ? "关联设备；实体或虚拟HID待核验" : "无设备句柄；来源未知"; } // 句柄存在不等于物理设备真实性证明。
    void Enqueue(string[] row) { if(pending.Count>=200) { pending.Dequeue(); dropped++; } pending.Enqueue(row); } // 高负载时有界丢弃并显示计数。
    Panel(int seconds,bool keys) { // 构建可见的持续诊断面板。
        duration=seconds; showKeys=keys; Text="键盘输入证据 — 关闭窗口停止"; Width=1200; Height=600; // 持续运行仍可用鼠标停止。
        var explanation=new Label { Dock=DockStyle.Top,Height=65,Text="同一按键可能出现HOOK与RAW两行，不能直接相加。软件模拟和系统屏幕键盘通常无法自动分开。\r\n无键码落盘；默认隐藏键码。虚拟HID、远程会话和安全桌面存在观测盲点。测试时请勿输入敏感内容。" }; // 在界面上明确限制。
        annotation.Dock=DockStyle.Top; annotation.DropDownStyle=ComboBoxStyle.DropDownList; annotation.Items.AddRange(new object[]{"未标注","用户声明：实体键盘测试","用户声明：软件模拟测试","用户声明：屏幕键盘测试"}); annotation.SelectedIndex=0; // 三种用户测试阶段独立显示。
        events.Dock=DockStyle.Fill; events.View=View.Details; events.FullRowSelect=true; events.GridLines=true; // 用有界表格实时呈现事件。
        foreach(var column in new string[]{"时间","通道","按下/抬起","键码","可验证分类","设备路径/注入标志","用户测试标注"}) events.Columns.Add(column,160); // 证据与用户声明分列。
        status.Dock=DockStyle.Bottom; status.Height=45; Controls.Add(events); Controls.Add(annotation); Controls.Add(explanation); Controls.Add(status); // 保持状态栏可见。
        timer.Interval=100; timer.Tick+=delegate { Flush(); if(duration>0 && elapsed.Elapsed.TotalSeconds>=duration) Close(); }; // 每100毫秒批量刷新并支持有限验收。
    } // 结束窗口构造。
    protected override void OnShown(EventArgs e) { // 显示窗口后才开始采集。
        base.OnShown(e); // 保留标准窗口事件。
        try { callback=Observe; hook=SetWindowsHookEx(13,callback,GetModuleHandle(null),0); if(hook==IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()); var devices=new Device[]{new Device{Page=1,Usage=6,Flags=0x100,Window=Handle}}; if(!RegisterRawInputDevices(devices,1,(uint)Marshal.SizeOf(typeof(Device)))) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()); rawRegistered=true; elapsed.Start(); timer.Start(); } catch(Exception ex) { failure=ex.Message; Close(); } // 任一路启动失败即停止，避免部分采集冒充完整运行。
    } // 完成双路注册。
    IntPtr Observe(int code,IntPtr message,IntPtr data) { // 低级钩子不拦截或改变任何按键。
        try { if(code>=0) { var key=(HookData)Marshal.PtrToStructure(data,typeof(HookData)); hookCount++; Enqueue(new string[]{DateTime.Now.ToString("HH:mm:ss.fff"),"HOOK",(key.Flags&0x80)!=0?"Up":"Down",showKeys?key.Key.ToString():"隐藏",Classify(key.Flags),"Flags=0x"+key.Flags.ToString("X"),annotation.Text}); } } catch(Exception ex) { failure=ex.Message; } // 回调异常只标记，避免跨原生边界抛出。
        return CallNextHookEx(hook,code,message,data); // 始终传递原始事件。
    } // 结束低级观察。
    protected override void WndProc(ref Message message) { // 收取设备关联证据。
        if(message.Msg==0xFF) { try { ReadRaw(message.LParam); } catch(Exception ex) { failure=ex.Message; } } // RawInput失败在刷新时明确停止。
        base.WndProc(ref message); // 保留Windows默认消息清理。
    } // 结束原生消息处理。
    void ReadRaw(IntPtr input) { // 仅读取本次键盘事件。
        uint size=0,header=(uint)Marshal.SizeOf(typeof(Header)); if(GetRawInputData(input,0x10000003,IntPtr.Zero,ref size,header)!=0) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()); // 先查询所需缓冲。
        if(size<Marshal.SizeOf(typeof(Raw)) || size>65536) throw new InvalidOperationException("RawInput大小不符合预期"); // 限制分配大小。
        IntPtr buffer=Marshal.AllocHGlobal((int)size); // 分配本次消息缓冲。
        try { // 确保任何路径都释放原生内存。
            if(GetRawInputData(input,0x10000003,buffer,ref size,header)!=size) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()); // 拒绝不完整读取。
            var raw=(Raw)Marshal.PtrToStructure(buffer,typeof(Raw)); if(raw.Header.Type!=1) return; rawCount++; // 只处理键盘而不采集鼠标。
            Enqueue(new string[]{DateTime.Now.ToString("HH:mm:ss.fff"),"RAW",(raw.Keyboard.Flags&1)!=0?"Up":"Down",showKeys?raw.Keyboard.Key.ToString():"隐藏",RawClass(raw.Header.Device!=IntPtr.Zero),DeviceName(raw.Header.Device),annotation.Text}); // 展示设备路径，不强行匹配另一通道。
        } finally { Marshal.FreeHGlobal(buffer); } // 及时释放原生缓冲。
    } // 结束原始事件读取。
    static string DeviceName(IntPtr device) { // 查询当前设备句柄而不扫描远端。
        if(device==IntPtr.Zero) return "未知（无句柄）"; uint size=0; if(GetRawInputDeviceInfoW(device,0x20000007,IntPtr.Zero,ref size)==uint.MaxValue || size==0 || size>32768) return "设备路径读取失败"; // 不将查询失败当成无设备。
        IntPtr buffer=Marshal.AllocHGlobal(checked((int)(size+1)*2)); // 为Unicode名称分配有界空间。
        try { if(GetRawInputDeviceInfoW(device,0x20000007,buffer,ref size)==uint.MaxValue) return "设备路径读取失败"; return Marshal.PtrToStringUni(buffer); } finally { Marshal.FreeHGlobal(buffer); } // 查询结束立即释放。
    } // 结束路径查询。
    void Flush() { // 批量更新，最多保留200条事件。
        events.BeginUpdate(); try { while(pending.Count>0) { events.Items.Add(new ListViewItem(pending.Dequeue())); if(events.Items.Count>200) events.Items.RemoveAt(0); } if(events.Items.Count>0) events.EnsureVisible(events.Items.Count-1); } finally { events.EndUpdate(); } // 界面大小不随运行时长增长。
        status.Text="HOOK事件="+hookCount+"；RAW事件="+rawCount+"；队列丢弃="+dropped+"；不代表独立按键总数。\r\n采集盲点可能导致漏报；未收到事件不证明不存在输入。"; // 分开统计两条证据通道。
        if(failure!=null) Close(); // 出错时停止而不是继续显示假健康状态。
    } // 结束刷新。
    void Cleanup() { // 重复调用安全的资源清理。
        timer.Stop(); if(hook!=IntPtr.Zero) { if(!UnhookWindowsHookEx(hook)) failure="移除钩子失败："+Marshal.GetLastWin32Error(); hook=IntPtr.Zero; } // 停止刷新并释放钩子。
        if(rawRegistered) { if(!RegisterRawInputDevices(new Device[]{new Device{Page=1,Usage=6,Flags=1,Window=IntPtr.Zero}},1,(uint)Marshal.SizeOf(typeof(Device)))) failure="注销RawInput失败："+Marshal.GetLastWin32Error(); rawRegistered=false; } // 不留下RawInput注册。
    } // 结束清理。
    protected override void OnFormClosed(FormClosedEventArgs e) { Cleanup(); base.OnFormClosed(e); } // 鼠标关闭和自动结束均走清理。
    protected override void Dispose(bool disposing) { if(disposing) { Cleanup(); timer.Dispose(); } base.Dispose(disposing); } // 异常退出路径同样释放资源。
    public static void Run(int seconds,bool keys) { using(var panel=new Panel(seconds,keys)) { Application.Run(panel); if(panel.failure!=null) throw new InvalidOperationException(panel.failure); Console.WriteLine("Stopped; HOOK="+panel.hookCount+" RAW="+panel.rawCount+" Dropped="+panel.dropped); } } // 可见运行，结束后只输出计数。
    public static void SelfTest() { // 白盒验证不会向操作系统注入键盘事件。
        if(Classify(0).Contains("软件注入") || !Classify(0x10).Contains("软件注入") || !Classify(0x12).Contains("软件注入") || !RawClass(false).Contains("未知") || !RawClass(true).Contains("待核验")) throw new Exception("分类边界失败"); // 验证标志解释不过度归因。
        using(var panel=new Panel(1,false)) { for(int i=0;i<1000;i++) panel.Enqueue(new string[]{"test","test","test","隐藏","test","test","test"}); if(panel.pending.Count!=200 || panel.dropped!=800) throw new Exception("队列上限失败"); } // 用合成内存记录验证持续运行的队列上限。
        Console.WriteLine("SELFTEST_OK: classification and bounded queue; no OS input injected"); // 明确测试范围。
    } // 结束逻辑测试。
} // 结束窗口类型。
} // 结束命名空间。
