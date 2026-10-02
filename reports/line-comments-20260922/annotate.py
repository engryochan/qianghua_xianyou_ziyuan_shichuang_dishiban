import ast
import io
import json
import re
import shutil
import tokenize
from pathlib import Path

root = Path.cwd()
audit = root / 'reports/line-comments-20260922'
source = root / '診斷操作系統'
metadata = {x['Name']: x for x in json.loads((audit / 'powershell-before.json').read_text(encoding='utf-8-sig'))}
backup = audit / 'before'
backup.mkdir(exist_ok=True)

operations = [
    ('Get-CimInstance', '查询 Windows 管理接口中的设备或系统信息'),
    ('Get-WmiObject', '通过 WMI 查询系统配置'),
    ('Get-PnpDevice', '读取即插即用设备及其当前状态'),
    ('Get-AuthenticodeSignature', '读取文件签名及其验证状态'),
    ('Get-FileHash', '计算文件哈希以核对内容是否变化'),
    ('Get-ItemProperty', '读取注册表或对象的属性'),
    ('Get-ChildItem', '枚举指定位置的文件、目录或注册表项'),
    ('Get-Command', '查找当前环境可用的命令及其位置'),
    ('Get-Process', '读取正在运行的进程信息'),
    ('Get-Service', '读取服务的运行状态'),
    ('Get-ComputerRestorePoint', '读取现有系统还原点'),
    ('Checkpoint-Computer', '请求建立系统还原点'),
    ('Enable-ComputerRestore', '启用指定磁盘的系统还原保护'),
    ('Get-ExecutionPolicy', '读取脚本执行策略'),
    ('Get-Content', '读取文件内容供后续处理'),
    ('Get-PSDrive', '读取磁盘或 PowerShell 驱动器的容量信息'),
    ('Get-Net', '读取网络相关配置'),
    ('Get-Date', '生成当前时间或格式化时间戳'),
    ('Test-Path', '检查目标路径是否存在'),
    ('Resolve-Path', '解析已存在路径的实际位置'),
    ('Join-Path', '组合父目录与子路径'),
    ('Split-Path', '提取路径中的指定部分'),
    ('New-ItemProperty', '创建或写入指定注册表属性'),
    ('Set-ItemProperty', '修改指定注册表或对象属性'),
    ('New-Item', '创建指定目录、文件或配置项'),
    ('Copy-Item', '复制文件或目录到目标位置'),
    ('Move-Item', '移动或替换指定文件'),
    ('Remove-Item', '删除指定路径下的项目'),
    ('Set-Content', '将内容写入目标文件'),
    ('Add-Content', '向目标文件追加内容'),
    ('Export-Csv', '将记录导出为 CSV 文件'),
    ('Import-Csv', '读取 CSV 记录'),
    ('ConvertTo-Json', '把对象序列化为 JSON'),
    ('ConvertFrom-Json', '把 JSON 文本解析为对象'),
    ('Select-Object', '选取记录中的指定字段或条目'),
    ('Where-Object', '按条件筛选输入记录'),
    ('Sort-Object', '按指定属性排序输入记录'),
    ('ForEach-Object', '逐项处理管道传入的记录'),
    ('Format-Table', '把结果排版成表格'),
    ('Out-Null', '丢弃不需要显示的输出'),
    ('Out-String', '把结果转换为文本'),
    ('Start-Process', '使用指定程序和参数启动子进程'),
    ('Stop-Process', '终止指定进程'),
    ('Start-Sleep', '等待指定时间后继续'),
    ('Start-Transcript', '开始记录 PowerShell 会话输出'),
    ('Stop-Transcript', '结束 PowerShell 会话记录'),
    ('Write-Warning', '显示警告信息'),
    ('Write-Error', '输出错误记录'),
    ('Write-Host', '向终端显示提示或结果'),
    ('Write-Output', '把结果写入输出管道'),
    ('Import-Module', '加载所需 PowerShell 模块'),
    ('Add-Type', '加载程序集或编译内嵌类型定义'),
    ('New-Object', '创建指定类型的对象'),
    ('ShouldProcess', '检查当前操作是否应当执行，支持预演或确认'),
    ('SetEnvironmentVariable', '写入指定作用域的环境变量'),
    ('GetEnvironmentVariable', '读取指定作用域的环境变量'),
    ('IsInRole', '检查当前身份是否具有指定权限角色'),
    ('pnputil', '调用 Windows 即插即用驱动管理工具'),
    ('powercfg', '调用 Windows 电源配置工具'),
    ('winget', '调用 WinGet 执行本行指定的软件管理操作'),
    ('pip', '准备或执行 Python 套件管理操作'),
    ('WriteAllText', '将文本写入指定文件'),
    ('ReadAllText', '读取整个文本文件'),
    ('AppendLine', '向报告缓冲区追加一行文本'),
    ('WriteLine', '输出一行文本'),
    ('WaitForExit', '等待子进程结束或到达指定时限'),
    ('HasExited', '检查子进程是否已经退出'),
    ('Dispose', '释放对象持有的系统资源'),
    ('Kill(', '终止当前跟踪的子进程'),
    ('Save-State', '保存当前执行状态到日志文件'),
    ('Save-Journal', '保存可用于审查和恢复的变更记录'),
    ('Add-Finding', '追加一项诊断发现'),
    ('Add-Action', '记录建议执行的后续操作'),
    ('Add-Status', '记录探测步骤的状态及耗时'),
    ('Save-Data', '将探测结果保存到报告目录'),
    ('Invoke-Probe', '运行有时间限制的诊断探测'),
    ('Invoke-Tool', '运行指定工具并收集输出'),
    ('installed.packages', '读取 R 套件安装清单'),
    ('install.packages', '安装本行指定的 R 套件'),
    ('write.csv', '将表格写入 CSV 文件'),
    ('writeLines', '将文本逐行写入目标文件'),
    ('readLines', '读取目标文件的各行文本'),
    ('Sys.setenv', '设置当前 R 进程的环境变量'),
    ('Sys.getenv', '读取 R 进程的环境变量'),
    ('setDTthreads', '限制 data.table 使用的线程数量'),
    ('dbConnect', '建立数据库连接'),
    ('dbDisconnect', '关闭数据库连接并释放资源'),
    ('dbGetQuery', '执行 SQL 查询并取得结果'),
    ('dbExecute', '执行指定 SQL 语句'),
    ('xgb.train', '训练 XGBoost 模型'),
    ('xgb.DMatrix', '构造 XGBoost 使用的数据矩阵'),
    ('set.seed', '固定 R 随机种子以便重复验证'),
    ('library(', '加载指定 R 套件'),
    ('requireNamespace', '检查指定 R 套件是否可用'),
    ('jsonlite::', '使用 jsonlite 转换或保存 JSON 结果'),
    ('reticulate::import', '通过 reticulate 导入 Python 模块'),
    ('subprocess.run', '运行子命令并收集标准输出和错误'),
    ('check_returncode', '检查子命令退出码并在失败时抛出异常'),
    ('argparse.ArgumentParser', '创建命令行参数解析器'),
    ('add_argument', '声明一个命令行参数及其约束'),
    ('parse_args', '解析命令行传入的参数'),
    ('write_text', '将文本写入目标文件'),
    ('read_text', '读取目标文本文件'),
    ('mkdir', '创建输出目录'),
    ('read_parquet', '读取 Parquet 数据'),
    ('write_parquet', '将数据写入 Parquet 文件'),
    ('to_parquet', '将表格保存为 Parquet 文件'),
    ('scan_parquet', '建立 Parquet 的延迟读取计划'),
    ('read_excel', '读取 Excel 工作表'),
    ('to_excel', '将表格写入 Excel 文件'),
    ('ExcelWriter', '创建指定引擎的 Excel 写入器'),
    ('duckdb.connect', '建立 DuckDB 数据库连接'),
    ('.execute(', '执行对象提供的命令或查询'),
    ('default_rng', '创建固定种子的随机数生成器'),
    ('KernelManager', '创建 Jupyter 内核管理器'),
    ('KernelSpec', '指定 Notebook 内核的解释器和启动参数'),
    ('NotebookClient', '执行 Notebook 并验证单元格结果'),
    ('shutdown_kernel', '关闭本次测试启动的 Notebook 内核'),
    ('cleanup_resources', '清理内核连接等临时资源'),
    ('nbformat.write', '保存执行后的 Notebook 文件'),
    ('.fit(', '使用给定数据拟合模型'),
    ('.predict(', '使用已拟合模型计算预测值'),
    ('json.dumps', '将结果序列化为 JSON 文本'),
    ('metadata.distributions', '枚举当前 Python 环境的套件元数据'),
    ('savefig', '将图形保存到文件'),
    ('write_html', '将交互图表保存为 HTML 文件'),
]

