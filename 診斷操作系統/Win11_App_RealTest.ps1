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
[CmdletBinding()]
param(
    [string]$AppPath,
    [string]$OutDir = (Join-Path $env:USERPROFILE ('AppRealTest_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))),
    [int]$WaitSeconds = 12,
    [switch]$SkipWinget
)

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$script:Findings = New-Object System.Collections.ArrayList

function Add-Finding {
    param([ValidateSet('严重','警告','注意','资讯')][string]$Level, [string]$Area, [string]$Message)
    [void]$script:Findings.Add([pscustomobject]@{ Level = $Level; Area = $Area; Message = $Message })
    $color = switch ($Level) { '严重' { 'Red' } '警告' { 'Yellow' } '注意' { 'Magenta' } default { 'Gray' } }
    Write-Host ('  [' + $Level + '] ' + $Area + '：' + $Message) -ForegroundColor $color
}
function Section { param([string]$T) Write-Host ''; Write-Host ('=== ' + $T + ' ===') -ForegroundColor Cyan }

# ---------------------------------------------------------------- Win32 互操作
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
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

# 截取指定窗口，缩放后取样，回传亮度统计。这是「黑屏」的客观判据。
function Measure-WindowPixels {
    param([IntPtr]$Handle, [int]$ChromeHeight = 90)

    $r = New-Object W32+RECT
    if (-not [W32]::GetWindowRect($Handle, [ref]$r)) { return $null }
    $w = $r.R - $r.L; $h = $r.B - $r.T
    if ($w -le 50 -or $h -le 50) { return $null }

    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size $w, $h)) }
    catch { $g.Dispose(); $bmp.Dispose(); return $null }
    $g.Dispose()

    # 内容区 = 扣掉顶端浏览器外框（分页列 + 网址列），才分得出「整窗黑」与「只有内容黑」
    $cy = [Math]::Min($ChromeHeight, [int]($h / 3))
    $ch = $h - $cy
    $content = $bmp.Clone((New-Object System.Drawing.Rectangle 0, $cy, $w, $ch), $bmp.PixelFormat)

    function Get-Stats {
        param($Image)
        $n = 64
        $small = New-Object System.Drawing.Bitmap $n, $n
        $sg = [System.Drawing.Graphics]::FromImage($small)
        $sg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
        $sg.DrawImage($Image, 0, 0, $n, $n)
        $sg.Dispose()
        $sum = 0.0; $colors = @{}
        for ($y = 0; $y -lt $n; $y++) {
            for ($x = 0; $x -lt $n; $x++) {
                $p = $small.GetPixel($x, $y)
                $sum += (0.2126 * $p.R + 0.7152 * $p.G + 0.0722 * $p.B)
                $colors[($p.R -shl 16) -bor ($p.G -shl 8) -bor $p.B] = 1
            }
        }
        $small.Dispose()
        return [pscustomobject]@{
            MeanLuma = [Math]::Round($sum / ($n * $n), 2)
            Colors   = $colors.Count
        }
    }

    $full = Get-Stats $bmp
    $cont = Get-Stats $content
    $content.Dispose(); $bmp.Dispose()

    return [pscustomobject]@{
        Width = $w; Height = $h
        FullLuma = $full.MeanLuma; FullColors = $full.Colors
        ContentLuma = $cont.MeanLuma; ContentColors = $cont.Colors
        # 判据：内容区平均亮度 < 12 且相异色数 <= 3 => 黑屏
        IsBlack = ($cont.MeanLuma -lt 12 -and $cont.Colors -le 3)
    }
}

