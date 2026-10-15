"""Render every QMD to HTML; retain per-document logs and a JSON result manifest."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
DEST = Path(__file__).resolve().parent
QUARTO = shutil.which('quarto')
if not QUARTO:
    raise SystemExit('Quarto was not found on PATH')
env = os.environ.copy()
# Windows R rejects the POSIX C.UTF-8 locale inherited from the agent shell.
for key in ('LC_ALL', 'LC_CTYPE', 'LANG'):
    env.pop(key, None)
files = sorted(ROOT.rglob('*.qmd'))

def render(item):
    index, path = item
    log = DEST / f'final-{index:02}.log'
    with log.open('wb') as stream:
        process = subprocess.run([QUARTO, 'render', str(path), '--to', 'html'],
                                 cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT)
    result = dict(file=path.relative_to(ROOT).as_posix(), exit_code=process.returncode,
                  log=log.name, html=path.with_suffix('.html').relative_to(ROOT).as_posix())
    print(f'[{index}/{len(files)}] exit={process.returncode} {path.name}', flush=True)
    return result

results = []
items = list(enumerate(files, 1))
if '--retry-failed' in sys.argv:
    previous = json.loads((DEST / 'final-results.json').read_text(encoding='utf-8'))
    results = [row for row in previous if row['exit_code'] == 0]
    complete = {row['file'] for row in results}
    items = [(i, path) for i, path in items if path.relative_to(ROOT).as_posix() not in complete]
with ThreadPoolExecutor(max_workers=3) as pool:
    for future in as_completed([pool.submit(render, pair) for pair in items]):
        results.append(future.result())
        (DEST / 'final-results.json').write_text(json.dumps(sorted(results, key=lambda x: x['file']),
            ensure_ascii=False, indent=2), encoding='utf-8')
raise SystemExit(1 if any(row['exit_code'] for row in results) else 0)
