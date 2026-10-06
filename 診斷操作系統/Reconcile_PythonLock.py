import re, subprocess, pathlib, json, os
REPO = r'C:\Users\PPCCpcpc\Documents\GitHub\qianghua_xianyou_ziyuan_shichuang_dishiban'
SRC  = pathlib.Path(REPO) / 'env' / 'python-ds-requirements.lock.txt'
WORK = pathlib.Path(r'C:\work\logs\candidate_final.txt')
UV   = os.path.expandvars(r'%USERPROFILE%\.local\bin\uv.exe')
PY   = r'C:\work\envs\ds\Scripts\python.exe'

# Shared infrastructure that many other pinned packages build on: never exile these.
# When a hard conflict pits one of these against an application-level framework,
# the framework is exiled to a satellite env instead.
BASE = {'fsspec','toolz','cffi','plotly','transformers','platformdirs','tenacity',
        'scikit-learn','datasets','virtualenv','boto3','botocore','numpy','pandas',
        'pyarrow','scipy','torch','huggingface-hub','tokenizers','protobuf','packaging',
        'pydantic','typing-extensions','requests','urllib3','jinja2','rich','click'}
SEED_EXCLUDE = {'dalex','flair','gevent','gluonts'}   # decided in earlier rounds, see report
def norm(n): return re.sub(r'[-_.]+','-',n).lower()

all_pins = {}
src_order = []
for raw in SRC.read_text(encoding='utf-8').splitlines():
    s=raw.strip()
    if not s or s.startswith('#') or '==' not in s: continue
    n,v=s.split('==',1); k=norm(n); all_pins[k]=(n.strip(),v.strip()); src_order.append(k)

exiled = set(SEED_EXCLUDE)
relaxed, frozen, journal = set(), set(), []

def write(cand_relaxed, cand_exiled):
    WORK.write_text('\n'.join(
        (f'{all_pins[k][0]}>={all_pins[k][1]}' if k in cand_relaxed else f'{all_pins[k][0]}=={all_pins[k][1]}')
        for k in src_order if k not in cand_exiled) + '\n', encoding='utf-8')

def solve(cand_relaxed, cand_exiled):
    write(cand_relaxed, cand_exiled)
    p = subprocess.run([UV,'pip','install','--python',PY,'--dry-run','-r',str(WORK)],
                       capture_output=True,text=True,encoding='utf-8',errors='replace')
    return p.returncode, (p.stderr or '')+(p.stdout or '')

for rnd in range(1,121):
    rc,err = solve(relaxed, exiled)
    if rc==0:
        print(f'[{rnd}] SOLVABLE'); journal.append({'round':rnd,'status':'solvable'}); break
    named=set()
    for m in re.finditer(r'you require ([A-Za-z0-9._-]+)[=><]=', err): named.add(norm(m.group(1)))
    for m in re.finditer(r'([A-Za-z0-9._-]+)[=><]=[0-9][^\s,]* depends on', err): named.add(norm(m.group(1)))
    named &= set(k for k in src_order if k not in exiled)
    fresh = sorted(c for c in named if c not in relaxed and c not in frozen)
    if fresh:
        relaxed.update(fresh); print(f'[{rnd}] relax -> {", ".join(fresh)}')
        journal.append({'round':rnd,'status':'relax','pkgs':fresh}); continue
    # repair: withdraw one relaxation
    done=False
    for c in sorted(named & relaxed):
        rc2,_=solve(relaxed-{c}, exiled)
        if rc2==0:
            relaxed.discard(c); frozen.add(c); done=True
            print(f'[{rnd}] REPAIR withdraw relax of {all_pins[c][0]}')
            journal.append({'round':rnd,'status':'repair','pkg':all_pins[c][0]}); break
    if done: continue
    # exile the application-level framework (not shared base)
    cand = sorted(c for c in named if c not in BASE)
    if not cand:
        print(f'[{rnd}] UNRESOLVABLE among base packages'); print(err[-1500:])
        journal.append({'round':rnd,'status':'stuck','error':err[-1500:]}); break
    victim = cand[0]
    for c in cand:
        rc3,_=solve(relaxed, exiled|{c})
        if rc3==0: victim=c; break
    exiled.add(victim); relaxed.discard(victim)
    print(f'[{rnd}] EXILE {all_pins[victim][0]}=={all_pins[victim][1]} -> satellite env')
    journal.append({'round':rnd,'status':'exile','pkg':all_pins[victim][0],'ver':all_pins[victim][1]})

kept=[k for k in src_order if k not in exiled]
print(f'\n=== CORE: {len(kept)} pkgs | exact {len(kept)-len(relaxed)} | relaxed(>=) {len(relaxed)} | exiled {len(exiled)} ===')
print('EXILED -> satellite:'); [print('   ',all_pins[k][0],'==',all_pins[k][1]) for k in sorted(exiled)]
print('RELAXED(>=):'); [print('   ',all_pins[k][0],'>=',all_pins[k][1]) for k in sorted(relaxed)]
pathlib.Path(r'C:\work\logs\reconcile_final.json').write_text(json.dumps(
  {'core_count':len(kept),'exact':len(kept)-len(relaxed),
   'relaxed':{all_pins[k][0]:all_pins[k][1] for k in sorted(relaxed)},
   'exiled':{all_pins[k][0]:all_pins[k][1] for k in sorted(exiled)},
   'journal':journal}, indent=2, ensure_ascii=False), encoding='utf-8')
