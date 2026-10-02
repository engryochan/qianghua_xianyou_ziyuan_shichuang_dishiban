"""Add Excel/Windows interoperability to existing venvs without upgrading packages.

Default: resolve only. --apply installs after ALL environments resolve successfully.
Snapshots and command logs are stored locally; no global settings are changed.
"""
import argparse
import datetime
import json
from pathlib import Path
import shutil
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--apply', action='store_true')
p.add_argument('--python', action='append', required=True)
p.add_argument('--output', required=True)
a = p.parse_args()
out = Path(a.output).resolve() / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
out.mkdir(parents=True, exist_ok=False)
uv = shutil.which('uv')
if not uv:
    raise SystemExit('uv not found')
extras = ['openpyxl', 'xlsxwriter', 'python-calamine', 'fastexcel', 'pywin32']
plans = []

def run(args, log):
    r = subprocess.run(args, capture_output=True, text=True, encoding='utf-8',
                       errors='replace', timeout=600)
    (out / log).write_text(r.stdout + r.stderr, encoding='utf-8')
    print(r.stderr if 'freeze' in args else r.stdout + r.stderr, flush=True)
    r.check_returncode()
    return r.stdout

for i, python in enumerate(a.python):
    python = str(Path(python).resolve())
    run([python, '-I', '-c',
         'import sys; assert sys.prefix != sys.base_prefix, "Requires a venv"'], f'{i}-venv.log')
    before = run([uv, 'pip', 'freeze', '--python', python], f'{i}-before.log')
    constraints = out / f'{i}-before.txt'
    constraints.write_text(before, encoding='utf-8')
    # Existing exact versions constrain all dependencies; resolution cannot upgrade them.
    args = [uv, 'pip', 'install', '--python', python, '--index-url',
            'https://pypi.org/simple', '--only-binary', ':all:', '--constraint',
            str(constraints), *extras]
    run([*args, '--dry-run'], f'{i}-plan.log')
    plans.append((i, python, args))

status = {'started': datetime.datetime.now().isoformat(), 'extras': extras,
          'mode': 'apply' if a.apply else 'plan', 'environments': []}
try:
    for i, python, args in plans:
        row = {'python': python, 'status': 'resolved'}
        status['environments'].append(row)
        if a.apply:
            row['status'] = 'installing'
            run(args, f'{i}-install.log')
            run([uv, 'pip', 'check', '--python', python], f'{i}-check.log')
            after = run([uv, 'pip', 'freeze', '--python', python], f'{i}-after.log')
            (out / f'{i}-after.txt').write_text(after, encoding='utf-8')
            row['status'] = 'installed-dependencies-checked'
finally:
    (out / 'status.json').write_text(json.dumps(status, indent=2), encoding='utf-8')
