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
# 创建指定类型的对象，并保存到 $session。
$session=New-Object -ComObject Microsoft.Update.Session
# 为 Windows Update 会话设置可识别的客户端名称。
$session.ClientApplicationID='Local workstation verification'
# 从当前更新会话创建搜索器，沿用本机更新来源配置。
$searcher=$session.CreateUpdateSearcher()
# Keep configured update service and all enterprise policy. No public-service override.
# 搜索尚未安装且未隐藏的适用更新，并保存结果。
$result=$searcher.Search("IsInstalled=0 and IsHidden=0")
# 构造或计算 $rows，保存本行指定的集合或索引结果。
$rows=@(foreach($u in $result.Updates) {
    # 把本行列出的字段组成结构化记录。
    [pscustomobject]@{Title=$u.Title;Identity=$u.Identity.UpdateID;Revision=$u.Identity.RevisionNumber;Type=[int]$u.Type;Downloaded=$u.IsDownloaded;EulaAccepted=$u.EulaAccepted;MaxDownloadSize=$u.MaxDownloadSize;RebootBehavior=[int]$u.InstallationBehavior.RebootBehavior}
# 结束此处的代码块、参数列表或集合定义。
})
# 把本行列出的字段组成结构化记录，并按后续管道保存或输出。
[pscustomobject]@{CheckedAt=(Get-Date -Format o);ResultCode=[int]$result.ResultCode;Count=$rows.Count;Updates=$rows} | ConvertTo-Json -Depth 5 | Tee-Object -FilePath (Join-Path $out 'windows-update-scan.json')
