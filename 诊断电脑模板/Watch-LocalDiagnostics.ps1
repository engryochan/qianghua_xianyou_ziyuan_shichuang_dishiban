#Requires -Version 5.1
param( # 持续运行默认开启，有限轮数用于验收。
    [ValidateRange(2,300)][int]$RefreshSeconds=5, # 两次采集之间至少等待指定秒数。
    [ValidateRange(0,100000)][int]$Iterations=0, # 零表示持续运行直到Ctrl+C。
    [ValidateRange(1,100)][int]$DisplayRows=20, # 控制终端展示行数。
    [switch]$SaveChanges, # 显式开启本地变化快照。
    [string]$OutDir=(Join-Path $env:LOCALAPPDATA 'KbdDiag'), # 默认避开项目及OneDrive目录。
    [switch]$NoClear # 测试或重定向时保留每轮输出。
) # 结束参数声明。
$ErrorActionPreference='Stop' # 失败必须明确报告。
$case=$null; $slot=0; $previous=''; $round=0; $inventory=$null; $inventoryAt=[datetime]::MinValue # 初始化有界状态。
if ($SaveChanges) { $case=Join-Path $OutDir ('watch-'+[guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $case | Out-Null } # 每次运行使用独立目录，最多保存十份快照。
try { # 运行诊断并保证结束提示。
    while ($true) { # 按用户要求持续循环。
        $round++; $issues=New-Object 'System.Collections.Generic.List[string]' # 每轮重建错误清单，防止内存累计。
        if (((Get-Date)-$inventoryAt).TotalSeconds -ge 60) { # 静态信息每分钟更新一次。
            $localInfo=$null; $keyboards=@(); $inventoryErrors=@() # 不把上次成功结果伪装成本次结果。
            try { $os=Get-CimInstance Win32_OperatingSystem; $pc=Get-CimInstance Win32_ComputerSystem; $localInfo=[pscustomobject]@{Computer=$env:COMPUTERNAME;OS=$os.Caption;Version=$os.Version;Build=$os.BuildNumber;Manufacturer=$pc.Manufacturer;Model=$pc.Model} } catch { $inventoryErrors+='本机系统读取失败：'+$_.Exception.Message } # 仅查询本机系统。
            try { $keyboards=@(Get-PnpDevice -PresentOnly -Class Keyboard | Select-Object Status,FriendlyName,InstanceId) } catch { $inventoryErrors+='键盘清单读取失败：'+$_.Exception.Message } # 仅查询本机键盘。
            $inventory=[pscustomobject]@{LocalSystem=$localInfo;LocalKeyboards=$keyboards;Errors=$inventoryErrors} # 缓存本机清单与失败信息。
            $inventoryAt=Get-Date # 记录实际采集时间。
        } # 结束低频清单采集。
        $processes=@{}; $connections=@(); $truncated=$false # 每轮替换进程与连接快照。
        try { Get-Process | ForEach-Object { $processes[[int]$_.Id]=$_.ProcessName } } catch { $issues.Add('进程清单不可用：'+$_.Exception.Message) } # 不读取进程命令行或用户输入。
        try { # 从本机TCP表查询连接，无网络扫描。
            $all=@(Get-NetTCPConnection -ErrorAction Stop | Where-Object State -eq Established | Sort-Object OwningProcess,RemoteAddress,RemotePort,LocalAddress,LocalPort) # 排序避免顺序变化产生假变化。
            $truncated=$all.Count -gt 2000 # 明确标记有界采集截断。
            $connections=@($all | Select-Object -First 2000 | ForEach-Object { [pscustomobject]@{LocalAddress=$_.LocalAddress;LocalPort=$_.LocalPort;RemoteAddress=$_.RemoteAddress;RemotePort=$_.RemotePort;ProcessId=$_.OwningProcess;Process=$processes[[int]$_.OwningProcess];RemoteDevice='未知';RemoteOS='未知';Attribution='未确认，普通连接不能证明远控'} }) # 不从IP猜测设备或操作者。
        } catch { $issues.Add('TCP连接读取失败：'+$_.Exception.Message) } # 权限或服务错误清楚显示。
        $snapshot=[pscustomobject]@{Inventory=$inventory;Connections=$connections;Truncated=$truncated;Errors=@($issues.ToArray())} # 只保留当前快照。
        $json=$snapshot | ConvertTo-Json -Depth 8 -Compress # 生成可比较的状态，不包含每轮时间戳。
        $changed=$json -cne $previous # 仅状态变化时保存。
        if ($SaveChanges -and $changed) { # 文件写入是可选功能。
            $payload=[pscustomobject]@{CapturedAt=(Get-Date).ToString('o');InventoryAt=$inventoryAt.ToString('o');Data=$snapshot} | ConvertTo-Json -Depth 10 # 为保存的证据添加时间。
            if ([Text.Encoding]::UTF8.GetByteCount($payload) -le 1MB) { # 每份快照最多1MiB。
                $target=Join-Path $case ('snapshot-{0:D2}.json' -f $slot) # 仅使用十个固定文件名。
                [IO.File]::WriteAllText($target,$payload,[Text.UTF8Encoding]::new($false)) # 覆盖本工具自己的快照槽，不删除用户文件。
                $slot=($slot+1)%10 # 十份快照轮替，单次运行最多10MiB。
            } else { $issues.Add('快照超过1MiB，未保存本轮；实时显示仍继续。') } # 不静默丢弃超限数据。
        } # 结束可选日志处理。
        $previous=$json # 只保留一个上轮状态用于比较。
        if (-not $NoClear -and -not [Console]::IsOutputRedirected) { Clear-Host } # 交互面板刷新，重定向不清屏。
        Write-Host ('本机诊断 | {0:o} | 第{1}轮 | Ctrl+C停止' -f (Get-Date),$round) # 明确显示诊断范围及退出方式。
        Write-Host '对端设备/系统/操作者：未确认。IP、端口及进程不构成入侵证据。' # 避免将连接包装成监控身份。
        Write-Host ('系统与键盘采集时间：{0:o}' -f $inventoryAt) # 缓存数据始终标注时间。
        $inventory.LocalSystem | Format-List | Out-Host # 显示已核实的本机系统信息。
        $inventory.LocalKeyboards | Format-Table -AutoSize -Wrap | Out-Host # 显示实际可读取的键盘设备。
        Write-Host ('已建立TCP连接：{0}；展示前{1}条；采集截断：{2}' -f $connections.Count,$DisplayRows,$truncated) # 不隐瞒展示上限。
        $connections | Select-Object -First $DisplayRows Process,ProcessId,RemoteAddress,RemotePort,RemoteDevice,RemoteOS | Format-Table -AutoSize | Out-Host # 显示线索及未知字段。
        @($inventory.Errors)+@($issues.ToArray()) | ForEach-Object { Write-Warning $_ } # 不能查询时显示失败而不是安全结论。
        if ($case) { Write-Host "变化快照目录：$case（最多十份，每份1MiB；旧运行目录需自行管理）" } # 明确磁盘上限作用于单次运行。
        if ($Iterations -gt 0 -and $round -ge $Iterations) { break } # 自动化验收使用有限轮数。
        Start-Sleep -Seconds $RefreshSeconds # 避免忙循环和持续高CPU占用。
    } # 结束当前循环。
} finally { Write-Host '本机诊断已停止；没有修改驱动、防护或启动设置。' } # 正常退出或中断均不留下后台采集任务。
