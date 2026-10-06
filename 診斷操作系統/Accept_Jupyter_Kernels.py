"""Section 8 of the regression: a kernel is only registered if its kernel.json
PARSES and points at an interpreter that really exists and can import ipykernel.
`jupyter kernelspec list` only lists DIRECTORIES -- it happily shows a kernel
whose JSON is malformed, which is exactly how six broken kernel.json files
survived an earlier 'verification'."""
import json, os, subprocess, sys

root = r'C:\work\jupyter\kernels'
bad = 0
for name in sorted(os.listdir(root)):
    kj = os.path.join(root, name, 'kernel.json')
    if not os.path.isfile(kj):
        print(f'  {name:6} FAIL no kernel.json'); bad += 1; continue
    try:
        with open(kj, encoding='utf-8') as f:
            spec = json.load(f)
    except Exception as e:
        print(f'  {name:6} FAIL unparseable: {type(e).__name__}: {e}'); bad += 1; continue
    exe = spec.get('argv', [None])[0]
    if not exe or not os.path.isfile(exe):
        print(f'  {name:6} FAIL argv[0] not an existing file: {exe!r}'); bad += 1; continue
    r = subprocess.run([exe, '-c', 'import ipykernel; print(ipykernel.__version__)'],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print(f'  {name:6} FAIL ipykernel import: {r.stderr.strip()[:70]}'); bad += 1; continue
    print(f'  {name:6} PASS ipykernel {r.stdout.strip()}  <- {exe}')

print(f'  kernels bad: {bad:d}')
sys.exit(1 if bad else 0)
