$ErrorActionPreference = 'Stop' # 记录查询失败。
$reportRoot = $PSScriptRoot # 限定本地报告目录。
& dism.exe /Online /Cleanup-Image /AnalyzeComponentStore /English | Out-File (Join-Path $reportRoot 'component-store.txt') -Encoding utf8 # 只分析组件存储，不执行清理。
$LASTEXITCODE | Set-Content (Join-Path $reportRoot 'dism-exit.txt') # 记录退出码。
& fsutil.exe volume diskfree C: | Out-File (Join-Path $reportRoot 'diskfree.txt') -Encoding utf8 # 查询物理容量及保留空间。
& vssadmin.exe list shadowstorage | Out-File (Join-Path $reportRoot 'shadowstorage.txt') -Encoding utf8 # 查询卷影占用，不删除。
'Completed' | Set-Content (Join-Path $reportRoot 'done.txt') # 标记只读查询结束。
