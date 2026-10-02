import csv, json # Load only standard evidence-processing modules.
from pathlib import Path # Resolve report paths independently of the current directory.
OUT=Path(__file__).parent # Store comparison beside the new audit.
BASE=OUT.parent/'steam-taiko-baseline-20261002'/'20261002-152429'/'all-files.csv' # Select the previous post-error baseline.
ROOT='C:\\Program Files (x86)\\Steam\\steamapps\\common\\Taiko5DX\\' # Limit comparison to the requested game directory.
with BASE.open(encoding='utf-8-sig',newline='') as f: old={r['path'][len(ROOT):]:r for r in csv.DictReader(f) if r['path'].startswith(ROOT) and r['kind']=='file'} # Read only baseline game files.
with (OUT/'all-files.csv').open(encoding='utf-8-sig',newline='') as f: new={r['path']:r for r in csv.DictReader(f)} # Read current hashes.
result={'baseline':str(BASE),'old_count':len(old),'new_count':len(new),'added':sorted(new.keys()-old.keys()),'removed':sorted(old.keys()-new.keys()),'changed':[p for p in new.keys()&old.keys() if new[p]['sha256']!=old[p]['sha256']],'baseline_missing_hash':[p for p,r in old.items() if not r['sha256']]} # Compare file sets and hashes without changes to targets.
(OUT/'baseline-comparison.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8') # Save the actual comparison result.
print(json.dumps(result,ensure_ascii=False,indent=2)) # Display all differences and limitations.
