#Requires -Version 5.1
<#
.SYNOPSIS
  驅動程式全機盤點（唯讀）。產出可直接附在 IT 工單上的報告。
.DESCRIPTION
  完全唯讀：不安裝、不更新、不移除任何驅動，也不修改任何設定。
  只做四件事：
    1. 列出硬體基礎（主機板 / BIOS / 晶片組 / 顯示卡 PCI ID）
    2. 找出驅動缺失或異常的裝置，附完整硬體 ID
    3. 列出第三方驅動的版本與日期，標出明顯老舊者
    4. 以唯讀方式查詢 Windows Update 有無可用驅動

  為什麼不直接安裝：
    - 驅動安裝需要系統管理員權限
    - 安裝驅動須自廠商網站下載並執行安裝程式，在有 DLP／端點防護的
      公司資產上，這應當事先取得同意
    - 驅動與韌體屬於 IT 管理範圍，貿然更新可能與公司標準映像衝突
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Driver_Report.ps1
.EXAMPLE
  .\Driver_Report.ps1 -OutDir C:\work\tmp   # 另存一份文字報告
#>
# 启用 PowerShell 高级脚本参数绑定及所列功能。
[CmdletBinding()]
# 声明脚本或函数接受的参数及默认值。
param([string]$OutDir)

# 处理 Set-StrictMode 所指定的操作或当前表达式的后续部分。
Set-StrictMode -Off
# 设置本脚本遇到 PowerShell 错误时的处理方式。
$ErrorActionPreference = 'Continue'
# 开始受异常处理保护的操作。
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# 创建指定类型的对象，并保存到 $sb。
$sb = New-Object System.Text.StringBuilder
# 定义 Say，封装此函数内的操作。
function Say { param([string]$T, [string]$C = 'Gray') Write-Host $T -ForegroundColor $C; [void]$sb.AppendLine($T) }
# 定义 Head，封装此函数内的操作。
function Head { param([string]$T) Say '' ; Say ('=== ' + $T + ' ===') 'Cyan' }

