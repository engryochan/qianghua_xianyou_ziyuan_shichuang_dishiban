"""Deterministic CPU model, Excel engine and notebook execution acceptance."""
import argparse
import json
from pathlib import Path
import numpy as np
import pandas as pd
import polars as pl
from sklearn.datasets import make_classification
from sklearn.model_selection import train_test_split
import xgboost as xgb
import lightgbm as lgb
from econml.dml import LinearDML
import nbformat
from nbclient import NotebookClient
import win32com.client

p = argparse.ArgumentParser()
p.add_argument('--output', required=True)
a = p.parse_args()
out = Path(a.output).resolve()
out.mkdir(parents=True, exist_ok=True)
X, y = make_classification(n_samples=20000, n_features=20, random_state=0)
Xtr, Xte, ytr, yte = train_test_split(X, y, random_state=0)
xacc = xgb.XGBClassifier(tree_method='hist', n_estimators=60, n_jobs=6,
                        random_state=0).fit(Xtr, ytr).score(Xte, yte)
lacc = lgb.LGBMClassifier(n_estimators=60, n_jobs=6, verbosity=-1,
                         random_state=0).fit(Xtr, ytr).score(Xte, yte)
assert xacc > .8 and lacc > .8
rng = np.random.default_rng(0)
n = 3000
xc = rng.normal(size=(n, 3))
t = rng.binomial(1, .5, n)
yy = 2*t + xc[:, 0] + rng.normal(size=n)
ate = float(LinearDML(discrete_treatment=True, random_state=0).fit(yy, t, X=xc).ate(xc))
assert abs(ate - 2) < .15
frame = pd.DataFrame({'group': ['A', 'B'], 'value': [3, 7]})
excel = out / 'engines.xlsx'
frame.to_excel(excel, index=False, engine='xlsxwriter')
pd.testing.assert_frame_equal(pd.read_excel(excel, engine='calamine'), frame)
assert pl.read_excel(excel, engine='calamine')['value'].sum() == 10
nb = nbformat.v4.new_notebook(cells=[nbformat.v4.new_code_cell(
    'import sys, duckdb\nassert duckdb.sql("select 6*7").fetchone()[0] == 42\nprint(sys.executable)')])
# Use an explicit kernel command so an unrelated registered kernel cannot mask errors.
import sys
from jupyter_client import KernelManager
from jupyter_client.kernelspec import KernelSpec
km = KernelManager()
km._kernel_spec = KernelSpec(argv=[sys.executable, '-m', 'ipykernel_launcher', '-f', '{connection_file}'],
                             display_name='Acceptance Python', language='python')
try:
    NotebookClient(nb, timeout=60, km=km).execute()
finally:
    if km.has_kernel:
        km.shutdown_kernel(now=True)
    km.cleanup_resources()
nbformat.write(nb, out / 'executed.ipynb')
result = {'status': 'passed', 'python': sys.executable, 'xgboost_accuracy': xacc,
          'lightgbm_accuracy': lacc, 'causal_ate': ate,
          'checks': ['xgboost-cpu', 'lightgbm-cpu', 'econml', 'pandas-calamine',
                     'polars-fastexcel', 'win32com-import', 'jupyter-kernel-execution']}
(out / 'models-result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result))
