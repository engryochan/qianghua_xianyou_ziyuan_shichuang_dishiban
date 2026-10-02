import csv, hashlib, json, os, struct, collections, datetime # Load standard libraries only.
from pathlib import Path # Use explicit filesystem paths.
ROOT = Path(r'C:\Program Files (x86)\Steam\steamapps\common\Taiko5DX') # Define the read-only target.
OUT = Path(__file__).parent # Write evidence only beside this audit script.
SOURCE = {'.c','.cpp','.cc','.h','.hpp','.cs','.py','.lua','.js','.ts','.java','.rs','.go','.sln','.vcxproj','.pdb','.map'} # Identify candidate source or debug files by suffix.
NEEDLES = [b'Application load error',b'0000065432',b'3:0000065432'] # Search for the exact reported diagnostic text.
rows, errors, pes, hits, links = [], [], [], [], [] # Store measured evidence.
def walk_error(exc): # Record directory traversal failures rather than hiding them.
    errors.append({'path':str(exc.filename),'error':str(exc)}) # Preserve the failed path and reason.
def pe_info(path): # Parse PE headers without executing or modifying the file.
    with path.open('rb') as f: # Open the executable for reading only.
        def read_at(offset, count): # Read a bounded structure at an explicit offset.
            f.seek(offset); return f.read(count) # Return only requested bytes.
        dos = read_at(0,64) # Read the DOS header.
        if len(dos)<64 or dos[:2]!=b'MZ': return None # Reject non-PE candidates.
        pos = struct.unpack_from('<I',dos,60)[0] # Locate the PE signature.
        header = read_at(pos,24) # Read signature and COFF header.
        if len(header)!=24 or header[:4]!=b'PE\x00\x00': return None # Validate the PE signature.
        machine,nsections,stamp,ptrsym,nsym,optsize,flags = struct.unpack_from('<HHIIIHH',header,4) # Decode the COFF header.
        opt = read_at(pos+24,optsize) # Read the optional header.
        magic = struct.unpack_from('<H',opt)[0] # Identify PE32 or PE32+.
        dd = 112 if magic==0x20b else 96 # Locate data directories.
        sections=[] # Record section names and raw file ranges.
        for index in range(nsections): # Inspect every declared section header.
            sh=read_at(pos+24+optsize+40*index,40) # Read the fixed-size section structure.
            name=sh[:8].rstrip(b'\x00').decode('ascii','replace') # Decode the section label.
            vs,va,rawsize,rawptr=struct.unpack_from('<IIII',sh,8) # Decode sizes and offsets.
            sections.append({'name':name,'virtual_size':vs,'rva':va,'raw_size':rawsize,'raw_offset':rawptr}) # Preserve header evidence.
        def directory(index): # Read a data directory if declared within the optional header.
            return struct.unpack_from('<II',opt,dd+index*8) if len(opt)>=dd+(index+1)*8 else (0,0) # Avoid reading past the header.
        def rva_to_offset(rva): # Translate an RVA using section bounds.
            for s in sections: # Test each declared section mapping.
                if s['rva']<=rva<s['rva']+max(s['virtual_size'],s['raw_size']): return s['raw_offset']+rva-s['rva'] # Return a file offset.
            return rva # Permit header RVAs for inspection.
        imports=[] # Collect library names, not inferred source code.
        imp_rva,imp_size=directory(1) # Locate the import table.
        if imp_rva: # Parse only when a table is present.
            for index in range(min(imp_size//20+1,4096)): # Bound the number of import descriptors.
                entry=read_at(rva_to_offset(imp_rva)+index*20,20) # Read one descriptor.
                if len(entry)!=20 or not any(entry): break # Stop at terminator or truncated input.
                name_rva=struct.unpack_from('<I',entry,12)[0] # Locate the imported library name.
                imports.append(read_at(rva_to_offset(name_rva),256).split(b'\x00')[0].decode('ascii','replace')) # Decode a bounded library name.
        clr=directory(14); debug=directory(6) # Inspect CLR and debug directory presence.
        return {'path':str(path.relative_to(ROOT)),'machine':hex(machine),'format':'PE32+' if magic==0x20b else 'PE32','clr_rva':clr[0],'clr_size':clr[1],'debug_rva':debug[0],'debug_size':debug[1],'coff_symbol_count':nsym,'sections':sections,'imports':imports} # Return observed PE metadata.
for directory, dirs, files in os.walk(ROOT,followlinks=False,onerror=walk_error): # Enumerate normal and hidden entries without following directory links.
    for name in list(dirs): # Inspect directories for reparse targets.
        p=Path(directory)/name # Construct the directory path.
        if getattr(p.lstat(),'st_file_attributes',0)&0x400: # Recognize Windows reparse points.
            links.append(str(p)); dirs.remove(name) # Record and do not traverse outside the target.
    for name in sorted(files): # Inspect each regular file.
        path=Path(directory)/name # Build an absolute target path.
        try: # Keep individual read failures visible.
            before=path.stat(); attrs=getattr(before,'st_file_attributes',0) # Capture size, timestamp and Windows attributes.
            if attrs&0x400: # Avoid opening file reparse targets.
                links.append(str(path)); continue # Record this intentionally untraversed path.
            digest=hashlib.sha256(); first=b''; tail=b''; offset=0; found=set() # Initialize a streaming full-file read.
            with path.open('rb') as handle: # Read target bytes without writes.
                while block:=handle.read(1024*1024): # Stream all file bytes with bounded memory.
                    if not first: first=block[:64] # Retain only the file signature prefix.
                    digest.update(block); data=tail+block # Hash and inspect the chunk with boundary overlap.
                    for needle in NEEDLES: # Search both ASCII and UTF-16LE diagnostic representations.
                        for pattern in (needle,needle.decode('ascii').encode('utf-16le')): # Include Windows wide-character strings.
                            if pattern in data: found.add(needle.decode('ascii')) # Record a literal match without attributing its meaning.
                    tail=data[-128:]; offset+=len(block) # Retain overlap for boundary-spanning strings.
            after=path.stat() # Check concurrent file change during the read.
            rows.append({'path':str(path.relative_to(ROOT)),'bytes':before.st_size,'bytes_read':offset,'sha256':digest.hexdigest(),'mtime_ns':before.st_mtime_ns,'attributes':attrs,'header_hex':first.hex(),'extension':path.suffix.lower(),'source_candidate':path.suffix.lower() in SOURCE,'stable_during_read':before.st_size==after.st_size and before.st_mtime_ns==after.st_mtime_ns}) # Preserve one full-file evidence row.
            if found: hits.append({'path':str(path.relative_to(ROOT)),'matches':sorted(found)}) # Preserve exact literal matches.
            if first[:2]==b'MZ': # Inspect executable-format candidates independent of their suffix.
                try: # Distinguish successful byte reads from malformed headers.
                    info=pe_info(path) # Read header structures only.
                    if info: pes.append(info) # Preserve valid PE metadata.
                except Exception as exc: errors.append({'path':str(path),'stage':'PE header','error':str(exc)}) # Record parse limitations.
        except Exception as exc: errors.append({'path':str(path),'stage':'read','error':str(exc)}) # Preserve unreadable targets.
with (OUT/'all-files.csv').open('w',encoding='utf-8-sig',newline='') as f: # Write a spreadsheet-readable evidence manifest.
    writer=csv.DictWriter(f,fieldnames=list(rows[0]) if rows else ['path']); writer.writeheader(); writer.writerows(rows) # Write all measured rows.
groups=collections.defaultdict(lambda:{'count':0,'bytes':0}) # Group observed files by extension.
for row in rows: # Sum only successfully read files.
    groups[row['extension']]['count']+=1; groups[row['extension']]['bytes']+=row['bytes'] # Update measured group totals.
summary={'timestamp':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=4))).isoformat(),'root':str(ROOT),'file_count':len(rows),'bytes':sum(r['bytes'] for r in rows),'read_bytes':sum(r['bytes_read'] for r in rows),'unstable_files':[r['path'] for r in rows if not r['stable_during_read']],'source_candidates':[r['path'] for r in rows if r['source_candidate']],'extensions':dict(groups),'pe_files':pes,'literal_error_matches':hits,'errors':errors,'untraversed_reparse_points':links,'scope':'Full file hashing and literal search; PE headers/import DLL names only. No execution, decompilation, archive extraction, DRM removal or writes to target.'} # State evidence and scope explicitly.
(OUT/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8') # Save the full machine-readable report.
print(json.dumps({k:summary[k] for k in ('timestamp','file_count','bytes','read_bytes','unstable_files','source_candidates','extensions','literal_error_matches','errors','untraversed_reparse_points')},ensure_ascii=False,indent=2)) # Print a concise result for review.
