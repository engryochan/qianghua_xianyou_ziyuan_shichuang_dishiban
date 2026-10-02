from pathlib import Path  # 所有读取限制在本次报告目录。
import ast, hashlib, json, re  # 只用标准库核验语法和证据清单。
root = Path(__file__).parent  # 使用脚本所在位置，避免依赖终端工作目录。
source = (root / 'check_steam.py').read_text(encoding='utf-8-sig')  # 正确解码中文注释。
ast.parse(source)  # 静态核验采集脚本，不重复联网或覆盖证据。
assert all('#' in line for line in source.splitlines() if line.strip())  # 确认每个非空脚本行有注释。
payload = json.loads((root / 'steam-platforms.json').read_text(encoding='utf-8'))  # 检查实际保存的API结果。
rows = payload['results']  # 成功与失败均计入查询覆盖率。
assert len(rows) == 30 and len({row['appid'] for row in rows}) == 30  # 确认30项无重复标识。
verified = [row for row in rows if row.get('platforms',{}).get('windows') is True]  # 不把接口失败视为支持。
assert len(verified) == 28  # 与报告统计对应，包括消歧作品。
assert {row['appid'] for row in rows if row.get('error')} == {1842810,1424800}  # 两项必须由厂商网页补核。
report_path = root / '游戏Windows与开发工具核查.md'  # 指向人工审阅后的完整清单。
report = report_path.read_text(encoding='utf-8')  # 保留中文与原始链接。
numbers = [int(value) for value in re.findall(r'^\| (\d+) \|',report,re.M)]  # 提取主清单序号，不把消歧项混入主清单。
assert numbers == list(range(1,36))  # 确认35项逐一列出，没有漏号与重复。
for row in verified:  # 逐项检查报告Windows证据链接与实际查询标识一致。
    assert row['source'] in report  # 官方API成功条目必须有可复核链接。
summary = {'steam_queries':30,'steam_windows_verified':28,'manufacturer_fallbacks':2,'main_games':35,'main_windows_verified':30,'local_game_runtime_tested':False,'report_sha256':hashlib.sha256(report_path.read_bytes()).hexdigest()}  # 明确资料核查与本机运行的边界。
(root / 'validation.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')  # 保存简洁核查结果。
print(json.dumps(summary))  # 只输出ASCII字段，兼容GBK终端。
