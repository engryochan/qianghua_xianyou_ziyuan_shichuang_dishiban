# 新旧主机对比评估：海兰 MiniPC T1（新）vs 华硕原机（旧）

> **2026-10-05 本轮复核说明（优先于下方历史评语）**：本报告保留早先章节作为历史记录，新增第十三节为本轮只读诊断与纠错的有效结论。当前已用约 **43.56%**，并未超过一半；目录逻辑大小不能等同独占磁盘占用，未核实差额不能认定为还原点；CPU“算力一比一”、双通道“已成立”、显卡“显著改善”、DLP“必然阻断升级”、可回收“39 GiB”等早先断言均须按第十三节收窄。此次仅新增或修改仓库报告及复核脚本，未修改系统、固件、安防、执行策略，也未安装软件。
**日期**：2026-10-05
**采集方式**：全程只读（未改动任何系统设置）。以普通用户身份执行，无法提权。
**新机数据来源**：本机实测（CIM/WMI、注册表、递归目录扫描、.NET 微基准）。
**旧机数据来源**：本仓库 `reports/2026-09-21/`（2026-09-21 08:11 采集）、`reports/2026-09-21/completion/`、`DxDiag.txt`（2026-09-19 导出）。

---

## 一、结论先行

1. **「视窗十版占掉一半空间」这个说法不成立。** 238 GiB 的盘已用 103.47 GiB，但真正归属 Windows 本体的只有约 31 GiB；另外 17.7 GiB 是休眠文件 + 分页文件（可配置），约 11.6 GiB 是系统还原点，剩下 43 GiB 是 Office、Chrome、WPS、安装包和用户资料。**`C:\Windows.old` 是个空壳（0 个文件），不是元凶。**
2. **标称 256 GB 与显示 238 GiB 的差额不是被占用，是进制换算。** 256,060,514,304 字节 ÷ 1024³ = 238.47 GiB，再扣 EFI 分区 300 MiB 与 MSR 16 MiB，C: 得 238.16 GiB。
3. **CPU 完全没变**：旧机 i5-12400F 与新机 i5-12400 是同一颗硅片，差别仅在后者带核显。算力一比一。
4. **真正退步的是内存频率与操作系统世代**：DDR4-3200 → DDR4-2667（−17%），Windows 11 25H2 → Windows 10 22H2（且被组策略钉死）。
5. **真正进步的是显示链路**：GT 730 配 2018 年的 391.35 驱动 → Intel UHD 730 配 2026-06 的 32.0.101.7088 驱动。本仓库 CLAUDE.md 里那条「8 年前的旧驱动」隐患，到此自然消失。
6. **最大的遗留瓶颈原封不动搬了过来**：依然是 256 GB 的 SATA SSD。旧机到最后只剩 59.92 GB，新机现在剩 134.70 GB——装回同一套 R + Python 工具链和套件后，会很快回到同一个窘境。

---

## 二、新主机实测设备信息

### 2.1 整机与主板

| 项目 | 实测值 |
|---|---|
| 主机名 | `SHJ-H0647-Ryochan` |
| 制造商 / 型号 | MiniPC / T1 |
| 机箱类型 | ChassisTypes = 13（一体式 / All-in-One 形态） |
| 主板 | Intel H610I Chipset |
| BIOS | American Megatrends 5.27，发布日期 2025-07-29 |
| 序列号 / 资产标签 | 均为 `Default string`（OEM 未写入） |

### 2.2 处理器

| 项目 | 实测值 |
|---|---|
| 型号 | 12th Gen Intel Core **i5-12400**（非 F，**带核显**） |
| 架构标识 | Intel64 Family 6 Model 151 Stepping 5（Alder Lake） |
| 核心 / 线程 | 6 核 / 12 线程（全 P-core，无 E-core） |
| 基准频率 | 2500 MHz |
| L2 / L3 缓存 | 7,680 KB / 18,432 KB |
| 虚拟化固件 | 已启用；SLAT（二级地址转换）支持 |

### 2.3 内存

| 插槽 | 容量 | 频率 | 类型 | 厂商 / 型号 |
|---|---|---|---|---|
| Controller0-ChannelA-DIMM0 | 16 GB | 2667 MT/s | DDR4 SO-DIMM | Heoriady（PartNumber 为空） |
| Controller1-ChannelA-DIMM0 | 16 GB | 2667 MT/s | DDR4 SO-DIMM | `HAILAN 8WNB 16G 2666` |

- 总计 32 GB（`TotalPhysicalMemory` = 34,117,074,944 B），**双通道已成立**（分属两个控制器）。
- `SMBIOSMemoryType = 26` → DDR4；`FormFactor = 12` → SO-DIMM（笔记本条）。
- **插槽 2/2 已占满**，主板上限 64 GB。要扩容必须整套换条，不能加装。
- **两条是不同品牌的混插**，但同规格同频，当前稳定运行于 2667 MT/s。

### 2.4 显示与音频

| 项目 | 实测值 |
|---|---|
| 显示适配器 | Intel UHD Graphics 730（核显，系统内唯一显示设备） |
| PCI ID | `VEN_8086&DEV_4692&SUBSYS_22128086&REV_0C` |
| 驱动版本 / 日期 | **32.0.101.7088 / 2026-06-17** |
| 当前分辨率 | 1920 × 1080 |
| 显示器 | XYM `F2725B`（2025 年）—— **与旧机是同一台显示器** |
| 音频 | High Definition Audio 设备（板载，状态 OK） |

### 2.5 存储

| 项目 | 实测值 |
|---|---|
| 物理盘 | `HAILAN 256G`，SSD，**SATA** 总线，固件 X1226A0 |
| 容量 | 256,060,514,304 B = 238.47 GiB |
| 健康状态 | Healthy |
| 控制器 | 标准 SATA AHCI 控制器（**系统侧未见 NVMe 控制器**） |
| 分区表 | ① EFI 系统分区 300 MiB ② MSR 保留 16 MiB ③ C: 238.16 GiB |
| **无独立恢复分区** | WinRE 应位于 `C:\Recovery`（该目录无权限读取） |

> `Get-StorageReliabilityCounter` 未返回数据——该 SSD 未暴露 SMART 磨损/通电时长计数，**无法评估寿命余量**。

### 2.6 网络

| 项目 | 实测值 |
|---|---|
| 网卡 | Realtek PCIe GbE Family Controller #2 |
| 链路速率 | 1 Gbps |
| 域 | WORKGROUP（未加域） |

### 2.7 操作系统与策略

| 项目 | 实测值 |
|---|---|
| 版本 | Microsoft Windows 10 专业版，**22H2，Build 19045.7725** |
| 安装时间 | **2026-07-30 17:37:56** |
| 授权 | Windows Pro，VOLUME_KMSCLIENT 通道，`LicenseStatus = 1`（已激活） |
| **版本锁定策略** | `TargetReleaseVersion = 1`、`TargetReleaseVersionInfo = 22H2` ← **被组策略钉在 Win10 22H2，不会收到 Win11** |
| ESU 扩展支持 | 映像内含 24 个 ESU SKU，**激活数 = 0** |
| 最近补丁 | KB5122878 / KB5122877（2026-10-05）、KB5034441 / KB5126256（2026-10-04） |
| 电源方案 | **平衡**（`381b4222-…`） |
| LongPathsEnabled | **0（未启用）** |
| 快速启动 | `HiberbootEnabled = 0`（关闭），但休眠文件仍存在 |
| 分页文件 | 自动管理，当前 5120 MB |
| 待重启标记 | CBS = False，WU = False，**PendingFileRenameOperations = True** |
| Hypervisor | `HypervisorPresent = False` |

