from pathlib import Path  # 限定本地证据输出位置。
import concurrent.futures, datetime, html, json, re, urllib.request  # 使用标准库读取公开商店元数据。
games = [(1842810,'太阁立志传Ⅴ DX'),(39680,'The Guild II Renaissance'),(311260,'The Guild 3'),(612720,'SAELIG'),(838350,'太吾绘卷'),(1948980,'大侠立志传'),(1696440,'绝世好武功'),(1222670,'模拟人生4'),(261550,'骑马与砍杀Ⅱ：霸主'),(233860,'Kenshi'),(2135150,'Elin'),(1129580,'Medieval Dynasty'),(1331550,'Big Ambitions'),(2161440,'风帆纪元'),(1424800,'大航海时代Ⅳ HD'),(1574360,'大航海时代：起源'),(335620,'Star Traders: Frontiers'),(1063790,'Citizen of Rome'),(2288150,'三国志8 REMAKE'),(1158310,'Crusader Kings III'),(205610,'Port Royale 3'),(1024650,'Port Royale 4'),(57620,'Patrician IV'),(1336980,'信长之野望·新生'),(779340,'Total War: THREE KINGDOMS'),(3450310,'Europa Universalis V'),(281990,'Stellaris'),(1295660,'Civilization VII'),(1466860,'Age of Empires IV'),(1407450,'大江湖之苍龙与白鸟')]  # 登记具体作品，模糊系列不冒充单一产品。
def fetch(game):  # 每个作品独立核验，失败不默认为支持。
    appid, expected = game  # 读取稳定商店标识。
    url = f'https://store.steampowered.com/api/appdetails?appids={appid}&l=english&cc=us'  # 使用官方公开API，不登录用户账号。
    result = {'appid':appid,'expected':expected,'source':f'https://store.steampowered.com/app/{appid}/','api':url}  # 保存可复核出处。
    try:  # 单项错误保留，不中断其他只读查询。
        request = urllib.request.Request(url, headers={'User-Agent':'Mozilla/5.0'})  # 普通HTTPS访问，不更改代理或证书校验。
        with urllib.request.urlopen(request, timeout=15) as response:  # 设置超时，保留系统TLS校验。
            payload = json.load(response)  # 解析服务器返回的JSON。
        (Path(__file__).parent / f'steam-{appid}.json').write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')  # 保存原始公共产品证据。
        entry = payload.get(str(appid),{})  # 不误用其他作品的数据。
        if not entry.get('success'):  # 下架、地区差异和接口错误不强行补值。
            result['error'] = 'API success=false'  # 明确标记UNKNOWN。
        else:  # 只处理成功返回的产品信息。
            data = entry['data']  # 读取产品详细数据。
            minimum = data.get('pc_requirements',{}).get('minimum','')  # 提取PC最低需求。
            plain = html.unescape(re.sub('<[^>]+>',' ',minimum))  # 将需求HTML变成可读文本，不执行HTML。
            result.update({'name':data.get('name'),'type':data.get('type'),'platforms':data.get('platforms'),'pc_minimum':re.sub(r'\s+',' ',plain).strip(),'categories':data.get('categories',[]),'release':data.get('release_date')})  # 保存Windows、工坊及发行信息，非本机验收。
    except Exception as error:  # 保留失败类型，避免输出敏感环境内容。
        result['error'] = type(error).__name__ + ': ' + str(error)[:180]  # 不自动规避公司网络限制。
    return result  # 每项均返回可追溯状态。
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:  # 适度并发独立的公开元数据查询。
    results = list(pool.map(fetch,games))  # 等待全部目标得到成功或错误结果。
output = {'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'OFFICIAL_PLATFORM_METADATA_NOT_LOCAL_GAME_TEST','results':results}  # 明确时间与验证范围。
(Path(__file__).parent / 'steam-platforms.json').write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')  # 写入机器可读清单。
print(json.dumps([{'expected':row['expected'],'name':row.get('name'),'windows':(row.get('platforms') or {}).get('windows'),'error':row.get('error')} for row in results],ensure_ascii=True))  # ASCII转义兼容本机GBK终端，不修改系统区域设置。
