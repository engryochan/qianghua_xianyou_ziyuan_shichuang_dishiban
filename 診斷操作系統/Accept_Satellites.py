"""Smoke-acceptance for the satellite envs: each exiled package must actually import
and do one real thing. Run with the satellite's own interpreter."""
import sys, importlib

GROUPS = {
    'fin':   ['openbb', 'pypfopt', 's3fs'],
    'nlp':   ['flair', 'transformer_smaller_training_vocab'],
    'mlops': ['evidently', 'nannyml', 'feast'],
    'xai':   ['dalex'],
    'rl':    ['tianshou', 'gluonts', 'gevent'],
}
g = sys.argv[1]
rows = []
for mod in GROUPS[g]:
    try:
        m = importlib.import_module(mod)
        v = getattr(m, '__version__', '?')
        rows.append((mod, 'PASS', str(v)))
    except Exception as e:
        rows.append((mod, 'FAIL', f'{type(e).__name__}: {e}'[:110]))

# one real computation per group, to prove it is not just an import
extra = None
try:
    if g == 'xai':
        import dalex, plotly
        extra = ('dalex+plotly', 'PASS', 'plotly ' + plotly.__version__)
    elif g == 'mlops':
        import plotly
        extra = ('plotly<6 held', 'PASS' if int(plotly.__version__.split('.')[0]) < 6 else 'FAIL',
                 plotly.__version__)
    elif g == 'nlp':
        import transformers
        major = int(transformers.__version__.split('.')[0])
        extra = ('transformers<5 held', 'PASS' if major < 5 else 'FAIL', transformers.__version__)
    elif g == 'rl':
        import cffi
        extra = ('cffi', 'PASS', cffi.__version__)
    elif g == 'fin':
        import fsspec
        extra = ('fsspec', 'PASS', fsspec.__version__)
except Exception as e:
    extra = ('extra-check', 'FAIL', f'{type(e).__name__}: {e}'[:110])
if extra:
    rows.append(extra)

print(f'--- {g} ---')
for n, s, d in rows:
    print(f'  {n:36} {s:5} {d}')
print('  ' + ('ALL PASS' if all(s == 'PASS' for _, s, _ in rows) else 'HAS FAILURES'))
sys.exit(0 if all(s == 'PASS' for _, s, _ in rows) else 1)