### 2.8 已装软件与常驻安防

已登记软件 **29 条**（旧机为 86 条），主要为：Microsoft Office 专业增强版 2016（16.0.19127.20800）、WPS Office 2019、Chrome 154、Edge 150、Firefox 153、Git 2.55.0.5、GitHub Desktop 3.6.6、WinRAR 7.23、PotPlayer、YeeChat、OneDrive。

**三层常驻安防（与旧机同款，全部已就位）**：

| 产品 | 版本 | 进程 / 路径 |
|---|---|---|
| Kaspersky Endpoint Security | 11.26.4.423 / 14.1.0.423 | `avp`、`avpsus`、`avpui` |
| Kaspersky Security Center 网络代理 | 16.2.0.1023 | `klnagent` |
| 亿赛通 电子文档安全管理系统（CDG） | 5.2.0 | `C:\Program Files\EsafeNet\Cobra DocGuard Client\` |
| 天锐绿盾（Tipray） | — | `C:\Inetpub\ftproot\Tipray\LdTerm\` |
| Windows Defender | 内置 | `SecurityHealthService` |

**Chrome 主窗口进程共载入 199 个模块，其中 21 个来自 DLP/安防**，包括 `BrowserGuardx64.dll`、`BrowerInject64.dll`、`LdBrowserMonitor64.dll`、`LdBrowserDataFlow64.dll`、`LdSendFileLimit64.dll`、`EstBrowserUrl64.dll`、`SQLiteDB64.dll`、`LdWaterMarkHook64.dll`、`MonFileOp64.dll` 等——**浏览器专用的那批钩子全都在**。按 CLAUDE.md 里记录的比对方法，这说明 Chrome 在新机上处于「管控软件完整支持」状态。

### 2.9 开发工具链现状（关键）

| 工具 | 新机 | 旧机（2026-09-21） |
|---|---|---|
| R / Rscript | **缺** | R 4.6.1（2026-06-24 ucrt） |
| Rtools / gcc | **缺** | rtools45，gcc 14.3.0 |
| Python | **仅 Microsoft Store 占位符** `WindowsApps\python.exe` | 3.14.7 / 3.13.15 ×3 / 3.12.14 ×2（共 7 个环境） |
| uv | **缺** | 0.12.17 |
| Quarto | **缺** | 1.10.18 |
| DuckDB CLI | **缺** | 1.5.5 |
| Node | **缺** | v24.19.0 |
| PowerShell 7 | **缺**（仅 Windows PowerShell 5.1） | 7.6.5 / 7.6.6 |
| Winget | **缺** | v1.29.380 |
| Positron / RStudio / VS Code | **缺** | （未在工具链盘点内） |
| WSL | `wsl.exe` 存在但**所有相关功能已禁用** | HypervisorPresent = False |
| Git | ✅ 2.55.0.5 | ✅ 2.55.0.5 |

> 注意：`C:\Users\PPCCpcpc\AppData\Local\Microsoft\WindowsApps\python.exe` **不是 Python**，它是微软商店的引导占位符，执行后只会打开商店页面。

---

## 三、「为何装完视窗十版就占掉一半空间」——逐项对账

C: 容量 238.16 GiB，可用 134.70 GiB，**已用 103.47 GiB**。全盘递归枚举得到 91.90 GiB（498,152 个文件），余下约 11.6 GiB 落在无权限读取的目录中。

| 项目 | 占用 (GiB) | 占已用比 | 说明 |
|---|---|---|---|
| `C:\Windows` | **31.11** | 30.1% | Windows 本体，见下方细分 |
| `C:\Program Files (x86)` | **14.18** | 13.7% | Office 8.00、Edge+WebView2 3.56、WPS 1.07、Chrome 0.53、Kaspersky 0.41、亿赛通 0.28 |
| `C:\Users` | **13.09** | 12.7% | 见下方细分 |
| `hiberfil.sys` | **12.71** | 12.3% | 休眠文件 ≈ 内存的 40%。休眠默认开启 |
| **系统还原 / 卷影副本（推断）** | **≈11.57** | 11.2% | `C:\System Volume Information` 拒绝访问；为已用量减去可枚举量的差额 |
| `C:\软件安装包` | **8.62** | 8.3% | 装机用的安装包，**装完没清** |
| `pagefile.sys` | **5.00** | 4.8% | 系统自动管理 |
| `C:\Program Files` | **2.97** | 2.9% | YeeChat 0.89、Chrome 0.50、Git 0.39、Firefox 0.33 |
| `C:\ProgramData` | **2.23** | 2.2% | |
| 回收站 | **0.90** | 0.9% | 单个 `$RU6WIZV.exe` 就占 0.9 GiB |
| `C:\Telegram` | 0.79 | 0.8% | |
| `C:\inetpub` | 0.24 | 0.2% | 天锐绿盾装在这里 |
| 其余 | 0.04 | — | |
| **合计** | **≈103.5** | 100% | |

### 3.1 `C:\Windows` 31.11 GiB 的构成

| 子目录 | GiB | 说明 |
|---|---|---|
| `WinSxS` | 13.42 | 组件存储。**这个数字具有欺骗性**——WinSxS 内大量是硬链接，`资源管理器`统计会重复计算，真实独占空间远小于此 |
| `System32` | 9.73 | |
| `servicing` | 2.22 | 239,285 个小文件 |
| `SoftwareDistribution` | 1.27 | **Windows 更新下载缓存，可安全清除** |
| `SysWOW64` | 1.03 | |
| `Microsoft.NET` | 0.59 | |
| `assembly` | 0.58 | |
| `Installer` | 0.24 | |
| `Logs` | 0.13 | |

### 3.2 `C:\Users\PPCCpcpc` 13.08 GiB 的构成

| 子目录 | GiB |
|---|---|
| `AppData` | 10.64 |
| `.cache` | 1.28 |
| `.codex` | 0.63 |
| `Documents` | 0.52 |

其中单个最大文件是 **`AppData\Local\Google\Chrome\User Data\OptGuideOnDeviceModel\2025.8.8.1141\weights.bin` = 3.98 GiB**——Chrome 内置的端上 AI 模型权重。

### 3.3 `C:\软件安装包` 8.62 GiB（36 个文件）

| 文件 | GiB | 备注 |
|---|---|---|
| `ProPlusRetail.img` | 4.27 | Office 安装镜像，**已装完** |
| `472.12-desktop-win10-win11-64bit-…-whql.exe` | 0.71 | **NVIDIA 驱动。新机是 Intel 核显，这个文件在本机毫无用处** |
| `DrvCeonwinstaller-2.20.0.3.exe` | 0.58 | 驱动工具 |
| `驱动.zip` | 0.37 | |
| WPS / YeeChat / QQ / 微信 / 搜狗 等 | 2.69 | 各类安装包 |

> `472.12` 正是本仓库 CLAUDE.md 里为旧机 GT 730（Kepler）准备的那版驱动。装机的人把旧机的驱动包一并带了过来，但新机没有 NVIDIA 显卡，这个包可以直接删。

### 3.4 理论可回收空间清单（**本次未执行任何清理**）

| 项目 | 可回收 (GiB) | 需要权限 | 代价 |
|---|---|---|---|
| `C:\软件安装包` 整个目录 | 8.62 | 普通用户 | 失去离线重装包（建议先备份到网盘/U 盘） |
| 系统还原点上限调整 | ≈11.6 | **管理员** | 失去回滚点 |
| 关闭休眠（`powercfg /h off`） | 12.71 | **管理员** | 失去休眠功能 |
| 清空回收站 | 0.90 | 普通用户 | 无 |
| `Windows\SoftwareDistribution\Download` | 1.27 | 普通用户 | 无（会自动重建） |
| Chrome 端上模型 `weights.bin` | 3.98 | 普通用户 | Chrome 会择机重新下载 |
| 清理组件存储（`DISM /StartComponentCleanup`） | 未知 | **管理员** | 无法再卸载已装更新 |
| **合计（不含 DISM）** | **≈39** | | |

执行后可用空间可望从 134.70 GiB 回到 **约 174 GiB**。这些都需要先生或 IT 决定，本次一项未动。

---

## 四、旧主机（台湾华硕原机）设备信息

> 来源：`reports/2026-09-21/*.json`（2026-09-21 采集，PowerShell 7.6.5，非管理员，离线只读）与 `DxDiag.txt`（2026-09-19 16:03 导出）。

| 项目 | 值 |
|---|---|
| 主机名 | `SHJ-H0647-RYOCH` |
| 制造商 / 型号 | **ASUS** / `System Product Name`（OEM 未写入型号） |
| 主板 BIOS | American Megatrends **3801**，2025-05-14，UEFI |
| CPU | 12th Gen Intel Core **i5-12400F**（**无核显**），6 核 / 12 线程，2500 MHz |
| 内存 | 2 × 16 GB **Kingston `HP32D4U2S8ME-16`**，**3200 MT/s**（实配 3200） |
| 显卡 | **NVIDIA GeForce GT 730**，2 GB |
| 显卡驱动 | `23.21.13.9135` → 真实版本 **391.35**，**2018-03-23** |
| 显示器 | Generic PnP Monitor `F2725B` / `XYM2704`，1920×1080 @ 60 Hz，HDMI |
| 硬盘 | **BORY R500 256G**，SSD，SATA，238.47 GB |
| C: 分区 | 237.21 GB，**剩余 59.92 GB（25.3%）** |
| 操作系统（末期） | **Windows 11 专业版 25H2，Build 26200.9457** |
| 操作系统（出厂） | Windows 10 专业版 Build 19045（DxDiag 导出时） |
| 授权 | Windows Pro，VOLUME_KMSCLIENT，已激活 |
| 电源方案 | **高性能**（`8c5e7fda-…`） |
| LongPathsEnabled | **1（已启用）** |
| 分页文件 | **手动 16,290 MB** |
| 网卡 | Realtek PCIe GbE Family Controller，1 Gbps，驱动 1168.27.50.919 |
| 常驻安防 | Kaspersky KES 14.1 + klnagent + Defender + 亿赛通 CDG + 天锐绿盾 |
| 软件登记 / Appx | 86 条 / 154 个 |
| Python 环境 | 7 个（3.14.7、3.13.15 ×3、3.12.14 ×2 等） |
| R 套件记录 | 696 条 |

---

## 五、两机逐项对比

| 维度 | 旧机（ASUS） | 新机（海兰 MiniPC T1） | 判定 |
|---|---|---|---|
| CPU | i5-12400F，6C/12T @2.5G | i5-12400，6C/12T @2.5G | **持平**（同一硅片，仅核显有无之别） |
| 内存容量 | 32 GB | 32 GB | 持平 |
| **内存频率** | **DDR4-3200** | **DDR4-2667** | **🔻 退步 −17%** |
| 内存形态 | DIMM（台式条） | **SO-DIMM**（笔记本条） | 中性，但换条选择面窄、单价高 |
| 内存一致性 | 同品牌同型号 Kingston | **Heoriady + HAILAN 混插** | **🔻 轻微退步** |
| 内存上限 | （未记录） | 64 GB，**2/2 插槽已满** | 扩容须整套换 |
| **显卡** | GT 730 独显 + **2018 年 391.35 驱动** | UHD 730 核显 + **2026-06 驱动** | **🔺 显著改善** |
| 显存 | 2 GB 独立 | 共享系统内存（最高 ~16 GB） | 中性偏退（占用系统内存） |
| CUDA / GPU 计算 | GT 730 理论支持但算力微不足道 | **完全无** | 🔻 退步（但实际影响≈0） |
| 硬盘型号 | BORY R500 256G | HAILAN 256G | 持平 |
| 硬盘接口 / 容量 | SATA / 238.47 GB | **SATA / 238.47 GB** | **持平 —— 瓶颈原样保留** |
| 剩余空间 | 59.92 GB（25.3%） | **134.70 GiB（56.6%）** | **🔺 改善**（因为还没装东西） |
| SMART 可读性 | （未记录） | **不可读** | 🔻 无法监控寿命 |
| **操作系统** | **Win11 Pro 25H2 / 26200.9457** | **Win10 Pro 22H2 / 19045.7725** | **🔻 退一代，且被策略锁死** |
| 虚拟化 / WSL2 | HypervisorPresent = False | 同样 False，**全部功能 InstallState=2 禁用** | 持平（两边都要开） |
| 电源方案 | **高性能** | **平衡** | 🔻 退步 |
| LongPaths | **1** | **0** | 🔻 退步（R/Python 深层路径会踩坑） |
| 分页文件 | 手动 16,290 MB | 自动 5,120 MB | 中性 |
| 网络 | GbE 1 Gbps | GbE 1 Gbps | 持平 |
| 显示器 | XYM F2725B | **同一台** | 持平 |
| 安防层数 | 三层 | **三层（同款，全部到位）** | 持平 |
| 开发工具链 | **齐全**（R/Python/uv/Quarto/DuckDB/Node/PS7/Rtools） | **仅 Git** | 🔻 需全部重建 |
| 机型形态 | 台式机箱 | 迷你主机（ChassisType 13） | 中性（省空间，但扩展受限） |

---

## 六、实测性能基准（新机）

> 用 .NET/C# 微基准在本机实测。**这组数字与旧机 `performance-baseline.json` 不可直接比较**——旧机那组跑的是 DuckDB / polars / NumPy，而新机尚未安装 Python。要做同口径对比，必须等工具链装好后重跑 `reports/2026-09-21/completion/benchmark.py`。

### 6.1 新机实测

| 项目 | 结果 |
|---|---|
| CPU 单线程（3 亿次 sqrt 循环） | 0.503 s → **596.9 M iter/s** |
| CPU 全核（12 线程 × 3 亿次） | 1.034 s → **3,483.1 M iter/s** 聚合，**扩展比 ×5.84** |
| 内存复制带宽（512 MiB × 8，`Array.Copy`） | 0.433 s → **18.49 GB/s**（读+写合计） |
| 磁盘顺序写（512 MiB，WriteThrough 真落盘） | 1.591 s → **321.8 MB/s** |
| 磁盘顺序读（1 GiB 未缓存大文件） | 2.461 s → **416.2 MB/s** |
| 小文件创建（4 KB × 2000） | 0.770 s → **2,598 个/秒** |

**读数解读**：

- **扩展比 ×5.84 而非 ×12**：i5-12400 是 6 个物理 P-core 带超线程。这类纯浮点循环下超线程几乎不贡献，×5.84 说明 6 个物理核已跑满，属正常。
- **顺序读 416 MB/s、写 322 MB/s**：SATA 3.0 的理论上限约 550 MB/s，实测处于该接口的正常区间。换成 NVMe 可以到 3000+ MB/s，**约 7 倍差距**。
- **小文件 2,598 个/秒**：这个数字里已经包含了三层安防（Kaspersky + 亿赛通 + 天锐绿盾）对每次文件创建的拦截开销。R 装包、Python 装轮子、Git 检出都是海量小文件操作，这是实际会被感知到的成本。
- 首次测读时得到 5,025 MB/s——那是操作系统页缓存命中（即内存速度），**不是磁盘速度**，故改用未缓存的大文件重测，上表取的是后者。

### 6.2 旧机历史基准（存档，供日后同口径对比）

来自 `reports/2026-09-21/completion/performance-baseline.json`（100 万行，5 次取中位数）：

| 测试 | 中位耗时 |
|---|---|
| `duckdb_1m_parquet_groupby` | 7.198 ms |
| `polars_1m_parquet_groupby` | 6.199 ms |
| `numpy_512_matrix_product` | 4.308 ms |

---

## 七、优劣势评估

### 7.1 新机优势

1. **显示链路彻底现代化。** 从 2018 年的 391.35 驱动跳到 2026-06 的 32.0.101.7088，驱动新了 8 年。CLAUDE.md 里记载的 Comet 黑屏调查虽已排除驱动因素，但那颗 Fermi/Kepler 老卡始终是个定时炸弹，现在拆除了。
2. **开局有 134.70 GiB 可用。** 旧机末期只剩 59.92 GB，装包都要掂量。现在有重建的余地。
3. **零历史包袱。** 2026-07-30 全新安装，`Windows.old` 是空的，没有「就地升级留下旧驱动」那类隐患（CLAUDE.md 2026-09-20 第二轮记录的正是这个坑）。
4. **管控软件完整覆盖。** Chrome 被注入 21 个 DLP 模块，浏览器专用钩子一个不缺——按仓库的比对式诊断方法，这台机器上的 Chrome 处于「在管控软件支持清单内」的状态。
5. **迷你形态，功耗与噪音更低。**

### 7.2 新机劣势

1. **内存频率退步 17%**（3200 → 2667）。双通道理论带宽从约 51.2 GB/s 降到约 42.7 GB/s。DuckDB、polars、Arrow 这类列式引擎对内存带宽高度敏感，**这是本次换机唯一会直接拖慢数据分析的硬件变化**。
2. **仍是 256 GB SATA SSD。** 容量没涨、接口没换。等 R 4.6 + 696 个 R 包 + 7 个 Python 环境 + Quarto + Positron 全装回来，很可能重演旧机「只剩 59 GB」的局面。
3. **内存混品牌插条**，长期稳定性与将来 XMP/扩容的余地存疑。且 2 槽已满，**升级必须整套换，不能加装**。
4. **操作系统退一代且被锁定。** `TargetReleaseVersion = 22H2` 是明确的组策略决定，不是意外。Windows 10 22H2 的常规支持已于 2025-10-14 结束，而**本机未激活任何 ESU 加载项**——但 2026-10-04/05 仍收到了安全更新。这两件事互相矛盾，**需要向 IT 核实本机的补丁来源与支持期限**，不要自行推断。
5. **SMART 不可读**，无法掌握这块国产 SSD 的磨损度与通电时长。
6. **无独立恢复分区**，WinRE 寄居在 C:。
7. **三项设置相对旧机退步**：电源方案「平衡」（旧为「高性能」）、`LongPathsEnabled = 0`（旧为 1）、分页文件 5 GB（旧为手动 16 GB）。
8. **存在 `PendingFileRenameOperations` 待重启标记。** 按 CLAUDE.md 的判断，单独出现未必代表 Windows 更新需要重启，但装大型工具链前重启一次更稳妥。
9. **无任何 GPU 计算路径。** 不过旧机的 GT 730 本就算力微不足道，实质影响接近于零。

### 7.3 两机共有的局限

1. **三层常驻安防**（Kaspersky + 亿赛通 CDG 透明加密 + 天锐绿盾）。按 CLAUDE.md 的硬性要求：**不要建议停用任何一个**，正解是请 IT 加白名单。
2. **会话以普通用户身份运行，无法提权。** 下一节所有标注「需管理员」的项目，都必须产出命令交由先生或 IT 手动执行。
3. **千兆网卡**，大数据集拉取受限。
4. **Rtools 的 gcc 只服务 R，不服务 Python。** Python 的 C 扩展需要 MSVC Build Tools，两条编译链独立——旧机上 `scikit-survival` 装不起来就是这个原因，新机会原样重现。

---

## 八、安装工具链前的准备清单

> 本次**一项未执行**。以下按「需要什么权限」分组，供先生决定执行顺序。

### 8.1 普通用户即可（先生自己可做）

| 动作 | 目的 |
|---|---|
| 备份并清空 `C:\软件安装包`（8.62 GiB） | 腾空间；其中 NVIDIA `472.12` 驱动在本机完全无用 |
| 清空回收站（0.90 GiB） | 腾空间 |
| 按 `env/python-ds-requirements.lock.txt` 重建 Python 环境 | 这是重建环境的**唯一依据**（见 CLAUDE.md） |
| 重启一次，清掉 `PendingFileRenameOperations` | 避免装机过程中被待重启状态干扰 |

### 8.2 需要管理员（须交 IT 执行）

| 动作 | 命令 / 位置 | 必要性 |
|---|---|---|
| **启用 WSL2** | `dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart`<br>`dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart`<br>然后重启 + `wsl --set-default-version 2` | **必需**。当前 `Microsoft-Windows-Subsystem-Linux`、`VirtualMachinePlatform`、`Microsoft-Hyper-V-All` 的 `InstallState` 全为 2（已禁用） |
| **启用长路径** | `HKLM\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled = 1` | 强烈建议。旧机已启用；R 与 Python 的深层包路径常超 260 字符 |
| 电源方案改回「高性能」 | `powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c` | 建议。旧机即为此设置 |
| 调整系统还原占用上限 | `vssadmin resize shadowstorage` | 可选，回收约 11.6 GiB |
| 关闭休眠 | `powercfg /h off` | 可选，回收 12.71 GiB。快速启动本就是关的，代价仅为失去休眠 |
| **为开发工具链申请 DLP 白名单** | 向 IT 提交 | **强烈建议**。R/Python 装包是海量小文件写入，三层安防逐个拦截会显著拖慢，且可能误杀 |

### 8.3 装机时必须避开的已知地雷（全部来自本仓库实测记录）

1. **R 的 `arrow` 与 Python 的 `pyarrow` 不能在同一进程共存。** 在 `.qmd` 里混用 R 与 Python chunk 时，knitr 走 reticulate，两者同进程，必炸。**R 端改用 `duckdb` 读写 Parquet，不要 `library(arrow)`。**
2. **reticulate 不认 `QUARTO_PYTHON`，只认 `RETICULATE_PYTHON`。** 否则它会自己临时下载一个干净的 Python，你的套件全都不在。
3. **`.Rprofile` 只该管「套件怎么装」**，不要写 `OMP_NUM_THREADS` / `TZ`，否则同一份脚本在不同机器跑出不同结果。
4. **Rtools 不要加进 PATH。** R 靠注册表 `HKLM\SOFTWARE\R-core\Rtools` 寻找；`rtools\usr\bin` 里的 `sh`/`find`/`sort` 会盖掉 Windows 内置同名指令。
5. **pak 的求解器是全域的**——一个被 CRAN 封存的包（如 `qs`/`fastshap`/`vip`）会把整批依赖标成冲突，错误讯息会伪装成「R 版本太新」。
6. **uv 建立的 venv 刻意不安装 pip**，用 `python -m pip list` 会得到空清单，别误判成空环境，改用 `importlib.metadata`。
7. **Positron 开启资料夹后会遇到 Restricted Mode**，需手动点横幅的 **Manage → Trust**。**这是安全决定，AI 不该代按。**
8. **Windows PowerShell 5.1 传参数给原生程序会吃掉内嵌引号**，用不需引号的写法。

### 8.4 验收标准

按 CLAUDE.md 的硬性要求：**验收标准是「跑出结果」，不是「安装成功」。** 装完后应：

1. 重跑 `reports/2026-09-21/completion/benchmark.py`，与旧机的 7.198 / 6.199 / 4.308 ms 同口径对比——这是量化「DDR4-2667 相对 3200 究竟损失多少」的**唯一可信方法**。
2. 用 `templates/r-python-template.qmd`（旧机已实测 render 成功）验证 R + Python 混用链路。
3. 注意：`诊断操作系统/Acceptance_Test.ps1` 有已知缺陷（会终止所有 comet 进程、部分检查永远 PASS），**不要把它的历史 28/28 当作当前验收**。

---

## 九、关于华为仓颉（Cangjie）与鸿蒙的可行性

> 以下为公开资料查证，**未在本机验证**（本机尚未安装任何相关工具链）。版本演进很快，实际安装前请以官网当时信息为准。

- 仓颉是华为自研的静态类型、多范式、编译型通用语言，2024-06-21 于 HDC 2024 发布开发者预览，2025-07-01 发布首个 LTS。截至 2026-05-29 的稳定版为 **1.1.3**，声称支持 HarmonyOS、Linux、Windows、macOS、Android、iOS。
- 华为已于 **2026-07-30 宣布开源仓颉源代码**。
- **Windows 支持存在明确的等级差**：官方文档说明工具链「已适配部分 Linux、macOS 与 Windows 版本，但完整功能测试仅在部分 Linux 发行版上完成」；**Windows 版编译器基于 MinGW 实现，部分功能相对 Linux 不可用**。
- Windows 下提供 exe 与 zip 两种安装包，zip 版通过 `envsetup.bat` / `envsetup.ps1` / `envsetup.sh` 配置环境。工具链含编译器、调试器、包管理器、静态分析、格式化与覆盖率工具。

**对本机的判断**：

1. **优先走 WSL2 + Linux 工具链**，而不是原生 Windows。既然官方承认完整功能测试只在 Linux 上做过，且 Windows 版受 MinGW 限制，WSL2 是风险最低的路径。这也强化了 §8.2 中「启用 WSL2」的优先级。
2. **WSL2 会再吃掉可观的磁盘空间。** 一个 Ubuntu 发行版加仓颉 SDK，预留 20–30 GiB 比较稳妥。以目前 134.70 GiB 可用、再加上 R + Python 全家桶的需求来看，**256 GB 的盘会非常吃紧**。这是建议优先解决存储的直接理由。
3. **MinGW 工具链与本机既有编译链互不冲突**：Rtools45 的 gcc 只服务 R，仓颉的 MinGW 自带一套，Python C 扩展要的又是 MSVC。三条链各管各的，但**都要各自向 IT 申请 DLP 白名单**。
4. **鸿蒙（HarmonyOS）应用开发需要 DevEco Studio**，那是另一套重量级 IDE，磁盘与内存开销都要单独评估。本机 32 GB 内存应付得来，磁盘是问题。

**来源**：
- [Installing the Cangjie Toolchain（官方文档 1.0.0）](https://docs.cangjie-lang.cn/en/docs/1.0.0/user_manual/source_en/first_understanding/install_Community.html)
- [Cangjie (programming language) — Wikipedia](https://en.wikipedia.org/wiki/Cangjie_(programming_language))
- [Huawei to open-source self-developed programming language Cangjie — SCMP](https://www.scmp.com/tech/big-tech/article/3316506/huawei-open-source-self-developed-programming-language-cangjie-rival-java-and-swift)
- [仓颉 SDK 构建指导书 — GitCode](https://gitcode.com/Cangjie/cangjie_build/blob/main/docs/linux_cross_windows.md)
- [仓颉编程语言正式发布 1.0.0 LTS 版本](https://developer.aliyun.com/article/1670464)

---

## 十、优先级建议

| 优先级 | 事项 | 理由 |
|---|---|---|
| **P0** | **向 IT 申请换/加装大容量 NVMe SSD** | 两代机器的同一个瓶颈。SATA 416 MB/s vs NVMe 3000+ MB/s 约 7 倍差距；256 GB 装不下「R 全家桶 + Python 多环境 + WSL2 + 仓颉 SDK」。主板为 H610I，系统侧未见 NVMe 控制器，**是否有空置 M.2 插槽需开盖或进 BIOS 核实** |
| **P0** | 向 IT 核实 Windows 10 22H2 的支持期限与补丁来源 | 未激活 ESU 却仍在收安全更新，这个矛盾必须澄清 |
| **P1** | 启用 WSL2 + VirtualMachinePlatform（需管理员） | R/Python/仓颉 三条路线都受益 |
| **P1** | 启用 LongPathsEnabled（需管理员） | 旧机已启用；不开会在装包时踩坑 |
| **P1** | 为开发工具链申请 DLP 白名单 | 小文件 2,598 个/秒的开销实打实 |
| **P2** | 清理 `C:\软件安装包` 等约 39 GiB | 先生自己即可完成大部分 |
| **P2** | 电源方案改回「高性能」（需管理员） | 与旧机对齐 |
| **P3** | 评估换一对 DDR4-3200 SO-DIMM | 可追回 17% 内存带宽，但需整套换条，性价比待评估 |

---

## 十一、本次未能验证的事项（诚实声明）

| 项目 | 原因 |
|---|---|
| `C:\System Volume Information` 与 `C:\Recovery` 的确切占用 | 拒绝访问（需管理员）。**11.57 GiB 这个数字是「已用量 − 可枚举量」的差额，属推断，不是实测** |
| `vssadmin list shadowstorage` / `fsutil volume diskfree` | 需管理员权限 |
| SSD 磨损度、通电时长、温度 | 该盘未向系统暴露 SMART 可靠性计数器 |
| 主板是否有空置 M.2 / NVMe 插槽 | 系统侧只见 SATA AHCI 控制器；需开盖或进 BIOS 确认 |
| 与旧机同口径的数据分析性能对比 | 新机尚未安装 Python/polars/DuckDB，无法重跑 `benchmark.py` |
| 仓颉工具链在本机的实际可用性 | 尚未安装 |
| 旧机的 TPM / Secure Boot / BitLocker 状态 | 旧机采集时同样因权限不足未取得（见 `00_summary.md` 的「未完成或不可用的探测」） |

**空数据不等于健康。** 以上每一项在做决策前都应先补齐。

---

## 十二、追加实测：能否在「不修改管理员设置、不动防毒软件」的前提下升级到 Windows 11

> 2026-10-05 同日追加。全程只读，未改动任何设置。新增产出：`DxDiag_new_machine.txt`（与旧机 `DxDiag.txt` 同口径，便于对比）。

### 12.1 结论

**不能。** 三道阻断，任何一道单独成立就足以否定，而三道同时存在。

**但要分清楚：硬件百分之百合格，拦住升级的全部是行政与管控层面——恰恰就是题目划定的不可触碰范围。**

### 12.2 硬件资格：Windows 自己判的是 Green

直接读取 Appraiser 的裁决（`HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\TargetVersionUpgradeExperienceIndicators`，资料版发布日 2026-10-01，评估时间戳为今日）：

| 目标 | 构建号 | UpgEx | RedReason | GatedBlockId | FailedPrereqs |
|---|---|---|---|---|---|
| **GE25H2**（Windows 11 25H2） | 26200 / 26220 | **Green** | {None} | {None} | {None} |
| **GE26H2**（Windows 11 26H2） | 26300 | **Green** | {None} | {None} | {None} |

这不是我的推断，是系统内建的升级评估器自己算出来的结论。逐项核对：

| Windows 11 要求 | 实测值 | 判定 |
|---|---|---|
| CPU 在官方支持列表 | i5-12400（Alder Lake，Family 6 Model 151） | ✅ |
| 内存 ≥ 4 GB | 32 GB | ✅ |
| 系统盘 ≥ 64 GB | 238.16 GiB，可用 134.70；Appraiser `Free: gt64`、`SystemDriveTooFull: 0` | ✅ |
| UEFI 固件 | `firmware_type = UEFI`；DxDiag `BIOS: 5.27 (type: UEFI)` | ✅ |
| GPT 磁盘 | `PartitionStyle = GPT` | ✅ |
| **TPM 2.0** | 设备 `ACPI\MSFT0101\1`「受信任的平台模块 2.0」，Status = OK，`tpm.sys` 服务运行中 | ✅ |
| 具备 Secure Boot 能力 | UEFI + GPT 已满足 | ✅ |
| DirectX 12 / WDDM 2.0+ | DirectX 12，Feature Levels **12_1**，驱动模型 **WDDM 2.7** | ✅ |

两点补充说明：

- **Secure Boot 目前是关闭的**（`UEFISecureBootEnabled = 0`）。Windows 11 的要求是「具备 Secure Boot 能力」而非「已启用」，Appraiser 也据此判了 Green，所以**不构成升级阻断**。但若日后要启用 BitLocker 或 VBS/HVCI，必须进 BIOS 开启——那是固件设置，同样需要管理员与实体操作。
- 核显 `Dedicated Memory: 128 MB`、`Shared Memory: 16,268 MB`，即最多可从 32 GB 系统内存中借走约 16 GB 作显存。这是核显相对独显的固有代价，与升级无关，但对内存吃紧的分析负载需留意。

### 12.3 阻断一：组策略把本机钉死在 Win10 22H2 —— 它本身就是「管理员设置」

`HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate`：

```
TargetReleaseVersion        = 1
TargetReleaseVersionInfo    = 22H2
TargetReleaseProductVersion = Windows 10
```

**实测一（真跑了一次在线 Windows Update 搜索，只搜不装）**：耗时 12.8 秒，返回 **0 项**；其中 Windows 11 功能更新 **0 个**。Windows Update 这条路是死的。

**实测二（该策略键能否由普通用户改写）**：ACL 中仅 `NT AUTHORITY\SYSTEM` 与 `BUILTIN\Administrators` 具 FullControl。以当前身份实际写入测试，返回：

```
Requested registry access is not allowed.
```

解除这条策略 = 修改管理员设置。题目明令不改，而且我们也改不了。

### 12.4 阻断二：当前账户不是管理员，就地升级根本起不来

- 身份：`SHJ-H0647-RYOCH\PPCCpcpc`，`IsAdmin: False`
- 所属群组仅 `BUILTIN\Users` 与 `NT AUTHORITY\Authenticated Users`
- 绕过 Windows Update 的常规三条路——挂载 ISO 跑 `setup.exe`、Windows 11 安装助手、媒体创建工具——**全部要求提权**
- 本会话无法提权（与 CLAUDE.md 既有记录一致）

即便策略不存在，这一条仍然卡死。

### 12.5 阻断三：防毒与 DLP 的内核过滤驱动栈（最该慎重的一条）

实测注册在系统中的相关过滤驱动与服务：

| 服务 | Start | Group | 归属 |
|---|---|---|---|
| `LdMFilter` | **0（Boot 启动）** | FSFilter Activity Monitor | 天锐绿盾 |
| `KLIF.KES-14-1` | 1（System 启动） | FSFilter Anti-Virus | Kaspersky |
| `klflt.KES-14-1` | 1（System 启动） | FSFilter Bottom | Kaspersky |
| `klfltdev.KES-14-1` | 3 | Pnp Device Filter | Kaspersky |
| `Ldcore` | 2 | — | 天锐绿盾 |
| `ldwfp` | 3 | — | 天锐绿盾（WFP 网络过滤） |
| `LdCdRomFilters` | 3 | — | 天锐绿盾 |
| `ProcessCtr` | 2 | — | 亿赛通 CDG |
| `CommonService` | 2 | — | 亿赛通 CDG |

三点风险：

1. **Windows 安装程序的相容性扫描会对开机启动的第三方过滤驱动亮灯。** `LdMFilter` 是 `Start = 0`，开机即载入；Kaspersky 的两个 FSFilter 是 `Start = 1`。典型处置就是要求先卸载或停用安防产品——**这直接违反「不动防毒软件」这个前提**。
2. **亿赛通 CDG 是透明加密。** 磁盘上存的是密文，靠过滤驱动即时解密。大版本就地升级会重建整个过滤驱动栈，**一旦驱动没跟上，已加密的文档可能变成读不出来的乱码**。业界标准做法是升级前由 IT 从服务端解除加密绑定或执行离线解密。这同样是「动 DLP」。
3. **本机同时装了两个版本的 Kaspersky Endpoint Security**（11.26.4.423 与 14.1.0.423，另有 KSC 网络代理 16.2.0.1023）。两个大版本共存本身就是异常状态，在就地升级场景下属高风险项，应先请 IT 厘清。

### 12.6 若要真的升级，需要走的流程（全部需 IT）

按风险从低到高：

1. IT 确认 Kaspersky Endpoint Security、亿赛通 CDG 5.2.0、天锐绿盾三者的当前版本**均已通过 Windows 11 25H2 认证**
2. IT 从 CDG 服务端对本机**解除加密绑定或执行离线解密**，并确认文档可明文读取
3. IT 厘清两个 KES 版本共存的问题
4. IT 调整或移除 `TargetReleaseVersion` 策略
5. 由管理员执行升级；**升级前完整备份**（本机无独立恢复分区，WinRE 寄居 C:，容错余地小）
6. 升级后用 CLAUDE.md 的比对式诊断复验三层安防：量测 Chrome 被注入的模块数。**本机当前基线为 199 个模块、其中 21 个 DLP 模块**，升级后若这个数字掉下来，就是管控软件没跟上

### 12.7 顺带填补 §11 的空白

本次追加实测已解决 §11 表中的两项「未能验证」：

| 原未验证项 | 现状 |
|---|---|
| TPM / Secure Boot 状态 | **已查明**：TPM 2.0 存在且正常；Secure Boot 具备能力但当前关闭 |
| DirectX / WDDM 等级 | **已查明**：DX12、Feature Level 12_1、WDDM 2.7 |

仍未解决：System Volume Information 与 Recovery 的确切占用、SSD 磨损度、M.2 插槽有无、同口径性能对比。


---

## 十三、2026-10-05 本轮只读实测、旧机全仓检索与评估增补

### 13.1 范围、证据与可重复性

本轮于北京时间约 15:46–15:49 采集。用户明确要求先不修改电脑设置：未清理文件、修改 PATH/注册表/电源/休眠/分页文件/执行策略，未启用 WSL、升级 Windows、安装工具链或重启。仅保存本仓库中的报告和复核脚本。CIM 查询起初被沙箱拒绝访问；经工具审批在沙箱外只读查询成功，直接运行 ps1 又被执行策略阻止，最终用相同脚本文本作为命令执行，**没有更改执行策略**。失败记录保留在 `本轮只读复核.json`，其空字段不是设备缺失证据。

- `本轮硬件实测.json`：CIM、物理盘与系统根目录文件的当前读数。
- `本轮空间逻辑扫描.json`：全 C: 可访问目录文件长度扫描，含每目录错误数与错误样本。
- `本轮CPU微基准.json`：本轮 CPU 五次计时、结果校验值及运行时版本。
- `ReadOnly-Recheck.ps1`、`ReadOnly-Space.ps1`、`ReadOnly-Cpu.ps1`：上述采集与测试源代码。
- `旧机证据索引_本轮.txt`：对全仓 md/qmd/txt/json/csv（含被 Git 忽略的报告，排除 Git 元数据及依赖目录）检索 ASUS、i5-12400F、BORY R500、内存料号，命中 92 个文件。命中不等于 92 份独立证据；重复采集、方案文本与原始实测分别辨别，设备结论以原始记录交叉核对。本轮不是对每份报告所有内容逐字审计。

### 13.2 新机硬件与空间的本轮读数

| 项目 | 本轮直接读取 | 判断边界 |
|---|---|---|
| SMBIOS 厂商/型号 | MiniPC / T1 | “海兰”来自用户说明及 HAILAN 硬盘、内存标识；SMBIOS 未直接写海兰整机厂商，不能据此认证生产地 |
| CPU | i5-12400，6 核 12 线程，基准 2.5 GHz | 此字段不是负载中的实时睿频 |
| 内存 | 2×16 GiB，ConfiguredClockSpeed 均为 2667 | 两条料号不同；不能仅凭 DeviceLocator 证明有效双通道、稳定性或劣质混插 |
| GPU | Intel UHD Graphics 730，32.0.101.7088 | 新驱动版本不等于所有应用已通过验收 |
| 物理 SSD | HAILAN 256G，256,060,514,304 B，SATA，Healthy | Healthy 是系统粗粒度状态，不能代替 SMART、寿命与坏块检查 |
| C: | 255,727,046,656 B = 238.16 GiB | 256 GB 标称与约 238 GiB 显示主要是十进制/二进制单位差异 |
| 扫描结束可用 | 144,337,281,024 B = 134.42 GiB | 是该时点快照，后台程序会持续改变 |
| 已用 | 103.74 GiB，约 43.56% | 可用约 56.44%，所以“已占超过一半”在本次读数下不成立 |
| Windows | Windows 10 专业版，Build 19045 | 22H2 与安装日期亦见同日历史快照；安装日期显示 7 月 30 日，不能视为昨日纯净安装证据 |
| 虚拟化 | 固件虚拟化与 SLAT 为 True，HypervisorPresent 为 False | WSL、VirtualMachinePlatform、Hyper-V-All 的 InstallState 均为 2（禁用） |

本轮目录扫描的**可访问文件逻辑长度**：Windows 31.12 GiB、Program Files (x86) 14.19 GiB、Users 13.05 GiB、软件安装包 8.62 GiB、Program Files 2.97 GiB、ProgramData 2.23 GiB、回收站约 0.90 GiB。`Windows.old` 枚举到 0 个文件且无扫描错误；Recovery、System Volume Information 则拒绝访问，不能写成零占用。

根目录直接读得：`hiberfil.sys` 13,646,827,520 B = **12.71 GiB**，`pagefile.sys` 5,368,709,120 B = **5 GiB**，`swapfile.sys` **16 MiB**。前两项约 17.71 GiB，是内存管理/休眠配套文件，并不是 R/Python 或 WSL 的安装体积。

**为何工具链尚未安装，已用仍达到约 104 GiB？** 这是已装办公、浏览器、安防、用户资料、安装包及 Windows 配套文件共同占用的系统盘，不能把“整盘已用”全部算成“Windows 安装占用”。31.12 GiB 也只是 Windows 目录可读逻辑长度，不是准确的独占物理大小：NTFS 硬链接重复统计、压缩/稀疏文件、簇取整、卷元数据和访问受限都会改变对账。故早先约 11.57 GiB 的算术差额只能称**未归因差额**，不能认定为系统还原/卷影副本，更不能承诺可回收 39 GiB 或清理后必有 174 GiB。需要精确归因时，后续由授权管理员只读取得组件存储、卷影占用及文件分配大小数据；本轮不做清理。

### 13.3 旧华硕原机的补证与时间口径

| 项目 | 查证结果 | 仓库原始来源 |
|---|---|---|
| 主板 | **ASUSTeK COMPUTER INC. PRIME H610M-R D4，Rev 1.xx** | `reports/2026-09-21/update-round2/board.json` |
| 整机 SMBIOS | ASUS / System Product Name | `reports/2026-09-21/01_system.json`、`rediagnosis/01_system.json` |
| CPU | i5-12400F，6 核 12 线程 | `rediagnosis/02_cpu.json` |
| 内存 | Kingston HP32D4U2S8ME-16，两条各 16 GiB，实配 3200 | `rediagnosis/03_memory.json` |
| GPU | GT 730，PCI DEV_0F02，2 GiB，391.35 | `rediagnosis/04_gpu.json`、`CLAUDE.md` 首节更正 |
| SSD | BORY R500 256G，SATA，约 238.47 GiB | `rediagnosis/07_disks.json` |
| BIOS | AMI 3801，2025-05-14 | `reports/2026-09-21/05_bios.json` |
| 系统 | 后期 Windows 11 Pro 25H2 / 26200.9457；9 月 19 日 DxDiag 仍为 Windows 10 | `01_system.json`、`DxDiag.txt`；后者不等于“出厂系统”证明 |
| C: 可用 | 9 月 21 日早期 59.92 GiB；同日再诊断 45.46 GiB | `06_volumes.json`、`rediagnosis/06_volumes.json` |

旧机可用空间与分页管理存在多次采集差异，应引用具体文件与时点；59.92 GiB 不能称为“宕机前最后余额”。旧机故障发生于用户叙述的昨日，本仓库 9 月 21 日采集不能证明 10 月 4 日的故障原因，未发现足以确认主板/电源/SSD 损坏的本轮故障证据。

### 13.4 功能与性能：可以判断什么，不能判断什么

**CPU 基本同档，整机性能尚不能判为完全相等。** Intel 两款规格均为 6 核 12 线程、最高 4.4 GHz、18 MB 缓存、基础功耗 65 W、最大睿频功耗 117 W；12400 多 UHD 730 核显。不同散热、功耗限制、温度、内存与后台进程可能改变持续性能，不能从型号证明“同一硅片”或“一比一算力”。

**内存容量持平，频率规格下降。** 2667/3200≈83.34%，名义传输率低约 16.66%；这不是所有程序耗时增加 17%。双通道是否生效、内存时序、持续带宽与稳定性仍待测；SMBIOS 声称上限 64 GiB，不等于实际已通过 64 GiB 内存兼容认证。

**显示功能更适合现代桌面需求，但 GPU 算力未作直接比较。** 新机有核显，无需依赖旧 GT 730 单独出图；旧机 12400F 没有核显。旧 GT 730 的 DEV_0F02 为仓库已纠正的 Fermi 版本，不能套用 Kepler 的 472.12 驱动建议。UHD 730 共享显存上限是动态预算，不是开机固定扣走 16 GiB。新机没有 NVIDIA CUDA 硬件路径，但不能写成“没有任何 GPU 计算路径”，Intel 核显仍可能经受支持的接口与框架参与计算；具体兼容性要验收。两机均不足以承担现代大模型训练或高性能 GPU 科学计算。

**存储容量瓶颈相同，速度优劣尚未同口径证明。** 两块都是 256 GB SATA SSD；新机空闲较多主要反映软件与资料布局差异。早先 416 MB/s 等数字保留作历史微测记录；没有本轮可复现的未缓存读取证据，不能据此认定是真实裸盘吞吐。NVMe 收益取决于盘、接口和任务，不能把“7 倍”套用到所有分析或编译。旧机已找到确切主板，新机只见 H610I 泛称，不能仅据芯片组推断空 M.2 插槽、扩展口、散热能力、噪声或功耗优劣，需机型手册或实物核对。

**系统与安全兼容性需要独立验证。** Windows 10 常规支持于 2025-10-14 结束，应核对组织 ESU 授权与更新来源；KMS 的 Windows 激活状态不是 ESU 证明。读取许可 SKU 或已装更新不足以断言 ESU 一定未生效。平衡电源方案也不能直接称“性能退步”，它可能正常达到睿频。过滤驱动存在只说明兼容性需检查，不证明 Windows 安装程序一定拒绝升级；两个注册项也不足以证明两套 KES 引擎正在共存。历史 §12 所称“三道阻断”“必须先解密”“硬件百分之百合格”超出证据：本轮未执行升级兼容性扫描、未验证厂商认证，不建议因此卸载、停用安防或解除文档加密。TPM 设备存在不等于已就绪；UEFI+GPT 不单独证明 Secure Boot 能力；BitLocker 并非一律要求 Secure Boot 已启用。应由 IT 用正式资格与兼容性检查决定。

### 13.5 本轮实际性能测量及其边界

本轮新做单线程 `sum(sqrt(i)), i=1..20,000,000`，先 JIT 预热，再测 5 次，保留计算结果防止无效测量；.NET 运行时 10.0.11。各次 **79.081、76.857、79.294、76.827、77.385 ms**，中位数 **77.385 ms**；五次结果均为 **59,628,481,635.85357**。脚本与原始数据已保存。

此微基准只说明当前会话能完成该浮点循环，受 JIT、线程调度与后台负载影响；不是 R/NumPy 科学计算速度、全核持续性能、内存带宽或长期稳定性验收。旧机没有同一测试的结果，不能计算新旧 CPU 提升率。本轮未写大文件测速，也未运行历史会终止应用的 Acceptance_Test.ps1。

旧机同口径数据分析历史基线确有原始文件：DuckDB 百万行 group-by 中位 **7.198 ms**、Polars **6.199 ms**、NumPy 512×512 矩阵乘积**连同 allclose 校验** **4.308 ms**。对应 Parquet 只有约 1.01 MiB，是高度规则的合成数据且经过预热，不能把这组毫秒数外推到真实 GB 级数据，也不能当成冷磁盘测试。

### 13.6 R、RStudio、Python、Positron 与 WSL2 安装后的复测路线

按用户说明上述工具尚未建立工作环境；本轮未安装。`Get-Command R` 在 PowerShell 中可命中历史别名 `r`，不能算 R 已装；WindowsApps 的 python 是商店入口。本会话还可见 Codex 私有 Node/Git 运行时，不能把它算成已经为用户部署好的通用工具链，亦不应写成整台设备绝对“无 Node”。

1. 安装后记录解释器绝对路径、版本、包版本/BLAS、IDE 渲染和终端状态；优先核对旧机锁版记录可用性，不为追求最新而盲目复制所有重复环境。
2. 在独立的新机输出目录运行 `completion/benchmark.py` 的同口径副本，保留 6 线程设置、预热、5 次中位数与数值校验；不覆盖旧机原始基线。同时增加真实 CSV/Excel/Parquet、R 模型和 Quarto 渲染验收。
3. 分开测热缓存与冷读、串行与并行、短任务与 10–20 分钟持续负载；记录温度/降频（能取得时）、可用内存、分页与后台活动，才可判断小机箱是否限制持续性能。
4. WSL2 启用并重启后验证发行版确为 VERSION 2、Linux 内存/交换、文件互访及 R/Python/仓颉编译；只读状态查询不能代替启用后验收。WSL2 不要求额外启用完整 Hyper-V-All，也不是原生 Windows R/Python 的必要前提。
5. 安装前后用相同单位记录磁盘净增长；WSL 动态 VHDX、包缓存、数据集、虚拟环境副本与容器镜像分别计量。可暂以工具链 20–40 GiB、WSL/SDK 20–30 GiB、数据与构建临时空间 30–50 GiB 做**规划预算**，这些不是实测安装体积，也不可简单视为必然全部相加。当前 134 GiB 可用适合开始学习与中型项目，完整科研、多个系统镜像和大型数据长期共存会受限。

### 13.7 仓颉、语言研发与操作系统研发的适配判断

仓颉官网下载中心目前提供 Windows、Linux、macOS 的 SDK 通道，官方安装指南有 Windows x64 exe/zip 及 Linux x64 包。**无需先启用 WSL2 才能尝试原生 Windows 仓颉**；可先选择满足目标项目的官方 Windows SDK，若需要 Linux 构建、生态或特定功能，再评估 WSL2。早先精确版本、开源日期以及“WSL2 风险最低”的断言未在本轮作充分确认，不作为安装决策依据。

本机 6 核 12 线程、32 GiB 内存适合仓颉入门、命令行工具、编译器前端、解释器、语法分析与小型系统原型。研发语言要逐步验证词法/语法、类型系统、IR/代码生成、运行时、包管理和测试；并非安装高端 IDE 就等于获得高性能语言研发能力。

操作系统研发需要明确 x86_64/ARM/RISC-V 目标，交叉工具链、链接脚本、QEMU 等虚拟机及启动/异常/内存/驱动测试。WSL2 是开发宿主环境，不能代替完整 OS 启动与硬件验证；优先在后续获准的模拟器/虚拟机中做实验，再用独立测试设备验证。学习性内核与小型模拟器负载可行，完整系统构建、多虚拟机、大型源树与镜像会首先受 256 GB 存储和持续散热约束。ARM/RISC-V 可模拟，但不等于本机有相应原生硬件。

若未来使用大型 LLVM/完整系统源树、多个环境与镜像，应先按项目实测容量，再评估 1 TB 级存储或独立构建机；本轮不替用户决定换盘、调设置或安装。整体判断：**新机是同档 CPU 的办公/中型开发主机替换，现代显示路径是功能优势，内存传输率与小容量 SATA 存储是明确局限；还没有证据将它定为整体高性能升级或整体性能降级。**

本轮公开资料核对（2026-10-05）：

- [Intel i5-12400 官方规格](https://www.intel.com/content/www/us/en/products/sku/134586/intel-core-i512400-processor-18m-cache-up-to-4-40-ghz/specifications.html)
- [Intel i5-12400F 官方规格](https://www.intel.com/content/www/us/en/products/sku/134587/intel-core-i512400f-processor-18m-cache-up-to-4-40-ghz/specifications.html)
- [微软 WSL 手动安装要求](https://learn.microsoft.com/en-us/windows/wsl/install-manual)
- [微软 Windows 10 支持结束说明](https://support.microsoft.com/en-us/servicing/os/windows-10/2025/10/october-14-2025-kb5066586-os-build-17763-7919)
- [仓颉官网下载中心](https://cangjie-lang.cn/download)
- [仓颉官方工具链安装指南](https://docs.cangjie-lang.cn/docs/1.0.0/user_manual/source_zh_cn/first_understanding/install_Community.html)
