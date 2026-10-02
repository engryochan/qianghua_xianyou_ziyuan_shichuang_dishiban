from pathlib import Path  # 只向用户指定下载目录写入新文件。
import argparse, datetime, hashlib, json, shutil, urllib.request, zipfile  # 使用标准库，不安装额外下载工具。
parser = argparse.ArgumentParser()  # 接收已核实的官方URL与固定文件名。
parser.add_argument('--url',required=True)  # 下载URL来自已保存的官方页面。
parser.add_argument('--name',required=True)  # 文件名不得含目录。
parser.add_argument('--source',required=True)  # 保存厂商来源页供复核。
args = parser.parse_args()  # 不读取平台账号或凭据。
assert args.url.startswith('https://') and Path(args.name).name == args.name  # 使用HTTPS并防止越出目标目录。
destination = Path('C:/Users/PPCCpcpc/Downloads')  # 使用已经实测存在的Windows下载目录。
target = destination / args.name  # 不覆盖既有个人文件。
partial = destination / (args.name+'.part')  # 未完成包明确标记，不能当成成功包。
record = {'name':args.name,'url':args.url,'source':args.source,'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'executed':False}  # 只下载，不安装或运行。
try:  # 即使失败也保存原因。
    assert not target.exists() and not partial.exists(), 'Existing file preserved'  # 保留同名文件，不盲目覆盖或删除。
    assert shutil.disk_usage(destination).free > 20*1024**3, 'Insufficient reserve'  # 保留系统与后续开发空间。
    request = urllib.request.Request(args.url,headers={'User-Agent':'Mozilla/5.0'})  # 普通HTTPS，保留系统证书校验。
    with urllib.request.urlopen(request,timeout=45) as response:  # 使用厂商正常重定向，不规避访问控制。
        length = int(response.headers.get('Content-Length','0'))  # 读取服务器声明的大小。
        assert length <= 4*1024**3, 'Package exceeds transfer budget'  # 防止异常大文件占满系统盘。
        record.update({'final_url':response.url,'declared_bytes':length,'content_type':response.headers.get('Content-Type')})  # 记录真实来源与响应。
        assert response.url.startswith('https://'), 'Redirected to insecure transport'  # 不静默降低传输保护。
        digest, total = hashlib.sha256(), 0  # 哈希用于文件完整性记录，不冒充厂商签名。
        with partial.open('xb') as output:  # 独占创建新文件，不覆盖现有内容。
            while True:  # 持续下载直到服务器EOF。
                chunk = response.read(1024*1024)  # 分块下载，避免大内存占用。
                if not chunk: break  # EOF后才能进入验证。
                total += len(chunk)  # 记录实际字节数。
                assert total <= 4*1024**3, 'Transfer exceeds package budget'  # 无Content-Length时仍限制体积。
                output.write(chunk)  # 保存原始包，不解包或执行。
                digest.update(chunk)  # 流式计算SHA256。
        assert total > 0 and (not length or total == length), 'Truncated download'  # 区分完整传输与截断包。
    with partial.open('rb') as sample:  # 检查文件头，不执行代码。
        magic = sample.read(4)  # EXE应为MZ，APK应为ZIP。
    assert magic.startswith(b'MZ' if args.name.endswith('.exe') else b'PK'), 'Unexpected package format'  # 避免将HTML错误页当成安装包。
    if args.name.endswith('.apk'):  # Android包至少应有清单，不声称已验证开发者签名。
        with zipfile.ZipFile(partial) as archive:  # 只读检查归档结构。
            assert 'AndroidManifest.xml' in archive.namelist(), 'Not an Android package'  # 排除错误ZIP文件。
    partial.rename(target)  # 验证后在同目录命名为正式文件。
    record.update({'status':'DOWNLOADED','bytes':total,'sha256':digest.hexdigest(),'path':str(target)})  # 完成状态与真实文件相对应。
except Exception as error:  # 失败文件保留.part标记，不冒充已下载。
    record.update({'status':'FAILED','error':type(error).__name__+': '+str(error)[:250]})  # 保留可复核原因。
(Path(__file__).parent / ('download-result-'+args.name+'.json')).write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')  # 保存逐包证据。
print(json.dumps(record,ensure_ascii=True))  # 兼容GBK终端，避免改变公司区域设置。
