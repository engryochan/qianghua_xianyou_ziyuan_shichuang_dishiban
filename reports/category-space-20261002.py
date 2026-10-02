import os, pathlib, json, time, shutil, subprocess # 仅枚举元数据，不读取业务文件内容。
home = pathlib.Path(os.environ['USERPROFILE']); repo = home/'OneDrive/文档/GitHub/basic-data-analytical-lab'; out = pathlib.Path(__file__).parent/'category-space-20261002.json' # 将证据保存在当前工作区。
targets = list((home/'OneDrive/文档/GitHub').iterdir()) + [home/'AppData/Local/GitHubDesktop',home/'AppData/Local/Temp',pathlib.Path('C:/Windows/Temp'),pathlib.Path('C:/work/tmp'),pathlib.Path('C:/work/cache'),pathlib.Path('C:/work/uvcache'),home/'AppData/Local/uv/cache',home/'.cache'] # 按项目及Temp/cache分组。
results = []; capacity = shutil.disk_usage('C:/')._asdict() # 记录当前容量，逻辑目录大小不可直接加总为物理占用。
for target in targets: # 顺序扫描降低磁盘竞争。
    start = time.monotonic(); stack = [str(target)]; total = count = skipped = errors = 0; big = []; complete = True # 每个目录设置明确扫描预算。
    while stack: # 枚举路径但不触发云文件内容下载。
        if time.monotonic()-start > 240: complete = False; break # 超时明确标记为部分扫描。
        current = stack.pop() # 获取下一目录。
        try: # 访问失败保留计数。
            with os.scandir(current) as entries: # 仅读取目录与文件元数据。
                for entry in entries: # 按现有条目顺序处理。
                    try: # 隔离单条元数据错误。
                        info = entry.stat(follow_symlinks=False) # 不跟随符号链接。
                        if entry.is_dir(follow_symlinks=False): # 云目录允许元数据枚举，联接与符号链接不递归。
                            if getattr(info,'st_reparse_tag',0)&0x20000000: skipped += 1 # 跳过名称替代型重解析点。
                            else: stack.append(entry.path) # 进入普通或云占位目录，不打开内容。
                        elif entry.is_file(follow_symlinks=False): # 统计逻辑长度，不冒充已分配空间。
                            total += info.st_size; count += 1 # 累计当前扫描到的文件。
                            if info.st_size >= 200*1024**2: big.append({'path':entry.path,'bytes':info.st_size}) # 记录大型文件候选。
                    except OSError: errors += 1 # 记录不可读元数据。
        except OSError: errors += 1 # 记录不可读目录。
    row = {'path':str(target),'logical_bytes':total,'files':count,'complete':complete,'skipped_links':skipped,'errors':errors,'seconds':round(time.monotonic()-start,1),'large':sorted(big,key=lambda x:x['bytes'],reverse=True)[:8]} # 保存覆盖范围与限制。
    results.append(row); out.write_text(json.dumps({'capacity':capacity,'results':results},ensure_ascii=False,indent=2),encoding='utf-8'); print(json.dumps({k:v for k,v in row.items() if k!='large'},ensure_ascii=False),flush=True) # 每项完成立即保存。
result = subprocess.run(['wsl.exe','--list','--verbose'],capture_output=True) # 只读查询发行版且捕获原始字节。
wsl_text = result.stdout.decode('utf-16-le',errors='replace') if b'\x00' in result.stdout else result.stdout.decode('utf-8',errors='replace') # 修正 WSL Unicode 输出解码。
out.write_text(json.dumps({'capacity':capacity,'results':results,'wsl_exit':result.returncode,'wsl':wsl_text},ensure_ascii=False,indent=2),encoding='utf-8') # 保存最终结果，未安装或清理任何内容。
