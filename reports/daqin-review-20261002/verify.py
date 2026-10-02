from pathlib import Path  # 使用标准库路径，不安装依赖。
import hashlib, json, re, sqlite3, statistics, time, sys, tokenize  # 提供指纹、审计、事务与计时。
root = Path(__file__).resolve().parent  # 将所有产物限制在审计目录。
source = root.parent.parent / '_大秦赋算筹_v1_3_0.qmd'  # 定位用户指定文档。
baseline = (root / 'baseline.qmd').read_bytes()  # 读取修改前字节基线。
current = source.read_bytes()  # 读取修改后字节，不运行文档代码。
text = current.decode('utf-8')  # 严格校验 UTF-8 编码。
lines = text.splitlines()  # 全文逐行结构扫描。
fence = None  # 记录围栏状态，以排除代码中的标题与引用。
headings, references, urls, inherited = [], [], set(), []  # 登记结构、引用与待核声明。
code_without_comments = []  # 记录旧代码的注释缺口，不自动执行或改写。
for number, line in enumerate(lines, 1):  # 扫描全文全部行。
    marker = re.match(r'^\s*(`{3,}|~{3,})(.*)$', line)  # 识别 Markdown 围栏。
    if marker:  # 处理开始和结束围栏。
        if fence is None:  # 开始新的围栏。
            fence = (marker[1][0], len(marker[1]), marker[2].strip(), number)  # 保存语言与起点。
        elif marker[1][0] == fence[0] and len(marker[1]) >= fence[1] and not marker[2].strip():  # 只允许合法闭合。
            fence = None  # 结束围栏。
        continue  # 围栏行不参与标题判断。
    if fence is not None:  # 仅检查明确的 Python/PowerShell 示例。
        if re.search(r'python|powershell|\bps1\b', fence[2], re.I) and line.strip() and '#' not in line:  # 注释检查仅是启发式。
            code_without_comments.append(number)  # 保留缺口位置，字符串与多行代码仍需人工判定。
        continue  # 不把代码中的字样当正文主张。
    if re.match(r'^#{1,6}\s', line):  # 识别正文标题。
        headings.append({'line': number, 'title': line})  # 保存章节索引供人工复核。
    references.extend({'line': number, 'section': match} for match in re.findall(r'§(\d+(?:\.\d+)*)', line))  # 收集数字章节引用。
    urls.update(re.findall(r'https?://[^\s<>\]\)]+', line))  # 清点外链，不声称已核验全部网址。
    if re.search(r'PASS|CLOSED|M5|天下第一|最新|最强|已核|结案', line):  # 筛查高确定性与时间敏感声明。
        inherited.append({'line': number, 'excerpt': line[:320]})  # 继承状态仅为审阅候选。
sections = {match[1] for row in headings if (match := re.match(r'^#+\s+(\d+(?:\.\d+)*)(?:\s|\.)', row['title']))}  # 提取显式编号标题。
unresolved = [item for item in references if item['section'] not in sections]  # 非编号标题也可能解释引用，故只列候选。
connection = sqlite3.connect(':memory:')  # 仅使用内存数据库，不接触现实个人或公司数据。
connection.execute('CREATE TABLE career(person INTEGER PRIMARY KEY, skill INTEGER, target INTEGER, stock INTEGER, cash INTEGER, evidence TEXT)')  # 建立合成人物与整数交易状态。
rows = [(i, i % 11, 8, 10, 1000, 'SYNTHETIC') for i in range(10000)]  # 生成固定的万人人工样本。
connection.executemany('INSERT INTO career VALUES(?,?,?,?,?,?)', rows)  # 参数化写入，避免把数据当 SQL。
connection.commit()  # 固定基线事务。
checks = {}  # 保存可核对的验收结果。
checks['ten_thousand_rows'] = connection.execute('SELECT COUNT(*) FROM career').fetchone()[0] == 10000  # 验证完整导入。
before_gap = connection.execute('SELECT SUM(MAX(target-skill,0)) FROM career').fetchone()[0]  # 记录任务型技能差距，不计算人格排名。
connection.execute('UPDATE career SET skill=skill+1 WHERE skill<target')  # 模拟一轮学习，规则并非真实学习效果预测。
after_gap = connection.execute('SELECT SUM(MAX(target-skill,0)) FROM career').fetchone()[0]  # 实际查询学习后状态。
checks['learning_transition'] = after_gap < before_gap  # 验证状态变化符合规则。
connection.commit()  # 将学习状态保存为下一项测试基线。
before_trade = connection.execute('SELECT stock,cash FROM career WHERE person=0').fetchone()  # 记录模拟交易前状态。
connection.execute('SAVEPOINT trade')  # 创建明确的交易恢复点。
connection.execute('UPDATE career SET stock=stock-1,cash=cash+125 WHERE person=0')  # 模拟库存与整数金额的原子更新。
connection.execute('ROLLBACK TO trade')  # 注入失败场景并恢复交易。
connection.execute('RELEASE trade')  # 关闭恢复点。
checks['transaction_rollback'] = connection.execute('SELECT stock,cash FROM career WHERE person=0').fetchone() == before_trade  # 验证恢复后完全一致。
payload = "'); DROP TABLE career; --"  # 构造 SQL 注入文本，仅作为数据。
connection.execute('UPDATE career SET evidence=? WHERE person=?', (payload, 0))  # 使用参数化写入阻止代码解释。
checks['data_not_code'] = connection.execute('SELECT COUNT(*) FROM career').fetchone()[0] == 10000  # 检查恶意文本未删除表。
def permit(actor, subject, role):  # 原型只允许本人和持授权标记的审阅者。
    return actor == subject or role == 'authorized_reviewer'  # 范围授权模拟，不替代生产安全边界。
