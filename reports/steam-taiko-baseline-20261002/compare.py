from pathlib import Path  # 限定对比目录为本轮报告。
import csv, json  # 只使用标准库读取已保存的状态。
ROOT = Path(__file__).resolve().parent  # 获取快照根目录。
dirs = sorted(p for p in ROOT.iterdir() if p.is_dir() and (p / 'all-files.csv').exists())  # 选择本工具产生的快照。
if len(dirs) < 2: raise SystemExit('Need at least two snapshots')  # 没有对照时不制造结论。
before = ROOT / '20261002-151409'; after = dirs[-1]  # 以完整哈希基线和最新快照对比。
if before == after: raise SystemExit('Run snapshot.py after your next game session before comparison')  # 防止把自身对比误报为没有变化。
def read(folder):  # 用完整路径作为条目主键。
    with (folder / 'all-files.csv').open(encoding='utf-8-sig', newline='') as handle: return {r['path']: r for r in csv.DictReader(handle)}  # 读取文件和目录元数据。
old, new = read(before), read(after)  # 加载两次只读快照。
added, removed = sorted(new.keys() - old.keys()), sorted(old.keys() - new.keys())  # 识别新增与消失条目。
changed = []  # 初始化变化列表。
for path in sorted(old.keys() & new.keys()):  # 逐项核对共同条目。
    keys = ['bytes', 'mtime_ns', 'attributes']  # 默认比较长度、时间与属性。
    if old[path]['hash_state'] == new[path]['hash_state'] == 'OK': keys.append('sha256')  # 仅比较两次稳定校验值。
    differences = {key: {'before': old[path][key], 'after': new[path][key]} for key in keys if old[path][key] != new[path][key]}  # 保存具体字段差异。
    if differences: changed.append({'path': path, 'differences': differences})  # 不从变化本身推断原因。
result = {'before': str(before), 'after': str(after), 'added': added, 'removed': removed, 'changed': changed, 'limits': 'Observed differences only; not proof the game caused changes. Steam logs/cache may change continuously.'}  # 标注因果局限。
(after / 'diff.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')  # 保留机器可读对照。
(after / '启动后差异报告.txt').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8-sig')  # 保存用户可读文本。
print(json.dumps({'added': len(added), 'removed': len(removed), 'changed': len(changed), 'report': str(after / '启动后差异报告.txt')}, ensure_ascii=True))  # 输出简洁回执。
