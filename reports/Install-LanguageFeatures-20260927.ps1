$ErrorActionPreference = 'Stop' # 安装错误必须记录而不能静默忽略。
$auditRoot = $PSScriptRoot # 将安装证据保存在脚本同目录。
$names = @('Language.Basic~~~zh-TW~0.0.1.0','Language.Fonts.Hant~~~und-HANT~0.0.1.0','Language.Handwriting~~~ja-JP~0.0.1.0','Language.Handwriting~~~zh-TW~0.0.1.0','Language.OCR~~~zh-TW~0.0.1.0','Language.Speech~~~ja-JP~0.0.1.0','Language.Speech~~~zh-TW~0.0.1.0','Language.TextToSpeech~~~zh-TW~0.0.1.0') # 仅安装用户授权的八项缺失功能，先安装基础组件。
$results = @() # 收集逐项结果。
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' | Select-Object ACP,OEMCP | ConvertTo-Json | Set-Content (Join-Path $auditRoot 'ime-codepage-before.json') -Encoding UTF8 # 记录兼容性基线。
foreach ($name in $names) { # 按顺序安装，避免并发修改 Windows 组件。
    try { # 每项独立处理并保留错误信息。
        $before = Get-WindowsCapability -Online -Name $name # 重新核实当前状态。
        $result = $null # 清除上一项的安装返回值。
        if ($before.State -eq 'NotPresent') { # 只补装缺失项。
            $result = Add-WindowsCapability -Online -Name $name -LogPath (Join-Path $auditRoot 'ime-install-dism.log') # 使用 Windows 官方组件服务，保留现有更新策略。
        } # 结束条件安装。
        $after = Get-WindowsCapability -Online -Name $name # 查询安装后的真实状态。
        $results += [pscustomobject]@{Name=$name;Before=[string]$before.State;After=[string]$after.State;RestartNeeded=$result.RestartNeeded;Error=$null} # 保存可核验的结果。
    } catch { # 捕获失败后继续核查其他授权项。
        $results += [pscustomobject]@{Name=$name;Before=$null;After='Error';RestartNeeded=$null;Error=$_.Exception.Message} # 保留失败原因，不修改企业策略来规避错误。
    } # 结束错误处理。
    $results | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $auditRoot 'ime-install-results.json') -Encoding UTF8 # 每项完成后更新进度。
} # 结束安装循环。
Get-WindowsCapability -Online | Where-Object { $_.Name -match 'Language\..*(ja-JP|zh-TW|Hant|Jpan)' } | Select-Object Name,@{Name='State';Expression={[string]$_.State}} | ConvertTo-Json | Set-Content (Join-Path $auditRoot 'ime-capabilities-after.json') -Encoding UTF8 # 保存所有相关组件最终状态。
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' | Select-Object ACP,OEMCP | ConvertTo-Json | Set-Content (Join-Path $auditRoot 'ime-codepage-after.json') -Encoding UTF8 # 核实代码页保持不变。
'Completed' | Set-Content (Join-Path $auditRoot 'ime-install-completed.txt') -Encoding UTF8 # 写入完成标记；不自动重启。
