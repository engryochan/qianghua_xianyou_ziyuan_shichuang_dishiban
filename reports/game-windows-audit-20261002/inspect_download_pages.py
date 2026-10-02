from pathlib import Path  # 限制证据输出在本次报告目录。
import concurrent.futures, html, json, re, urllib.request  # 只读官方网页，不改变网络或安全策略。
pages = ['https://whhx.ehijoy.com/javascripts/down_html/main.js']  # 下载页明确引用的公开脚本；仅当数据读取，不执行网页代码。
def inspect(url):  # 独立保留每个页面的结果。
    result = {'page':url}  # 保存来源，不将第三方包冒充官方。
    try:  # 页面访问失败不进行规避。
        request = urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0'})  # 使用普通HTTPS与系统证书校验。
        with urllib.request.urlopen(request,timeout=25) as response:  # 只取得网页，尚未下载或执行安装包。
            raw = response.read(8000000)  # 限制网页读取体积。
            final = response.url  # 保存正常重定向后的来源。
        page = raw.decode('utf-8',errors='replace')  # 用于提取网址，非执行网页脚本。
        (Path(__file__).parent / ('download-page-'+re.sub(r'[^a-zA-Z0-9]+','_',url)+'.html')).write_text(page,encoding='utf-8')  # 保存证据。
        urls = sorted(set(html.unescape(value).replace('\\/','/') for value in re.findall(r'https?[^\s<>"\x27]+',page)))  # 提取明确写出的网址。
        result.update({'final':final,'links':[value for value in urls if any(key in value.lower() for key in ['.apk','.exe','download','down_url','ehijoy','ejoy.com','xinglan'])]})  # 只输出可能相关的入口。
    except Exception as error:  # 明确保留失败而非猜测下载地址。
        result['error'] = type(error).__name__+': '+str(error)[:200]  # 不输出登录信息。
    return result  # 返回逐页核查。
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:  # 少量并行只读网页。
    results = list(pool.map(inspect,pages))  # 等待全部页面得到结果。
(Path(__file__).parent / 'download-links.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')  # 保存机器可读来源。
print(json.dumps(results,ensure_ascii=True))  # ASCII输出避免GBK终端乱码。
