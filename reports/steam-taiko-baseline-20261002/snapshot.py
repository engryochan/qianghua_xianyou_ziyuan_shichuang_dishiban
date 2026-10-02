from pathlib import Path  # 使用路径对象限定读取范围。
import os, json, hashlib, csv, re, struct, datetime, winreg  # 使用标准库采集元数据与设置。
OUT = Path(__file__).resolve().parent  # 所有报告仅写入本轮工作区。
STAMP = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=4))).strftime('%Y%m%d-%H%M%S')  # 使用用户所在第比利斯时区。
DEST = OUT / STAMP  # 每次运行独立保存，便于启动后对比。
DEST.mkdir(parents=True, exist_ok=False)  # 不覆盖既有快照。
STEAM = Path(r'C:\Program Files (x86)\Steam')  # 使用实读到的客户端安装路径。
GAME = STEAM / 'steamapps/common/Taiko5DX'  # 使用安装清单中的游戏目录。
errors, rows, settings, documents, peinfo = [], [], [], [], []  # 初始化明确分域的结果。
def digest(path):  # 对文件计算校验值，不执行或修改文件。
    h = hashlib.sha256()  # 使用 SHA256。
    with path.open('rb') as handle:  # 只读打开文件。
        for block in iter(lambda: handle.read(4 * 1024 * 1024), b''): h.update(block)  # 分块控制内存。
    return h.hexdigest()  # 返回实际读到的字节指纹。
def textread(path):  # 解码文本但不解释为可执行指令。
    data = path.read_bytes()  # 仅读取指定文本。
    for encoding in ('utf-8-sig', 'utf-16', 'gb18030', 'cp932'):  # 兼容常见发行说明编码。
        try: return data.decode(encoding)  # 首选严格解码。
        except UnicodeError: pass  # 继续尝试明确的备用编码。
    return data.decode('utf-8', errors='replace')  # 保留不可解码提示。
def redact(text):  # 对报告中的账号与令牌进行最小披露处理。
    text = re.sub(r'(?im)^.*(?:token|password|secret|cookie|loginusers|AccountName|PersonaName|LastOwner|SteamID|RememberPassword|ConnectCache).*$', '[REDACTED sensitive field]', text)  # 隐藏认证字段与账户标识。
    text = re.sub(r'\b7656119\d{10}\b', '[STEAM_ID]', text)  # 隐藏常见 Steam64 标识。
    text = re.sub(r'(?i)([?&](?:token|auth|key|session)[^=]*=)[^\s&"]+', r'\1[REDACTED]', text)  # 隐藏链接中的认证参数。
    return text  # 返回可保存的报告文本。
def scan(root, label):  # 枚举普通与隐藏文件，但不跟随重解析目录。
    if not root.exists(): settings.append({'scope': label, 'state': 'ABSENT', 'path': str(root)}); return  # 明确记录不存在的路径。
    for current, dirs, files in os.walk(root, followlinks=False, onerror=lambda e: errors.append(str(e))):  # 完整遍历并登记读取错误。
        dirs[:] = [d for d in dirs if not (Path(current, d).stat().st_file_attributes & 1024)]  # 跳过重解析目录防止越界或循环。
        for name in dirs + files:  # 同时保存目录与文件元数据。
            path = Path(current, name)  # 定位当前条目。
            try:  # 个别受保护文件不阻断其他盘点。
                st = path.stat(); attrs = st.st_file_attributes; is_file = path.is_file()  # 读取属性、长度与时间。
                item = {'scope': label, 'path': str(path), 'kind': 'file' if is_file else 'directory', 'bytes': st.st_size if is_file else 0, 'mtime_ns': st.st_mtime_ns, 'attributes': attrs, 'hidden': bool(attrs & 2), 'system': bool(attrs & 4), 'sha256': '', 'hash_state': 'NOT_REQUESTED'}  # 保存可机器比较的记录。
                if is_file and (path.is_relative_to(GAME) or label.startswith('game') or path.suffix.lower() in ('.vdf', '.acf', '.json', '.ini', '.cfg', '.manifest') or path.name.lower() in ('steam.exe', 'steamservice.exe', 'dxsetup.exe')):  # 校验游戏全部文件及主要配置。
                    before = (st.st_size, st.st_mtime_ns); item['sha256'] = digest(path); after = path.stat()  # 对读取前后状态进行检查。
                    item['hash_state'] = 'OK' if before == (after.st_size, after.st_mtime_ns) else 'CHANGED_DURING_READ'  # 不将并发变化误报为稳定基线。
                rows.append(item)  # 保存完整条目。
            except Exception as exc: errors.append(str(path) + ': ' + str(exc))  # 报告盲区而非声称全部可读。
