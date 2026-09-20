"""Small deterministic end-to-end checks; only writes below the chosen results folder."""
import argparse
import importlib.metadata as metadata
import json
from pathlib import Path
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--output", required=True)
parser.add_argument("--extended", action="store_true")
args = parser.parse_args()
out = Path(args.output)
out.mkdir(parents=True, exist_ok=True)

import numpy as np
import pandas as pd
import polars as pl
import pyarrow.parquet as pq
import duckdb
import scipy.stats as stats
import statsmodels.api as sm
from sklearn.linear_model import LinearRegression
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import seaborn
import plotly.express as px
import sqlalchemy
import jupyterlab
import ipykernel

df = pd.DataFrame({"group": ["A", "B", "A", "B"], "value": [1, 2, 3, 4]})
parquet = out / "sample.parquet"
df.to_parquet(parquet, index=False)
assert pq.read_table(parquet).num_rows == 4
assert pl.scan_parquet(parquet).select(pl.col("value").sum()).collect().item() == 10
with duckdb.connect() as con:
    assert con.execute("SELECT SUM(value) FROM read_parquet(?)", [str(parquet)]).fetchone()[0] == 10
    grouped = con.execute("SELECT \"group\", SUM(value) AS total FROM read_parquet(?) GROUP BY 1 ORDER BY 1", [str(parquet)]).fetchall()
    assert grouped == [("A", 4), ("B", 6)]
for engine in ("openpyxl", "xlsxwriter"):
    excel = out / f"sample-{engine}.xlsx"
    df.to_excel(excel, index=False, engine=engine)
    pd.testing.assert_frame_equal(pd.read_excel(excel, engine="openpyxl"), df)
x = np.arange(12, dtype=float).reshape(-1, 1)
y = 2 * x[:, 0] + 1
assert np.isclose(LinearRegression().fit(x, y).coef_[0], 2)
assert np.isclose(sm.OLS(y, sm.add_constant(x)).fit().params[1], 2)
assert np.isclose(stats.linregress(x[:, 0], y).slope, 2)
engine = sqlalchemy.create_engine("sqlite:///:memory:")
df.to_sql("sample", engine, index=False)
with engine.connect() as con:
    assert con.execute(sqlalchemy.text("SELECT SUM(value) FROM sample")).scalar() == 10
fig, ax = plt.subplots()
ax.plot(x[:, 0], y)
fig.savefig(out / "regression.png")
plt.close(fig)
px.bar(df, x="group", y="value").write_html(out / "chart.html", include_plotlyjs=True)
checks = ["parquet", "polars-lazy", "duckdb-sql", "excel-openpyxl", "excel-xlsxwriter", "sklearn-regression", "scipy", "statsmodels", "sqlalchemy", "matplotlib", "plotly", "jupyter-import"]
if args.extended:
    import xgboost
    import lightgbm
    import shap
    import pyodbc
    import psycopg
    import pymysql
    import streamlit
    import papermill
    import win32com.client
    import joblib
    import pytest
    xgboost.XGBRegressor(n_estimators=3, max_depth=2, n_jobs=2).fit(x, y).predict(x)
    lightgbm.LGBMRegressor(n_estimators=3, min_child_samples=2, n_jobs=2, verbosity=-1).fit(x, y).predict(x)
    checks += ["xgboost-cpu", "lightgbm-cpu", "shap-import", "database-driver-imports", "streamlit-import", "office-com-import"]
report = {"status": "passed", "python": sys.version, "executable": sys.executable,
          "checks": checks, "packages": {d.metadata["Name"]: d.version for d in metadata.distributions()}}
(out / "smoke-result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps({"status": "passed", "checks": checks, "output": str(out)}))
