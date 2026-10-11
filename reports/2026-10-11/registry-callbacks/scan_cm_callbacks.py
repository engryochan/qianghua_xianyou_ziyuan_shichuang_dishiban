"""唯讀：掃 System32\\drivers 下的 .sys，找出匯入登錄檔回呼 API 的驅動。

原理：PE 的 Import Name Table 把被匯入的函式名以 ASCII 明文存在檔案裡，
所以直接搜位元組就能判斷某個驅動「有沒有能力」註冊登錄檔回呼，
不需要核心除錯器。

界限：這證明的是「具備能力並連結了該 API」，不是「此刻有活躍的回呼」。
後者仍需 !reg querycallbacks。純讀檔，不載入也不執行任何驅動。
"""
import os
import sys

# -I 會連帶忽略 PYTHONIOENCODING，所以在程式內明確設定，
# 否則重導到檔案時會用地區代碼頁(GBK)寫出，拿 UTF-8 讀就是亂碼。
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = r"C:\Windows\System32\drivers"

# 登錄檔回呼相關
CM = [b"CmRegisterCallbackEx", b"CmRegisterCallback", b"CmUnRegisterCallback",
      b"CmCallbackGetKeyObjectIDEx", b"CmCallbackGetKeyObjectID",
      b"CmSetCallbackObjectContext"]
# 對照：檔案系統篩選與行程/執行緒/映像通知，用來分辨驅動的管控面向
OTHER = [b"FltRegisterFilter", b"IoAttachDeviceToDeviceStack",
         b"PsSetCreateProcessNotifyRoutineEx", b"PsSetCreateProcessNotifyRoutine",
         b"PsSetLoadImageNotifyRoutine", b"PsSetCreateThreadNotifyRoutine",
         b"ObRegisterCallbacks"]

def walk(root):
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in filenames:
            if fn.lower().endswith(".sys"):
                yield os.path.join(dirpath, fn)

rows = []
errors = []
total = 0
for path in walk(ROOT):
    total += 1
    try:
        with open(path, "rb") as fh:
            blob = fh.read()
    except Exception as exc:
        errors.append((path, type(exc).__name__))
        continue
    cm = [m.decode() for m in CM if m in blob]
    if not cm:
        continue
    other = [m.decode() for m in OTHER if m in blob]
    rows.append((path, cm, other))

print("掃描 .sys 總數: %d；讀取失敗 %d" % (total, len(errors)))
print("匯入登錄檔回呼 API 的驅動: %d" % len(rows))
print()
rows.sort(key=lambda r: os.path.basename(r[0]).lower())
for path, cm, other in rows:
    rel = path[len(ROOT) + 1:] if path.startswith(ROOT) else path
    print("--- %s" % rel)
    print("    Cm   : %s" % ", ".join(sorted(cm)))
    if other:
        print("    其他 : %s" % ", ".join(sorted(other)))
if errors:
    print()
    print("讀取失敗（通常是權限）:")
    for path, kind in errors[:20]:
        print("    %s  [%s]" % (path[len(ROOT) + 1:], kind))
