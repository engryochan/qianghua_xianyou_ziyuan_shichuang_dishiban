#Requires -Version 5.1
param([ValidateRange(0,3600)][int]$DurationSeconds=0,[switch]$ShowKeyCodes,[switch]$SelfTest) # 默认持续显示，零时长需手动关闭窗口；键码必须显式开启。
$ErrorActionPreference='Stop' # 编译和启动失败应明确报告。
$source=Join-Path $PSScriptRoot 'KeyboardEvidence.cs' # 加载同目录的原生采集实现。
$refs=@('System.Windows.Forms','System.Drawing') # WindowsPowerShell所需的界面引用。
if ($PSVersionTable.PSEdition -eq 'Core') { $refs=@((Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll').FullName)+@((Join-Path $PSHOME 'System.Windows.Forms.dll'),(Join-Path $PSHOME 'System.Windows.Forms.Primitives.dll'),(Join-Path $PSHOME 'System.Drawing.Common.dll')) } # PowerShell7显式补全桌面程序集。
if ($PSVersionTable.PSEdition -eq 'Core') { $refs += @((Get-ChildItem $PSHOME -Filter 'System.Private.Windows*.dll').FullName) } # 补充新版WinForms内部引用。
if (-not ('KeyboardEvidence.Panel' -as [type])) { Add-Type -TypeDefinition ([IO.File]::ReadAllText($source)) -ReferencedAssemblies $refs } # 同一进程仅编译一次。
if ($SelfTest) { [KeyboardEvidence.Panel]::SelfTest(); return } # 逻辑测试不采集也不模拟系统按键。
Write-Host '实时显示本机输入证据；关闭窗口停止。两路事件不等于两次按键。无法自动确认屏幕键盘或操作者。' # 明确界面能力边界。
[KeyboardEvidence.Panel]::Run($DurationSeconds,[bool]$ShowKeyCodes) # 显示可见窗口，不后台保存输入内容。
