from pathlib import Path # 修改指定脚本的预检隔离。
p=Path('诊断电脑模板/Diag-KeyboardSource.ps1'); t=p.read_text(encoding='utf-8-sig') # 读取当前修订。
a=t.index('if (-not $CompileOnly) {'); b=t.index('$cs =',a) # 仅替换预检区块。
pre='''if (-not $CompileOnly) {
    $checks = [ordered]@{
        'hid-devices' = { Get-PnpDevice -PresentOnly -Class Keyboard,HIDClass -ErrorAction Stop | Select-Object Status,Class,FriendlyName,InstanceId,Problem,Manufacturer | Export-Csv (Join-Path $case 'hid-devices.csv') -NoTypeInformation -Encoding UTF8 }
        'accessibility' = { 'StickyKeys','Keyboard Response','ToggleKeys' | ForEach-Object { Get-ItemProperty "HKCU:\\Control Panel\\Accessibility\\$_" | Out-File (Join-Path $case ("acc-" + ($_ -replace ' ','') + '.txt')) -Encoding UTF8 } }
        'input-methods' = { Get-WinUserLanguageList | Format-List * | Out-File (Join-Path $case 'input-methods.txt') -Encoding UTF8 }
        'remote-macro-candidates' = { Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object { $_.Name -match 'teamviewer|anydesk|rustdesk|todesk|sunlogin|splashtop|screenconnect|connectwise|vnc|remoting_host|autohotkey|autoit|powertoys|inputdirector|synergy|barrier' } | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath | Export-Csv (Join-Path $case 'remote-macro-candidates.csv') -NoTypeInformation -Encoding UTF8 }
    }
    $status = foreach ($check in $checks.GetEnumerator()) {
        try { & $check.Value; [pscustomobject]@{Check=$check.Key;Status='OK';Error=$null} }
        catch { $_ | Out-String | Set-Content (Join-Path $case ($check.Key + '-error.txt')) -Encoding UTF8; Write-Warning $_; [pscustomobject]@{Check=$check.Key;Status='Unavailable';Error=$_.Exception.Message} }
    }
    $status | ConvertTo-Json | Set-Content (Join-Path $case 'preflight-status.json') -Encoding UTF8
}
''' # 每一项失败只影响自身，避免设备查询失败跳过辅助功能检查。
pre='\n'.join('# 独立读取预检项目并记录成功或具体错误。\n'+line if line.strip() else line for line in pre.splitlines())+'\n# 编译低级键盘事件诊断类型。\n' # 为每行PowerShell代码提供注释。
t=t[:a]+pre+t[b:] # 保留编译与采集实现。
t=t.replace('逐事件判定 实体 / 注入','逐事件读取系统注入标志') # 修正描述。
p.write_text(t,encoding='utf-8-sig') # 保持Windows PowerShell中文编码。