# 生成当前时间或格式化时间戳。
Say ('驅動程式盤點（唯讀）  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
# 处理 Say 所指定的操作或当前表达式的后续部分。
Say ('主機：' + $env:COMPUTERNAME)

# ---------------------------------------------------------------- 1. 硬體基礎
# 处理 Head 所指定的操作或当前表达式的后续部分。
Head '1. 硬體基礎'
# 查询 Windows 管理接口中的设备或系统信息，并保存到 $bb。
$bb = Get-CimInstance Win32_BaseBoard
# 查询 Windows 管理接口中的设备或系统信息，并保存到 $bios。
$bios = Get-CimInstance Win32_BIOS
# 查询 Windows 管理接口中的设备或系统信息；选取记录中的指定字段或条目，并保存到 $cpu。
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
# 读取注册表或对象的属性，并保存到 $cv。
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
# 处理 Say 所指定的操作或当前表达式的后续部分。
Say ('主機板   : ' + $bb.Manufacturer + ' ' + $bb.Product + ' (' + $bb.Version + ')')
# 处理 Say 所指定的操作或当前表达式的后续部分。
Say ('BIOS     : ' + $bios.Manufacturer + ' ' + $bios.SMBIOSBIOSVersion + '  發行日 ' + ([datetime]$bios.ReleaseDate).ToString('yyyy-MM-dd'))
# 处理 Say 所指定的操作或当前表达式的后续部分。
Say ('CPU      : ' + $cpu.Name)
# 处理 Say 所指定的操作或当前表达式的后续部分。
Say ('OS       : Build ' + $cv.CurrentBuild + '.' + $cv.UBR + '（>=22000 即為 Windows 11）')

# 处理 Head 所指定的操作或当前表达式的后续部分。
Head '2. 顯示卡（含 PCI ID —— 判斷世代必須看 ID，不能看卡名）'
# 按本行的迭代范围或条件重复执行循环体。
foreach ($g in @(Get-CimInstance Win32_VideoController)) {
    # 处理 Say 所指定的操作或当前表达式的后续部分。
    Say ('名稱     : ' + $g.Name)
    # 处理 Say 所指定的操作或当前表达式的后续部分。
    Say ('PCI ID   : ' + $g.PNPDeviceID)
    # 处理 Say 所指定的操作或当前表达式的后续部分。
    Say ('驅動版本 : ' + $g.DriverVersion + '   日期 ' + ([datetime]$g.DriverDate).ToString('yyyy-MM-dd'))
    # NVIDIA 的 Windows 驅動版本字串要取末 5 碼重組才是對外版本號
    # 检查本行条件；满足时执行对应分支。
    if ($g.DriverVersion -match '(\d+)\.(\d+)\.(\d+)\.(\d+)$') {
        # 计算本行表达式并设置 $digits，供后续步骤使用。
        $digits = ($g.DriverVersion -replace '\D', '')
        # 检查本行条件；满足时执行对应分支。
        if ($digits.Length -ge 5) {
            # 计算本行表达式并设置 $last5，供后续步骤使用。
            $last5 = $digits.Substring($digits.Length - 5)
            # 处理 Say 所指定的操作或当前表达式的后续部分。
            Say ('對外版本 : ' + $last5.Substring(0, 3) + '.' + $last5.Substring(3) + '（由末 5 碼反解）')
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 检查本行条件；满足时执行对应分支。
    if ($g.PNPDeviceID -match 'DEV_0F02') {
        # 处理 Say 所指定的操作或当前表达式的后续部分。
        Say '判定     : GF108 核心，屬 Fermi 世代（GT 730 另有 Kepler GK208 版本，不能依卡名推定）' 'Yellow'
        # 处理 Say 所指定的操作或当前表达式的后续部分。
        Say '           NVIDIA 對 Fermi 的最後一版驅動為 391.35（2018-03），2019-01 起連安全修補都停止。' 'Yellow'
        # 处理 Say 所指定的操作或当前表达式的后续部分。
        Say '           此卡在軟體層面已到頂，沒有更新版可裝；唯一出路是更換硬體。' 'Yellow'
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 处理 Say 所指定的操作或当前表达式的后续部分。
    Say ''
# 结束此处的代码块、参数列表或集合定义。
}

# ---------------------------------------------------------------- 3. 異常裝置
# 处理 Head 所指定的操作或当前表达式的后续部分。
Head '3. 驅動缺失或異常的裝置'
# 必須排除 CM_PROB_PHANTOM：那是「曾經接過、現在不在」的裝置快取
# （拔掉的螢幕、未實體化的 Microsoft 串流代理等），不是驅動問題。
# 不濾掉的話 4 個真問題會被灌水成 10 個，送到 IT 手上只是浪費對方時間。
# 读取即插即用设备及其当前状态；按条件筛选输入记录，并保存到 $all。
$all = @(Get-PnpDevice | Where-Object { $_.Problem -and $_.Problem -ne 'CM_PROB_NONE' })
# 按条件筛选输入记录，并保存到 $phantom。
$phantom = @($all | Where-Object { $_.Problem -eq 'CM_PROB_PHANTOM' })
# 按条件筛选输入记录，并保存到 $bad。
$bad = @($all | Where-Object { $_.Problem -ne 'CM_PROB_PHANTOM' })
# 检查本行条件；满足时执行对应分支。
if ($phantom.Count) {
    # 处理 Say 所指定的操作或当前表达式的后续部分。
    Say ('（另有 ' + $phantom.Count + ' 個 CM_PROB_PHANTOM 裝置已排除——那是已移除裝置的快取紀錄，不是驅動問題）') 'DarkGray'
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if ($bad.Count -eq 0) {
    # 处理 Say 所指定的操作或当前表达式的后续部分。
    Say '無（所有在線裝置驅動正常）' 'Green'
# 结束上一代码块并进入另一条件分支。
} else {
    # 处理 Say 所指定的操作或当前表达式的后续部分。
    Say ('共 ' + $bad.Count + ' 個，以下為完整硬體 ID，可直接貼給 IT 或用於查找驅動：') 'Yellow'
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($d in $bad) {
        # 处理 Say 所指定的操作或当前表达式的后续部分。
        Say ''
        # 处理 Say 所指定的操作或当前表达式的后续部分。
        Say ('  裝置     : ' + $(if ($d.FriendlyName) { $d.FriendlyName } else { '(無名稱)' }))
        # 处理 Say 所指定的操作或当前表达式的后续部分。
        Say ('  狀態     : ' + $d.Status + '  /  ' + $d.Problem)
        # 处理 Say 所指定的操作或当前表达式的后续部分。
        Say ('  InstanceId: ' + $d.InstanceId)
        # 读取即插即用设备及其当前状态，并保存到 $hw。
        $hw = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction SilentlyContinue).Data
        # 检查本行条件；满足时执行对应分支。
        if ($hw) { Say ('  HardwareIds: ' + ($hw -join ' | ')) }
        # 读取即插即用设备及其当前状态，并保存到 $loc。
        $loc = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_LocationInfo' -ErrorAction SilentlyContinue).Data
        # 检查本行条件；满足时执行对应分支。
        if ($loc) { Say ('  位置     : ' + $loc) }
        # 检查本行条件；满足时执行对应分支。
        if ($d.InstanceId -match 'VEN_8086') { Say '  來源     : Intel 裝置，通常由 Intel Chipset Device Software (INF Update Utility) 提供' }
        # 检查本行条件；满足时执行对应分支。
        if ($d.InstanceId -match 'INTC1056') { Say '  來源     : Intel 動態調校 (DPTF) 驅動' }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ---------------------------------------------------------------- 4. 第三方驅動清單
# 处理 Head 所指定的操作或当前表达式的后续部分。
Head '4. 第三方驅動版本與日期（依日期由舊到新）'
# 查询 Windows 管理接口中的设备或系统信息，并保存到 $drv。
$drv = Get-CimInstance Win32_PnPSignedDriver |
    # 按条件筛选输入记录。
    Where-Object { $_.DeviceName -and $_.DriverProviderName -and $_.DriverProviderName -notmatch '^Microsoft$' } |
    # 选取记录中的指定字段或条目。
    Select-Object @{n = '裝置'; e = { $_.DeviceName } },
    # 处理 @{n 所指定的操作或当前表达式的后续部分。
    @{n = '廠商'; e = { $_.DriverProviderName } },
    # 处理 @{n 所指定的操作或当前表达式的后续部分。
    @{n = '版本'; e = { $_.DriverVersion } },
    # 处理 @{n 所指定的操作或当前表达式的后续部分。
    @{n = '日期'; e = { if ($_.DriverDate) { ([datetime]$_.DriverDate).ToString('yyyy-MM-dd') } else { '' } } } |
    # 按指定属性排序输入记录。
    Sort-Object 日期
# 把结果排版成表格；把结果转换为文本。
Say (($drv | Format-Table -AutoSize | Out-String -Width 200).TrimEnd())

# 生成当前时间或格式化时间戳；按条件筛选输入记录，并保存到 $old。
$old = @($drv | Where-Object { $_.日期 -and [datetime]$_.日期 -lt (Get-Date).AddYears(-5) })
# 检查本行条件；满足时执行对应分支。
if ($old.Count) {
    # 处理 Say 所指定的操作或当前表达式的后续部分。
    Say ''
    # 处理 Say 所指定的操作或当前表达式的后续部分。
    Say ('以下 ' + $old.Count + ' 項驅動已超過 5 年，值得評估更新（但不代表故障）：') 'Yellow'
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($o in $old) { Say ('  ' + $o.日期 + '  ' + $o.裝置 + '  ' + $o.版本) }
# 结束此处的代码块、参数列表或集合定义。
}

# ---------------------------------------------------------------- 5. Windows Update
# 处理 Head 所指定的操作或当前表达式的后续部分。
Head '5. Windows Update 有無可用驅動（唯讀查詢，不安裝）'
# 开始受异常处理保护的操作。
try {
    # 创建指定类型的对象，并保存到 $ses。
    $ses = New-Object -ComObject Microsoft.Update.Session
    # 计算本行表达式并设置 $sea，供后续步骤使用。
    $sea = $ses.CreateUpdateSearcher()
    # 计算本行表达式并设置 $res，供后续步骤使用。
    $res = $sea.Search("IsInstalled=0 and Type='Driver'")
    # 处理 Say 所指定的操作或当前表达式的后续部分。
    Say ('可用驅動更新：' + $res.Updates.Count + ' 筆')
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($u in $res.Updates) { Say ('  - ' + $u.Title + '  (' + [math]::Round($u.MaxDownloadSize / 1MB, 1) + ' MB)') }
    # 计算本行表达式并设置 $res2，供后续步骤使用。
    $res2 = $sea.Search("IsInstalled=0")
    # 处理 Say 所指定的操作或当前表达式的后续部分。
    Say ('所有可用更新：' + $res2.Updates.Count + ' 筆')
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($u in $res2.Updates) { Say ('  - ' + $u.Title) }
    # 检查本行条件；满足时执行对应分支。
    if ($res.Updates.Count -eq 0) {
        # 处理 Say 所指定的操作或当前表达式的后续部分。
        Say ''
        # 处理 Say 所指定的操作或当前表达式的后续部分。
        Say '注意：Windows Update 回報 0 筆，但這不代表第 3 節的缺失裝置會被補上。' 'Yellow'
        # 处理 Say 所指定的操作或当前表达式的后续部分。
        Say '      晶片組 INF 驅動通常不經 Windows Update 派送，須由主機板廠或 Intel 官方安裝。' 'Yellow'
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束上一代码块并进入异常处理。
} catch {
    # 处理 Say 所指定的操作或当前表达式的后续部分。
    Say ('查詢失敗：0x' + ('{0:X}' -f $_.Exception.HResult) + ' —— ' + $_.Exception.Message) 'Yellow'
    # 处理 Say 所指定的操作或当前表达式的后续部分。
    Say '若為 0x80244011，多半是暫時性錯誤，重試通常即可。'
# 结束此处的代码块、参数列表或集合定义。
}

# ---------------------------------------------------------------- 6. 更新政策
# 处理 Head 所指定的操作或当前表达式的后续部分。
Head '6. 更新相關政策（影響驅動與功能更新的取得）'
# 计算本行表达式并设置 $wu，供后续步骤使用。
$wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
# 检查本行条件；满足时执行对应分支。
if (Test-Path $wu) {
    # 读取注册表或对象的属性，并保存到 $p。
    $p = Get-ItemProperty $wu
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($n in ($p.PSObject.Properties.Name | Where-Object { $_ -notlike 'PS*' })) {
        # 处理 Say 所指定的操作或当前表达式的后续部分。
        Say ('  ' + $n + ' = ' + $p.$n)
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 检查本行条件；满足时执行对应分支。
    if ($p.TargetReleaseProductVersion -and [int]$cv.CurrentBuild -ge 22000 -and $p.TargetReleaseProductVersion -match 'Windows 10') {
        # 处理 Say 所指定的操作或当前表达式的后续部分。
        Say ''
        # 处理 Say 所指定的操作或当前表达式的后续部分。
        Say '★ 政策把版本鎖定在 Windows 10，但本機已是 Windows 11。' 'Yellow'
        # 处理 Say 所指定的操作或当前表达式的后续部分。
        Say '  這條政策已名實不符，可能影響後續功能更新。建議交由 IT 確認是否清除——' 'Yellow'
        # 处理 Say 所指定的操作或当前表达式的后续部分。
        Say '  屬群組原則層級設定，且可能是公司統一派送，不應自行更動。' 'Yellow'
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束上一代码块并进入另一条件分支。
} else { Say '  無 WindowsUpdate 政策機碼' }
# 读取注册表或对象的属性。
Say ('  WSUS 伺服器：' + $(if ((Get-ItemProperty $wu -ErrorAction SilentlyContinue).WUServer) { (Get-ItemProperty $wu).WUServer } else { '（未設定，使用公開 Windows Update）' }))

# ---------------------------------------------------------------- 結語
# 处理 Head 所指定的操作或当前表达式的后续部分。
Head '本報告的界線'
# 处理 Say 所指定的操作或当前表达式的后续部分。
Say '本腳本完全唯讀，未安裝、未更新、未移除任何驅動，也未修改任何設定。'
# 处理 Say 所指定的操作或当前表达式的后续部分。
Say '需要更新的項目請交由具管理員權限者處理，並建議先經 IT 確認，理由：'
# 处理 Say 所指定的操作或当前表达式的后续部分。
Say '  1. 驅動安裝需系統管理員權限'
# 处理 Say 所指定的操作或当前表达式的后续部分。
Say '  2. 須自廠商網站下載並執行安裝程式，在有 DLP／端點防護的公司資產上應先取得同意'
# 处理 Say 所指定的操作或当前表达式的后续部分。
Say '  3. 驅動與韌體屬 IT 管理範圍，可能與公司標準映像或資產管理衝突'

# 检查本行条件；满足时执行对应分支。
if ($OutDir) {
    # 检查本行条件；满足时执行对应分支。
    if (-not (Test-Path $OutDir)) { $null = New-Item -ItemType Directory -Path $OutDir -Force }
    # 生成当前时间或格式化时间戳；组合父目录与子路径，并保存到 $f。
    $f = Join-Path $OutDir ('Driver_Report_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.txt')
    # 将内容写入目标文件。
    Set-Content -Path $f -Value $sb.ToString() -Encoding UTF8
    # 向终端显示提示或结果。
    Write-Host ''
    # 向终端显示提示或结果。
    Write-Host ('報告另存：' + $f) -ForegroundColor Green
# 结束此处的代码块、参数列表或集合定义。
}
