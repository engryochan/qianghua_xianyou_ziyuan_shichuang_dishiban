import os,json,pathlib,time # 只读程序文件元数据。
home=pathlib.Path(os.environ['USERPROFILE']); packages=json.loads(pathlib.Path('reports/microsoft-apps-20261002.json').read_text(encoding='utf-8-sig')); rows=[] # 读取已核实的微软应用路径。
targets=[(p['Name'],'Framework' if p['IsFramework'] else 'MicrosoftApp',p['InstallLocation']) for p in packages] # 微软应用不等同全部出厂预装。
targets += [(p.name,'Tool',str(p)) for p in [home/'.codex',home/'AppData/Local/OpenAI/Codex',home/'AppData/Local/GitHubDesktop',home/'AppData/Local/github-copilot']] # 盘点用户所指工具。
targets += [(p.name,'Tool',str(p)) for p in (home/'AppData/Local').glob('github-copilot-git-*')] # 补查Copilot附带Git运行时。
for name,kind,path in targets: # 顺序盘点各包避免重复路径。
    start=time.monotonic(); stack=[path]; size=count=errors=0; complete=True # 初始化有界查询。
    while stack: # 遍历元数据。
        if time.monotonic()-start>60: complete=False; break # 超时明确标记。
        current=stack.pop() # 取下一目录。
        try: # 记录权限错误而不改变ACL。
            with os.scandir(current) as entries: # 不打开内容。
                for e in entries: # 处理目录项。
                    try: # 单条错误隔离。
                        s=e.stat(follow_symlinks=False) # 不跟随链接。
                        if e.is_dir(follow_symlinks=False) and not getattr(s,'st_reparse_tag',0)&0x20000000: stack.append(e.path) # 只进入非名称替代目录。
                        elif e.is_file(follow_symlinks=False): size+=s.st_size;count+=1 # 累计逻辑大小。
                    except OSError: errors+=1 # 保留不可读证据。
        except OSError: errors+=1 # 未访问成功不能当作零占用。
    rows.append({'name':name,'kind':kind,'path':path,'logical_bytes':size,'files':count,'errors':errors,'complete':complete}) # 保存类别与扫描范围。
    pathlib.Path('reports/app-space-20261002.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8') # 每项完成保存进度。
print(json.dumps({'packages':len(rows),'errors':sum(r['errors'] for r in rows)})) # 输出简要验证结果。
