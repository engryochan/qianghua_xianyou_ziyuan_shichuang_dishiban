$ErrorActionPreference = 'Stop' # 不把部分复制当成更新成功。
$taskEvidenceDir = Split-Path -Parent $PSCommandPath # 只使用本次证据目录。
$taskDownloadDir = 'C:\Users\PPCCpcpc\Downloads' # 用户指定的下载目录。
$taskMapping = @{'游戏下载清单.csv'='大秦赋算筹_游戏下载清单_20261002.csv';'游戏下载结果.md'='大秦赋算筹_游戏下载结果_20261002.md'} # 更新实际处理结果而非伪造游戏包。
foreach ($taskSourceName in $taskMapping.Keys) { # 对两份报告逐项备份及更新。
    $taskSourcePath = Join-Path $taskEvidenceDir $taskSourceName # 读取新核查结果。
    $taskTargetPath = Join-Path $taskDownloadDir $taskMapping[$taskSourceName] # 确定现有报告的绝对位置。
    $taskBackupPath = $taskTargetPath + '.before-followup.bak' # 保存上一轮原文，允许追溯与恢复。
    if ((Test-Path -LiteralPath $taskTargetPath) -and -not (Test-Path -LiteralPath $taskBackupPath)) { Copy-Item -LiteralPath $taskTargetPath -Destination $taskBackupPath -ErrorAction Stop } # 不覆盖已有备份。
    Copy-Item -LiteralPath $taskSourcePath -Destination $taskTargetPath -Force -ErrorAction Stop # 只更新本轮生成的两份清单，不改其他文件。
    Get-Item -LiteralPath $taskTargetPath | Select-Object FullName,Length # 验证更新后的真实文件。
} # 结束报告更新，不安装或执行游戏。
