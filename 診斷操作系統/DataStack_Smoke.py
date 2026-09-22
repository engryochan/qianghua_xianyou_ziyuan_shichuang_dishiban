# 声明模块的用途说明字符串，保留其原文内容。
"""Small deterministic end-to-end checks; only writes below the chosen results folder."""
# 导入 argparse，供后续代码调用。
import argparse
# 导入 importlib.metadata as metadata，供后续代码调用。
import importlib.metadata as metadata
# 导入 json，供后续代码调用。
import json
# 导入 pathlib 中的 Path，供后续代码调用。
from pathlib import Path
# 导入 sys，供后续代码调用。
import sys

# 创建命令行参数解析器，并保存到 parser。
parser = argparse.ArgumentParser()
# 声明一个命令行参数及其约束。
parser.add_argument("--output", required=True)
# 声明一个命令行参数及其约束。
parser.add_argument("--extended", action="store_true")
# 解析命令行传入的参数，并保存到 args。
args = parser.parse_args()
# 计算本行表达式并设置 out，供后续步骤使用。
out = Path(args.output)
# 创建输出目录。
out.mkdir(parents=True, exist_ok=True)

# 导入 numpy as np，供后续代码调用。
import numpy as np
# 导入 pandas as pd，供后续代码调用。
import pandas as pd
# 导入 polars as pl，供后续代码调用。
import polars as pl
# 导入 pyarrow.parquet as pq，供后续代码调用。
import pyarrow.parquet as pq
# 导入 duckdb，供后续代码调用。
import duckdb
# 导入 scipy.stats as stats，供后续代码调用。
import scipy.stats as stats
# 导入 statsmodels.api as sm，供后续代码调用。
import statsmodels.api as sm
# 导入 sklearn.linear_model 中的 LinearRegression，供后续代码调用。
from sklearn.linear_model import LinearRegression
# 导入 matplotlib，供后续代码调用。
import matplotlib
# 调用 matplotlib.use，使用本行列出的输入完成对应操作。
matplotlib.use("Agg")
# 导入 matplotlib.pyplot as plt，供后续代码调用。
import matplotlib.pyplot as plt
# 导入 seaborn，供后续代码调用。
import seaborn
# 导入 plotly.express as px，供后续代码调用。
import plotly.express as px
# 导入 sqlalchemy，供后续代码调用。
import sqlalchemy
# 导入 jupyterlab，供后续代码调用。
import jupyterlab
# 导入 ipykernel，供后续代码调用。
import ipykernel

# 构造或计算 df，保存本行指定的集合或索引结果。
df = pd.DataFrame({"group": ["A", "B", "A", "B"], "value": [1, 2, 3, 4]})
# 计算本行表达式并设置 parquet，供后续步骤使用。
parquet = out / "sample.parquet"
# 将表格保存为 Parquet 文件。
df.to_parquet(parquet, index=False)
# 断言本行条件成立；不满足时中止验收并报错。
assert pq.read_table(parquet).num_rows == 4
# 断言本行条件成立；不满足时中止验收并报错。
assert pl.scan_parquet(parquet).select(pl.col("value").sum()).collect().item() == 10
# 进入上下文管理器，确保结束时自动释放相应资源。
with duckdb.connect() as con:
    # 断言本行条件成立；不满足时中止验收并报错。
    assert con.execute("SELECT SUM(value) FROM read_parquet(?)", [str(parquet)]).fetchone()[0] == 10
    # 读取 Parquet 数据；执行对象提供的命令或查询，并保存到 grouped。
    grouped = con.execute("SELECT \"group\", SUM(value) AS total FROM read_parquet(?) GROUP BY 1 ORDER BY 1", [str(parquet)]).fetchall()
    # 断言本行条件成立；不满足时中止验收并报错。
    assert grouped == [("A", 4), ("B", 6)]
# 按本行的迭代范围或条件重复执行循环体。
for engine in ("openpyxl", "xlsxwriter"):
    # 计算本行表达式并设置 excel，供后续步骤使用。
    excel = out / f"sample-{engine}.xlsx"
    # 将表格写入 Excel 文件。
    df.to_excel(excel, index=False, engine=engine)
    # 读取 Excel 工作表。
    pd.testing.assert_frame_equal(pd.read_excel(excel, engine="openpyxl"), df)
