# 大秦赋算筹：游戏 Windows 支持与开发工具核查

核查日期：2026-10-02。输入：工作区当前 `_大秦赋算筹_v1_3_0.qmd`，重点为 §37.3.1、§38.2.2、§40.2、§41.3，并搜索其他章节的作品名称。范围：35 个明确作品、1 个仅用于消歧的作品，以及 1 个未能唯一定位的名称。系列泛称按文档的具体作品展开，不等同核查该系列全部历代产品。DLC/威力加强版单独注明，不重复计算作品数。

本轮是官方产品资料与平台元数据核查，没有安装、启动或测试游戏帧率，也没有更改公司安全软件、系统设置或原 QMD。Windows 版存在不等于本机 Windows 11、显卡、语言、账号区域与全部扩展已经验收。手机游戏的模拟器运行也不等于原生 Windows 版。

## 判定与证据

- 30 个 Steam 条目查询中，28 项成功返回且 `platforms.windows=true`，包括仅用于消歧的大江湖；两个条目返回 `success=false`，改用厂商系统需求页补核。这是接口失败/地区限制的未知结果，不能解释为“不支持 Windows”。
- 明确清单的 35 款中，30 款已确认存在 Windows 版本；4 款现有页面只有 Android/iOS 信息，尚未确认原生 Windows；三国志战略版有厂商历史桌面版公告，当前客户端架构与可用性仍待核。
- 原始响应在 `steam-<appid>.json`，汇总在 `steam-platforms.json`。首次沙盒访问连接被拒；获准只读访问后成功保存上述响应。首次成功查询的终端摘要遇到 GBK 无法编码 ™ 字符，JSON 已先保存；输出脚本改为 ASCII 转义，不改变系统区域设置。
- 本轮没有确认这些作品提供完整、可用于重新编译及融合发行的游戏源码与授权。下表工具是可核实的事件/数据/模组工具，不能据此反推出厂商私有引擎的编译器。

工具记号：**D**＝独立实现大秦模型：VS Code 编辑器＋Python 运行时＋SQL 数据层；不是该游戏源码的编译器。**W**＝官方 Steam 元数据有 Workshop，但具体制作 SDK、脚本版本及授权尚需逐项审阅；工坊不等于开源。**M**＝已有明确的厂商模组/事件工具说明。D 可用于所有作品的机制研究，但不自动获得游戏代码、素材或导出数据的使用权。

## 逐项清单

