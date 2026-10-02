$ErrorActionPreference = 'Stop' # 遇到写入错误停止，不冒充完成。
$taskEvidenceDir = Split-Path -Parent $PSCommandPath # 仅使用本次脚本所在证据目录。
$taskDownloadDir = 'C:\Users\PPCCpcpc\Downloads' # 用户已指定的下载位置。
$taskMapping = @{'游戏下载清单.csv'='大秦赋算筹_游戏下载清单_20261002.csv';'游戏下载结果.md'='大秦赋算筹_游戏下载结果_20261002.md'} # 保持清单与游戏包名称不同。
foreach ($taskSourceName in $taskMapping.Keys) { # 逐项复制结果，既有文件不覆盖。
    $taskSourcePath = Join-Path $taskEvidenceDir $taskSourceName # 工作区内已生成的结果。
    $taskTargetPath = Join-Path $taskDownloadDir $taskMapping[$taskSourceName] # 仅写用户指定目录。
    if (Test-Path -LiteralPath $taskTargetPath) { throw "Existing file preserved: $taskTargetPath" } # 不覆盖个人文件。
    Copy-Item -LiteralPath $taskSourcePath -Destination $taskTargetPath -ErrorAction Stop # 复制可审阅清单，不运行任何安装包。
    Get-Item -LiteralPath $taskTargetPath | Select-Object FullName,Length # 验证真实文件。
} # 结束两项清单发布。
$taskLandingPath = Join-Path $taskDownloadDir 'WuhuiHuaxia_official.apk.part' # 仅指向本轮下载脚本创建的失败网页。
$taskLandingEvidence = Join-Path $taskEvidenceDir 'whhx-download-landing.html' # 将网页保存为正确的证据类型。
if ((Test-Path -LiteralPath $taskLandingPath) -and -not (Test-Path -LiteralPath $taskLandingEvidence)) { # 保留已下载的网页证据，不删除用户文件。
    $taskLandingFile = Get-Item -LiteralPath $taskLandingPath # 核验已知临时文件大小。
    if ($taskLandingFile.Length -ne 1353) { throw 'Unexpected landing file; preserved' } # 不移动内容不符的文件。
    Move-Item -LiteralPath $taskLandingPath -Destination $taskLandingEvidence -ErrorAction Stop # 单文件移动至证据目录，不递归、不改变游戏包。
} # 完成已知失败网页整理。
Get-PSDrive -Name C | Select-Object Free # 保存完成后的真实可用空间。
