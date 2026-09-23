# ① 手机真实加速度数据 → 走/跑/静止 分类
#
# 怎么拿数据（不需要任何付费/可疑 App）：
#   Android: 装 "Physics Toolbox Sensor Suite" 或 "Sensor Logger"，录一段后导出 CSV
#   iPhone : 装 "Sensor Logger"（Apple App Store，免费），录后导出 CSV
#   每个活动（走/跑/静止）各录 30–60 秒，导出成单独的 CSV。
#
# CSV 需要有「时间 + 三轴加速度」四列。列名不统一没关系，改下面 COLS 即可。
# 常见列名：
#   Physics Toolbox: time, ax, ay, az   （单位可能是 g 或 m/s^2，脚本会自动判断）
#   Sensor Logger  : seconds_elapsed, x, y, z  （在 Accelerometer.csv 里）
#
# 用法：把三个 CSV 路径填进 FILES，然后：
#   & "C:\work\envs\ds\Scripts\python.exe" "templates\信号分析\加速度_真实数据.py"

import sys, numpy as np, pandas as pd, warnings
warnings.filterwarnings("ignore")
from scipy import signal as sps
from scipy.stats import iqr
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import GroupKFold, cross_val_score
from sklearn.dummy import DummyClassifier

# ============ 改这里 ============
FILES = {
    "still": [r"C:\path\to\静止1.csv", r"C:\path\to\静止2.csv"],
    "walk":  [r"C:\path\to\走路1.csv", r"C:\path\to\走路2.csv"],
    "run":   [r"C:\path\to\跑步1.csv", r"C:\path\to\跑步2.csv"],
}
COLS = ("time", "ax", "ay", "az")   # 时间列, x, y, z 的实际列名
FS_TARGET = 50                       # 目标采样率(Hz)；脚本会按时间列重采样到这个频率
# ================================

def load_csv(path):
    df = pd.read_csv(path)
    # 容错匹配列名
    cols = {c.lower().strip(): c for c in df.columns}
    def pick(cands):
        for k in cands:
            if k in cols: return cols[k]
        return None
    tc = pick([COLS[0].lower(), "time", "seconds_elapsed", "timestamp", "t"])
    xc = pick([COLS[1].lower(), "ax", "x", "accelerationx", "gforcex"])
    yc = pick([COLS[2].lower(), "ay", "y", "accelerationy", "gforcey"])
    zc = pick([COLS[3].lower(), "az", "z", "accelerationz", "gforcez"])
    if None in (tc, xc, yc, zc):
        raise ValueError("找不到时间/xyz 列，实际列名是：%s" % list(df.columns))
    t = pd.to_numeric(df[tc], errors="coerce").values.astype(float)
    if t.max() > 1e6: t = t / 1000.0          # 毫秒→秒
    t = t - t[0]
    xyz = df[[xc, yc, zc]].apply(pd.to_numeric, errors="coerce").values.astype(float)
    # 单位判断：静止时合力≈9.8 → m/s^2，需转 g
    if np.nanmedian(np.linalg.norm(xyz, axis=1)) > 5:
        xyz = xyz / 9.80665
    # 按时间重采样到均匀 FS_TARGET
    dur = t[-1]
    n = int(dur * FS_TARGET)
    tt = np.linspace(0, dur, n)
    out = np.stack([np.interp(tt, t, xyz[:, i]) for i in range(3)], 1)
    return out

def features(win, fs):
    mag = np.linalg.norm(win, axis=1); feats = []
    for col in [win[:,0], win[:,1], win[:,2], mag]:
        feats += [col.mean(), col.std(), iqr(col), np.sqrt((col**2).mean())]
        f, pxx = sps.welch(col - col.mean(), fs=fs, nperseg=min(64, len(col)))
        feats += ([f[np.argmax(pxx)], pxx.max()/pxx.sum(), (f*pxx).sum()/pxx.sum()]
                  if pxx.sum() > 0 else [0, 0, 0])
    return feats

def main():
    WIN, STEP = FS_TARGET*2, FS_TARGET
    X, y, groups = [], [], []; gid = 0; missing = []
    for act, paths in FILES.items():
        for p in paths:
            try:
                sig = load_csv(p)
            except Exception as e:
                missing.append((p, str(e)[:60])); continue
            for st in range(0, len(sig)-WIN, STEP):
                X.append(features(sig[st:st+WIN], FS_TARGET)); y.append(act); groups.append(gid)
            gid += 1
    if missing:
        print("以下档案读不到（先把 FILES 里的路径改对）：")
        for p, e in missing: print("  -", p, "|", e)
    if not X:
        print("\n没有可用数据。请先按脚本顶部说明录制并导出 CSV，再填好 FILES。"); return
    X = np.array(X); y = np.array(y); groups = np.array(groups)
    print("窗口样本数 =", len(y), " 特征维度 =", X.shape[1], " session 数 =", len(set(groups)))
    print("类别分布：", {a: int((y==a).sum()) for a in set(y)})
    if len(set(groups)) < 2:
        print("每类至少要 2 段独立录制才能做分组验证。"); return
    cv = GroupKFold(n_splits=min(len(set(groups)), 6))
    dummy = cross_val_score(DummyClassifier(strategy="most_frequent"), X, y, cv=cv, groups=groups)
    rf = cross_val_score(RandomForestClassifier(n_estimators=200, random_state=0, n_jobs=2),
                         X, y, cv=cv, groups=groups)
    print("\n=== 真实数据结果（按 session 分组验证，无泄漏）===")
    print("瞎猜基线      : %.1f%%" % (100*dummy.mean()))
    print("RandomForest  : %.1f%%  (± %.1f%%)" % (100*rf.mean(), 100*rf.std()))
    print("逐折          :", " ".join("%.0f" % (100*s) for s in rf))
    print("\n对照：合成数据是 100%%。你的真实数据大概率落在 88–97%%——")
    print("那个差距，就是「真实世界的噪声」，也是这次实验最该记住的东西。")

if __name__ == "__main__":
    main()
