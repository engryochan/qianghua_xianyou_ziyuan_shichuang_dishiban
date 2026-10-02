$ErrorActionPreference='Stop' # 任意断言失败终止验收。
$root=Join-Path (Split-Path (Split-Path $PSScriptRoot)) '诊断电脑模板' # 定位五个被测脚本。
$dest=Join-Path $PSScriptRoot ('validation-'+$PSVersionTable.PSEdition) # 按运行时分开保存证据。
New-Item -ItemType Directory -Path $dest -Force | Out-Null # 创建本地测试输出目录。
foreach ($file in Get-ChildItem $root -Filter '*.ps1') { # 对每个入口进行语法与边界验证。
    $tokens=$null; $errors=$null # 清空上次解析状态。
    $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors) # 使用当前PowerShell解析器。
    if ($errors.Count) { throw ($errors | Out-String) } # 语法错误必须失败。
    $rejected=$false # 跟踪零时长是否被拒绝。
    try { & $file.FullName -DurationSeconds 0 } catch [Management.Automation.ParameterBindingException] { $rejected=$true } # 确保原无限采集模式不会意外恢复。
    if (-not $rejected) { throw "Invalid duration accepted: $($file.Name)" } # 未拒绝非法参数则验收失败。
    Write-Output "PARSE_AND_BOUNDARY_OK $($file.Name)" # 输出逐入口验收结果。
} # 完成五个入口检查。
foreach ($name in 'Diag-KeyboardSource.ps1','Diag-RawInputDevice.ps1') { # 测试原生资源在同一进程内重复使用。
    1..2 | ForEach-Object { & (Join-Path $root $name) -DurationSeconds 1 -OutDir $dest } # 两次实际安装钩子或注册Raw Input并自动退出。
    Write-Output "REPEAT_OK $name" # 第二次成功可排查类型重复和窗口生命周期问题。
} # 完成重复采集测试。
foreach ($file in Get-ChildItem $dest -Recurse -Filter '*log.csv') { # 核查默认采集是否遗漏键码隐私控制。
    foreach ($row in Import-Csv $file.FullName) { if ($row.VKey -and $row.VKey -ne '-') { throw "Unexpected key code in $($file.FullName)" } } # 默认情况下每条普通键码字段都必须隐藏。
} # 完成日志内容检查。
Write-Output 'VALIDATION_OK' # 所有断言通过才输出成功标记。
