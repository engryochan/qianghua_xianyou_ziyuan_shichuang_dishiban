# Read the source snapshots and annotation manifest without importing project scripts.
import ast, difflib, json
# Use filesystem paths to compare the original and annotated text.
from pathlib import Path
# Resolve the current project and local validation folder.
root = Path.cwd(); audit = root / 'reports/line-comments-20260922'
# Load the list of all annotated files.
manifest = json.loads((audit / 'coverage.json').read_text(encoding='utf-8'))
# Collect one verification record per source file.
rows = []
# Compare every source file against its untouched local snapshot.
for item in manifest:
    # Read original and current source with BOM-aware UTF-8 decoding.
    before = (audit / 'before' / item['name']).read_text(encoding='utf-8-sig'); after = (root / '診斷操作系統' / item['name']).read_text(encoding='utf-8-sig')
    # Split into physical lines for an exact insertion-only comparison.
    a = before.splitlines(); b = after.splitlines()
    # Align the two line sequences without the frequent-line heuristic.
    matcher = difflib.SequenceMatcher(None, a, b, autojunk=False)
    # Require every changed span to contain only newly inserted comment lines.
    for tag, i, j, x, y in matcher.get_opcodes():
        # Existing source lines must remain intact and in the same order.
        assert tag == 'equal' or (tag == 'insert' and all(line.lstrip().startswith('#') for line in b[x:y])), (item['name'], tag, i)
    # Check Python syntax trees without importing or executing the scripts.
    if item['name'].endswith('.py'):
        # Ignore source offsets while requiring identical executable syntax trees.
        assert ast.dump(ast.parse(before)) == ast.dump(ast.parse(after)), item['name']
    # Retain a concise verification result for this file.
    rows.append({'name': item['name'], 'comment_insertions_only': True, 'new_comments': item['new_comments']})
# Persist the complete insertion-only verification evidence.
(audit / 'comment-only-validation.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding='utf-8')
# Report the checked file count and total added comments.
print(f'{len(rows)} files: comment insertions only; {sum(x["new_comments"] for x in rows)} comments. Python AST equality PASS.')
