# C盘空间与WSL准备实测

日期：2026-10-02。只读盘点，未清理文件、安装WSL或修改公司网管及资安策略。

## 当前容量

结束时已用193932124160字节（180.62 GiB），可用60771512320字节（56.60 GiB），总量237.21 GiB。相较10月1日最后一次可用57.70 GiB，少约1.10 GiB；本轮不能确定期间增长文件及操作主体。

## 已核实的重要目录

| 项目 | 逻辑大小 | 覆盖范围 |
|---|---:|---|
| 恢复数据库 | 28.30 GiB | 1971文件，完整枚举 |
| basic-data-analytical-lab/.git | 7.63 GiB | 完整枚举；主历史包7.62 GiB |
| pagefile.sys | 15.91 GiB | 当前系统文件长度 |
| Chrome/User Data | 8.16 GiB | 41249文件，完整元数据枚举 |
| C:/work/projects | 1.27 GiB | 完整枚举 |
| C:/work/envs | 至少5.34 GiB | 时间预算内部分扫描，不能视为完整大小 |
| 用户临时目录 | 约62.4 MiB | 完整枚举，但在用文件需跳过 |
| Downloads | 282字节 | 完整枚举 |

恢复数据库路径：C:/Users/PPCCpcpc/OneDrive/文档/GitHub/basic-data-analytical-lab/风控案例/a168风控与客户分析评分体系/数据库。

旧版10万行样本目录仅约100.4 MiB，不能与恢复数据库混同。uv缓存及.cache扫描未完成，大小不能当作完整总量。逻辑大小可能受硬链接和云占位文件影响，不能据此精确预测释放量。

10月1日已完成的管理员全卷分配报告另确认：NTFS元数据2.52 GiB、System Volume Information 3.04 GiB、系统保留2.57 GiB。此处为昨日快照，未重新执行全卷分配扫描。卷影副本已包含在System Volume Information中，不能重复计算。其余空间包括Windows、安装软件、用户数据及分析工具；本轮不冒充完整全盘目录审计。

## 清理候选

- Chrome普通Cache、Code Cache、GPUCache逻辑合计约1.39 GiB。应通过浏览器清除缓存选项处理，保留密码、登录状态与企业扩展。
- Service Worker/CacheStorage约0.71 GiB，可能存有网页离线工作内容，需要先核验使用需求。
- 用户Temp约62.4 MiB，清理只能跳过在用文件。
- uv缓存应先完成盘点，再采用官方uv cache prune；硬链接意味着缓存逻辑长度不等于空间收益。
- 28.30 GiB数据库及Git历史不得当作垃圾。若要迁移，须先完成独立备份、校验和恢复验证。目录名为旧版或废弃不等于已授权删除。
- 保留分页文件、恢复分区、安全代理、分析环境、Codex运行时与回滚证据。

## WSL建议预算

建议先装一个发行版并使用小样本。规划为Windows留25–30 GiB机动空间，每个实验发行版先预算10–15 GiB（人为预算，不是官方最低要求）；当前空间不适合同时建立多份完整数据副本。WSL发行版虚拟磁盘随数据增长，默认显示的1TB是虚拟最大值，不是预先占用1TB。

需要多个长期数据分析系统时，优先由IT批准增加SSD并放置发行版虚拟磁盘。WSL2用于比较Linux发行版与工作流，不能替代独立启动系统的全部硬件性能测试。

来源：https://learn.microsoft.com/en-us/windows/wsl/disk-space

来源：https://docs.astral.sh/uv/concepts/cache/
