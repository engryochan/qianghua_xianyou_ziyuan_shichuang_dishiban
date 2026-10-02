import os, json, pathlib, time # 只读取文件元数据，不打开文件内容。
root=pathlib.Path.cwd(); home=pathlib.Path(os.environ['USERPROFILE']); out=root/'reports/space-audit-20260924' # 限定报告写入项目目录。
targets=[home/'AppData/Local/Temp',home/'AppData/Local/uv/cache',home/'AppData/Local/pip/Cache',home/'.cache',home/'.codex',home/'Downloads',pathlib.Path('C:/Windows.old'),pathlib.Path('C:/Windows/Temp'),pathlib.Path('C:/Windows/SoftwareDistribution/Download'),pathlib.Path('C:/$Recycle.Bin'),pathlib.Path('C:/work'),root/'reports',pathlib.Path('C:/ProgramData/Package Cache'),pathlib.Path('C:/ProgramData/NVIDIA Corporation'),home/'AppData/Local/CrashDumps',home/'AppData/Local/Microsoft/Edge/User Data',home/'AppData/Local/Google/Chrome/User Data',home/'AppData/Local/JetBrains',home/'AppData/Local/Programs',pathlib.Path('C:/Forensic')] # 覆盖缓存安装包环境与备份候选。
results=[] # 汇总每个目标，父子重叠不得累加。
for target in targets: # 顺序扫描避免并发磁盘压力。
    total=0; count=0; skipped=0; errors=[]; groups={}; large=[]; stack=[str(target)] if target.exists() else [] # 初始化有界统计。
    while stack: # 遍历目录但不跟随重解析点。
        current=stack.pop() # 获取下一目录。
        try: # 记录访问失败而不伪装为零。
            with os.scandir(current) as entries: # 枚举元数据，不触发文件内容下载。
                for entry in entries: # 处理直接子项。
                    try: # 隔离单个文件读取错误。
                        stat=entry.stat(follow_symlinks=False) # 避免解析链接目标。
                        if entry.is_dir(follow_symlinks=False): # 只遍历普通目录。
                            if getattr(stat,'st_file_attributes',0)&0x400: skipped+=1 # 跳过目录联接与云重解析目录。
                            else: stack.append(entry.path) # 压入普通子目录。
                        elif entry.is_file(follow_symlinks=False): # 统计文件逻辑大小。
                            total+=stat.st_size; count+=1; rel=pathlib.Path(entry.path).relative_to(target); key='/'.join(rel.parts[:2]) if len(rel.parts)>2 else rel.parts[0]; groups[key]=groups.get(key,0)+stat.st_size # 汇总前两层占用。
                            if stat.st_size>=100*1024**2: large.append({'path':entry.path,'bytes':stat.st_size}) # 保存大型文件候选路径。
                    except OSError as e: errors.append(str(e)) # 明确不可读取项目。
        except OSError as e: errors.append(str(e)) # 保存目录权限问题。
    row={'path':str(target),'exists':target.exists(),'logical_bytes':total,'files':count,'skipped_reparse_dirs':skipped,'error_count':len(errors),'errors':errors[:10],'groups':sorted(groups.items(),key=lambda x:x[1],reverse=True)[:25],'large':sorted(large,key=lambda x:x['bytes'],reverse=True)[:40]} # 避免输出无界列表。
    results.append(row); (out/'inventory.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8'); print(json.dumps({k:row[k] for k in ('path','logical_bytes','files','error_count','skipped_reparse_dirs')},ensure_ascii=False),flush=True) # 每个目标完成立即保存进度。
