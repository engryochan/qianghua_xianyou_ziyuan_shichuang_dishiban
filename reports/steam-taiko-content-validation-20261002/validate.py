import csv, hashlib, json, struct, collections, datetime, uuid # Use standard read-only parsing libraries.
from pathlib import Path # Resolve explicit filesystem paths.
ROOT=Path(r'C:\Program Files (x86)\Steam\steamapps\common\Taiko5DX') # Define the untouched game directory.
OUT=Path(__file__).parent # Save evidence only in the project report directory.
BASE=OUT.parent/'steam-taiko-source-audit-20261002' # Locate the earlier complete audit.
with (BASE/'分类文件清单.csv').open(encoding='utf-8-sig',newline='') as f: old={r['path']:r for r in csv.DictReader(f)} # Load all previously classified files.
pebaseline=json.loads((BASE/'summary.json').read_text(encoding='utf-8')) # Load previously measured PE sections.
pebyname={p['path']:p for p in pebaseline['pe_files']} # Index the PE evidence.
ASF_HEADER='75b22630-668e-11cf-a6d9-00aa0062ce6c' # Define the documented ASF header GUID.
ASF_DATA='75b22636-668e-11cf-a6d9-00aa0062ce6c' # Define the ASF media-data object GUID.
ASF_PROP='8cabdca1-a947-11cf-8ee4-00c00c205365' # Define the ASF file-properties object GUID.
def asf(path): # Validate container boundaries without executing media codecs.
    result={'top_objects':[],'header_children':[],'issues':[],'decode_test':'U: no installed media decoder used'} # State the limited structural scope.
    size=path.stat().st_size # Capture physical file length.
    with path.open('rb') as f: # Inspect the untouched media container.
        offset=0 # Start at the first top-level object.
        while offset<size: # Walk every top-level object within the file.
            f.seek(offset); head=f.read(24) # Read GUID and object size.
            if len(head)!=24: result['issues'].append('truncated top-level object'); break # Record truncated object headers.
            guid=str(uuid.UUID(bytes_le=head[:16])); length=struct.unpack_from('<Q',head,16)[0] # Decode the documented object fields.
            result['top_objects'].append({'guid':guid,'offset':offset,'size':length}) # Preserve parsed boundary evidence.
            if length<24 or offset+length>size: result['issues'].append('invalid top-level object boundary'); break # Reject ranges outside the file.
            if guid==ASF_HEADER: # Inspect header subobjects only for an ASF header.
                fixed=f.read(6); count=struct.unpack_from('<I',fixed)[0]; child=offset+30 # Read the declared child count.
                for index in range(count): # Validate every declared header subobject.
                    f.seek(child); sub=f.read(24) # Read the child GUID and length.
                    if len(sub)!=24: result['issues'].append('truncated header child'); break # Preserve truncation evidence.
                    sg=str(uuid.UUID(bytes_le=sub[:16])); sl=struct.unpack_from('<Q',sub,16)[0] # Decode child fields.
                    if sl<24 or child+sl>offset+length: result['issues'].append('invalid header child boundary'); break # Check containment in the header object.
                    result['header_children'].append({'guid':sg,'offset':child,'size':sl}) # Preserve all child ranges.
                    if sg==ASF_PROP and sl>=104: # Read the standard file-properties structure.
                        f.seek(child); props=f.read(104) # Read bounded properties without extracting media.
                        declared=struct.unpack_from('<Q',props,40)[0]; duration=struct.unpack_from('<Q',props,64)[0]; preroll=struct.unpack_from('<Q',props,80)[0] # Decode file size and timing fields.
                        result['declared_file_size']=declared; result['duration_seconds']=max(0,duration/10000000-preroll/1000) # Report documented container metadata.
                        if declared!=size: result['issues'].append('declared file size differs from actual') # Identify a concrete file-size mismatch.
                    child+=sl # Advance to the next child object.
                if child!=offset+length: result['issues'].append('header children do not consume declared header') # Check complete child coverage.
            offset+=length # Advance to the next top-level object.
        result['covered_bytes']=offset # Record actual structure coverage.
    if not result['top_objects'] or result['top_objects'][0]['guid']!=ASF_HEADER: result['issues'].append('missing first ASF header') # Enforce the documented first object.
    if not any(o['guid']==ASF_DATA for o in result['top_objects']): result['issues'].append('missing ASF data object') # Require a media-data object.
    return result # Return structural evidence rather than playback success.
