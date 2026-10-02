from pathlib import Path # 使用可靠的Unicode文件路径。
root = Path('诊断电脑模板') # 限定修改范围。
def save(name, text): # 为所有代码行添加注释并保存Windows兼容编码。
    lines = []; inside = False # 跟踪嵌入C#区块。
    for line in text.splitlines(): # 逐行处理以保持代码顺序。
        s = line.strip() # 判断代码和注释边界。
        if inside and s in ("'@", '"@'): inside = False; lines.append(line); continue # here-string结束标记必须独占一行。
        if inside: lines.append(line + (' // 声明或执行键盘诊断逻辑。' if s and not s.startswith('//') else '')); continue # C#使用自身的注释语法。
        if s and not s.startswith('#'): lines.append('# ' + ('定义采集参数及边界。' if s.startswith(('param','[int]','[switch]','[string]','[Validate')) else '执行本地诊断或资源清理，不修改系统配置。')) # 在PowerShell代码前注释以保持续行语法。
        lines.append(line) # 保留原代码。
        if s.endswith(("@'", '@"')): inside = True # 开始C#文本。
    (root / name).write_text('\n'.join(lines)+'\n', encoding='utf-8-sig') # 保留PS5中文兼容性。
for name in ('Diag-KeyboardSource.ps1','Diag-RawInputDevice.ps1'): # 修复两个有限采集器。
    t = (root/name).read_text(encoding='utf-8-sig') # 加载原始文本。
    t = t.replace('[int]$DurationSeconds = 120', '[ValidateRange(1,600)][int]$DurationSeconds = 120') # 禁止无限运行及毫秒整数溢出。
    t = t.replace('yyyyMMdd-HHmmss', 'yyyyMMdd-HHmmss-fffffff') # 避免同秒覆盖报告。
    t = t.replace("$ErrorActionPreference = 'Continue'", "$ErrorActionPreference = 'Stop'") # 使编译与日志失败可见。
    t = t.replace('[string]$OutDir =', '[switch]$CompileOnly,\n    [string]$OutDir =') # 添加无采集编译验收模式。
    if name == 'Diag-KeyboardSource.ps1': # 修复低级钩子。
        start = t.index('# ---------- 只读预检') # 预检只在实际运行时执行。
        end = t.index('# ---------- 低级键盘') # 保持C#编译入口独立。
        pre = t[start:end].replace('-ErrorAction SilentlyContinue', '-ErrorAction Stop').replace('Get-PnpDevice -Class Keyboard,HIDClass', 'Get-PnpDevice -PresentOnly -Class Keyboard,HIDClass') # 不将访问失败当成无设备。
        pre = pre.replace('Get-PnpDevice -PresentOnly', 'Get-PnpDevice -PresentOnly') # 保持设备查询参数。
        t = t[:start] + 'if (-not $CompileOnly) {\ntry {\n' + pre + '} catch { $_ | Out-String | Set-Content (Join-Path $case "preflight-error.txt"); Write-Warning $_ }\n}\n' + t[end:] # 记录预检失败但允许无需管理员的钩子测试。
        t = t.replace('static string outPath; static bool recVk;', 'static string outPath; static bool recVk; static readonly object writeLock = new object(); static Exception writeError;') # 序列化异步写入并保留失败。
        t = t.replace('"PHYSICAL"', '"NOT_FLAGGED_INJECTED"').replace('实体按键 PHYSICAL', '未标记注入事件') # 禁止把标志缺失当成硬件真实性证明。
        t = t.replace('StringBuilder sb = new StringBuilder(); string ln;', 'lock (writeLock) { StringBuilder sb = new StringBuilder(); string ln;') # 防止计时器并发写入。
        t = t.replace('catch {} }', 'catch (Exception ex) { writeError = ex; } } }') # 不再吞掉写入错误。
        t = t.replace('outPath = path; recVk = includeVk; proc = CB;', 'CountPhysical = CountInjected = CountInjectedLowIL = 0; writeError = null; q = new ConcurrentQueue<string>(); outPath = path; recVk = includeVk; proc = CB;') # 重复调用重置统计。
        t = t.replace('MSG m; while (GetMessage(out m, IntPtr.Zero, 0, 0) > 0) { }\n        if (quit != null) quit.Dispose(); flush.Dispose();\n        UnhookWindowsHookEx(hookId); Flush();', 'try { MSG m; int result; while ((result = GetMessage(out m, IntPtr.Zero, 0, 0)) > 0) { } if (result < 0) throw new System.ComponentModel.Win32Exception(); }\n        finally { if (quit != null) quit.Dispose(); using (var done = new ManualResetEvent(false)) { flush.Dispose(done); done.WaitOne(); } UnhookWindowsHookEx(hookId); hookId = IntPtr.Zero; Flush(); }\n        if (writeError != null) throw new IOException("Failed to write keyboard diagnostic log", writeError);') # 确保钩子和计时器退出且最终错误可见。
        t = t.replace('$log = Join-Path', 'if ($CompileOnly) { Write-Output "COMPILE_OK"; return }\n$log = Join-Path') # 编译测试不启动键盘采集。
        t = t.replace('先确认 remote-macro-candidates.csv 为空再判读。', '候选进程清单为空也不能排除其他来源；注入标志不能识别操作者或证明入侵。') # 修正误导性归因。
    else: # 修复Raw Input资源生命周期与来源判定。
        t = t.replace('$case =', "$ErrorActionPreference = 'Stop'\n$case =", 1) # 传播编译与写入错误。
        t = t.replace('[switch]$CompileOnly,', '[switch]$CompileOnly,\n    [switch]$RecordKeyCodes,') # 保留显式键码记录能力。
        t = t.replace('static string outPath;', 'static string outPath; static bool recordKeys; static Exception failure;') # 保存明确的记录选项及错误。
        t = t.replace('Handle(m.LParam)', 'ReadInput(m.LParam)').replace('void Handle(IntPtr hRaw)', 'void ReadInput(IntPtr hRaw)') # 避免方法遮蔽NativeWindow.Handle属性。
        t = t.replace('if (GetRawInputData(hRaw, RID_INPUT, IntPtr.Zero, ref size, hdr) != 0) return;', 'if (GetRawInputData(hRaw, RID_INPUT, IntPtr.Zero, ref size, hdr) != 0) throw new System.ComponentModel.Win32Exception(); if (size < Marshal.SizeOf(typeof(RAWINPUT))) return;') # 校验数据长度。
        t = t.replace('src = "INJECTED"', 'src = "NO_DEVICE_HANDLE"').replace('src = "PHYSICAL"', 'src = "DEVICE_ASSOCIATED"') # 不把设备句柄当作入侵判断。
        t = t.replace('{0:o},{1},{2},{3}\\r\\n", DateTime.Now, ev, src, dev)', '{0:o},{1},{2},{3},{4}\\r\\n", DateTime.Now, ev, src, dev, recordKeys ? raw.keyboard.VKey.ToString() : "-")') # 只有显式开关才记录键码。
        t = t.replace('catch {}', 'catch (Exception ex) { failure = ex; Application.ExitThread(); }') # 保留落盘错误。
        t = t.replace('if (m.Msg == WM_INPUT) ReadInput(m.LParam);', 'if (m.Msg == WM_INPUT) { try { ReadInput(m.LParam); } catch (Exception ex) { failure = ex; Application.ExitThread(); } }') # 不允许异常跨越原生回调。
        t = t.replace('public static void Start(string path, int durationSec)', 'public static void Start(string path, int durationSec, bool includeKeys)') # 接收记录选项。
        a = t.index('        outPath = path; sink = new Sink();'); b = t.index('\n    }\n}', a) # 替换缺少清理的消息循环。
        t = t[:a] + '''        outPath = path; recordKeys = includeKeys; failure = null; sink = new Sink();
        using (var timer = new System.Windows.Forms.Timer()) {
            try { timer.Interval = durationSec * 1000; timer.Tick += delegate { Application.ExitThread(); }; timer.Start(); Application.Run(); }
            finally { timer.Stop(); RAWINPUTDEVICE[] remove = new RAWINPUTDEVICE[1]; remove[0].usUsagePage=1; remove[0].usUsage=6; remove[0].dwFlags=1; RegisterRawInputDevices(remove,1,(uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE))); sink.DestroyHandle(); sink=null; }
        }
        if (failure != null) throw new System.IO.IOException("Raw Input diagnostic failed", failure);''' + t[b:] # 退出时注销输入注册并释放窗口。
        t = t.replace('$log = Join-Path', 'if ($CompileOnly) { Write-Output "COMPILE_OK"; return }\n$log = Join-Path') # 编译测试不启动采集。
        t = t.replace('Timestamp,Event,Source,Device', 'Timestamp,Event,Source,Device,VKey').replace('[RawKbd]::Start($log, $DurationSeconds)', '[RawKbd]::Start($log, $DurationSeconds, [bool]$RecordKeyCodes)') # 同步CSV表头与调用。
        t = t.replace('(null) 即软件注入。', '(null) 表示未提供设备句柄，不能据此认定软件注入或入侵。') # 明确证据边界。
    save(name,t) # 保存带逐行注释的修订。