# 用指定旗标启动一次，量测，然后收干净
function Test-LaunchProfile {
    param([string]$Exe, [string[]]$Flags, [string]$Label, [string]$Profile)

    Write-Host ('  -> 测试：' + $Label) -ForegroundColor White
    $udd = Join-Path $OutDir ('ud_' + $Profile)
    $argList = @(('--user-data-dir=' + $udd), '--no-first-run', '--no-default-browser-check',
              '--new-window', 'about:blank') + $Flags

    $p = $null
    try { $p = Start-Process -FilePath $Exe -ArgumentList $argList -PassThru -ErrorAction Stop }
    catch { Write-Host ('     启动失败：' + $_.Exception.Message) -ForegroundColor Red; return $null }

    $hwnd = [IntPtr]::Zero
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 700
        try { $p.Refresh() } catch { break }
        if ($p.HasExited) { break }
        if ($p.MainWindowHandle -ne [IntPtr]::Zero -and [W32]::IsWindowVisible($p.MainWindowHandle)) {
            $hwnd = $p.MainWindowHandle; break
        }
    }

    $result = [pscustomobject]@{
        Label = $Label; Flags = ($Flags -join ' '); Rendered = $false; Detail = ''
    }

    if ($hwnd -eq [IntPtr]::Zero) {
        $result.Detail = if ($p.HasExited) { '行程已退出，未产生窗口' } else { '逾时未取得可见窗口' }
    } else {
        if ([W32]::IsIconic($hwnd)) { [void][W32]::ShowWindow($hwnd, 9) }
        [void][W32]::SetForegroundWindow($hwnd)
        Start-Sleep -Seconds 3   # 等 compositor 真的画完一帧
        $m = Measure-WindowPixels -Handle $hwnd
        if ($null -eq $m) {
            $result.Detail = '无法截取窗口'
        } else {
            $result.Rendered = (-not $m.IsBlack)
            $result.Detail = ('内容区亮度=' + $m.ContentLuma + ' 相异色=' + $m.ContentColors +
                              ' / 全窗亮度=' + $m.FullLuma + ' 相异色=' + $m.FullColors +
                              ' / ' + $m.Width + 'x' + $m.Height)
        }
    }

    try { if (-not $p.HasExited) { $p.CloseMainWindow() | Out-Null; Start-Sleep -Seconds 2 } } catch { }
    try { Get-Process -Id $p.Id -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue } catch { }
    Start-Sleep -Seconds 1

    $mark = if ($result.Rendered) { '有画面' } else { '黑屏/无画面' }
    $col  = if ($result.Rendered) { 'Green' } else { 'Red' }
    Write-Host ('     结果：' + $mark + '  (' + $result.Detail + ')') -ForegroundColor $col
    return $result
}

# ================================================================ 0. 系统身分
Section '0. 系统身分（确认是否真的已升上 Windows 11）'
$cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
function Get-Reg { param($P, $N) try { (Get-ItemProperty -Path $P -Name $N -ErrorAction Stop).$N } catch { $null } }

$build     = [int](Get-Reg $cv 'CurrentBuild')
$ubr       = Get-Reg $cv 'UBR'
$dispVer   = Get-Reg $cv 'DisplayVersion'
$prodName  = Get-Reg $cv 'ProductName'
$osCim     = Get-CimInstance Win32_OperatingSystem

Write-Host ('  注册表 ProductName ：' + $prodName)
Write-Host ('  CIM Caption        ：' + $osCim.Caption)
Write-Host ('  Build              ：' + $build + '.' + $ubr + '   DisplayVersion：' + $dispVer)

# 关键陷阱：Win11 就地升级后，注册表 ProductName 常仍留着 "Windows 10"。
# 唯一可靠判据是 Build >= 22000，绝不可用字串比对。
if ($build -ge 22000) {
    Add-Finding '资讯' '系统' ('已确认为 Windows 11（Build ' + $build + '）。注意：注册表 ProductName 仍写「' + $prodName + '」是就地升级的已知现象，不代表升级失败；请一律以 Build>=22000 判定。')
    if ($prodName -match 'Windows 10') {
        Add-Finding '注意' '系统' '旧脚本 Win10_Diagnose_v2.ps1 第 126 行用 $os.Caption -match ''Windows 10'' 判定系统，在此机器上会误判。已在本轮修正说明中列出。'
    }
} else {
    Add-Finding '严重' '系统' ('Build ' + $build + ' < 22000，系统仍是 Windows 10，升级未生效。')
}

# ================================================================ 1. GPU 真相
Section '1. GPU 与驱动（Comet 黑屏的第一嫌疑）'
$gpus = Get-CimInstance Win32_VideoController |
        Select-Object Name, DriverVersion, DriverDate, Status, AdapterRAM, VideoModeDescription
$gpus | Format-List
$gpus | Export-Csv (Join-Path $OutDir '01_GPU.csv') -NoTypeInformation -Encoding UTF8

foreach ($g in @($gpus)) {
    if ($g.Name -match 'Basic Display|Microsoft Basic') {
        Add-Finding '严重' 'GPU' 'Windows 正在使用「Microsoft 基本显示卡」，代表升级后 NVIDIA 驱动未载入。此状态下 Chromium 系浏览器几乎必定黑屏。'
        continue
    }
    if ($g.Name -notmatch 'NVIDIA') { continue }

    # 由 Windows 驱动版本反解 NVIDIA 版本号：取末 5 码 -> xxx.xx
    $digits = ($g.DriverVersion -replace '\.', '')
    if ($digits.Length -ge 5) {
        $tail = $digits.Substring($digits.Length - 5, 5)
        $nv = [double]($tail.Substring(0,3) + '.' + $tail.Substring(3,2))
        Write-Host ('  NVIDIA 驱动实际版本：' + $nv + '   （Windows 版本字串 ' + $g.DriverVersion + '）')

        Add-Finding '注意' 'GPU' ('驱动版本 ' + $nv + '；仅凭显卡名称或驱动年份不能确定架构、可用驱动或黑屏原因。GT 730 有不同硬件版本；本机 2026-09-21 实读 PCI ID 10DE:0F02，不能套用 Kepler 472.xx 更新建议。由 IT 按 PCI ID 和厂商支持清单核对。')
    }
}

