$ErrorActionPreference = 'Stop'; # 使读取失败进入明确的错误回执。
$outDir = Join-Path $PSScriptRoot 'policy-evidence'; # 所有输出仅保存在本项目报告目录。
New-Item -ItemType Directory -Path $outDir -Force | Out-Null; # 创建证据目录，不写公司设置。
$startTime = [DateTimeOffset]::Parse('2026-10-02T14:50:00+04:00').LocalDateTime; # 将用户时区窗口转换为事件查询本地时间。
$endTime = [DateTimeOffset]::Parse('2026-10-02T15:40:00+04:00').LocalDateTime; # 覆盖安装与两次已知启动错误。
$targetPattern = 'Taiko5DX|1842810|steam_api|SteamService|steam\.exe|65432'; # 只保存目标应用事件。
$logNames = @('Microsoft-Windows-CodeIntegrity/Operational','Microsoft-Windows-AppLocker/EXE and DLL','Microsoft-Windows-AppLocker/MSI and Script','Microsoft-Windows-AppLocker/Packaged app-Execution','Microsoft-Windows-Windows Defender/Operational','Application'); # 只读检查常见应用拦截通道。
$queries = foreach ($logName in $logNames) { # 逐个通道保留启用状态与读取结果。
    $record = [ordered]@{Log=$logName;Enabled=$null;Records=$null;QueryState='UNKNOWN';WindowEvents=$null;Matched=@();Error=$null}; # 不把缺日志默认当无拦截。
    try { # 查询日志但不启用、清空或改变其配置。
        $logInfo = Get-WinEvent -ListLog $logName; $record.Enabled=$logInfo.IsEnabled; $record.Records=$logInfo.RecordCount; # 保存实际日志元数据。
        try { $events = @(Get-WinEvent -FilterHashtable @{LogName=$logName;StartTime=$startTime;EndTime=$endTime} -MaxEvents 2000); $record.WindowEvents=$events.Count; $record.QueryState=if ($events.Count -eq 2000) {'READ_LIMIT_REACHED'} else {'READ_OK'}; $record.Matched=@($events | Where-Object { $_.Message -match $targetPattern -or ($_.ProviderName -match 'Kaspersky|Esafe|Tipray' -and $_.Level -le 3) } | Select-Object TimeCreated,Id,ProviderName,LevelDisplayName,Message); } catch { $record.QueryState=$_.FullyQualifiedErrorId; $record.Error=$_.Exception.Message }; # 区分无记录、访问拒绝与命中上限。
    } catch { $record.QueryState='LOG_METADATA_UNREADABLE'; $record.Error=$_.Exception.Message }; # 标记通道不存在或无权限。
    [pscustomobject]$record; # 返回该通道回执。
}; # 完成限定时间窗查询。
$queries | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outDir 'event-queries.json') -Encoding UTF8; # 保存明确目标事件与读取边界。
$defender = [ordered]@{Status='UNKNOWN';Protection=@();MatchingThreats=@();Error=$null}; # 初始不推定 Defender 已拦截。
try { $defender.Protection=Get-MpComputerStatus | Select-Object AntivirusEnabled,AMRunningMode,RealTimeProtectionEnabled,BehaviorMonitorEnabled,IoavProtectionEnabled; $defender.MatchingThreats=@(Get-MpThreatDetection | Where-Object { ($_.Resources -join ' ') -match $targetPattern } | Select-Object InitialDetectionTime,LastThreatStatusChangeTime,ThreatID,ActionSuccess,Resources); $defender.Status='READ_OK'; } catch { $defender.Status='UNREADABLE'; $defender.Error=$_.Exception.Message }; # 仅读状态和目标检测，不改排除项或防护。
$defender | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $outDir 'defender.json') -Encoding UTF8; # 保存目标威胁查询结果。
$firewall = [ordered]@{Status='UNKNOWN';TargetRules=@();Error=$null}; # 防火墙存在不等于加载错误来源。
try { $filters=@(Get-NetFirewallApplicationFilter -PolicyStore ActiveStore | Where-Object { $_.Program -match 'Taiko5DX|steam\.exe|SteamService' }); $firewall.TargetRules=@(foreach ($filter in $filters) { $filter | Get-NetFirewallRule | Select-Object Name,DisplayName,Enabled,Direction,Action,Profile,PolicyStoreSourceType,@{Name='Program';Expression={$filter.Program}} }); $firewall.Status='READ_OK'; } catch { $firewall.Status='UNREADABLE'; $firewall.Error=$_.Exception.Message }; # 查询目标应用规则，不新增、删除或放行。
$firewall | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $outDir 'firewall-target.json') -Encoding UTF8; # 保存规则事实而不归因为根因。
$applocker = [ordered]@{Status='UNKNOWN';Collections=@();Error=$null}; # 只记录集合模式，不导出全公司策略。
try { $policy=Get-AppLockerPolicy -Effective; $applocker.Collections=@($policy.RuleCollections | Select-Object CollectionType,EnforcementMode,@{Name='RuleCount';Expression={$_.Count}}); $applocker.Status='READ_OK'; } catch { $applocker.Status='UNREADABLE'; $applocker.Error=$_.Exception.Message }; # 不执行或修改有效策略。
$applocker | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $outDir 'applocker-state.json') -Encoding UTF8; # 记录无法访问的情况。
$logRoots=@('C:\Inetpub\ftproot\Tipray\LdTerm\log','C:\ProgramData\Kaspersky Lab\KES.14.1','C:\Program Files\EsafeNet\Cobra DocGuard Client'); # 限定已确认产品路径。
$localFiles = foreach ($root in $logRoots) { # 只读取日志候选元数据。
    try { Get-ChildItem -LiteralPath $root -File -Recurse -Depth 3 -Force | Where-Object { $_.Extension -match '^\.(log|txt|etl|db|dat|rpt|trace)$' } | Select-Object FullName,Length,LastWriteTime; } catch { [pscustomobject]@{FullName=$root;Length=$null;LastWriteTime=$null;Error=$_.Exception.Message}; }; # 不打开策略库或受保护二进制日志。
}; # 完成日志目录盘点。
$localFiles | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outDir 'vendor-log-files.json') -Encoding UTF8; # 提供给 IT 定位厂商报告。
$queries | Select-Object Log,Enabled,QueryState,WindowEvents,@{Name='Matched';Expression={$_.Matched.Count}} | Format-Table -AutoSize; # 返回可以核实的摘要。
[pscustomobject]@{Defender=$defender.Status;TargetThreats=$defender.MatchingThreats.Count;Firewall=$firewall.Status;TargetRules=$firewall.TargetRules.Count;AppLocker=$applocker.Status}; # 显示后续审阅所需状态。
