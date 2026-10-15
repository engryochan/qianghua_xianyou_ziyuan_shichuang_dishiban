from pathlib import Path
import os
import re

root = Path(__file__).resolve().parents[2]
for path in root.rglob('*.qmd'):
    original = path.read_bytes()
    text = original.decode('utf-8-sig')
    newline = '\r\n' if b'\r\n' in original else '\n'
    text = text.replace('\r\n', '\n')
    relative = os.path.relpath(root / 'styles/offline.scss', path.parent).replace('\\', '/')
    text = text.replace('    theme: cosmo\n', f'    theme:\n      - cosmo\n      - {relative}\n')
    if '  html:\n' in text and '    html-math-method:' not in text:
        text = text.replace('  html:\n', '  html:\n    html-math-method: mathml\n', 1)
    if path.name == '電腦已昇級至視窗11版（工欲善其事必先利其器）.qmd':
        reference = text.index(': https://www.ig.com/en/cfd-trading/volume-based-cash-rebates')
        start = text.rfind('## 提問十四\n', 0, reference)
        end = text.index('## 提問十五\n', start)
        section = text[start:end]
        section = re.sub(r'(?<=\])\[(\d+)\]', r'[rebate-\1]', section)
        section = re.sub(r'(?m)^\[(\d+)\]:', r'[rebate-\1]:', section)
        text = text[:start] + section + text[end:]
    if path == root / 'templates/r-python-template.qmd':
        text = text.replace('Sys.setenv(RETICULATE_PYTHON = file.path(getwd(), ".venv/Scripts/python.exe"))', '''python <- Sys.getenv("RETICULATE_PYTHON", unset = "")
if (!nzchar(python)) {
  candidates <- c("../.venv/Scripts/python.exe", ".venv/Scripts/python.exe",
                  "C:/work/envs/ds/Scripts/python.exe")
  available <- candidates[file.exists(candidates)]
  if (!length(available)) stop("請設定 RETICULATE_PYTHON 為現有 Python 環境的完整路徑。")
  python <- available[[1]]
}
if (!file.exists(python)) stop("RETICULATE_PYTHON 指向不存在的檔案：", python)
Sys.setenv(RETICULATE_PYTHON = normalizePath(python, winslash = "/"))''')
        text = text.replace('group by g order by g", pq))\n```', 'group by g order by g", pq))\ndbDisconnect(con, shutdown = TRUE)\n```')
    updated = text.replace('\n', newline).encode('utf-8')
    if original.startswith(b'\xef\xbb\xbf'):
        updated = b'\xef\xbb\xbf' + updated
    if updated != original:
        path.write_bytes(updated)
