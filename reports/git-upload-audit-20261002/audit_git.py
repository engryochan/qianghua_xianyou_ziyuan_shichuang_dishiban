import csv, json, os, subprocess, collections, datetime # Load standard audit modules only.
from pathlib import Path # Resolve workspace-relative evidence files.
ROOT=Path(__file__).resolve().parents[2] # Restrict the audit to this repository.
OUT=Path(__file__).parent # Write reports only within the ignored reports directory.
def git(*args): # Run read-only Git queries with optional index writes disabled.
    env=dict(os.environ); env['GIT_OPTIONAL_LOCKS']='0' # Prevent optional Git index refresh writes.
    result=subprocess.run(['git',*args],cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE) # Capture output without shell interpolation.
    if result.returncode: raise RuntimeError(result.stderr.decode('utf-8','replace')) # Preserve failures instead of treating them as empty results.
    return result.stdout # Return binary-safe Git output.
def paths(*args): # Parse NUL-delimited Git filenames including spaces and Chinese names.
    return {p.decode('utf-8','surrogateescape') for p in git(*args).split(b'\x00') if p} # Preserve full relative filenames.
head=git('rev-parse','HEAD').decode().strip() # Read current local HEAD.
branch=git('branch','--show-current').decode('utf-8').strip() # Read the current branch name.
tracked=paths('ls-files','-z') # List index-tracked paths.
untracked=paths('ls-files','--others','--exclude-standard','-z') # List not-yet-tracked files outside ignore rules.
ignored=paths('ls-files','--others','--ignored','--exclude-standard','-z') # List all ignored untracked files explicitly.
changed=paths('diff','HEAD','--name-only','-z') # Compare tracked worktree/index changes against the current commit.
tree=git('ls-tree','-r','-z','HEAD') # Read the complete committed tree rather than infer upload from folder names.
committed={} # Store paths and Git object identities from HEAD.
for entry in tree.split(b'\x00'): # Parse each committed tree entry.
    if not entry: continue # Skip the final delimiter.
    meta,path=entry.split(b'\t',1); mode,kind,oid=meta.decode().split() # Separate object metadata from the path.
    committed[path.decode('utf-8','surrogateescape')]={'mode':mode,'kind':kind,'oid':oid} # Preserve committed object evidence.
flags=git('ls-files','-v','-z') # Read assume-unchanged and skip-worktree flags.
special_flags=[s.decode('utf-8','replace') for s in flags.split(b'\x00') if s and (s[:1].islower() or s[:1]==b'S')] # Record flags that could hide normal status checks.
rows,errors,links=[],[],[] # Track every current file and inspection limitation.
def onerror(exc): # Keep traversal failures visible.
    errors.append({'path':str(exc.filename),'error':str(exc)}) # Save the failing path and reason.
for directory,dirs,files in os.walk(ROOT,followlinks=False,onerror=onerror): # Include hidden files while avoiding external directory targets.
    for name in list(dirs): # Check directory redirections before traversal.
        p=Path(directory)/name # Resolve a directory candidate.
        if getattr(p.lstat(),'st_file_attributes',0)&0x400: links.append(str(p)); dirs.remove(name) # Record but do not follow reparse directories.
    for name in files: # Classify each local file, including Git internal metadata.
        p=Path(directory)/name; rel=p.relative_to(ROOT).as_posix() # Use Git-compatible slash-separated relative paths.
        try: # Preserve per-file inspection failures.
            st=p.lstat() # Read attributes without loading file contents or OneDrive placeholders.
            if rel.startswith('.git/'): status='Git内部元数据（不按文件上传）' # Git metadata is not part of the committed worktree.
            elif rel in changed: status='已追踪但本地内容未提交' # Identify changed index/worktree files relative to remote-matching HEAD.
            elif rel in committed: status='当前提交中已有（远端HEAD已核实一致）' # Classify committed paths with direct remote-tip proof.
            elif rel in tracked: status='已暂存新增但尚未提交' # Separate staged additions from current commit contents.
            elif rel in ignored: status='被Git忽略（本轮未证明其他历史或分支是否含有）' # Avoid claiming ignored files have never been published anywhere.
            elif rel in untracked: status='未追踪（不在当前提交）' # Identify files outside the current Git commit.
            else: # Resolve files Git enumeration can omit, such as nested .git markers.
                check=subprocess.run(['git','check-ignore','-q','--',rel],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE) # Check the actual ignore rule without changing it.
                if check.returncode==0: ignored.add(rel); status='被Git忽略（本轮未证明其他历史或分支是否含有）' # Classify a confirmed ignored path.
                else: status='未归类需复核' # Preserve any unresolved race or nested-repository case.
            rows.append({'path':rel,'category':status,'bytes':st.st_size,'attributes':getattr(st,'st_file_attributes',0),'head_blob':committed.get(rel,{}).get('oid','')}) # Store names, size and commit evidence only.
        except Exception as exc: errors.append({'path':rel,'error':str(exc)}) # Record inaccessible metadata.
