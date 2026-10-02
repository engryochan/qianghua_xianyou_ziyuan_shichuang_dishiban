from pathlib import Path  # 所有来源读取本次核查目录。
import csv, datetime, json, re  # 使用标准库生成逐项清单。
root = Path(__file__).parent  # 明确证据目录。
report = (root / '游戏Windows与开发工具核查.md').read_text(encoding='utf-8')  # 使用已经审阅的35项清单。
steam = json.loads((root / 'steam-platforms.json').read_text(encoding='utf-8'))['results']  # 原始平台核查是资料证据，不是实际下载。
by_id = {row['appid']:row for row in steam}  # 按产品ID对应，避免串错标题。
mobile = {25:'公开官网可读取但未找到独立包；HTTPS入口握手失败，未取得APK',32:'官网已找到包链接，但HTTPS下载连接被远端中断，未取得APK',33:'官方包地址已追踪，下载结果见下',34:'预约产品，未取得已发布安装包',35:'已找到官方下载配置入口，最终结果见包记录'}  # 保存最新观察，不将旧入口失败当成没有安装包。
records = []  # 主清单逐项记录。
for line in report.splitlines():  # 只解析明确编号的表格。
    if not re.match(r'^\| \d+ \|',line): continue  # 排除标题、工具及消歧表。
    columns = [value.strip() for value in line.strip('|').split('|')]  # 原表无嵌套竖线。
    number, game = int(columns[0]), columns[1]  # 保存序号与完整名称。
    url = re.search(r'\]\((https?[^)]+)\)',columns[-1]).group(1)  # 保存官方产品页或入驻页。
    status = mobile.get(number,'授权与下载渠道待核，未取得免费独立本体包')  # 未下载状态不写成成功。
    app_match = re.search(r'/app/(\d+)',url) if 'steampowered.com' in url else None  # 不将TapTap编号当成Steam产品。
    if app_match:  # 使用已保存官方API判断免费本体与付费本体。
        appid = int(app_match.group(1))  # 定位对应游戏。
        payload_path = root / f'steam-{appid}.json'  # 不额外联网或改变授权。
        payload = json.loads(payload_path.read_text(encoding='utf-8')).get(str(appid),{}) if payload_path.exists() else {}  # 接口失败保留未知。
        data = payload.get('data',{})  # 只处理实际返回的资料。
        if data.get('is_free') is True: status = '官方标记免费本体；需游戏平台账号及客户端下载，未下载本体'  # 免费游戏不等于独立安装包。
        elif data.get('is_free') is False: status = '官方渠道付费本体；按用户仅免费要求未下载；试玩版另核'  # 不付款、不替代为来源不明包。
    if number == 24: status = '官网安装包可免费取得；游戏运行需注册授权，结果见下载记录'  # 避免混淆免费包与免费游戏。
    records.append({'序号':number,'游戏':game,'官方出处':url,'处理结果':status,'安装包已下载':False})  # 每项都有明确状态，不冒充安装验收。
assert [row['序号'] for row in records] == list(range(1,36))  # 确认没有漏项。
downloads = [json.loads(path.read_text(encoding='utf-8')) for path in sorted(root.glob('download-result-*.json'))]  # 仅以实际包记录决定完成状态。
successful = [row for row in downloads if row.get('status') == 'DOWNLOADED']  # 错误HTML与.part不算已下载。
for row in records:  # 将真正下载成功的包对应到主清单。
    matching = [item for item in successful if (row['序号']==24 and item['name']=='Capitalism_Lab_Installer.exe') or (row['序号']==33 and item['name']=='WuhuiHuaxia_Android_official.apk') or (row['序号']==35 and item['name']=='Sanguozhi_Zhanlue_official.apk')]  # 只匹配已核定作品与文件名，不将下载链接算作包。
    if matching: row.update({'安装包已下载':True,'处理结果':'官方安装包已保存；未执行；'+matching[0]['name']})  # 明确安装包下载不是安装或运行验收。
