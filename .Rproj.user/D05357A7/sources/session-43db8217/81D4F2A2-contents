import csv, json, collections, datetime # Use standard libraries only.
from pathlib import Path # Resolve explicit filesystem paths.
OUT=Path(__file__).parent # Save reports only in the workspace.
ROOT=Path(r'C:\Program Files (x86)\Steam\steamapps\common\Taiko5DX') # Keep the game target read-only.
with (OUT/'all-files.csv').open(encoding='utf-8-sig',newline='') as f: baseline={r['path']:r for r in csv.DictReader(f)} # Read the prior complete byte-hash evidence.
summary=json.loads((OUT/'summary.json').read_text(encoding='utf-8')) # Reuse previously measured PE headers with an explicit timestamp.
def classify(rel): # Assign exactly one category to every file by observed location and suffix.
    p=Path(rel); ext=p.suffix.lower(); parts=[x.upper() for x in p.parts] # Normalize comparison keys.
    if ext=='.exe': return '程序', 'PE 结构已实读；角色结合名称与官方文档' # Separate executable logic from resources.
    if ext=='.dll': return 'Steam 接口库', '发布版库；导入表与签名已实读' # Classify the three measured Valve libraries.
    if ext=='.txt': return '说明文档', 'UTF-8 BOM 文本' # Classify the bundled README files.
    if ext in {'.te5','.ts5'}: return '事件数据', 'EVENT 目录与配对实读；内部字段未解析' # Identify data placement without inventing field meanings.
    if 'SOUND' in parts: return '声音资源', 'SOUND/STREAM/SE 位置实读；内部编码未解析' # Classify sound files by directory evidence.
    if ext in {'.wmv','.pmf'}: return '影片资源', '文件头及扩展名支持格式分类；未播放' # Distinguish videos from code.
    if ext in {'.g1t','.rgba8','.tg5'}: return '图像/图形候选资源', '扩展名/命名/目录推断；未解包解码' # Mark graphics inference explicitly.
    if ext in {'.efps','.ftx','.g1e','.g1em','.g1s'}: return '效果候选资源', 'BASE/eff 位置及名称推断；字段未解析' # Avoid claiming exact effect semantics.
    if 'EVCON' in parts: return '事件转换器配套表', 'Evcon 目录及 DAT 表名实读；字段未解析' # Separate converter tables from runtime messages.
    return '其他专用数据', '名称/目录实读；数据定义未确认' # Preserve uncertain classifications.
rows,changed,errors=[],[],[] # Track every file and verification limitation.
for path in sorted(ROOT.rglob('*')): # Refresh all current directory entries including hidden files.
    if not path.is_file(): continue # Classify files rather than directory objects.
    rel=str(path.relative_to(ROOT)) # Use target-relative paths in reports.
    try: # Keep read failures visible.
        st=path.stat() # Capture current size and modification timestamp.
        if getattr(st,'st_file_attributes',0)&0x400: raise RuntimeError('Reparse file not followed') # Prevent traversal of redirected file targets.
        with path.open('rb') as f: head=f.read(64) # Refresh every file header without writing to the target.
        previous=baseline.get(rel) # Find its complete-read baseline.
        same=bool(previous and int(previous['bytes'])==st.st_size and int(previous['mtime_ns'])==st.st_mtime_ns and previous['header_hex']==head.hex()) # Verify current metadata and header against the saved audit.
        if not same: changed.append(rel) # Expose any candidate changes requiring new full hashes.
        cat,evidence=classify(rel) # Assign a documented category.
        rows.append({'path':rel,'category':cat,'bytes':st.st_size,'extension':path.suffix.lower(),'header_ascii':''.join(chr(b) if 32<=b<127 else '.' for b in head[:16]),'header_hex':head.hex(),'classification_basis':evidence,'metadata_header_match':same,'sha256_from_full_audit':previous['sha256'] if previous else '', 'hash_audit_time':summary['timestamp']}) # State that hashes come from the prior complete read.
    except Exception as exc: errors.append({'path':rel,'error':str(exc)}) # Preserve inspection failures.
removed=sorted(set(baseline)-{r['path'] for r in rows}) # Detect removed baseline files.
with (OUT/'分类文件清单.csv').open('w',encoding='utf-8-sig',newline='') as f: # Create a complete categorized manifest.
    writer=csv.DictWriter(f,fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows) # Write every successful row.
