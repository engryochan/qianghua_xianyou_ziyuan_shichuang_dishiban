import os,time,json,pathlib # 不读取文件内容。
root=pathlib.Path('C:/Windows'); stack=[str(root)]; total=files=errors=skips=0; groups={}; start=time.monotonic() # 初始化目录统计。
while stack: # 顺序枚举。
    current=stack.pop() # 获取下一目录。
    try: # 保留访问错误。
        with os.scandir(current) as entries: # 仅读取元数据。
            for entry in entries: # 处理条目。
                try: # 隔离单条错误。
                    info=entry.stat(follow_symlinks=False) # 不跟随链接。
                    if entry.is_dir(follow_symlinks=False): # 递归非联接目录。
                        if getattr(info,'st_reparse_tag',0)&0x20000000: skips+=1 # 跳过名称替代链接。
                        else: stack.append(entry.path) # 枚举目录，不打开内容。
                    elif entry.is_file(follow_symlinks=False): # 累计逻辑长度。
                        key=pathlib.Path(entry.path).relative_to(root).parts[0]; groups[key]=groups.get(key,0)+info.st_size; total+=info.st_size; files+=1 # 硬链接可能重复，按第一层汇总。
                except OSError: errors+=1 # 记录不可读条目。
    except OSError: errors+=1 # 记录不可读目录。
result={'logical_bytes':total,'files':files,'errors':errors,'skipped_links':skips,'seconds':time.monotonic()-start,'groups':sorted(groups.items(),key=lambda x:x[1],reverse=True)} # 逻辑长度不代表物理总量。
pathlib.Path('reports/system-files-20261002/windows-logical.json').write_text(json.dumps(result,indent=2),encoding='utf-8'); print(json.dumps(result)) # 保存证据。