def explain(line):
    s = line.strip()
    exact = {
        '$session.ClientApplicationID=\'Local workstation verification\'': '为 Windows Update 会话设置可识别的客户端名称。',
        '$searcher=$session.CreateUpdateSearcher()': '从当前更新会话创建搜索器，沿用本机更新来源配置。',
        '$result=$searcher.Search("IsInstalled=0 and IsHidden=0")': '搜索尚未安装且未隐藏的适用更新，并保存结果。',
        '$out=[IO.Path]::GetFullPath($OutputDirectory)': '把报告输出目录转换为完整绝对路径。',
    }
    if s in exact:
        return exact[s]
    if s.startswith(('\"\"\"', "'''")):
        return '声明模块的用途说明字符串，保留其原文内容。'
    if s.startswith(('import ', 'from ')):
        return '导入 ' + (s[7:] if s.startswith('import ') else s[5:].replace(' import ', ' 中的 ')) + '，供后续代码调用。'
    if re.match(r'^[A-Za-z_]\w*(?:,\s*[A-Za-z_]\w*)+\s*=', s):
        lhs, rhs = s.split('=', 1)
        if 'make_classification' in rhs:
            return '生成固定随机种子的分类样本，分别保存特征矩阵 X 与标签 y。'
        if 'train_test_split' in rhs:
            return '按固定随机种子划分训练集与测试集，分别保存特征和标签。'
        return '将右侧返回的多项结果依次分配给 ' + lhs.strip() + '。'
    if s.startswith('using '):
        return '在内嵌 C# 代码中引入 ' + s[6:].rstrip(';') + ' 命名空间。'
    if s.startswith('public class '):
        return '声明供 PowerShell 调用的 C# 辅助类型。'
    if '[DllImport(' in s:
        return '声明 Windows 原生接口的动态库导入规则。'
    if 'extern ' in s:
        return '声明对应 Windows 原生函数的参数和返回类型。'
    if s.startswith('[pscustomobject]'):
        return '把本行列出的字段组成结构化记录' + ('，并按后续管道保存或输出。' if '|' in s else '。')
    if s.startswith('$null=') or s.startswith('$null ='):
        stripped = re.sub(r'^\$null\s*=\s*', '', s)
        return explain(stripped).rstrip('。') + '；将不需要的返回值丢弃。'
    if 'XGBClassifier(' in s:
        return '配置 CPU 直方图算法、树数量与线程数，准备 XGBoost 分类验收。'
    if 'LGBMClassifier(' in s:
        return '配置 LightGBM 分类器的树数量与 CPU 线程数。'
    if re.match(r'^(random_state|n_jobs|errors|display_name|encoding|indent|capture_output|text|timeout|engine|index|row.names)\s*=', s):
        return '补充当前函数调用的命名参数' + ('，随后拟合模型并计算测试分数。' if '.fit(' in s else '。')
    if s.startswith('#Requires'):
        return '声明脚本运行所需的 PowerShell 版本或权限。'
    if re.fullmatch(r'[\]\)};,\s]+', s):
        return '结束此处的代码块、参数列表或集合定义。'
    if re.match(r'^\}\s*(catch|finally|else|elseif)', s):
        return '结束上一代码块并进入' + ('异常处理。' if 'catch' in s else '必定执行的资源清理。' if 'finally' in s else '另一条件分支。')
    if re.match(r'^(function\s+|def\s+)', s):
        name = re.search(r'(?:function|def)\s+([^\s(]+)', s).group(1)
        return f'定义 {name}，封装此函数内的操作。'
    if re.match(r'^(from\s+|import\s+)', s):
        return '导入本行列出的模块或对象，供后续代码调用。'
    if s.startswith('param('):
        return '声明脚本或函数接受的参数及默认值。'
    if s.startswith('[CmdletBinding'):
        return '启用 PowerShell 高级脚本参数绑定及所列功能。'
    if re.match(r'^\[(?:switch|string|int|bool|Validate|Parameter|Allow)', s):
        names = re.findall(r'\]\s*(\$[A-Za-z_]\w*)', s)
        return '声明参数' + (' ' + '、'.join(names) if names else '') + '的类型、默认值或校验规则。'
    if re.match(r'^(if|elseif|elif)\s*[(:]', s):
        return '检查本行条件；满足时执行对应分支。'
    if re.match(r'^(for|foreach|while)\s*[ (]', s):
        return '按本行的迭代范围或条件重复执行循环体。'
    if re.match(r'^(try|catch|except|finally|else)\b', s):
        return {'try': '开始受异常处理保护的操作。', 'catch': '捕获并处理前述操作抛出的异常。', 'except': '捕获并处理前述操作抛出的异常。', 'finally': '无论是否发生异常，都执行此处的收尾操作。', 'else': '当前述条件不成立时执行此分支。'}[re.match(r'\w+', s).group()]
    if re.match(r'^(assert\b|stopifnot\()', s):
        return '断言本行条件成立；不满足时中止验收并报错。'
    if re.match(r'^(throw\b|raise\b|stop\()', s):
        return '报告本行指定的错误并中止当前执行路径。'
    if re.match(r'^(return|exit|break|continue)\b', s):
        return {'return':'返回本行结果并结束当前函数。','exit':'以指定状态结束当前脚本或进程。','break':'结束当前循环或选择分支。','continue':'跳过本次循环余下操作。'}[re.match(r'\w+', s).group()]
    if s.startswith('with '):
        return '进入上下文管理器，确保结束时自动释放相应资源。'
    if s.startswith('switch '):
        return '根据指定值选择并执行对应分支。'
    if re.match(r'^(cat|print)\(', s):
        return '输出本行的状态信息或计算结果。'
    target = re.match(r'^(\$[\w:.]+(?:\[[^\]]+\])?|[A-Za-z_][\w.$]*(?:\[[^\]]+\])?)\s*(?:<-|=(?!=)|\+=)', s)
    notes = []
    for pattern, note in operations:
        if pattern.lower() in s.lower() and note not in notes:
            notes.append(note)
    if notes:
        return '；'.join(notes[:3]) + (f'，并保存到 {target.group(1)}。' if target else '。')
    if target:
        name = target.group(1)
        if 'ErrorActionPreference' in name:
            return '设置本脚本遇到 PowerShell 错误时的处理方式。'
        if 'OutputEncoding' in name:
            return '设置终端输出的文字编码。'
        if 'ExitCode' in s or 'LASTEXITCODE' in s:
            return f'将上一操作的退出状态记录到 {name}。'
        if re.search(r'@\(|\[|list\(|c\(', s):
            return f'构造或计算 {name}，保存本行指定的集合或索引结果。'
        return f'计算本行表达式并设置 {name}，供后续步骤使用。'
    if s.startswith('& '):
        return '调用本行指定的程序或脚本，并传入列出的参数。'
    if re.match(r'^[\w.$:]+\(', s):
        name = s.split('(', 1)[0]
        return f'调用 {name}，使用本行列出的输入完成对应操作。'
    if re.match(r'^\$[\w.]+\(', s):
        return f'调用 {s.split("(",1)[0]}，处理当前对象或集合。'
    if re.match(r'^["\']', s):
        return '提供当前表达式所需的文本、字段名称或列表元素。'
    if re.match(r'^[\w.-]+\s*=', s):
        return '为当前对象或函数调用设置本行命名的字段或参数。'
    if s.startswith('|'):
        return '将上一阶段的结果传入后续管道操作。'
    if s.startswith(('-', '[', '(', ')', '.', '}')):
        return '继续当前表达式，补充参数、类型转换或结果处理。'
    name = s.split()[0]
    return f'处理 {name} 所指定的操作或当前表达式的后续部分。'

