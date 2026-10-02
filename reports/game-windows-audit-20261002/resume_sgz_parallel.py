from pathlib import Path  # 使用明确的用户下载目录。
import concurrent.futures, datetime, hashlib, json, math, shutil, urllib.request, zipfile  # 标准HTTP范围下载，不安装工具。
root = Path(__file__).parent  # 仅将进度与结果写入本次报告。
destination = Path('C:/Users/PPCCpcpc/Downloads').resolve()  # 固定输出目录，不接受外部路径指令。
name = 'Sanguozhi_Zhanlue_official.apk'  # 本轮已核实官方独立包名称。
target, partial = destination / name, destination / (name+'.part')  # 保留已有下载前缀，不覆盖完成文件。
url = 'https://cddp-link.aligames.com/rlink/837883'  # 从官方站点引用的下载配置取得。
total = 3966371199  # 已由本轮官方Content-Range响应实测确认。
record = {'name':name,'url':url,'source':'https://cdn.aligames.com/prism-sgzzlb/1.0.0/prod/static/js/fabpc.64935628.js','utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'executed':False,'declared_bytes':total}  # 明确只下载。
try:  # 任何错误均保留前缀与分段供核查。
    assert partial.exists() and not target.exists(), 'Unexpected target state'  # 只续传本轮已开始的包。
    prefix = partial.stat().st_size  # 先前单连接必须已停止，固定续传位置。
    assert 0 < prefix < total and shutil.disk_usage(destination).free > 20*1024**3 + (total-prefix), 'Invalid prefix or insufficient reserve'  # 保留系统空间。
    step = math.ceil((total-prefix)/8)  # 最多八个范围连接，不改变系统全局参数。
    ranges = [(index,start,min(start+step-1,total-1)) for index,start in enumerate(range(prefix,total,step))]  # 范围必须恰好覆盖剩余字节。
    def fetch(segment):  # 各范围独立核验服务器位置。
        index,start,end = segment  # 读取预先计算的范围。
        path = destination / (name+f'.range-{index}.part')  # 只创建本轮专属分段文件。
        assert not path.exists(), 'Existing range preserved'  # 不覆盖任何既有文件。
        request = urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0','Range':f'bytes={start}-{end}'})  # 普通HTTPS范围请求，证书校验不变。
        with urllib.request.urlopen(request,timeout=45) as response:  # 只接受已核实支持的206响应。
            assert response.status == 206 and response.headers.get('Content-Range') == f'bytes {start}-{end}/{total}', 'Range mismatch'  # 防止服务器忽略范围导致重复拼接。
            assert response.url.startswith('https://'), 'Insecure redirect'  # 不降低传输保护。
            length = 0  # 每段独立统计完整性。
            with path.open('xb') as output:  # 独占创建新分段。
                while True:  # 直到范围响应结束。
                    chunk = response.read(1024*1024)  # 有界内存占用。
                    if not chunk: break  # EOF后核验长度。
                    length += len(chunk)  # 实际传输字节计数。
                    assert length <= end-start+1, 'Oversized range'  # 不接受越界数据。
                    output.write(chunk)  # 保存原始字节，不解压执行。
        assert length == end-start+1, 'Truncated range'  # 只有完整范围才能合并。
        return path  # 返回已核验分段。
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool: chunks = list(pool.map(fetch,ranges))  # 等待八段全部完成，不提前宣告成功。
    assert partial.stat().st_size == prefix, 'Prefix changed during range fetch'  # 防止另一下载进程同时写入。
    with partial.open('ab') as output:  # 严格按范围顺序接续已有前缀。
        for path in chunks:  # pool.map保留范围顺序。
            with path.open('rb') as source: shutil.copyfileobj(source,output,1024*1024)  # 分块合并，不重复整包占用内存。
    assert partial.stat().st_size == total, 'Merged size mismatch'  # 必须与官方声明总长度一致。
    with zipfile.ZipFile(partial) as archive: assert 'AndroidManifest.xml' in archive.namelist(), 'Invalid APK structure'  # 检查APK结构，不声称Android签名已验证。
    digest = hashlib.sha256()  # 对合并后的完整包计算哈希。
    with partial.open('rb') as source:  # 不运行游戏或脚本。
        for chunk in iter(lambda:source.read(1024*1024),b''): digest.update(chunk)  # 流式核验最终包。
    partial.rename(target)  # 完整验证后才成为正式安装包。
    for path in chunks:  # 只删除刚生成且已经合并的专属分段。
        assert path.resolve().parent == destination and path.name.startswith(name+'.range-'), 'Unexpected cleanup path'  # 校验绝对目标属于下载目录。
        path.unlink()  # 单文件清理，不递归删除任何目录。
    record.update({'status':'DOWNLOADED','bytes':total,'sha256':digest.hexdigest(),'path':str(target),'transfer':'verified HTTP ranges plus preserved prefix'})  # 标记真实完成结果。
except Exception as error: record.update({'status':'FAILED','error':type(error).__name__+': '+str(error)[:250]})  # 保留未知，不误报完成。
(root / ('download-result-'+name+'.json')).write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')  # 与现有清单生成器一致。
print(json.dumps(record,ensure_ascii=True))  # 兼容GBK终端，未更改区域设置。