| # | 文档中的具体作品 | Windows 支持 | 可用开发途径／需要的工具 | 平台依据 |
|---|---|---|---|---|
| 1 | 太阁立志传Ⅴ DX | 是；明确含 Windows 11 中文 64 位 | M：官方事件编辑／Event Converter，文本编辑器可辅助；地区版本工具交付需核。D：职业与履历模型 | [厂商系统需求](https://www.gamecity.com.tw/taikou5dx/windows_spec.html) |
| 2 | The Guild II Renaissance | 是 | D；完整源码与正式制作 SDK 未确认 | [Steam](https://store.steampowered.com/app/39680/) |
| 3 | The Guild 3 | 是 | W＋D；制作工具与版本待核 | [Steam](https://store.steampowered.com/app/311260/) |
| 4 | SAELIG | 是 | D；完整源码与正式制作 SDK 未确认 | [Steam](https://store.steampowered.com/app/612720/) |
| 5 | 太吾绘卷 | 是 | W＋D；不猜测原引擎编译器 | [Steam](https://store.steampowered.com/app/838350/) |
| 6 | 大侠立志传 | 是 | W＋D；模组 SDK 细节待核 | [Steam](https://store.steampowered.com/app/1948980/) |
| 7 | 绝世好武功 | 是 | W＋D；模组 SDK 细节待核 | [Steam](https://store.steampowered.com/app/1696440/) |
| 8 | 模拟人生4；Get to Work／Get Famous | 本体是；扩展依赖本体，不是独立操作系统 | D；游戏脚本运行时须对应游戏版本，本轮未核定其编译链 | [Steam 本体](https://store.steampowered.com/app/1222670/) |
| 9 | 骑马与砍杀Ⅱ：霸主 | 是 | M：Bannerlord Modding Kit；C# 模组用 Visual Studio／匹配的 .NET 与 MSBuild；XML 与资产编辑 | [Steam](https://store.steampowered.com/app/261550/) |
| 10 | Kenshi | 是 | M：Forgotten Construction Set（FCS）数据编辑；不需要重编游戏引擎；D | [Steam](https://store.steampowered.com/app/233860/) |
| 11 | Elin | 是 | W＋D；具体 SDK／C# 接口版本待核，不直接套用其他游戏工具链 | [Steam](https://store.steampowered.com/app/2135150/) |
| 12 | Medieval Dynasty | 是 | D；完整源码与正式制作 SDK 未确认 | [Steam](https://store.steampowered.com/app/1129580/) |
| 13 | Big Ambitions | 是 | W＋D；工坊制作范围待核 | [Steam](https://store.steampowered.com/app/1331550/) |
| 14 | 风帆纪元 | 是 | D；完整源码与正式制作 SDK 未确认 | [Steam](https://store.steampowered.com/app/2161440/) |
| 15 | 大航海时代Ⅳ with 威力加强版 HD Version | 是；不能将旧需求页视作本机 Windows 11 验收 | D；完整源码与正式制作 SDK 未确认 | [厂商系统需求](https://www.gamecity.ne.jp/d4/hd/windows_spec.html) |
| 16 | 大航海时代：起源 | 是；网络服务及地区可用性另核 | D；客户端、服务器源码及接口授权未确认 | [Steam](https://store.steampowered.com/app/1574360/) |
| 17 | Star Traders: Frontiers | 是 | W＋D；制作与数据接口范围待核 | [Steam](https://store.steampowered.com/app/335620/) |
| 18 | Citizen of Rome — Dynasty Ascendant | 是 | W＋D；完整源码及 SDK 未确认 | [Steam](https://store.steampowered.com/app/1063790/) |
| 19 | 三国志8 REMAKE／with Power Up Kit | 本体是；PK 交付与需求另核，不能由本体 API 证明所有附加产品状态 | D；游戏内编辑功能不等于提供原游戏源码；正式编译链未确认 | [Steam 本体](https://store.steampowered.com/app/2288150/) |
| 20 | Crusader Kings III／Roads to Power | 本体是；扩展依赖本体 | M：事件／数据脚本与官方编辑能力；VS Code 可编辑，游戏加载；D。版本语法需复核 | [Steam](https://store.steampowered.com/app/1158310/) |
| 21 | Port Royale 3 | 是 | D；完整源码与正式制作 SDK 未确认 | [Steam](https://store.steampowered.com/app/205610/) |
| 22 | Port Royale 4 | 是 | D；完整源码与正式制作 SDK 未确认 | [Steam](https://store.steampowered.com/app/1024650/) |
| 23 | Patrician IV | 是 | D；完整源码与正式制作 SDK 未确认 | [Steam](https://store.steampowered.com/app/57620/) |
| 24 | Capitalism Lab | 是；厂商明确含 Windows 11 | M：官方 MOD Kit、资源构建工具、TXT 场景脚本／生成器；D | [厂商需求](https://www.capitalismlab.com/buy-game/system-requirements/) |
| 25 | 大周列国志 | 未确认原生 Windows；当前入驻页列 Android/iOS | D；无已核实的完整源码／编译 SDK；模拟器仅是运行途径 | [入驻页](https://www.taptap.cn/app/190784) |
| 26 | 信长之野望·新生／Awakening | 是；不同地区及加强版另核 | D；游戏内人物／剧本编辑不等于引擎源码，完整编译链未确认 | [Steam](https://store.steampowered.com/app/1336980/) |
| 27 | Total War: THREE KINGDOMS | 是 | D；Assembly Kit 是待进一步核对当前官方文档与交付的候选工具，本轮官网链接无法读取；不列为已完成工具验证 | [Steam](https://store.steampowered.com/app/779340/) |
| 28 | Europa Universalis V | 是 | W＋D；官方 Wiki 本轮 401，脚本语法与制作链尚未完成复核，不套用 EU IV 工具 | [Steam](https://store.steampowered.com/app/3450310/) |
| 29 | Stellaris | 是 | W＋D；脚本／数据模组制作文档本轮未完整读取，不宣称已核定全部工具 | [Steam](https://store.steampowered.com/app/281990/) |
| 30 | Civilization VII | 是 | M：官方 Modding SDK／Development Tools＋Steam Workshop；SDK 内容用文本编辑器辅助，具体版本按 SDK 文档 | [Steam](https://store.steampowered.com/app/1295660/) |
| 31 | Age of Empires IV | 是 | M：Content Editor，地图／Tuning Packs／游戏模式；不是重编原引擎；D | [Steam](https://store.steampowered.com/app/1466860/) |
| 32 | 大秦帝国之帝国烽烟 | 未确认原生 Windows；当前入驻页列 Android/iOS | D；源码／正式 SDK 未确认 | [入驻页](https://www.taptap.cn/app/166665) |
| 33 | 无悔华夏 | 未确认原生 Windows；当前入驻页列 Android/iOS | D；源码／正式 SDK 未确认 | [入驻页](https://www.taptap.cn/app/176581) |
| 34 | 猫话列国 | 未确认原生 Windows；入驻页为手机游戏预约，不代表已可安装 | D；产品可用性、源码／SDK 未确认 | [入驻页](https://www.taptap.cn/app/234249) |
| 35 | 三国志·战略版 | 厂商 2019 公告提桌面版；当前原生 Windows 客户端、模拟器或包装层未核定 | D；服务端与客户端源码／SDK 未确认；不能凭历史公告保证当前安装成功 | [厂商桌面版公告](https://sgz.ejoy.com/news/detail-4107.html) |

另列：

| 文档名称 | 核查结果 | 工具与限制 |
|---|---|---|
| 大江湖之苍龙与白鸟 | [Steam](https://store.steampowered.com/app/1407450/) 官方 API 确认 Windows；文档仅为名称消歧提及，不是 GM 主清单 | D；本轮未确认完整源码／制作 SDK |
| 春秋战国 | 文档原本标记名称不唯一，不能核定 Windows，也不能确定编译器 | 先确定发行商、完整标题与产品 ID；不擅自替换为“华夏史诗：战国” |

## 已确认的制作工具依据

1. 太阁事件工具：[中文官网事件编辑说明](https://www.gamecity.com.tw/taikou5dx/)；[DX Event Converter 官方手册](https://www.gamecity.ne.jp/manual/KSjyrFfh/Taiko5DXEV_JP/)。事件文本转换不等于编译游戏源码；日文手册不保证所有地区版本提供完全相同的工具。
2. Bannerlord：[厂商 Mod 文档](https://moddocs.bannerlord.com/)；[C# 自定义模式与 Visual Studio 示例](https://moddocs.bannerlord.com/multiplayer/custom_game_mode/)。应按当前游戏 SDK 匹配目标框架与引用，不能把“最新版 .NET”一律替换进去。
3. Kenshi：[Lo-Fi 官方日文更新说明含 FCS](https://kenshi-jp.hatenablog.com/entry/Main_Update1.0.64)；[厂商模组论坛](https://www.lofigames.com/phpBB3/viewforum.php?f=11)。FCS 编辑数据；不需要假设 C++ 引擎源码可下载。
4. CK3：[厂商 Royal Modding 开发日志](https://www.paradoxinteractive.com/games/crusader-kings-iii/news/dev-diary-87-royal-modding)。证明脚本／编辑能力，不代表本轮已验收当前全套语法。
5. Capitalism Lab：[官方 MOD 制作说明](https://www.capitalismlab.com/mod/how-to-make-a-mod/)；[脚本基础](https://www.capitalismlab.com/scripts/script-basics/)；[工具](https://www.capitalismlab.com/modding-tools/)。是游戏内容构建，不是通用操作系统编译器。
6. Civilization VII：[2026-08 更新的官方模组 FAQ](https://support.civilization.com/hc/en-us/articles/44037954953235-Civilization-VII-Third-Party-Party-Mods-FAQ)。确认 SDK／Workshop 支持；不照搬 Civilization V 的 ModBuddy 为 VII 的已验证工具。
7. AoE IV：[官方 Tuning Packs 文档入口](https://support.ageofempires.com/hc/en-us/sections/4409121920276-Tuning-Packs)；[官方 Content Editor 发布说明](https://www.ageofempires.com/news/age-of-empires-iv-season-one-update-release-notes/)。旧发布说明使用 Beta 名称，不用于断言今天的工具成熟度。

## 编译器、编辑器与独立研发

[VS Code](https://code.visualstudio.com/docs/languages/overview) 是编辑器。Python 使用 Python 运行时；C# 使用对应 .NET SDK／MSBuild；有合法 C/C++ 源码才考虑 MSVC／Clang 与项目构建配置。这些工具不能从一个 EXE 自动恢复完整可维护源码、原素材与构建系统。安装游戏也不会获得原游戏的私有代码。

《大秦赋算筹》首期建议：**VS Code＋隔离的 Python 环境＋SQLite（业务事件）／DuckDB（分析）＋轻量浏览器界面**。这是架构建议，不是声称本机依赖已全部通过验收。Godot 可作为后续需要地图与场景交互时的候选；其引擎以 [MIT 许可开放](https://godotengine.org/license/)，与商业游戏是否开源是两回事。先测试小型二维场景、驱动兼容与内存，不直接引入大型三维引擎。

独立核心先实现 `Person / Career / Skill / Reputation / Organization / Institution / Commodity / Inventory / Trade / Event`。各模块交换自有 JSON／CSV 与明确版本的数据契约；只有游戏提供且授权允许的导出／API 才做适配器。不预设所有游戏都能相互读取存档或交换状态。

首个验收闭环：一个人物、三种职业、五项技能、三种商品、一座市场，完成学习→交易→库存／资金变化→声望／履历记录→保存重开→事件重放。检查资金与库存约束、相同输入可重放、存档兼容、响应时间与内存。先秦礼制、制度与事件绑定可追溯史料；虚构数值与真实履历分开，游戏技能分数不代表现实职业能力认证。

待核心通过后，选择一款职业模型参考和一款企业经济模组做研究实验；不需先把 35 款游戏全部装入空间紧张的公司电脑。人工智能可辅助生成与审阅自有代码，但不能凭空获得商业游戏源码、替代授权或证明算法正确。

## 审阅盲点与后续验证

- Windows metadata ≠ Windows 11 及本机性能保证；老游戏还需显示、字体、存档路径与安全软件兼容验收。
- 模组支持 ≠ 引擎源码开放；工坊条目 ≠ SDK 版本、API 稳定性与再发行许可。
- TapTap 导航栏的“下载 PC 版”是平台入口，不能当作所展示手机游戏的原生 Windows 证据。
- 厂商历史桌面版公告 ≠ 当前下载可用或原生架构；预约页 ≠ 游戏已发布。
- 模组可能随本体更新失效，保持游戏与模组版本对应；“禁止退化”采用基线与回归验收，而非承诺所有最新版绝对更优。
- 需要维护组织资安兼容时，由 IT 审核安装与允许的接口，不修改或规避现有公司防御设置。

当前证据足以选择独立研发路线；尚不足以承诺所有游戏代码互搭、全部最新扩展已兼容、或该电脑已能运行全部作品。
