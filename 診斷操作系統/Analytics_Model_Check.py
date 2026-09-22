# 声明模块的用途说明字符串，保留其原文内容。
"""Deterministic CPU model, Excel engine and notebook execution acceptance."""
# 导入 argparse，供后续代码调用。
import argparse
# 导入 json，供后续代码调用。
import json
# 导入 pathlib 中的 Path，供后续代码调用。
from pathlib import Path
# 导入 numpy as np，供后续代码调用。
import numpy as np
# 导入 pandas as pd，供后续代码调用。
import pandas as pd
# 导入 polars as pl，供后续代码调用。
import polars as pl
# 导入 sklearn.datasets 中的 make_classification，供后续代码调用。
from sklearn.datasets import make_classification
# 导入 sklearn.model_selection 中的 train_test_split，供后续代码调用。
from sklearn.model_selection import train_test_split
# 导入 xgboost as xgb，供后续代码调用。
import xgboost as xgb
# 导入 lightgbm as lgb，供后续代码调用。
import lightgbm as lgb
# 导入 econml.dml 中的 LinearDML，供后续代码调用。
from econml.dml import LinearDML
# 导入 nbformat，供后续代码调用。
import nbformat
# 导入 nbclient 中的 NotebookClient，供后续代码调用。
from nbclient import NotebookClient
# 导入 win32com.client，供后续代码调用。
import win32com.client

# 创建命令行参数解析器，并保存到 p。
p = argparse.ArgumentParser()
# 声明一个命令行参数及其约束。
p.add_argument('--output', required=True)
# 解析命令行传入的参数，并保存到 a。
a = p.parse_args()
# 计算本行表达式并设置 out，供后续步骤使用。
out = Path(a.output).resolve()
# 创建输出目录。
out.mkdir(parents=True, exist_ok=True)
# 生成固定随机种子的分类样本，分别保存特征矩阵 X 与标签 y。
X, y = make_classification(n_samples=20000, n_features=20, random_state=0)
# 按固定随机种子划分训练集与测试集，分别保存特征和标签。
Xtr, Xte, ytr, yte = train_test_split(X, y, random_state=0)
# 配置 CPU 直方图算法、树数量与线程数，准备 XGBoost 分类验收。
xacc = xgb.XGBClassifier(tree_method='hist', n_estimators=60, n_jobs=6,
                        # 补充当前函数调用的命名参数，随后拟合模型并计算测试分数。
                        random_state=0).fit(Xtr, ytr).score(Xte, yte)
# 配置 LightGBM 分类器的树数量与 CPU 线程数。
lacc = lgb.LGBMClassifier(n_estimators=60, n_jobs=6, verbosity=-1,
                         # 补充当前函数调用的命名参数，随后拟合模型并计算测试分数。
                         random_state=0).fit(Xtr, ytr).score(Xte, yte)
# 断言本行条件成立；不满足时中止验收并报错。
assert xacc > .8 and lacc > .8
# 创建固定种子的随机数生成器，并保存到 rng。
rng = np.random.default_rng(0)
# 计算本行表达式并设置 n，供后续步骤使用。
n = 3000
# 计算本行表达式并设置 xc，供后续步骤使用。
xc = rng.normal(size=(n, 3))
# 计算本行表达式并设置 t，供后续步骤使用。
t = rng.binomial(1, .5, n)
# 构造或计算 yy，保存本行指定的集合或索引结果。
yy = 2*t + xc[:, 0] + rng.normal(size=n)
# 使用给定数据拟合模型，并保存到 ate。
ate = float(LinearDML(discrete_treatment=True, random_state=0).fit(yy, t, X=xc).ate(xc))
# 断言本行条件成立；不满足时中止验收并报错。
assert abs(ate - 2) < .15
# 构造或计算 frame，保存本行指定的集合或索引结果。
frame = pd.DataFrame({'group': ['A', 'B'], 'value': [3, 7]})
# 计算本行表达式并设置 excel，供后续步骤使用。
excel = out / 'engines.xlsx'
# 将表格写入 Excel 文件。
frame.to_excel(excel, index=False, engine='xlsxwriter')
# 读取 Excel 工作表。
pd.testing.assert_frame_equal(pd.read_excel(excel, engine='calamine'), frame)
# 断言本行条件成立；不满足时中止验收并报错。
assert pl.read_excel(excel, engine='calamine')['value'].sum() == 10
# 构造或计算 nb，保存本行指定的集合或索引结果。
nb = nbformat.v4.new_notebook(cells=[nbformat.v4.new_code_cell(
    # 提供当前表达式所需的文本、字段名称或列表元素。
    'import sys, duckdb\nassert duckdb.sql("select 6*7").fetchone()[0] == 42\nprint(sys.executable)')])
# Use an explicit kernel command so an unrelated registered kernel cannot mask errors.
# 导入 sys，供后续代码调用。
import sys
# 导入 jupyter_client 中的 KernelManager，供后续代码调用。
from jupyter_client import KernelManager
# 导入 jupyter_client.kernelspec 中的 KernelSpec，供后续代码调用。
from jupyter_client.kernelspec import KernelSpec
# 创建 Jupyter 内核管理器，并保存到 km。
km = KernelManager()
# 指定 Notebook 内核的解释器和启动参数，并保存到 km._kernel_spec。
km._kernel_spec = KernelSpec(argv=[sys.executable, '-m', 'ipykernel_launcher', '-f', '{connection_file}'],
                             # 补充当前函数调用的命名参数。
                             display_name='Acceptance Python', language='python')
# 开始受异常处理保护的操作。
try:
    # 执行对象提供的命令或查询；执行 Notebook 并验证单元格结果。
    NotebookClient(nb, timeout=60, km=km).execute()
# 无论是否发生异常，都执行此处的收尾操作。
finally:
    # 处理 if 所指定的操作或当前表达式的后续部分。
    if km.has_kernel:
        # 关闭本次测试启动的 Notebook 内核。
        km.shutdown_kernel(now=True)
    # 清理内核连接等临时资源。
    km.cleanup_resources()
# 保存执行后的 Notebook 文件。
nbformat.write(nb, out / 'executed.ipynb')
# 计算本行表达式并设置 result，供后续步骤使用。
result = {'status': 'passed', 'python': sys.executable, 'xgboost_accuracy': xacc,
          # 提供当前表达式所需的文本、字段名称或列表元素。
          'lightgbm_accuracy': lacc, 'causal_ate': ate,
          # 提供当前表达式所需的文本、字段名称或列表元素。
          'checks': ['xgboost-cpu', 'lightgbm-cpu', 'econml', 'pandas-calamine',
                     # 提供当前表达式所需的文本、字段名称或列表元素。
                     'polars-fastexcel', 'win32com-import', 'jupyter-kernel-execution']}
# 将文本写入目标文件；将结果序列化为 JSON 文本。
(out / 'models-result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
# 输出本行的状态信息或计算结果。
print(json.dumps(result))
