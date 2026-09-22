<#
.SYNOPSIS
  Win11_App_RealTest.ps1 — 应用「实际跑出画面」验证器

.DESCRIPTION
  本脚本不检查「是否安装成功」，只检查「是否真的画得出来」。
  针对 Comet / Chromium 系浏览器黑屏，提供客观的像素级判定：
  截取窗口 -> 缩放取样 -> 计算平均亮度与相异色数 -> 判定是否黑屏。
  然后依序尝试一组渲染旗标，找出第一个能真正画出画面的组合。

  设计前提（承袭本仓库 CLAUDE.md 的硬性要求）：
    * 以一般使用者身分执行，不提权；需要管理员的动作只输出指令不代跑。
    * 不建议停用 亿赛通 CDG / Kaspersky / Defender，只输出加白名单所需资讯。
    * PATH 一律读注册表的持久值，不信任 $env:PATH 这个行程启动快照。
    * Windows PowerShell 5.1 传参给原生程式会吃掉内嵌引号，
      故所有外部程式呼叫一律用「阵列传参」，绝不拼接含引号的字串。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Win11_App_RealTest.ps1
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Win11_App_RealTest.ps1 -AppPath 'C:\Path\To\Comet.exe'
#>
# 启用 PowerShell 高级脚本参数绑定及所列功能。
[CmdletBinding()]
# 声明脚本或函数接受的参数及默认值。
param(
    # 声明参数 $AppPath的类型、默认值或校验规则。
    [string]$AppPath,
    # 声明参数 $OutDir的类型、默认值或校验规则。
    [string]$OutDir = (Join-Path $env:USERPROFILE ('AppRealTest_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))),
    # 声明参数 $WaitSeconds的类型、默认值或校验规则。
    [int]$WaitSeconds = 12,
    # 声明参数 $SkipWinget的类型、默认值或校验规则。
    [switch]$SkipWinget
# 结束此处的代码块、参数列表或集合定义。
)

# 设置本脚本遇到 PowerShell 错误时的处理方式。
$ErrorActionPreference = 'Continue'
# 创建指定目录、文件或配置项；丢弃不需要显示的输出。
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
# 创建指定类型的对象，并保存到 $script:Findings。
$script:Findings = New-Object System.Collections.ArrayList

# 定义 Add-Finding，封装此函数内的操作。
function Add-Finding {
    # 声明脚本或函数接受的参数及默认值。
    param([ValidateSet('严重','警告','注意','资讯')][string]$Level, [string]$Area, [string]$Message)
    # 继续当前表达式，补充参数、类型转换或结果处理。
    [void]$script:Findings.Add([pscustomobject]@{ Level = $Level; Area = $Area; Message = $Message })
    # 计算本行表达式并设置 $color，供后续步骤使用。
    $color = switch ($Level) { '严重' { 'Red' } '警告' { 'Yellow' } '注意' { 'Magenta' } default { 'Gray' } }
    # 向终端显示提示或结果。
    Write-Host ('  [' + $Level + '] ' + $Area + '：' + $Message) -ForegroundColor $color
# 结束此处的代码块、参数列表或集合定义。
}
# 定义 Section，封装此函数内的操作。
function Section { param([string]$T) Write-Host ''; Write-Host ('=== ' + $T + ' ===') -ForegroundColor Cyan }

# ---------------------------------------------------------------- Win32 互操作
# 原文块第 1 行：加载程序集或编译内嵌类型定义。
# 原文块第 2 行：在内嵌 C# 代码中引入 System 命名空间。
# 原文块第 3 行：在内嵌 C# 代码中引入 System.Runtime.InteropServices 命名空间。
# 原文块第 4 行：声明供 PowerShell 调用的 C# 辅助类型。
# 原文块第 5 行：继续当前表达式，补充参数、类型转换或结果处理。
# 原文块第 6 行：声明 Windows 原生接口的动态库导入规则。
# 原文块第 7 行：声明 Windows 原生接口的动态库导入规则。
# 原文块第 8 行：声明 Windows 原生接口的动态库导入规则。
# 原文块第 9 行：声明 Windows 原生接口的动态库导入规则。
# 原文块第 10 行：声明 Windows 原生接口的动态库导入规则。
# 原文块第 11 行：结束此处的代码块、参数列表或集合定义。
# 原文块第 12 行：提供当前表达式所需的文本、字段名称或列表元素。
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class W32 {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
}
'@ -ErrorAction SilentlyContinue
# 加载程序集或编译内嵌类型定义。
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

# 截取指定窗口，缩放后取样，回传亮度统计。这是「黑屏」的客观判据。
# 定义 Measure-WindowPixels，封装此函数内的操作。
function Measure-WindowPixels {
    # 声明脚本或函数接受的参数及默认值。
    param([IntPtr]$Handle, [int]$ChromeHeight = 90)

    # 创建指定类型的对象，并保存到 $r。
    $r = New-Object W32+RECT
    # 检查本行条件；满足时执行对应分支。
    if (-not [W32]::GetWindowRect($Handle, [ref]$r)) { return $null }
    # 计算本行表达式并设置 $w，供后续步骤使用。
    $w = $r.R - $r.L; $h = $r.B - $r.T
    # 检查本行条件；满足时执行对应分支。
    if ($w -le 50 -or $h -le 50) { return $null }

    # 创建指定类型的对象，并保存到 $bmp。
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    # 构造或计算 $g，保存本行指定的集合或索引结果。
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    # 开始受异常处理保护的操作。
    try { $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size $w, $h)) }
    # 捕获并处理前述操作抛出的异常。
    catch { $g.Dispose(); $bmp.Dispose(); return $null }
    # 释放对象持有的系统资源。
    $g.Dispose()

    # 内容区 = 扣掉顶端浏览器外框（分页列 + 网址列），才分得出「整窗黑」与「只有内容黑」
    # 构造或计算 $cy，保存本行指定的集合或索引结果。
    $cy = [Math]::Min($ChromeHeight, [int]($h / 3))
    # 计算本行表达式并设置 $ch，供后续步骤使用。
    $ch = $h - $cy
    # 创建指定类型的对象，并保存到 $content。
    $content = $bmp.Clone((New-Object System.Drawing.Rectangle 0, $cy, $w, $ch), $bmp.PixelFormat)

    # 定义 Get-Stats，封装此函数内的操作。
    function Get-Stats {
        # 声明脚本或函数接受的参数及默认值。
        param($Image)
        # 计算本行表达式并设置 $n，供后续步骤使用。
        $n = 64
        # 创建指定类型的对象，并保存到 $small。
        $small = New-Object System.Drawing.Bitmap $n, $n
        # 构造或计算 $sg，保存本行指定的集合或索引结果。
        $sg = [System.Drawing.Graphics]::FromImage($small)
        # 构造或计算 $sg.InterpolationMode，保存本行指定的集合或索引结果。
        $sg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
        # 调用 $sg.DrawImage，使用本行列出的输入完成对应操作。
        $sg.DrawImage($Image, 0, 0, $n, $n)
        # 释放对象持有的系统资源。
        $sg.Dispose()
        # 计算本行表达式并设置 $sum，供后续步骤使用。
        $sum = 0.0; $colors = @{}
        # 按本行的迭代范围或条件重复执行循环体。
        for ($y = 0; $y -lt $n; $y++) {
            # 按本行的迭代范围或条件重复执行循环体。
            for ($x = 0; $x -lt $n; $x++) {
                # 计算本行表达式并设置 $p，供后续步骤使用。
                $p = $small.GetPixel($x, $y)
                # 计算本行表达式并设置 $sum，供后续步骤使用。
                $sum += (0.2126 * $p.R + 0.7152 * $p.G + 0.0722 * $p.B)
                # 构造或计算 $colors[($p.R -shl 16) -bor ($p.G -shl 8) -bor $p.B]，保存本行指定的集合或索引结果。
                $colors[($p.R -shl 16) -bor ($p.G -shl 8) -bor $p.B] = 1
            # 结束此处的代码块、参数列表或集合定义。
            }
        # 结束此处的代码块、参数列表或集合定义。
        }
        # 释放对象持有的系统资源。
        $small.Dispose()
        # 返回本行结果并结束当前函数。
        return [pscustomobject]@{
            # 构造或计算 MeanLuma，保存本行指定的集合或索引结果。
            MeanLuma = [Math]::Round($sum / ($n * $n), 2)
            # 计算本行表达式并设置 Colors，供后续步骤使用。
            Colors   = $colors.Count
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }

    # 计算本行表达式并设置 $full，供后续步骤使用。
    $full = Get-Stats $bmp
    # 计算本行表达式并设置 $cont，供后续步骤使用。
    $cont = Get-Stats $content
    # 释放对象持有的系统资源。
    $content.Dispose(); $bmp.Dispose()

    # 返回本行结果并结束当前函数。
    return [pscustomobject]@{
        # 计算本行表达式并设置 Width，供后续步骤使用。
        Width = $w; Height = $h
        # 计算本行表达式并设置 FullLuma，供后续步骤使用。
        FullLuma = $full.MeanLuma; FullColors = $full.Colors
        # 计算本行表达式并设置 ContentLuma，供后续步骤使用。
        ContentLuma = $cont.MeanLuma; ContentColors = $cont.Colors
        # 判据：内容区平均亮度 < 12 且相异色数 <= 3 => 黑屏
        # 计算本行表达式并设置 IsBlack，供后续步骤使用。
        IsBlack = ($cont.MeanLuma -lt 12 -and $cont.Colors -le 3)
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# 用指定旗标启动一次，量测，然后收干净
# 定义 Test-LaunchProfile，封装此函数内的操作。
function Test-LaunchProfile {
    # 声明脚本或函数接受的参数及默认值。
    param([string]$Exe, [string[]]$Flags, [string]$Label, [string]$Profile)

    # 向终端显示提示或结果。
    Write-Host ('  -> 测试：' + $Label) -ForegroundColor White
    # 组合父目录与子路径，并保存到 $udd。
    $udd = Join-Path $OutDir ('ud_' + $Profile)
    # 构造或计算 $argList，保存本行指定的集合或索引结果。
    $argList = @(('--user-data-dir=' + $udd), '--no-first-run', '--no-default-browser-check',
              # 提供当前表达式所需的文本、字段名称或列表元素。
              '--new-window', 'about:blank') + $Flags

    # 计算本行表达式并设置 $p，供后续步骤使用。
    $p = $null
    # 开始受异常处理保护的操作。
    try { $p = Start-Process -FilePath $Exe -ArgumentList $argList -PassThru -ErrorAction Stop }
    # 捕获并处理前述操作抛出的异常。
    catch { Write-Host ('     启动失败：' + $_.Exception.Message) -ForegroundColor Red; return $null }

    # 构造或计算 $hwnd，保存本行指定的集合或索引结果。
    $hwnd = [IntPtr]::Zero
    # 生成当前时间或格式化时间戳，并保存到 $deadline。
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    # 按本行的迭代范围或条件重复执行循环体。
    while ((Get-Date) -lt $deadline) {
        # 等待指定时间后继续。
        Start-Sleep -Milliseconds 700
        # 开始受异常处理保护的操作。
        try { $p.Refresh() } catch { break }
        # 检查本行条件；满足时执行对应分支。
        if ($p.HasExited) { break }
        # 检查本行条件；满足时执行对应分支。
        if ($p.MainWindowHandle -ne [IntPtr]::Zero -and [W32]::IsWindowVisible($p.MainWindowHandle)) {
            # 计算本行表达式并设置 $hwnd，供后续步骤使用。
            $hwnd = $p.MainWindowHandle; break
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }

    # 构造或计算 $result，保存本行指定的集合或索引结果。
    $result = [pscustomobject]@{
        # 计算本行表达式并设置 Label，供后续步骤使用。
        Label = $Label; Flags = ($Flags -join ' '); Rendered = $false; Detail = ''
    # 结束此处的代码块、参数列表或集合定义。
    }

    # 检查本行条件；满足时执行对应分支。
    if ($hwnd -eq [IntPtr]::Zero) {
        # 检查子进程是否已经退出，并保存到 $result.Detail。
        $result.Detail = if ($p.HasExited) { '行程已退出，未产生窗口' } else { '逾时未取得可见窗口' }
    # 结束上一代码块并进入另一条件分支。
    } else {
        # 检查本行条件；满足时执行对应分支。
        if ([W32]::IsIconic($hwnd)) { [void][W32]::ShowWindow($hwnd, 9) }
        # 继续当前表达式，补充参数、类型转换或结果处理。
        [void][W32]::SetForegroundWindow($hwnd)
        Start-Sleep -Seconds 3   # 等 compositor 真的画完一帧
        # 计算本行表达式并设置 $m，供后续步骤使用。
        $m = Measure-WindowPixels -Handle $hwnd
        # 检查本行条件；满足时执行对应分支。
        if ($null -eq $m) {
            # 计算本行表达式并设置 $result.Detail，供后续步骤使用。
            $result.Detail = '无法截取窗口'
        # 结束上一代码块并进入另一条件分支。
        } else {
            # 计算本行表达式并设置 $result.Rendered，供后续步骤使用。
            $result.Rendered = (-not $m.IsBlack)
            # 计算本行表达式并设置 $result.Detail，供后续步骤使用。
            $result.Detail = ('内容区亮度=' + $m.ContentLuma + ' 相异色=' + $m.ContentColors +
                              # 提供当前表达式所需的文本、字段名称或列表元素。
                              ' / 全窗亮度=' + $m.FullLuma + ' 相异色=' + $m.FullColors +
                              # 提供当前表达式所需的文本、字段名称或列表元素。
                              ' / ' + $m.Width + 'x' + $m.Height)
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束此处的代码块、参数列表或集合定义。
    }

    # 开始受异常处理保护的操作。
    try { if (-not $p.HasExited) { $p.CloseMainWindow() | Out-Null; Start-Sleep -Seconds 2 } } catch { }
    # 开始受异常处理保护的操作。
    try { Get-Process -Id $p.Id -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue } catch { }
    # 等待指定时间后继续。
    Start-Sleep -Seconds 1

    # 计算本行表达式并设置 $mark，供后续步骤使用。
    $mark = if ($result.Rendered) { '有画面' } else { '黑屏/无画面' }
    # 计算本行表达式并设置 $col，供后续步骤使用。
    $col  = if ($result.Rendered) { 'Green' } else { 'Red' }
    # 向终端显示提示或结果。
    Write-Host ('     结果：' + $mark + '  (' + $result.Detail + ')') -ForegroundColor $col
    # 返回本行结果并结束当前函数。
    return $result
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================ 0. 系统身分
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '0. 系统身分（确认是否真的已升上 Windows 11）'
# 计算本行表达式并设置 $cv，供后续步骤使用。
$cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
# 定义 Get-Reg，封装此函数内的操作。
function Get-Reg { param($P, $N) try { (Get-ItemProperty -Path $P -Name $N -ErrorAction Stop).$N } catch { $null } }

# 构造或计算 $build，保存本行指定的集合或索引结果。
$build     = [int](Get-Reg $cv 'CurrentBuild')
# 计算本行表达式并设置 $ubr，供后续步骤使用。
$ubr       = Get-Reg $cv 'UBR'
# 计算本行表达式并设置 $dispVer，供后续步骤使用。
$dispVer   = Get-Reg $cv 'DisplayVersion'
# 计算本行表达式并设置 $prodName，供后续步骤使用。
$prodName  = Get-Reg $cv 'ProductName'
# 查询 Windows 管理接口中的设备或系统信息，并保存到 $osCim。
$osCim     = Get-CimInstance Win32_OperatingSystem

# 向终端显示提示或结果。
Write-Host ('  注册表 ProductName ：' + $prodName)
# 向终端显示提示或结果。
Write-Host ('  CIM Caption        ：' + $osCim.Caption)
# 向终端显示提示或结果。
Write-Host ('  Build              ：' + $build + '.' + $ubr + '   DisplayVersion：' + $dispVer)

# 关键陷阱：Win11 就地升级后，注册表 ProductName 常仍留着 "Windows 10"。
# 唯一可靠判据是 Build >= 22000，绝不可用字串比对。
# 检查本行条件；满足时执行对应分支。
if ($build -ge 22000) {
    # 追加一项诊断发现。
    Add-Finding '资讯' '系统' ('已确认为 Windows 11（Build ' + $build + '）。注意：注册表 ProductName 仍写「' + $prodName + '」是就地升级的已知现象，不代表升级失败；请一律以 Build>=22000 判定。')
    # 检查本行条件；满足时执行对应分支。
    if ($prodName -match 'Windows 10') {
        # 追加一项诊断发现。
        Add-Finding '注意' '系统' '旧脚本 Win10_Diagnose_v2.ps1 第 126 行用 $os.Caption -match ''Windows 10'' 判定系统，在此机器上会误判。已在本轮修正说明中列出。'
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束上一代码块并进入另一条件分支。
} else {
    # 追加一项诊断发现。
    Add-Finding '严重' '系统' ('Build ' + $build + ' < 22000，系统仍是 Windows 10，升级未生效。')
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================ 1. GPU 真相
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '1. GPU 与驱动（Comet 黑屏的第一嫌疑）'
# 查询 Windows 管理接口中的设备或系统信息，并保存到 $gpus。
$gpus = Get-CimInstance Win32_VideoController |
        # 选取记录中的指定字段或条目。
        Select-Object Name, DriverVersion, DriverDate, Status, AdapterRAM, VideoModeDescription
# 处理 $gpus 所指定的操作或当前表达式的后续部分。
$gpus | Format-List
# 组合父目录与子路径；将记录导出为 CSV 文件。
$gpus | Export-Csv (Join-Path $OutDir '01_GPU.csv') -NoTypeInformation -Encoding UTF8

# 按本行的迭代范围或条件重复执行循环体。
foreach ($g in @($gpus)) {
    # 检查本行条件；满足时执行对应分支。
    if ($g.Name -match 'Basic Display|Microsoft Basic') {
        # 追加一项诊断发现。
        Add-Finding '严重' 'GPU' 'Windows 正在使用「Microsoft 基本显示卡」，代表升级后 NVIDIA 驱动未载入。此状态下 Chromium 系浏览器几乎必定黑屏。'
        # 跳过本次循环余下操作。
        continue
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 检查本行条件；满足时执行对应分支。
    if ($g.Name -notmatch 'NVIDIA') { continue }

    # 由 Windows 驱动版本反解 NVIDIA 版本号：取末 5 码 -> xxx.xx
    # 计算本行表达式并设置 $digits，供后续步骤使用。
    $digits = ($g.DriverVersion -replace '\.', '')
    # 检查本行条件；满足时执行对应分支。
    if ($digits.Length -ge 5) {
        # 计算本行表达式并设置 $tail，供后续步骤使用。
        $tail = $digits.Substring($digits.Length - 5, 5)
        # 构造或计算 $nv，保存本行指定的集合或索引结果。
        $nv = [double]($tail.Substring(0,3) + '.' + $tail.Substring(3,2))
        # 向终端显示提示或结果。
        Write-Host ('  NVIDIA 驱动实际版本：' + $nv + '   （Windows 版本字串 ' + $g.DriverVersion + '）')

        # 追加一项诊断发现。
        Add-Finding '注意' 'GPU' ('驱动版本 ' + $nv + '；仅凭显卡名称或驱动年份不能确定架构、可用驱动或黑屏原因。GT 730 有不同硬件版本；本机 2026-09-21 实读 PCI ID 10DE:0F02，不能套用 Kepler 472.xx 更新建议。由 IT 按 PCI ID 和厂商支持清单核对。')
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================ 2. 找出 Comet
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '2. 定位 Comet 可执行档'
# 构造或计算 $candidates，保存本行指定的集合或索引结果。
$candidates = @()
# 检查本行条件；满足时执行对应分支。
if ($AppPath) { $candidates += $AppPath }
# 按条件筛选输入记录，并保存到 $roots。
$roots = @($env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:APPDATA) | Where-Object { $_ }
# 按本行的迭代范围或条件重复执行循环体。
foreach ($r in $roots) {
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($sub in @('Perplexity\Comet\Application\Comet.exe', 'Comet\Application\Comet.exe', 'Perplexity\Comet\Comet.exe')) {
        # 组合父目录与子路径，并保存到 $p。
        $p = Join-Path $r $sub
        # 检查本行条件；满足时执行对应分支。
        if (Test-Path $p) { $candidates += $p }
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}
# 注册表 App Paths 与解除安装键也查一遍
# 按本行的迭代范围或条件重复执行循环体。
foreach ($hive in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                    # 提供当前表达式所需的文本、字段名称或列表元素。
                    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                    # 提供当前表达式所需的文本、字段名称或列表元素。
                    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
    # 读取注册表或对象的属性。
    Get-ItemProperty $hive -ErrorAction SilentlyContinue |
        # 按条件筛选输入记录。
        Where-Object { $_.DisplayName -match 'Comet|Perplexity' } |
        # 逐项处理管道传入的记录。
        ForEach-Object {
            # 向终端显示提示或结果。
            Write-Host ('  注册表登载：' + $_.DisplayName + '  版本 ' + $_.DisplayVersion)
            # 检查本行条件；满足时执行对应分支。
            if ($_.InstallLocation -and (Test-Path $_.InstallLocation)) {
                # 枚举指定位置的文件、目录或注册表项。
                Get-ChildItem $_.InstallLocation -Filter 'Comet.exe' -Recurse -ErrorAction SilentlyContinue |
                    # 逐项处理管道传入的记录。
                    ForEach-Object { $candidates += $_.FullName }
            # 结束此处的代码块、参数列表或集合定义。
            }
        # 结束此处的代码块、参数列表或集合定义。
        }
# 结束此处的代码块、参数列表或集合定义。
}
# 检查目标路径是否存在；选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $exe。
$exe = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

# 检查本行条件；满足时执行对应分支。
if (-not $exe) {
    # 追加一项诊断发现。
    Add-Finding '严重' 'Comet' '找不到 Comet.exe。请用 -AppPath 参数指定完整路径后重跑。'
# 结束上一代码块并进入另一条件分支。
} else {
    # 计算本行表达式并设置 $fv，供后续步骤使用。
    $fv = (Get-Item $exe).VersionInfo
    # 向终端显示提示或结果。
    Write-Host ('  找到：' + $exe) -ForegroundColor Green
    # 向终端显示提示或结果。
    Write-Host ('  档案版本：' + $fv.FileVersion + '   产品版本：' + $fv.ProductVersion)
    # 追加一项诊断发现。
    Add-Finding '资讯' 'Comet' ('可执行档 ' + $exe + '，版本 ' + $fv.FileVersion)
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================ 3. 黑屏实测
# 检查本行条件；满足时执行对应分支。
if ($exe) {
    # 处理 Section 所指定的操作或当前表达式的后续部分。
    Section '3. 黑屏客观实测（逐一旗标，量测像素）'
    # 向终端显示提示或结果。
    Write-Host '  判据：内容区平均亮度 < 12 且相异色数 <= 3 => 判定黑屏' -ForegroundColor DarkGray
    # 向终端显示提示或结果。
    Write-Host '  测试期间请勿遮挡弹出的窗口（截图取的是萤幕实际像素）' -ForegroundColor Yellow
    # 等待指定时间后继续。
    Start-Sleep -Seconds 2

    # 构造或计算 $profiles，保存本行指定的集合或索引结果。
    $profiles = @(
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ L = 'A 预设（重现问题）';            F = @();                                      P = 'a' },
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ L = 'B 关闭 GPU 沙箱（测 DLP 拦截）'; F = @('--disable-gpu-sandbox');                P = 'b' },
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ L = 'C 关闭 GPU 合成';              F = @('--disable-gpu-compositing');            P = 'c' },
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ L = 'D 完全关闭 GPU';               F = @('--disable-gpu');                        P = 'd' },
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ L = 'E ANGLE 走 SwiftShader 软算';   F = @('--use-angle=swiftshader');              P = 'e' },
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ L = 'F ANGLE 走 D3D9 旧路径';        F = @('--use-angle=d3d9');                     P = 'f' },
        # 处理 @{ 所指定的操作或当前表达式的后续部分。
        @{ L = 'G 关 DirectComposition';       F = @('--disable-features=DirectComposition'); P = 'g' }
    # 结束此处的代码块、参数列表或集合定义。
    )

    # 构造或计算 $results，保存本行指定的集合或索引结果。
    $results = @()
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($pr in $profiles) {
        # 计算本行表达式并设置 $r，供后续步骤使用。
        $r = Test-LaunchProfile -Exe $exe -Flags $pr.F -Label $pr.L -Profile $pr.P
        # 检查本行条件；满足时执行对应分支。
        if ($r) { $results += $r }
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 组合父目录与子路径；将记录导出为 CSV 文件。
    $results | Export-Csv (Join-Path $OutDir '02_BlackScreenTest.csv') -NoTypeInformation -Encoding UTF8

    # 选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $baseline。
    $baseline = $results | Where-Object { $_.Label -like 'A *' } | Select-Object -First 1
    # 选取记录中的指定字段或条目；按条件筛选输入记录，并保存到 $works。
    $works    = $results | Where-Object { $_.Rendered -and $_.Label -notlike 'A *' } | Select-Object -First 1

    # 向终端显示提示或结果。
    Write-Host ''
    # 检查本行条件；满足时执行对应分支。
    if ($baseline -and $baseline.Rendered) {
        # 追加一项诊断发现。
        Add-Finding '资讯' 'Comet' '预设启动即可正常算绘，本次未重现黑屏。若你仍看到黑屏，可能只发生在特定网页或特定时机，请带着该网址重跑本脚本。'
    # 结束上一代码块并进入另一条件分支。
    } elseif ($works) {
        # 追加一项诊断发现。
        Add-Finding '严重' 'Comet' ('黑屏已重现（预设旗标）。确认为算绘路径问题，非应用本身损毁。')
        # 追加一项诊断发现。
        Add-Finding '资讯' 'Comet' ('第一个能画出画面的旗标组合：「' + $works.Label + '」 -> ' + $works.Flags)
        # 检查本行条件；满足时执行对应分支。
        if ($works.Flags -match 'gpu-sandbox') {
            # 追加一项诊断发现。
            Add-Finding '注意' '资安' 'GPU 沙箱关闭后即正常，强烈指向常驻的透明加密／DLP（亿赛通 CDG）或防毒挂钩注入了 GPU 行程。正解是请 IT 把 Comet.exe 加入白名单，不要自行停用任何资安软体。'
        # 结束上一代码块并进入另一条件分支。
        } else {
            # 追加一项诊断发现。
            Add-Finding '注意' 'Comet' '绕过硬体算绘后即正常，与 GPU 驱动过旧的推论一致。根治仍是升级显卡驱动。'
        # 结束此处的代码块、参数列表或集合定义。
        }
    # 结束上一代码块并进入另一条件分支。
    } else {
        # 追加一项诊断发现。
        Add-Finding '严重' 'Comet' '所有旗标组合皆无法画出画面。问题可能不在算绘层（例如安装损毁、设定档损坏、或安全软体直接阻挡行程）。请见报告建议。'
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================ 4. 其余软体版本
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '4. 其余软体：安装清单与最新版落差'
# 构造或计算 $installed，保存本行指定的集合或索引结果。
$installed = foreach ($hive in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                 # 提供当前表达式所需的文本、字段名称或列表元素。
                                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                 # 提供当前表达式所需的文本、字段名称或列表元素。
                                 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
    # 读取注册表或对象的属性。
    Get-ItemProperty $hive -ErrorAction SilentlyContinue |
        # 按条件筛选输入记录。
        Where-Object { $_.DisplayName } |
        # 选取记录中的指定字段或条目。
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
# 结束此处的代码块、参数列表或集合定义。
}
# 按指定属性排序输入记录，并保存到 $installed。
$installed = $installed | Sort-Object DisplayName -Unique
# 向终端显示提示或结果。
Write-Host ('  注册表登载软体数：' + @($installed).Count)
# 组合父目录与子路径；将记录导出为 CSV 文件。
$installed | Export-Csv (Join-Path $OutDir '03_Installed.csv') -NoTypeInformation -Encoding UTF8

# 检查本行条件；满足时执行对应分支。
if (-not $SkipWinget) {
    # 查找当前环境可用的命令及其位置；调用 WinGet 执行本行指定的软件管理操作，并保存到 $winget。
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    # 检查本行条件；满足时执行对应分支。
    if ($winget) {
        # 向终端显示提示或结果；调用 WinGet 执行本行指定的软件管理操作。
        Write-Host '  执行 winget upgrade（这是「是否最新版」的唯一客观判据）...'
        # 阵列传参，避开 PS 5.1 吃掉内嵌引号的陷阱
        # 组合父目录与子路径；调用 WinGet 执行本行指定的软件管理操作，并保存到 $wgOut。
        $wgOut = Join-Path $OutDir '04_winget_upgrade.txt'
        # 调用 WinGet 执行本行指定的软件管理操作。
        & winget upgrade --include-unknown --accept-source-agreements 2>&1 |
            # 处理 Tee-Object 所指定的操作或当前表达式的后续部分。
            Tee-Object -FilePath $wgOut | Out-Host
        # 调用 WinGet 执行本行指定的软件管理操作；追加一项诊断发现。
        Add-Finding '资讯' '版本' ('winget 可升级清单已写入 ' + $wgOut + '。请逐项核对，勿一次全升。')
    # 结束上一代码块并进入另一条件分支。
    } else {
        # 调用 WinGet 执行本行指定的软件管理操作；追加一项诊断发现。
        Add-Finding '注意' '版本' 'winget 不存在，无法客观比对最新版。可由 Microsoft Store 安装「应用程式安装程式」取得。'
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================ 5. PATH 持久值
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '5. PATH（读注册表持久值，非行程快照）'
# 读取指定作用域的环境变量，并保存到 $userPath。
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
# 读取指定作用域的环境变量，并保存到 $machPath。
$machPath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
# 组合父目录与子路径。
$userPath | Out-File (Join-Path $OutDir '05_PATH_user.txt') -Encoding UTF8
# 组合父目录与子路径。
$machPath | Out-File (Join-Path $OutDir '05_PATH_machine.txt') -Encoding UTF8
# 按条件筛选输入记录；向终端显示提示或结果。
Write-Host ('  使用者 PATH 项目数：' + @($userPath -split ';' | Where-Object { $_ }).Count)
# 按条件筛选输入记录；向终端显示提示或结果。
Write-Host ('  系统   PATH 项目数：' + @($machPath -split ';' | Where-Object { $_ }).Count)
# 按本行的迭代范围或条件重复执行循环体。
foreach ($seg in @(($userPath + ';' + $machPath) -split ';')) {
    # 检查本行条件；满足时执行对应分支。
    if ($seg -match 'rtools' -and $seg -match 'usr\\bin') {
        # 追加一项诊断发现。
        Add-Finding '警告' 'PATH' ('PATH 含 ' + $seg + '：Rtools 的 usr\bin 会用 sh/find/sort 盖掉 Windows 内建同名指令，且 R 是靠注册表找 Rtools，不需要 PATH。建议移除。')
    # 结束此处的代码块、参数列表或集合定义。
    }
# 结束此处的代码块、参数列表或集合定义。
}

# ================================================================ 报告
# 处理 Section 所指定的操作或当前表达式的后续部分。
Section '报告'
# 创建指定类型的对象，并保存到 $sb。
$sb = New-Object System.Text.StringBuilder
# 生成当前时间或格式化时间戳；向报告缓冲区追加一行文本。
[void]$sb.AppendLine('应用实际算绘验证报告   ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('主机：' + $env:COMPUTERNAME)
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('系统：' + $prodName + ' / Caption ' + $osCim.Caption + ' / Build ' + $build + '.' + $ubr)
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('')
# 按本行的迭代范围或条件重复执行循环体。
foreach ($lv in @('严重','警告','注意','资讯')) {
    # 按条件筛选输入记录，并保存到 $rows。
    $rows = @($script:Findings | Where-Object { $_.Level -eq $lv })
    # 检查本行条件；满足时执行对应分支。
    if ($rows.Count -eq 0) { continue }
    # 向报告缓冲区追加一行文本。
    [void]$sb.AppendLine('【' + $lv + '】')
    # 按本行的迭代范围或条件重复执行循环体。
    foreach ($r in $rows) { [void]$sb.AppendLine('  - ' + $r.Area + '：' + $r.Message) }
    # 向报告缓冲区追加一行文本。
    [void]$sb.AppendLine('')
# 结束此处的代码块、参数列表或集合定义。
}
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('--- 需要管理员权限、请自行手动执行 ---')
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('1) 先由 IT 核对显卡 PCI 硬件 ID、架构及 Windows 11 驱动支持；不可仅凭 GT 730 名称选择 472.xx。')
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('   本机 10DE:0F02 为旧型 Fermi；不要强装其他架构驱动。')
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('   黑屏根因仍需对照应用、日志及厂商诊断，不能单凭驱动年份下结论。')
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('2) 若需请 IT 加白名单，提供下列资讯：')
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('   程式路径：' + $(if ($exe) { $exe } else { '(未定位)' }))
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('   需放行：GPU 行程建立、DirectComposition 呈现、本机 user-data-dir 读写')
# 向报告缓冲区追加一行文本。
[void]$sb.AppendLine('')
# 组合父目录与子路径。
$sb.ToString() | Out-File (Join-Path $OutDir '00_报告.txt') -Encoding UTF8
# 向终端显示提示或结果。
Write-Host $sb.ToString()
# 向终端显示提示或结果。
Write-Host ('所有输出位于：' + $OutDir) -ForegroundColor Green
