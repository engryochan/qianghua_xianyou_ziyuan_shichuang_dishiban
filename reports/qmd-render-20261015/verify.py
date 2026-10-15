"""Check source fence balance and rendered HTML; generate a navigable result index."""
from pathlib import Path
from html import escape
from html.parser import HTMLParser
import json
import hashlib
import re
from urllib.parse import quote, unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
DEST = Path(__file__).resolve().parent

class Document(HTMLParser):
    def __init__(self):
        super().__init__()
        self.headings = self.code_blocks = self.math = 0
        self.ids = set()
        self.links = []
        self.resources = []
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in ('h1', 'h2', 'h3', 'h4', 'h5', 'h6'): self.headings += 1
        if tag == 'pre': self.code_blocks += 1
        if 'math' in (a.get('class') or '').split(): self.math += 1
        if a.get('id'): self.ids.add(a['id'])
        if tag == 'a' and a.get('href'): self.links.append(a['href'])
        if tag in ('img', 'script') and a.get('src'): self.resources.append(a['src'])
        if tag == 'link' and a.get('rel') == 'stylesheet': self.resources.append(a.get('href', ''))

rows = json.loads((DEST/'final-results.json').read_text(encoding='utf-8'))
assert len(rows) == len(list(ROOT.rglob('*.qmd'))), 'Incomplete render manifest'
for row in rows:
    path = ROOT / row['file']
    text = path.read_text(encoding='utf-8-sig')
    fence = None
    for n, line in enumerate(text.splitlines(), 1):
        match = re.match(r'^ {0,3}(`{3,}|~{3,})(.*)$', line)
        if not match: continue
        marks, info = match.groups()
        if fence is None: fence = (marks[0], len(marks), n)
        elif marks[0] == fence[0] and len(marks) >= fence[1] and not info.strip(): fence = None
    row['unclosed_fence'] = fence
    row['unresolved_chatgpt_citations'] = len(re.findall(r':chatgpt-content-reference\{[^}]*\}|(?:cite|filecite)[^]*', text))
    html = ROOT / row['html']
    row['output_bytes'] = html.stat().st_size if html.exists() else 0
    row['source_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    row['output_sha256'] = hashlib.sha256(html.read_bytes()).hexdigest() if html.exists() else None
    row['output_is_current'] = html.exists() and html.stat().st_mtime >= path.stat().st_mtime
    doc = Document()
    rendered = html.read_text(encoding='utf-8') if html.exists() else ''
    doc.feed(rendered)
    row.update(headings=doc.headings, code_blocks=doc.code_blocks, math_elements=doc.math)
    row['missing_local_resources'] = []
    for target in doc.resources:
        url = urlsplit(target)
        if url.scheme or url.netloc or not url.path: continue
        if not (html.parent / unquote(url.path)).exists(): row['missing_local_resources'].append(target)
    row['missing_fragment_links'] = sorted(set(target for target in doc.links
        if target.startswith('#') and len(target) > 1 and unquote(target[1:]) not in doc.ids))
    log = (DEST / row['log']).read_text(encoding='utf-8', errors='replace')
    row['warnings'] = [line for line in log.splitlines() if '[WARNING]' in line or 'WARNING:' in line]
    row['verified'] = (row['exit_code'] == 0 and row['output_bytes'] > 1000 and
        '<html' in rendered and '</html>' in rendered and doc.headings > 0 and
        fence is None and row['output_is_current'] and not row['missing_local_resources'])
(DEST/'verification.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding='utf-8')
links = '\n'.join('<tr><td><a href="' + quote('../../' + row['html'], safe='/') + '">' +
    escape(row['file']) + '</a></td><td>' + ('通過' if row['verified'] else '失敗') +
    '</td><td>' + str(row['output_bytes']) + '</td></tr>' for row in rows)
(DEST/'index.html').write_text('''<!doctype html><html lang="zh-Hant"><meta charset="utf-8">
<title>QMD 渲染驗收 · 2026-10-15</title><style>body{font:16px system-ui;margin:2rem;line-height:1.6}
table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:.4rem .8rem}</style>
<h1>QMD 渲染驗收 · 2026-10-15</h1><p>HTML 格式；R／Python 範本實際執行。
本次驗證文件結構與渲染結果，並非對文內所有歷史敘述、外部來源或專業主張逐條背書。</p>
<table><tr><th>文件（點擊開啟）</th><th>驗收</th><th>HTML 位元組</th></tr>''' + links + '</table></html>', encoding='utf-8')
print(f"Verified {sum(row['verified'] for row in rows)}/{len(rows)} documents")
for row in rows:
    if not row['verified']: print('FAILED:', row['file'])
raise SystemExit(0 if all(row['verified'] for row in rows) else 1)