name = 'Full-Keyboard-State.ps1' # 修复状态查看器。
t = (root/name).read_text(encoding='utf-8-sig') # 读取原状态采样功能。
t = 'param([ValidateRange(1,600)][int]$DurationSeconds=30, [ValidateRange(20,2000)][int]$IntervalMilliseconds=100, [switch]$AllKeys)\n$ErrorActionPreference="Stop"\n' + t # 加入自动退出与采样间隔。
t = t.replace('Add-Type @"', 'if (-not ("FullKeyboardState" -as [type])) {\nAdd-Type @"',1).replace('"@', '"@\n}',1) # 支持同会话重复运行。
t = t.replace('while ($true) {', '$watch = [Diagnostics.Stopwatch]::StartNew()\nwhile ($watch.Elapsed.TotalSeconds -lt $DurationSeconds) {').replace('if (Test-KeyDown $item.Value)', 'if (($AllKeys -or $item.Value -in 0xA0,0xA1,0xA2,0xA3,0xA4,0xA5,0x5B,0x5C,0x14,0x90,0x91) -and (Test-KeyDown $item.Value))') # 默认只检测修饰键与锁定键。
t = t.replace('    Clear-Host', '    # 保留终端输出便于核验，不清空其他诊断内容。').replace('Start-Sleep -Milliseconds 100', 'Start-Sleep -Milliseconds $IntervalMilliseconds').replace('不记录字符、文本、密码或网络地址。','默认仅显示修饰键；-AllKeys 会显示所有键位，请勿输入敏感内容。') # 修正隐私说明与终端行为。
save(name,t) # 保存状态查看器。
name='Log-AllKeys-Async.ps1' # 修复轮询记录器。
t=(root/name).read_text(encoding='utf-8-sig') # 读取轮询实现。
t='param([ValidateRange(1,600)][int]$DurationSeconds=30, [switch]$RecordKeyCodes, [string]$OutDir=(Join-Path $env:TEMP "KbdDiag"))\n$ErrorActionPreference="Stop"\nAdd-Type -AssemblyName System.Windows.Forms\n' + t # 加入边界与缺失的程序集。
t=t.replace('# Run as Administrator','# 无需管理员权限。').replace('Add-Type @"','if (-not ("K" -as [type])) {\nAdd-Type @"',1).replace('"@','"@\n}',1) # 允许重复运行。
t=t.replace('$OutDir = "C:\\Forensic\\KeyLogs"','').replace('yyyyMMdd_HHmmss','yyyyMMdd_HHmmss_fffffff').replace('$vkRange = 1..254','$vkRange = if ($RecordKeyCodes) { 1..254 } else { @(0xA0,0xA1,0xA2,0xA3,0xA4,0xA5,0x5B,0x5C,0x14,0x90,0x91) }') # 默认只记录修饰键。
t=t.replace('try {\n    while ($true)', '$watch=[Diagnostics.Stopwatch]::StartNew()\ntry {\n    while ($watch.Elapsed.TotalSeconds -lt $DurationSeconds)').replace('正在记录所有按键事件','正在记录选定键位状态变化；轮询可能漏掉短按，不能证明事件来源').replace('Write-Host "记录中断: $($_.Exception.Message)" -ForegroundColor Red','throw') # 不隐藏错误且明确轮询限制。
save(name,t) # 保存受限轮询工具。
save('RawInputKeyLogger.ps1', '''#Requires -Version 5.1
param([ValidateRange(1,600)][int]$DurationSeconds=30, [switch]$RecordKeyCodes, [switch]$CompileOnly, [string]$OutDir=(Join-Path $env:TEMP 'KbdDiag'))
$ErrorActionPreference='Stop'
# 复用已修正的Raw Input采集器，避免维护两个不同的原生消息循环。
& (Join-Path $PSScriptRoot 'Diag-RawInputDevice.ps1') -DurationSeconds $DurationSeconds -RecordKeyCodes:$RecordKeyCodes -CompileOnly:$CompileOnly -OutDir $OutDir
''') # 保留旧文件入口并提供相同的设备关联和可选键码功能。
