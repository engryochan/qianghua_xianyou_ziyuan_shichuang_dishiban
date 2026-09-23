#Requires -Version 5.1
# 定义采集参数及边界。
param([ValidateRange(1,600)][int]$DurationSeconds=30, [switch]$RecordKeyCodes, [switch]$CompileOnly, [string]$OutDir=(Join-Path $env:TEMP 'KbdDiag'))
# 执行本地诊断或资源清理，不修改系统配置。
$ErrorActionPreference='Stop'
# 复用已修正的Raw Input采集器，避免维护两个不同的原生消息循环。
# 执行本地诊断或资源清理，不修改系统配置。
& (Join-Path $PSScriptRoot 'Diag-RawInputDevice.ps1') -DurationSeconds $DurationSeconds -RecordKeyCodes:$RecordKeyCodes -CompileOnly:$CompileOnly -OutDir $OutDir