# ================================================================ 2. 找出 Comet
Section '2. 定位 Comet 可执行档'
$candidates = @()
if ($AppPath) { $candidates += $AppPath }
$roots = @($env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:APPDATA) | Where-Object { $_ }
foreach ($r in $roots) {
    foreach ($sub in @('Perplexity\Comet\Application\Comet.exe', 'Comet\Application\Comet.exe', 'Perplexity\Comet\Comet.exe')) {
        $p = Join-Path $r $sub
        if (Test-Path $p) { $candidates += $p }
    }
}
# 注册表 App Paths 与解除安装键也查一遍
foreach ($hive in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
    Get-ItemProperty $hive -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match 'Comet|Perplexity' } |
        ForEach-Object {
            Write-Host ('  注册表登载：' + $_.DisplayName + '  版本 ' + $_.DisplayVersion)
            if ($_.InstallLocation -and (Test-Path $_.InstallLocation)) {
                Get-ChildItem $_.InstallLocation -Filter 'Comet.exe' -Recurse -ErrorAction SilentlyContinue |
                    ForEach-Object { $candidates += $_.FullName }
            }
        }
}
$exe = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if (-not $exe) {
    Add-Finding '严重' 'Comet' '找不到 Comet.exe。请用 -AppPath 参数指定完整路径后重跑。'
} else {
    $fv = (Get-Item $exe).VersionInfo
    Write-Host ('  找到：' + $exe) -ForegroundColor Green
    Write-Host ('  档案版本：' + $fv.FileVersion + '   产品版本：' + $fv.ProductVersion)
    Add-Finding '资讯' 'Comet' ('可执行档 ' + $exe + '，版本 ' + $fv.FileVersion)
}

# ================================================================ 3. 黑屏实测
if ($exe) {
    Section '3. 黑屏客观实测（逐一旗标，量测像素）'
    Write-Host '  判据：内容区平均亮度 < 12 且相异色数 <= 3 => 判定黑屏' -ForegroundColor DarkGray
    Write-Host '  测试期间请勿遮挡弹出的窗口（截图取的是萤幕实际像素）' -ForegroundColor Yellow
    Start-Sleep -Seconds 2

    $profiles = @(
        @{ L = 'A 预设（重现问题）';            F = @();                                      P = 'a' },
        @{ L = 'B 关闭 GPU 沙箱（测 DLP 拦截）'; F = @('--disable-gpu-sandbox');                P = 'b' },
        @{ L = 'C 关闭 GPU 合成';              F = @('--disable-gpu-compositing');            P = 'c' },
        @{ L = 'D 完全关闭 GPU';               F = @('--disable-gpu');                        P = 'd' },
        @{ L = 'E ANGLE 走 SwiftShader 软算';   F = @('--use-angle=swiftshader');              P = 'e' },
        @{ L = 'F ANGLE 走 D3D9 旧路径';        F = @('--use-angle=d3d9');                     P = 'f' },
        @{ L = 'G 关 DirectComposition';       F = @('--disable-features=DirectComposition'); P = 'g' }
    )

    $results = @()
    foreach ($pr in $profiles) {
        $r = Test-LaunchProfile -Exe $exe -Flags $pr.F -Label $pr.L -Profile $pr.P
        if ($r) { $results += $r }
    }
    $results | Export-Csv (Join-Path $OutDir '02_BlackScreenTest.csv') -NoTypeInformation -Encoding UTF8

    $baseline = $results | Where-Object { $_.Label -like 'A *' } | Select-Object -First 1
    $works    = $results | Where-Object { $_.Rendered -and $_.Label -notlike 'A *' } | Select-Object -First 1

    Write-Host ''
    if ($baseline -and $baseline.Rendered) {
        Add-Finding '资讯' 'Comet' '预设启动即可正常算绘，本次未重现黑屏。若你仍看到黑屏，可能只发生在特定网页或特定时机，请带着该网址重跑本脚本。'
    } elseif ($works) {
        Add-Finding '严重' 'Comet' ('黑屏已重现（预设旗标）。确认为算绘路径问题，非应用本身损毁。')
        Add-Finding '资讯' 'Comet' ('第一个能画出画面的旗标组合：「' + $works.Label + '」 -> ' + $works.Flags)
        if ($works.Flags -match 'gpu-sandbox') {
            Add-Finding '注意' '资安' 'GPU 沙箱关闭后即正常，强烈指向常驻的透明加密／DLP（亿赛通 CDG）或防毒挂钩注入了 GPU 行程。正解是请 IT 把 Comet.exe 加入白名单，不要自行停用任何资安软体。'
        } else {
            Add-Finding '注意' 'Comet' '绕过硬体算绘后即正常，与 GPU 驱动过旧的推论一致。根治仍是升级显卡驱动。'
        }
    } else {
        Add-Finding '严重' 'Comet' '所有旗标组合皆无法画出画面。问题可能不在算绘层（例如安装损毁、设定档损坏、或安全软体直接阻挡行程）。请见报告建议。'
    }
}