rows,details,errors=[],{},[] # Preserve per-file checks and limitations.
for path in sorted(ROOT.rglob('*')): # Inspect all current files rather than a sample.
    if not path.is_file(): continue # Skip directory objects.
    rel=str(path.relative_to(ROOT)) # Preserve target-relative filenames.
    try: # Keep failures explicit instead of reporting them as passes.
        before=path.stat(); digest=hashlib.sha256(); total=0; zeros=0; first=b'' # Initialize full-byte verification.
        with path.open('rb') as f: # Open each target for reading only.
            while block:=f.read(1024*1024): # Read the entire content in bounded chunks.
                if not first: first=block[:64] # Preserve the initial structure bytes.
                digest.update(block); total+=len(block); zeros+=block.count(0) # Hash and measure zero-byte content.
        after=path.stat(); previous=old.get(rel); same=bool(previous and digest.hexdigest()==previous['sha256_from_full_audit']) # Compare against the exact earlier bytes.
        d={'read_test':'PASS' if total==before.st_size else 'FAIL','hash_vs_baseline':'PASS' if same else 'CHANGED_OR_NEW','zero_byte_count':zeros,'semantic_review':'U','runtime_test':'U: game and converters not executed'} # Separate integrity, meaning and runtime evidence.
        ext=path.suffix.lower() # Select only checks appropriate to the actual extension.
        if ext=='.txt': # Validate and review the complete human-readable document.
            text=path.read_text(encoding='utf-8-sig',errors='strict') # Require valid UTF-8 rather than replacing errors.
            d.update({'utf8_test':'PASS','nul_chars':text.count('\x00'),'replacement_chars':text.count('\ufffd'),'line_count':len(text.splitlines()),'save_path_mentioned':'KoeiTecmo\\Taiko5DX\\SaveData' in text,'steam_mentioned':'Steam' in text,'semantic_review':'REVIEWED: product README, not program source'}) # Verify encoding and common documented facts.
        elif ext=='.wmv': # Apply documented ASF structural checks to every WMV.
            d['asf']=asf(path); d['structure_test']='PASS' if not d['asf']['issues'] else 'ISSUE' # Distinguish container checks from decoding.
        elif rel in pebyname: # Validate all previously measured PE section bounds against current unchanged files.
            pe=pebyname[rel]; bad=[s['name'] for s in pe['sections'] if s['raw_size'] and s['raw_offset']+s['raw_size']>before.st_size] # Check each raw section stays inside the file.
            d.update({'structure_test':'PASS' if same and not bad else 'ISSUE','out_of_file_sections':bad,'architecture':pe['machine'],'clr_directory':pe['clr_rva'],'signature_test':'PRIOR_VALID_UNCHANGED_HASH' if same else 'U'}) # Reuse dated signature evidence only when bytes match.
        elif ext in {'.te5','.ts5'}: # Check event pairs without pretending to decode the event language.
            other=path.with_suffix('.TS5' if ext=='.te5' else '.TE5') # Locate the same-stem companion file.
            d.update({'pair_test':'PASS' if other.is_file() else 'FAIL','structure_test':'U: compiled event fields not decoded'}) # Record real pairing and the unresolved field semantics.
        elif ext=='.g1t': # Classify container-prefix families without inventing a full decoder.
            family=first[:4].decode('ascii','replace'); d['prefix_family']=family # Record the observed resource family.
            if family=='GT1G': d['uint32_at_offset_8']=struct.unpack_from('<I',first,8)[0]; d['offset8_equals_file_size']=d['uint32_at_offset_8']==before.st_size # Record a size consistency observation, not a format guarantee.
            d['structure_test']='U: container/image payload not decoded' # Keep complete resource validation unresolved.
        elif ext in {'.wb2','.wh2'}: # Verify companion sound-resource filenames.
            other=path.with_suffix('.WH2' if ext=='.wb2' else '.WB2'); d['pair_test']='PASS' if other.is_file() else 'FAIL' # Check every sound-bank pair.
        d['stable_during_read']=before.st_size==after.st_size and before.st_mtime_ns==after.st_mtime_ns # Detect concurrent changes during the complete read.
        details[rel]=d # Preserve detailed per-file checks.
        rows.append({'path':rel,'bytes':before.st_size,'sha256':digest.hexdigest(),'read_test':d['read_test'],'hash_vs_baseline':d['hash_vs_baseline'],'structure_test':d.get('structure_test','U'),'pair_test':d.get('pair_test','NA'),'semantic_review':d['semantic_review'],'runtime_test':d['runtime_test'],'zero_bytes':zeros,'stable_during_read':d['stable_during_read']}) # Make every validation dimension visible in the CSV.
    except Exception as exc: errors.append({'path':rel,'error':str(exc)}) # Preserve any unreadable or malformed file.
with (OUT/'逐文件内容验证结果.csv').open('w',encoding='utf-8-sig',newline='') as f: # Create a complete verification matrix.
    writer=csv.DictWriter(f,fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows) # Write every successfully checked file.
result={'time':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=4))).isoformat(),'count':len(rows),'bytes':sum(r['bytes'] for r in rows),'hash_counts':dict(collections.Counter(r['hash_vs_baseline'] for r in rows)),'structure_counts':dict(collections.Counter(r['structure_test'] for r in rows)),'semantic_counts':dict(collections.Counter(r['semantic_review'] for r in rows)),'all_zero_files':[r['path'] for r in rows if r['bytes'] and r['zero_bytes']==r['bytes']],'errors':errors,'missing_from_baseline':sorted(set(old)-set(details)),'details':details} # Summarize without conflating untested content with passing integrity.
(OUT/'details.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8') # Save complete reproducible evidence.
print(json.dumps({k:v for k,v in result.items() if k!='details'},ensure_ascii=False,indent=2)) # Display concise actual outcomes.