manifest = []
for path in sorted(source.iterdir()):
    if path.suffix.lower() not in ('.ps1', '.py', '.r'):
        continue
    if not (backup / path.name).exists():
        shutil.copy2(path, backup / path.name)
    raw = (backup / path.name).read_bytes()
    text = raw.decode('utf-8-sig')
    lines = text.splitlines(keepends=True)
    comment_lines, inline, protected = set(), set(), {}
    if path.suffix.lower() == '.ps1':
        for token in metadata[path.name]['Tokens']:
            start, end = token['Start'] - 1, token['End'] - 1
            if token['Kind'] == 'Comment':
                for k in range(start, end + 1):
                    if k == start and lines[k][:token['Column']-1].strip():
                        inline.add(k)
                    else:
                        comment_lines.add(k)
            elif end > start and token['Kind'] not in ('NewLine', 'LineContinuation', 'EndOfInput'):
                for k in range(start, end + 1):
                    protected[k] = min(start, protected.get(k, start))
    elif path.suffix.lower() == '.py':
        for token in tokenize.generate_tokens(io.StringIO(text).readline):
            if token.type == tokenize.COMMENT:
                (inline if lines[token.start[0]-1][:token.start[1]].strip() else comment_lines).add(token.start[0]-1)
            if token.type == tokenize.STRING and token.end[0] > token.start[0]:
                for k in range(token.start[0]-1, token.end[0]):
                    protected[k] = token.start[0]-1
    else:
        quote = None
        string_start = None
        for k, line in enumerate(lines):
            escaped = False
            if quote:
                protected[k] = string_start
            for col, char in enumerate(line):
                if escaped:
                    escaped = False
                    continue
                if char == '\\' and quote:
                    escaped = True
                    continue
                if quote:
                    if char == quote:
                        quote = None
                elif char in ('"', "'", '`'):
                    quote, string_start = char, k
                elif char == '#':
                    (inline if line[:col].strip() else comment_lines).add(k)
                    break
            if quote:
                protected[k] = string_start
    # Keep explicit continuation chains intact, placing their notes before the chain.
    marker = '`' if path.suffix.lower() == '.ps1' else '\\'
    for k in range(1, len(lines)):
        if lines[k-1].rstrip().endswith(marker):
            start = protected.get(k-1, k-1)
            protected[k-1] = start
            protected[k] = start
    notes = {}
    coverage = []
    for k, line in enumerate(lines):
        s = line.strip()
        if not s or k in comment_lines or s.startswith('#'):
            continue
        if k in inline and k not in protected:
            coverage.append({'original_line': k+1, 'kind': 'existing-inline'})
            continue
        anchor = protected.get(k, k)
        while anchor in protected and protected[anchor] < anchor:
            anchor = protected[anchor]
        explanation = explain(line)
        prefix = f'原文块第 {k-anchor+1} 行：' if k in protected else ''
        notes.setdefault(anchor, []).append(prefix + explanation)
        coverage.append({'original_line': k+1, 'kind': 'adjacent-block' if k in protected else 'preceding-comment', 'anchor_original_line': anchor+1})
    output = []
    for k, line in enumerate(lines):
        indentation = re.match(r'\s*', line).group().rstrip('\r\n')
        newline = '\r\n' if line.endswith('\r\n') else '\n'
        for note in notes.get(k, []):
            output.append(indentation + '# ' + note + newline)
        output.append(line)
    annotated = ''.join(output)
    if path.suffix.lower() == '.py':
        assert ast.dump(ast.parse(text)) == ast.dump(ast.parse(annotated)), path.name
    # PowerShell 5.1 needs BOM to decode added Chinese comments consistently.
    encoding = 'utf-8-sig' if path.suffix.lower() == '.ps1' or raw.startswith(b'\xef\xbb\xbf') else 'utf-8'
    path.write_bytes(annotated.encode(encoding))
    manifest.append({'name':path.name, 'original_lines':len(lines), 'new_comments':sum(map(len,notes.values())), 'covered_code_lines':len(coverage), 'coverage':coverage})
(audit / 'coverage.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps([dict(name=x['name'], added=x['new_comments'], covered=x['covered_code_lines']) for x in manifest], ensure_ascii=False))