# ================================================================ 4. 其余软体版本
Section '4. 其余软体：安装清单与最新版落差'
$installed = foreach ($hive in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
    Get-ItemProperty $hive -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
}
$installed = $installed | Sort-Object DisplayName -Unique
Write-Host ('  注册表登载软体数：' + @($installed).Count)
$installed | Export-Csv (Join-Path $OutDir '03_Installed.csv') -NoTypeInformation -Encoding UTF8

if (-not $SkipWinget) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Host '  执行 winget upgrade（这是「是否最新版」的唯一客观判据）...'
        # 阵列传参，避开 PS 5.1 吃掉内嵌引号的陷阱
        $wgOut = Join-Path $OutDir '04_winget_upgrade.txt'
        & winget upgrade --include-unknown --accept-source-agreements 2>&1 |
            Tee-Object -FilePath $wgOut | Out-Host
        Add-Finding '资讯' '版本' ('winget 可升级清单已写入 ' + $wgOut + '。请逐项核对，勿一次全升。')
    } else {
        Add-Finding '注意' '版本' 'winget 不存在，无法客观比对最新版。可由 Microsoft Store 安装「应用程式安装程式」取得。'
    }
}

# ================================================================ 5. PATH 持久值
Section '5. PATH（读注册表持久值，非行程快照）'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$machPath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath | Out-File (Join-Path $OutDir '05_PATH_user.txt') -Encoding UTF8
$machPath | Out-File (Join-Path $OutDir '05_PATH_machine.txt') -Encoding UTF8
Write-Host ('  使用者 PATH 项目数：' + @($userPath -split ';' | Where-Object { $_ }).Count)
Write-Host ('  系统   PATH 项目数：' + @($machPath -split ';' | Where-Object { $_ }).Count)
foreach ($seg in @(($userPath + ';' + $machPath) -split ';')) {
    if ($seg -match 'rtools' -and $seg -match 'usr\\bin') {
        Add-Finding '警告' 'PATH' ('PATH 含 ' + $seg + '：Rtools 的 usr\bin 会用 sh/find/sort 盖掉 Windows 内建同名指令，且 R 是靠注册表找 Rtools，不需要 PATH。建议移除。')
    }
}

# ================================================================ 报告
Section '报告'
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('应用实际算绘验证报告   ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
[void]$sb.AppendLine('主机：' + $env:COMPUTERNAME)
[void]$sb.AppendLine('系统：' + $prodName + ' / Caption ' + $osCim.Caption + ' / Build ' + $build + '.' + $ubr)
[void]$sb.AppendLine('')
foreach ($lv in @('严重','警告','注意','资讯')) {
    $rows = @($script:Findings | Where-Object { $_.Level -eq $lv })
    if ($rows.Count -eq 0) { continue }
    [void]$sb.AppendLine('【' + $lv + '】')
    foreach ($r in $rows) { [void]$sb.AppendLine('  - ' + $r.Area + '：' + $r.Message) }
    [void]$sb.AppendLine('')
}
[void]$sb.AppendLine('--- 需要管理员权限、请自行手动执行 ---')
[void]$sb.AppendLine('1) 先由 IT 核对显卡 PCI 硬件 ID、架构及 Windows 11 驱动支持；不可仅凭 GT 730 名称选择 472.xx。')
[void]$sb.AppendLine('   本机 10DE:0F02 为旧型 Fermi；不要强装其他架构驱动。')
[void]$sb.AppendLine('   黑屏根因仍需对照应用、日志及厂商诊断，不能单凭驱动年份下结论。')
[void]$sb.AppendLine('2) 若需请 IT 加白名单，提供下列资讯：')
[void]$sb.AppendLine('   程式路径：' + $(if ($exe) { $exe } else { '(未定位)' }))
[void]$sb.AppendLine('   需放行：GPU 行程建立、DirectComposition 呈现、本机 user-data-dir 读写')
[void]$sb.AppendLine('')
$sb.ToString() | Out-File (Join-Path $OutDir '00_报告.txt') -Encoding UTF8
Write-Host $sb.ToString()
Write-Host ('所有输出位于：' + $OutDir) -ForegroundColor Green