existing={r['path'] for r in rows} # Capture the measured file set.
missing=sorted(set(committed)-existing) # List committed paths absent from the working tree.
counts=collections.defaultdict(lambda:{'count':0,'bytes':0}) # Aggregate exclusive categories.
for r in rows: counts[r['category']]['count']+=1; counts[r['category']]['bytes']+=r['bytes'] # Sum current logical file sizes.
for filename,selected in [('全部文件同步分类.csv',rows),('当前版本尚未上传文件.csv',[r for r in rows if r['category'] not in {'当前提交中已有（远端HEAD已核实一致）','Git内部元数据（不按文件上传）'}])]: # Create full and action-focused manifests.
    with (OUT/filename).open('w',encoding='utf-8-sig',newline='') as f: # Write Excel-compatible CSV files.
        writer=csv.DictWriter(f,fieldnames=['path','category','bytes','attributes','head_blob']); writer.writeheader(); writer.writerows(selected) # Preserve every selected file.
ignore_input=b''.join(r['path'].encode('utf-8','surrogateescape')+b'\x00' for r in rows if r['path'] in ignored) # Prepare ignored filenames without interpreting them as shell code.
if ignore_input: # Retrieve the matching ignore rule for each ignored path.
    proc=subprocess.run(['git','check-ignore','-v','-z','--stdin'],cwd=ROOT,input=ignore_input,stdout=subprocess.PIPE,stderr=subprocess.PIPE) # Read rule provenance only.
    fields=proc.stdout.split(b'\x00'); provenance=[] # Decode NUL-separated rule records.
    for index in range(0,len(fields)-3,4): provenance.append(dict(zip(['source','line','pattern','path'],[x.decode('utf-8','replace') for x in fields[index:index+4]]))) # Preserve rule source and line number.
    (OUT/'ignore-rules.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2),encoding='utf-8') # Save exact ignore-rule evidence.
result={'time':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=4))).isoformat(),'root':str(ROOT),'branch':branch,'head':head,'remote_head_verified_in_prior_readonly_ls_remote':'20586c8f86129cfaaace0ebb6e272812798fc7d5','head_matches_verified_remote':head=='20586c8f86129cfaaace0ebb6e272812798fc7d5','committed_path_count':len(committed),'counts':dict(counts),'changed_paths':sorted(changed),'missing_committed_paths':missing,'special_index_flags':special_flags,'errors':errors,'untraversed_reparse_dirs':links,'scope':'Current branch HEAD and local files only; no pull/fetch/push/commit, no OneDrive cloud confirmation; output files created after the scan are not in its snapshot.'} # State point-in-time scope and remote proof.
(OUT/'summary.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8') # Save audit evidence.
lines=['# GitHub 上传／拉取状态核查','',f"核查时间：{result['time']}。分支：`{branch}`。",'',f"本地 HEAD：`{head}`；直接远端查询 HEAD：`{result['remote_head_verified_in_prior_readonly_ls_remote']}`。相同＝当前分支没有未推送/未拉取提交。",'','| 分类 | 文件数 | 逻辑大小 MiB |','|---|---:|---:|'] # Build the concise report.
for k,v in counts.items(): lines.append(f"| {k} | {v['count']} | {v['bytes']/1048576:.3f} |") # Report logical sizes without confusing disk allocation.
lines+=['','## 尚未进入当前远端版本的非忽略文件',''] # List all relevant uncommitted paths in readable form.
for r in rows: # Select files requiring explicit Git inclusion or commit decisions.
    if r['category'] in {'已追踪但本地内容未提交','已暂存新增但尚未提交','未追踪（不在当前提交）','未归类需复核'}: lines.append(f"- `{r['path']}` — {r['category']}，{r['bytes']:,} 字节") # Preserve each filename rather than sample it.
lines+=['','## 被忽略文件按顶层目录汇总',''] # Summarize large ignored groups while providing the complete CSV.
top=collections.Counter(r['path'].split('/')[0] for r in rows if r['path'] in ignored) # Count ignore groups by their first component.
for k,v in top.most_common(): lines.append(f'- `{k}`：{v} 个文件') # Display all ignored top-level groups.
lines+=['','## 限制与说明','','“已上传”指当前远端分支提交树中已有，并不表示任意本地文件都上传过。被忽略/未追踪文件不在当前提交；其他历史、其他分支、其他仓库是否曾含相同内容未逐一调查。','.git 是 Git 内部对象/索引/日志，不应把该目录当普通文件整体提交。逻辑文件大小不等于实际磁盘占用。','本轮未修改用户文件、忽略规则、Git 配置、分支或远端；仅写入本地 reports 审计产物。未读取文件正文、令牌或密码。','OneDrive 云端是否已上传或尚待下载不能由 Git 状态证明，本轮没有确认 OneDrive 服务端状态。','完整逐文件列表见 全部文件同步分类.csv；当前版本尚未上传文件.csv 包含全部未追踪/未提交/被忽略文件；ignore-rules.json 显示忽略来源。','本报告和清单等产物在目录扫描后生成，因此不包含在自己的扫描快照中；它们位于被忽略的 reports/ 下，也没有上传。'] # Explain limitations and self-generated report handling.
(OUT/'上传与拉取核查报告.md').write_text('\n'.join(lines)+'\n',encoding='utf-8') # Save the full readable report.
print(json.dumps(result,ensure_ascii=False,indent=2)) # Show concise audit totals.
