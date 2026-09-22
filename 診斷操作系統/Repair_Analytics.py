# 原文块第 1 行：声明模块的用途说明字符串，保留其原文内容。
# 原文块第 3 行：处理 Default: 所指定的操作或当前表达式的后续部分。
# 原文块第 4 行：处理 Snapshots 所指定的操作或当前表达式的后续部分。
# 原文块第 5 行：声明模块的用途说明字符串，保留其原文内容。
"""Add Excel/Windows interoperability to existing venvs without upgrading packages.

Default: resolve only. --apply installs after ALL environments resolve successfully.
Snapshots and command logs are stored locally; no global settings are changed.
"""
# 导入 argparse，供后续代码调用。
import argparse
# 导入 datetime，供后续代码调用。
import datetime
# 导入 json，供后续代码调用。
import json
# 导入 pathlib 中的 Path，供后续代码调用。
from pathlib import Path
# 导入 shutil，供后续代码调用。
import shutil
# 导入 subprocess，供后续代码调用。
import subprocess

# 创建命令行参数解析器，并保存到 p。
p = argparse.ArgumentParser(description=__doc__)
# 声明一个命令行参数及其约束。
p.add_argument('--apply', action='store_true')
# 声明一个命令行参数及其约束。
p.add_argument('--python', action='append', required=True)
# 声明一个命令行参数及其约束。
p.add_argument('--output', required=True)
# 解析命令行传入的参数，并保存到 a。
a = p.parse_args()
# 计算本行表达式并设置 out，供后续步骤使用。
out = Path(a.output).resolve() / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
# 创建输出目录。
out.mkdir(parents=True, exist_ok=False)
# 计算本行表达式并设置 uv，供后续步骤使用。
uv = shutil.which('uv')
# 处理 if 所指定的操作或当前表达式的后续部分。
if not uv:
    # 报告本行指定的错误并中止当前执行路径。
    raise SystemExit('uv not found')
# 构造或计算 extras，保存本行指定的集合或索引结果。
extras = ['openpyxl', 'xlsxwriter', 'python-calamine', 'fastexcel', 'pywin32']
# 构造或计算 plans，保存本行指定的集合或索引结果。
plans = []

# 定义 run，封装此函数内的操作。
def run(args, log):
    # 运行子命令并收集标准输出和错误，并保存到 r。
    r = subprocess.run(args, capture_output=True, text=True, encoding='utf-8',
                       # 补充当前函数调用的命名参数。
                       errors='replace', timeout=600)
    # 将文本写入目标文件。
    (out / log).write_text(r.stdout + r.stderr, encoding='utf-8')
    # 输出本行的状态信息或计算结果。
    print(r.stderr if 'freeze' in args else r.stdout + r.stderr, flush=True)
    # 检查子命令退出码并在失败时抛出异常。
    r.check_returncode()
    # 返回本行结果并结束当前函数。
    return r.stdout

# 按本行的迭代范围或条件重复执行循环体。
for i, python in enumerate(a.python):
    # 计算本行表达式并设置 python，供后续步骤使用。
    python = str(Path(python).resolve())
    # 调用 run，使用本行列出的输入完成对应操作。
    run([python, '-I', '-c',
         # 提供当前表达式所需的文本、字段名称或列表元素。
         'import sys; assert sys.prefix != sys.base_prefix, "Requires a venv"'], f'{i}-venv.log')
    # 准备或执行 Python 套件管理操作，并保存到 before。
    before = run([uv, 'pip', 'freeze', '--python', python], f'{i}-before.log')
    # 计算本行表达式并设置 constraints，供后续步骤使用。
    constraints = out / f'{i}-before.txt'
    # 将文本写入目标文件。
    constraints.write_text(before, encoding='utf-8')
    # Existing exact versions constrain all dependencies; resolution cannot upgrade them.
    # 准备或执行 Python 套件管理操作，并保存到 args。
    args = [uv, 'pip', 'install', '--python', python, '--index-url',
            # 提供当前表达式所需的文本、字段名称或列表元素。
            'https://pypi.org/simple', '--only-binary', ':all:', '--constraint',
            # 调用 str，使用本行列出的输入完成对应操作。
            str(constraints), *extras]
    # 调用 run，使用本行列出的输入完成对应操作。
    run([*args, '--dry-run'], f'{i}-plan.log')
    # 调用 plans.append，使用本行列出的输入完成对应操作。
    plans.append((i, python, args))

# 计算本行表达式并设置 status，供后续步骤使用。
status = {'started': datetime.datetime.now().isoformat(), 'extras': extras,
          # 提供当前表达式所需的文本、字段名称或列表元素。
          'mode': 'apply' if a.apply else 'plan', 'environments': []}
# 开始受异常处理保护的操作。
try:
    # 按本行的迭代范围或条件重复执行循环体。
    for i, python, args in plans:
        # 计算本行表达式并设置 row，供后续步骤使用。
        row = {'python': python, 'status': 'resolved'}
        # 处理 status['environments'].append(row) 所指定的操作或当前表达式的后续部分。
        status['environments'].append(row)
        # 处理 if 所指定的操作或当前表达式的后续部分。
        if a.apply:
            # 构造或计算 row['status']，保存本行指定的集合或索引结果。
            row['status'] = 'installing'
            # 调用 run，使用本行列出的输入完成对应操作。
            run(args, f'{i}-install.log')
            # 准备或执行 Python 套件管理操作。
            run([uv, 'pip', 'check', '--python', python], f'{i}-check.log')
            # 准备或执行 Python 套件管理操作，并保存到 after。
            after = run([uv, 'pip', 'freeze', '--python', python], f'{i}-after.log')
            # 将文本写入目标文件。
            (out / f'{i}-after.txt').write_text(after, encoding='utf-8')
            # 构造或计算 row['status']，保存本行指定的集合或索引结果。
            row['status'] = 'installed-dependencies-checked'
# 无论是否发生异常，都执行此处的收尾操作。
finally:
    # 将文本写入目标文件；将结果序列化为 JSON 文本。
    (out / 'status.json').write_text(json.dumps(status, indent=2), encoding='utf-8')