scan(STEAM, 'steam')  # 包含游戏、公共依赖、缓存、下载临时与用户目录。
doc_paths = {Path(os.environ['USERPROFILE']) / 'Documents/KoeiTecmo/Taiko5DX', Path(os.environ['USERPROFILE']) / 'OneDrive/文档/KoeiTecmo/Taiko5DX'}  # 同时检查普通与重定向文档候选。
try:  # 优先读取 Windows 实际文档目录。
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders') as key: doc_paths.add(Path(os.path.expandvars(winreg.QueryValueEx(key, 'Personal')[0])) / 'KoeiTecmo/Taiko5DX')  # 只读取文档路径。
except OSError as exc: errors.append('Documents registry: ' + str(exc))  # 记录权限或键缺失。
for path in sorted(doc_paths): scan(path, 'game-user-data')  # 记录现有存档与设置，不打开其内容。
for row in rows:  # 从全量文件目录生成游戏专项记录。
    path = Path(row['path'])  # 恢复路径对象。
    if row['kind'] != 'file' or not path.is_relative_to(GAME): continue  # 仅分析游戏目录文件类型。
    if path.suffix.lower() in ('.c', '.cpp', '.h', '.hpp', '.cs', '.py', '.lua', '.js', '.java', '.sln', '.vcxproj', '.pdb'): documents.append({'candidate': str(path), 'extension': path.suffix, 'note': 'candidate only; not proof of complete game source'})  # 只登记源码及调试候选。
    if path.suffix.lower() in ('.exe', '.dll'):  # 对发行程序仅识别 PE 类型。
        try:  # 不进行反编译或代码执行。
            with path.open('rb') as handle:  # 只读文件头。
                head = handle.read(64); offset = struct.unpack_from('<I', head, 60)[0]; handle.seek(offset); pe = handle.read(280)  # 读取 PE 与可选头。
            valid = head[:2] == b'MZ' and pe[:4] == b'PE\0\0'; machine = struct.unpack_from('<H', pe, 4)[0]; magic = struct.unpack_from('<H', pe, 24)[0]  # 验证签名与体系结构。
            directory = 24 + (112 if magic == 0x20b else 96); clr = struct.unpack_from('<II', pe, directory + 14 * 8)  # 读取 CLR 目录存在性。
            peinfo.append({'path': str(path), 'valid_pe': valid, 'machine': hex(machine), 'pe_magic': hex(magic), 'clr_directory_present': bool(clr[0] and clr[1]), 'note': 'No CLR directory does not prove language, encryption, DRM or source availability'})  # 保留技术结论的边界。
        except Exception as exc: errors.append('PE ' + str(path) + ': ' + str(exc))  # 记录无法识别的文件。
safe_keys = {'Language', 'AutoUpdateBehavior', 'AllowOtherDownloadsWhileRunning', 'ScheduledAutoUpdate', 'DownloadThrottleKbps', 'DownloadRegion', 'DownloadRate', 'EnableCloud', 'CloudEnabled', 'InGameOverlayEnabled', 'OverlayEnabled', 'EnableGameOverlay', 'LaunchOptions', 'MaxServerBrowserPingsPerMin', 'StreamingEnabled', 'RememberPassword'} - {'RememberPassword'}  # 仅输出非认证设置白名单。
for row in rows:  # 读取配置的允许字段，不复制完整账户配置。
    path = Path(row['path'])  # 定位配置文件。
    if row['kind'] != 'file' or path.suffix.lower() not in ('.vdf', '.acf', '.ini', '.cfg') or row['bytes'] > 8 * 1024 * 1024: continue  # 不把大型二进制当文本。
    if 'loginusers' in path.name.lower(): continue  # 不读取登录账户文件内容。
    try:  # 保存来源、行号、字段和值。
        for number, line in enumerate(textread(path).splitlines(), 1):  # 逐行匹配已知设置。
            match = re.match(r'\s*"([^"\n]+)"\s+"([^"\n]*)"', line)  # 只接收简单 VDF 键值。
            if match and match[1] in safe_keys: settings.append({'file': str(path), 'line': number, 'key': match[1], 'value': redact(match[2])})  # 未知字段不猜测含义。
    except Exception as exc: errors.append('config ' + str(path) + ': ' + str(exc))  # 标记配置盲区。