# 计算本行表达式并设置 x，供后续步骤使用。
x = np.arange(12, dtype=float).reshape(-1, 1)
# 构造或计算 y，保存本行指定的集合或索引结果。
y = 2 * x[:, 0] + 1
# 断言本行条件成立；不满足时中止验收并报错。
assert np.isclose(LinearRegression().fit(x, y).coef_[0], 2)
# 断言本行条件成立；不满足时中止验收并报错。
assert np.isclose(sm.OLS(y, sm.add_constant(x)).fit().params[1], 2)
# 断言本行条件成立；不满足时中止验收并报错。
assert np.isclose(stats.linregress(x[:, 0], y).slope, 2)
# 补充当前函数调用的命名参数。
engine = sqlalchemy.create_engine("sqlite:///:memory:")
# 调用 df.to_sql，使用本行列出的输入完成对应操作。
df.to_sql("sample", engine, index=False)
# 进入上下文管理器，确保结束时自动释放相应资源。
with engine.connect() as con:
    # 断言本行条件成立；不满足时中止验收并报错。
    assert con.execute(sqlalchemy.text("SELECT SUM(value) FROM sample")).scalar() == 10
# 将右侧返回的多项结果依次分配给 fig, ax。
fig, ax = plt.subplots()
# 调用 ax.plot，使用本行列出的输入完成对应操作。
ax.plot(x[:, 0], y)
# 将图形保存到文件。
fig.savefig(out / "regression.png")
# 调用 plt.close，使用本行列出的输入完成对应操作。
plt.close(fig)
# 将交互图表保存为 HTML 文件。
px.bar(df, x="group", y="value").write_html(out / "chart.html", include_plotlyjs=True)
# 构造或计算 checks，保存本行指定的集合或索引结果。
checks = ["parquet", "polars-lazy", "duckdb-sql", "excel-openpyxl", "excel-xlsxwriter", "sklearn-regression", "scipy", "statsmodels", "sqlalchemy", "matplotlib", "plotly", "jupyter-import"]
# 处理 if 所指定的操作或当前表达式的后续部分。
if args.extended:
    # 导入 xgboost，供后续代码调用。
    import xgboost
    # 导入 lightgbm，供后续代码调用。
    import lightgbm
    # 导入 shap，供后续代码调用。
    import shap
    # 导入 pyodbc，供后续代码调用。
    import pyodbc
    # 导入 psycopg，供后续代码调用。
    import psycopg
    # 导入 pymysql，供后续代码调用。
    import pymysql
    # 导入 streamlit，供后续代码调用。
    import streamlit
    # 导入 papermill，供后续代码调用。
    import papermill
    # 导入 win32com.client，供后续代码调用。
    import win32com.client
    # 导入 joblib，供后续代码调用。
    import joblib
    # 导入 pytest，供后续代码调用。
    import pytest
    # 使用给定数据拟合模型；使用已拟合模型计算预测值。
    xgboost.XGBRegressor(n_estimators=3, max_depth=2, n_jobs=2).fit(x, y).predict(x)
    # 使用给定数据拟合模型；使用已拟合模型计算预测值。
    lightgbm.LGBMRegressor(n_estimators=3, min_child_samples=2, n_jobs=2, verbosity=-1).fit(x, y).predict(x)
    # 构造或计算 checks，保存本行指定的集合或索引结果。
    checks += ["xgboost-cpu", "lightgbm-cpu", "shap-import", "database-driver-imports", "streamlit-import", "office-com-import"]
# 计算本行表达式并设置 report，供后续步骤使用。
report = {"status": "passed", "python": sys.version, "executable": sys.executable,
          # 枚举当前 Python 环境的套件元数据。
          "checks": checks, "packages": {d.metadata["Name"]: d.version for d in metadata.distributions()}}
# 将文本写入目标文件；将结果序列化为 JSON 文本。
(out / "smoke-result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
# 输出本行的状态信息或计算结果。
print(json.dumps({"status": "passed", "checks": checks, "output": str(out)}))
