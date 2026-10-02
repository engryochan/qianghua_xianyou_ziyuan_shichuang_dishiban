from pathlib import Path  # 将公开产品证据保存在本次报告目录。
import concurrent.futures, datetime, json, urllib.request  # 只读查询官方API，不登录、不安装。
targets = [(1565750,'SAELIG'),(2286710,'绝世好武功'),(3288620,'Elin'),(2162830,'风帆纪元'),(1407510,'大江湖之苍龙与白鸟')]  # 来自已保存官方本体元数据的demo标识。
def check(target):  # 每款试玩版独立记录，失败不冒充可下载。
    appid, game = target  # 明确作品对应。
    row = {'appid':appid,'game':game,'url':f'https://store.steampowered.com/app/{appid}/'}  # 保存官方入口。
    try:  # 只处理合法公开响应。
        request = urllib.request.Request(f'https://store.steampowered.com/api/appdetails?appids={appid}&l=english&cc=us',headers={'User-Agent':'Mozilla/5.0'})  # 保持正常HTTPS证书校验。
        with urllib.request.urlopen(request,timeout=20) as response: payload = json.load(response)  # API没有下载游戏或接受条款。
        (Path(__file__).parent / f'demo-{appid}.json').write_text(json.dumps(payload,ensure_ascii=False,indent=2),encoding='utf-8')  # 保存原始响应。
        item = payload.get(str(appid),{})  # 不误用其他产品。
        data = item.get('data',{})  # 失败没有数据时保持未知。
        row.update({'api_success':item.get('success',False),'name':data.get('name'),'type':data.get('type'),'windows':data.get('platforms',{}).get('windows'),'is_free':data.get('is_free')})  # 这仍是平台资料核查，不是包下载。
    except Exception as error: row['error'] = type(error).__name__+': '+str(error)[:160]  # 不规避访问限制。
    return row  # 逐项保留结果。
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool: results = list(pool.map(check,targets))  # 有界并行公开查询。
(Path(__file__).parent / 'demo-availability.json').write_text(json.dumps({'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'results':results},ensure_ascii=False,indent=2),encoding='utf-8')  # 保存本轮日期与范围。
print(json.dumps(results,ensure_ascii=True))  # 避免GBK终端无法输出特殊字符。
