# Speedtest 与加密检查证据记录

日期：2026-09-30。未更改任何安全、网络或更新策略。

## 测速

- 用户截图：网页下载183.33 Mbps、上传199.59 Mbps、延迟8 ms；桌面版339.63/191.79 Mbps、延迟6 ms。
- 本轮实际启动已安装 Ookla Speedtest 1.27.200.0，观察测试结束：下载349.47 Mbps、上传193.49 Mbps、延迟6 ms，显示MagtiCom/Tbilisi。
- Chrome网页复测被浏览器工具的站点安全策略阻止，未绕过。网页数值来自用户截图，不是本轮自动复测。不能确认同一服务器编号、相同测试时刻或连接方式。
- 截图网页下载比桌面低约46.0%；不代表所有网页实际下载都被限速。

## 安全检查

- 受信任根存储存在Kaspersky Endpoint Security Personal Certification Authority。证书存在不等于某条连接被检查。
- 独立curl HTTPS请求www.microsoft.com成功，所见链为Microsoft TLS G2 RSA CA OCSP 04 / Microsoft TLS RSA Root G2 / DigiCert Global Root G2。该请求未见Kaspersky替换证书，不能据此排除Chrome或其他地址的选择性检查。
- Defender AMRunningMode=Normal，AntivirusEnabled=True，RealTimeProtectionEnabled=True。
- AVP.KES.14.1=Stopped；avpsus.KES.14.1及klnagent=Running。未修改这些状态，需IT核对是否预期。
- 亿赛通CdgTwin64、天锐LdTerm及LdTermDaemon、MsMpEng进程存在。进程存在不证明其检查了测速流量或发送内容给厂商。
- 测试过程单次CPU采样不能建立因果；服务低CPU也不能排除驱动或浏览器内模块开销。

## 未确定项

尚未获得实际Chrome测速连接证书、检查策略命中、网关审计或相同节点的同步资源轨迹。因此不能认定速度差来自TLS解密、文件透明加密、某个厂商或监控者。

## 下一步

用户或IT手动执行同一具体节点的交替网页/桌面测试，各三次且不同时运行。记录时间、节点编号、连接模式和CPU/网络使用。IT核对该时段实际策略命中与浏览器测速目标证书。任何例外测试必须由IT批准并在受控环境执行；本轮不关闭防护、不增加例外。