cats=collections.defaultdict(lambda:{'count':0,'bytes':0}) # Aggregate exclusive categories.
dirs=collections.defaultdict(lambda:{'count':0,'bytes':0}) # Aggregate immediate containing directories.
headers=collections.defaultdict(collections.Counter) # Track actual header-prefix variants per extension.
for r in rows: # Process every measured file exactly once.
    cats[r['category']]['count']+=1; cats[r['category']]['bytes']+=r['bytes'] # Update category totals.
    directory=str(Path(r['path']).parent); dirs[directory]['count']+=1; dirs[directory]['bytes']+=r['bytes'] # Update directory totals.
    headers[r['extension']][r['header_hex'][:16]]+=1 # Count the first eight bytes without assuming encryption.
pairs={} # Verify TE5/TS5 pairing for each locale directory.
for directory in ('data/EVENT','data/EVENT_SC','data/EVENT_TW'): # Inspect the three actual event directories.
    entries=[Path(r['path']) for r in rows if Path(r['path']).parent==Path(directory)] # Select one locale set.
    te={p.stem for p in entries if p.suffix.lower()=='.te5'}; ts={p.stem for p in entries if p.suffix.lower()=='.ts5'} # Compare paired filename stems.
    pairs[directory]={'te5':len(te),'ts5':len(ts),'paired':len(te&ts),'only_te5':sorted(te-ts),'only_ts5':sorted(ts-te)} # Save measured pairing evidence.
result={'time':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=4))).isoformat(),'hash_audit_time':summary['timestamp'],'file_count':len(rows),'bytes':sum(r['bytes'] for r in rows),'categories':dict(cats),'directories':dict(dirs),'header_variants':{k:dict(v) for k,v in headers.items()},'event_pairs':pairs,'metadata_or_header_changes':changed,'removed':removed,'errors':errors} # Preserve current refresh and dated full-hash provenance.
(OUT/'classification-summary.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8') # Save machine-readable architecture evidence.
lines=['# 太阁立志传Ⅴ DX：文件分类与架构核查','',f"当前目录/文件头复核：{result['time']}。完整逐字节哈希基线：{summary['timestamp']}。",'',f"共 {len(rows)} 个文件，{result['bytes']:,} 字节；本轮元数据/文件头变化 {len(changed)}，删除 {len(removed)}，读取错误 {len(errors)}。本轮未重复读取全部资源字节；完整读取证据来自上述哈希基线。",'','## 分门别类','', '| 分类 | 文件数 | 大小 MiB | 占总字节 |','|---|---:|---:|---:|'] # Build a reproducible classification report.
for k,v in cats.items(): lines.append(f"| {k} | {v['count']} | {v['bytes']/1048576:.3f} | {v['bytes']/result['bytes']*100:.3f}% |") # Calculate auditable category proportions.
lines+=['','## 实际目录','', '| 目录 | 直接文件数 | 直接文件大小 MiB |','|---|---:|---:|'] # Show the actual layout rather than inferred software modules.
for k,v in sorted(dirs.items()): lines.append(f"| `{k}` | {v['count']} | {v['bytes']/1048576:.3f} |") # Preserve every file-bearing directory.
lines+=['','## 事件文件配对','', '| 目录 | TE5 | TS5 | 同名配对 |','|---|---:|---:|---:|'] # Report structural checks for event data.
for k,v in pairs.items(): lines.append(f"| `{k}` | {v['te5']} | {v['ts5']} | {v['paired']} |") # Show measured event-pair totals.
lines+=['','## 扩展名与实读文件头','', '| 扩展名 | 前八字节十六进制（最多列三种） |','|---|---|'] # Distinguish format signatures from suffix guesses.
for k,v in sorted(headers.items()): lines.append(f"| `{k}` | "+'; '.join(f'`{h}` × {n}' for h,n in v.most_common(3))+' |') # Display representative prefix diversity with counts.
(OUT/'文件分类与架构核查.md').write_text('\n'.join(lines)+'\n',encoding='utf-8') # Save the generated report for further review.
print(json.dumps({k:result[k] for k in ('time','file_count','bytes','categories','event_pairs','metadata_or_header_changes','removed','errors')},ensure_ascii=False,indent=2)) # Display concise measured results.
