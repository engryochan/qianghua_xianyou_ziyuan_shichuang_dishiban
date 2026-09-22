#Requires -Version 5.1
# 启用 PowerShell 高级脚本参数绑定及所列功能。
[CmdletBinding()]
# 声明脚本或函数接受的参数及默认值。
param([string]$OutputDirectory=(Join-Path $PSScriptRoot '..\reports\2026-09-21\update-round2'))
# 设置本脚本遇到 PowerShell 错误时的处理方式。
$ErrorActionPreference='Stop'
# 把报告输出目录转换为完整绝对路径。
$out=[IO.Path]::GetFullPath($OutputDirectory)
# 创建指定目录、文件或配置项；将不需要的返回值丢弃。
$null=New-Item -ItemType Directory -Path $out -Force
# 创建指定类型的对象，并保存到 $rows。
$rows=New-Object System.Collections.Generic.List[object]
# Exact products already installed and found by winget upgrade. No force or reboot flag.
# 构造或计算 $ids，保存本行指定的集合或索引结果。
$ids=@('MoonshotAI.Kimi','Microsoft.Teams','JetBrains.PyCharm','Adobe.Acrobat.Reader.64-bit','Microsoft.Edge','Microsoft.VCRedist.2015+.x64','Microsoft.VCRedist.2015+.x86')
# 按本行的迭代范围或条件重复执行循环体。
foreach ($id in $ids) {
    # 生成当前时间或格式化时间戳；向终端显示提示或结果。
    Write-Host ('Updating '+$id+' at '+(Get-Date -Format o))
    # 组合父目录与子路径，并保存到 $file。
    $file=Join-Path $out ($id+'.log')
    # 调用 WinGet 执行本行指定的软件管理操作。
    & winget upgrade --id $id --exact --source winget --silent --accept-source-agreements --accept-package-agreements --disable-interactivity *> $file
    # 将上一操作的退出状态记录到 $code。
    $code=$LASTEXITCODE
    # 生成当前时间或格式化时间戳。
    $rows.Add([pscustomobject]@{Id=$id;ExitCode=$code;Finished=(Get-Date -Format o);Log=$file})
    # 组合父目录与子路径；将内容写入目标文件；把对象序列化为 JSON。
    $rows | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $out 'apps-install-results.json') -Encoding UTF8
    # 向终端显示提示或结果。
    Write-Host ('Exit='+$code+' '+$id)
    # 读取文件内容供后续处理；向终端显示提示或结果。
    Get-Content -LiteralPath $file -Tail 6 | Write-Host
# 结束此处的代码块、参数列表或集合定义。
}
# 组合父目录与子路径；调用 WinGet 执行本行指定的软件管理操作。
& winget upgrade --source winget --accept-source-agreements --disable-interactivity *> (Join-Path $out 'winget-after.txt')
# 读取文件内容供后续处理；组合父目录与子路径；调用 WinGet 执行本行指定的软件管理操作。
Get-Content (Join-Path $out 'winget-after.txt') -Tail 25