checks['cross_user_denied'] = not permit(1, 2, 'user')  # 验证普通用户不能跨用户访问。
checks['self_allowed'] = permit(1, 1, 'user')  # 验证本人访问未被破坏。
checks['unknown_role_denied'] = not permit(1, 2, 'administrator_from_external_text')  # 外部文本不授予权限。
checks['authorized_review_allowed'] = permit(1, 2, 'authorized_reviewer')  # 验证明确授权的测试路径。
duration = []  # 记录同一进程内查询用时样本。
for iteration in range(7):  # 多次测量，区分预热和正式样本。
    started = time.perf_counter()  # 使用单调高分辨计时器。
    measured = connection.execute('SELECT SUM(MAX(target-skill,0)) FROM career').fetchone()[0]  # 测量相同任务。
    duration.append((time.perf_counter()-started)*1000)  # 保存毫秒样本。
checks['repeatable_query'] = measured == after_gap  # 检查计时查询未改变结果。
checks['baseline_preserved'] = current.startswith(baseline)  # 验证旧文档逐字节保留。
checks['fences_balanced'] = fence is None  # 验证围栏闭合。
checks['utf8_lf_no_bom'] = not current.startswith(b'\xef\xbb\xbf') and b'\r\n' not in current and current.endswith(b'\n')  # 验证既有编码约定。
with tokenize.open(__file__) as script:  # 使用 Python 自身词法分析检查脚本注释。
    script_text = script.read()  # 读取本脚本，内容不含用户隐私。
comment_lines = {token.start[0] for token in tokenize.generate_tokens(iter(script_text.splitlines(keepends=True)).__next__) if token.type == tokenize.COMMENT}  # 识别真实注释而非字符串内井号。
checks['every_script_line_commented'] = all(index in comment_lines for index, line in enumerate(script_text.splitlines(), 1) if line.strip())  # 验证用户每行注释要求。
result = {'scope':'LOCAL_SYNTHETIC_ONLY', 'python':sys.version, 'baseline_sha256':hashlib.sha256(baseline).hexdigest(), 'current_sha256':hashlib.sha256(current).hexdigest(), 'bytes':len(current), 'lines':len(lines), 'headings':headings, 'unique_urls':sorted(urls), 'unresolved_reference_candidates':unresolved, 'inherited_claim_candidates':inherited, 'legacy_code_comment_candidates':code_without_comments, 'checks':checks, 'synthetic_before_gap':before_gap, 'synthetic_after_gap':after_gap, 'query_ms_after_warmup':duration[1:], 'query_median_ms':statistics.median(duration[1:])}  # 记录原始证据与边界。
(root / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')  # 保存审计结果至工作区。
print(json.dumps({key:result[key] for key in ('bytes','lines','checks','synthetic_before_gap','synthetic_after_gap','query_median_ms')}, ensure_ascii=False))  # 终端仅输出摘要。
connection.close()  # 释放内存数据库。
sys.exit(0 if all(checks.values()) else 1)  # 任何明确验收失败均返回非零。
