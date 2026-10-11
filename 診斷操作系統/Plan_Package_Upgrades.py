"""算出派森環境中「可安全升級」與「必須held住」的組件集合。

為何需要這支工具
----------------
`uv pip install --upgrade <名稱>` **只求解被指名的套件及其依賴**，
不檢查既有套件的約束會不會被破壞。2026-10-11 實測踩過：
在 `xai` 升 pandas 到 3.0.6，`dalex` 要 `pandas<3.0.0` 當場被違反；
在 `rl` 升 toolz 到 1.2.0，`gluonts` 要 `toolz~=0.10` 被違反，
而且 **`import gluonts` 照樣成功**——匯入可用不等於宣告相容，
只有 `uv pip check` 才抓得到。

所以升級前要先算：某個套件升到最新版，會不會違反**任何其他已安裝套件**
對它宣告的版本範圍。

用法
----
    python Plan_Package_Upgrades.py <env名稱> <outdated清單檔>

`outdated清單檔` 是 `uv pip list --outdated` 的原始輸出。
輸出三段：可安全升級、必須held住（附阻擋者與原因）、無法判定。

界限
----
本工具做的是**單層靜態檢查**：只看「把 X 升到最新版是否違反他人對 X 的約束」。
它**不**模擬升級 X 連帶拉動的依賴變動。所以它是**必要條件而非充分條件**——
升完仍須 `uv pip check`，再跑 `Run_Full_Regression.ps1`。
"""

import sys
import importlib.metadata as md

try:
    from packaging.requirements import Requirement
    from packaging.version import Version, InvalidVersion
    from packaging.utils import canonicalize_name
except ImportError:
    sys.stderr.write("需要 packaging 套件；請用含 packaging 的環境執行本工具。\n")
    raise


def parse_outdated(path):
    """讀 uv pip list --outdated 的輸出，回 {正規化名稱: (現版, 最新版)}。"""
    out = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            if line.startswith(("Using Python", "Package", "---")):
                continue
            parts = line.split()
            if len(parts) < 3:
                continue
            name, cur, latest = parts[0], parts[1], parts[2]
            try:
                Version(cur), Version(latest)
            except InvalidVersion:
                continue
            out[canonicalize_name(name)] = (cur, latest)
    return out


def collect_constraints():
    """掃所有已安裝套件的 requires，回 {被約束者: [(約束來源, Requirement)]}。"""
    cons = {}
    for dist in md.distributions():
        owner = dist.metadata["Name"]
        if not owner:
            continue
        for raw in (dist.requires or []):
            try:
                req = Requirement(raw)
            except Exception:
                continue
            # 只看無 extra 條件者；extra 依賴未必已安裝
            marker = str(req.marker) if req.marker else ""
            if "extra ==" in marker:
                continue
            cons.setdefault(canonicalize_name(req.name), []).append((owner, req))
    return cons


def main():
    if len(sys.argv) < 3:
        sys.stderr.write(__doc__)
        return 2
    env_name, outdated_path = sys.argv[1], sys.argv[2]

    outdated = parse_outdated(outdated_path)
    cons = collect_constraints()

    safe, held, unknown = [], [], []

    for name, (cur, latest) in sorted(outdated.items()):
        blockers = []
        for owner, req in cons.get(name, []):
            if canonicalize_name(owner) == name:
                continue  # 自我約束不算
            if not req.specifier:
                continue
            try:
                ok = req.specifier.contains(Version(latest), prereleases=True)
            except Exception:
                unknown.append((name, cur, latest, owner, str(req)))
                continue
            if not ok:
                blockers.append((owner, str(req.specifier)))
        if blockers:
            held.append((name, cur, latest, blockers))
        else:
            safe.append((name, cur, latest))

    print("=" * 74)
    print("環境: %s      過時組件: %d" % (env_name, len(outdated)))
    print("=" * 74)

    print("\n【可安全升級】%d 個" % len(safe))
    for name, cur, latest in safe:
        print("  %-40s %-18s -> %s" % (name, cur, latest))

    print("\n【必須 held 住】%d 個（升了會違反既有約束）" % len(held))
    for name, cur, latest, blockers in held:
        print("  %-40s %-18s -x %s" % (name, cur, latest))
        for owner, spec in blockers:
            print("      阻擋者: %-28s 要求 %s" % (owner, spec))

    if unknown:
        print("\n【無法判定】%d 個" % len(unknown))
        for row in unknown:
            print("  %s" % (row,))

    # 給 PowerShell 取用的機讀區塊
    print("\n### SAFE_LIST_BEGIN")
    print(" ".join(n for n, _, _ in safe))
    print("### SAFE_LIST_END")
    print("### HELD_LIST_BEGIN")
    print(" ".join(n for n, _, _, _ in held))
    print("### HELD_LIST_END")
    return 0


if __name__ == "__main__":
    sys.exit(main())