for hive, prefix in ((winreg.HKEY_CURRENT_USER, r'Software\Valve\Steam'), (winreg.HKEY_LOCAL_MACHINE, r'SOFTWARE\WOW6432Node\Valve\Steam\Apps\CommonRedist'), (winreg.HKEY_CURRENT_USER, r'Software\KoeiTecmo\Taiko5DX'), (winreg.HKEY_LOCAL_MACHINE, r'SYSTEM\CurrentControlSet\Services\Steam Client Service')):  # 限定应用相关注册表范围。
    try:  # 不导出机器其他安全设置。
        with winreg.OpenKey(hive, prefix) as key:  # 以默认只读权限访问。
            for index in range(winreg.QueryInfoKey(key)[1]):  # 枚举本键值。
                name, value, kind = winreg.EnumValue(key, index)  # 读取设置类型与值。
                if re.search(r'(?i)token|password|secret|account|user|auth|login', name): continue  # 排除认证标识。
                settings.append({'registry': prefix, 'hive': 'HKCU' if hive == winreg.HKEY_CURRENT_USER else 'HKLM', 'key': name, 'type': kind, 'value': redact(str(value))})  # 保存非敏感应用设置。
            settings.append({'registry': prefix, 'subkeys': [winreg.EnumKey(key, i) for i in range(winreg.QueryInfoKey(key)[0])]})  # 记录存在的子键，不声称完成其所有值读取。
    except OSError as exc: errors.append('registry ' + prefix + ': ' + str(exc))  # 不存在与拒绝访问均保留具体错误。
for name in ('content_log.txt', 'runprocess_log.txt', 'gameprocess_log.txt', 'cloud_log.txt'):  # 保存与安装和启动有关的限定日志。
    path = STEAM / 'logs' / name  # 不采集浏览器认证或聊天日志。
    if path.exists(): (DEST / name).write_text(redact(textread(path)), encoding='utf-8')  # 仅保存脱敏文本。
manifest = STEAM / 'steamapps/appmanifest_1842810.acf'  # 定位用户已安装的产品清单。
if manifest.exists(): (DEST / 'appmanifest_1842810.redacted.txt').write_text(redact(textread(manifest)), encoding='utf-8')  # 保存可读安装状态。
with (DEST / 'all-files.csv').open('w', encoding='utf-8-sig', newline='') as handle:  # 输出完整普通及隐藏文件目录。
    writer = csv.DictWriter(handle, fieldnames=list(rows[0]) if rows else ['path']); writer.writeheader(); writer.writerows(rows)  # CSV 可用于后续逐项对比。
game_rows = [r for r in rows if Path(r['path']).is_relative_to(GAME) and r['kind'] == 'file']  # 按实际游戏目录单独统计。
payload = {'captured_at_tbilisi': STAMP, 'phase': 'CURRENT_BASELINE_AFTER_INSTALL_ATTEMPT_NOT_PROVEN_BEFORE_FIRST_LAUNCH', 'steam_root': str(STEAM), 'game_root': str(GAME), 'total_entries': len(rows), 'game_files': len(game_rows), 'game_logical_bytes': sum(r['bytes'] for r in game_rows), 'source_candidates': documents, 'pe_headers': peinfo, 'settings': settings, 'errors': errors, 'limits': ['Live non-atomic snapshot', 'All accessible filesystem entries under Steam; no reparse traversal', 'Steam binaries not unpacked or decompiled', 'No encrypted/DRM classification from entropy', 'Settings whitelist only; credentials not exported', 'Remote server/account settings and inaccessible files not enumerated', 'File sizes are logical, not unique physical disk allocation']}  # 汇总真实范围。
(DEST / 'snapshot.json').write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding='utf-8')  # 保存可机器对比的状态。
lines = ['Steam 与太阁立志传Ⅴ DX 当前基线报告', '时间（Asia/Tbilisi）: ' + STAMP, '阶段: 安装尝试后的当前快照；不是严格首次启动前快照', 'Steam: ' + str(STEAM), '游戏: ' + str(GAME), '条目数: ' + str(len(rows)), '游戏文件数: ' + str(len(game_rows)), '游戏逻辑字节: ' + str(payload['game_logical_bytes']), '源码/调试候选: ' + str(len(documents)), '范围和局限:', *payload['limits'], '设置:', json.dumps(settings, ensure_ascii=False, indent=2), 'PE 文件头:', json.dumps(peinfo, ensure_ascii=False, indent=2), '源码候选:', json.dumps(documents, ensure_ascii=False, indent=2), '读取异常:', *errors, '完整文件清单见 all-files.csv；运行日志见同目录。']  # 生成人类可读文本。
(DEST / '现有文件与设置报告.txt').write_text('\n'.join(lines), encoding='utf-8-sig')  # 满足用户文本报告要求。
print(json.dumps({'directory': str(DEST), 'entries': len(rows), 'game_files': len(game_rows), 'game_bytes': payload['game_logical_bytes'], 'source_candidates': len(documents), 'errors': len(errors)}, ensure_ascii=True))  # 只显示摘要，不泄露账户信息。