records += [{'序号':36,'游戏':'大江湖之苍龙与白鸟（仅消歧提及）','官方出处':'https://store.steampowered.com/app/1407450/','处理结果':'付费游戏平台渠道，未取得免费独立本体包','安装包已下载':False},{'序号':37,'游戏':'春秋战国（名称不唯一）','官方出处':'','处理结果':'无法唯一定位产品，未下载','安装包已下载':False}]  # 对补充提及的两个名称也逐项登记。
csv_path = root / '游戏下载清单.csv'  # 先在工作区形成可审阅结果。
with csv_path.open('w',encoding='utf-8-sig',newline='') as output:  # UTF8 BOM方便Windows Excel读取中文。
    writer = csv.DictWriter(output,fieldnames=list(records[0]))  # 保持每项相同字段。
    writer.writeheader(); writer.writerows(records)  # 一次写出35项，均非运行代码。
lines = ['# 大秦赋算筹游戏下载结果','',f'生成时间：{datetime.datetime.now().astimezone().isoformat()}。只下载免费取得的官方包；不付款、不安装、不执行。','',f'主清单35项，另外两个补充名称；成功保存安装包 {len(successful)} 个。游戏平台客户端不冒充游戏本体。','', '| 文件 | 字节数 | SHA256 |','|---|---:|---|']  # 明确成功数与任务限制。
lines += [f"| {item['name']} | {item['bytes']} | {item['sha256']} |" for item in successful]  # 哈希是本地完整性记录，不冒充开发者签名。
lines += ['','Capitalism Lab 包已实测 Authenticode 签名有效，签名者 Enlight Software Limited；运行游戏需注册授权。','无悔华夏官网当前重定向至2026.07.10路径的APK；已检查传输大小与Android清单结构，未验证Android开发者签名或最新资源版本，不称其为最新完整游戏资源。','', '## 逐项状态','', '| 序号 | 游戏 | 状态 | 官方出处 |','|---|---|---|---|']  # 保留实际验证与版本边界。
lines += [f"| {row['序号']} | {row['游戏']} | {row['处理结果']} | [入口]({row['官方出处']}) |" for row in records]  # 提供每款的出处及未下载原因。
lines += ['','另外：大江湖之苍龙与白鸟仅为文档消歧提及，官方Steam渠道，未取得免费独立本体包；春秋战国名称不唯一，未下载。','', '手机入口补充核查：大周发布的HTTP首页及游戏页可读，但未发现独立包；其HTTPS入口握手失败。大秦发布的HTTP官网可读，明确给出APK链接，但以HTTPS下载时连接被远端中断（WinError 10054）。三国战略版官网主体连接超时，但从旧官网引用的官方CDN配置取得Android入口，其最终下载结果按上表及包记录判定。猫话列国为预约页。上述不能归因于公司安全软件或入侵。未关闭TLS证书校验或修改公司网络防御设置。','', '无悔华夏初始入口返回HTML引导页，未将其误认为APK；已保存失败记录及官方脚本来源。','', '## 免费试玩补充核查','', '用户再次明确仅保存可直接下载的独立安装包，不安装游戏平台。官方API补核确认SAELIG、绝世好武功、Elin、风帆纪元、大江湖之苍龙与白鸟有Windows免费Demo条目，但它们依赖Steam分发，未把条目或客户端冒充已下载本体。','Kenshi官网确认免费试玩入口，但为Torrent途径，不是可直接取得的独立HTTPS安装包，本轮未取得试玩本体。','', '本清单是37个名称的逐项处理结果，不是37款已下载网游。其中包括单机游戏、手游、预约作品和一个名称不明的项目。下载游戏不取得原游戏完整源码；机制参考应独立实现，商业游戏的代码、资产、存档及接口仍需各自授权。','', '详见同目录CSV与工作区原始响应、包下载记录。']  # 留下最新用户条件、实际结果与盲点。
md_path = root / '游戏下载结果.md'  # 形成用户可读结果。
md_path.write_text('\n'.join(lines)+'\n',encoding='utf-8-sig')  # BOM兼容现有中文环境。
print(json.dumps({'main_games':35,'additional_names':2,'downloaded_packages':len(successful),'files':[str(csv_path),str(md_path)]}))  # ASCII终端摘要。
