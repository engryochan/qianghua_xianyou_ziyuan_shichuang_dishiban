# 传感器动作识别：三轴加速度 → 分类「走 / 跑 / 静止」
# 数据：物理建模的合成信号（等你导出手机真实 CSV 可直接替换 gen_session）
# 管线：原始加速度 → 分窗 → 时/频域特征 → RandomForest → 按 session 分组交叉验证
import numpy as np, warnings
warnings.filterwarnings("ignore")
from scipy import signal as sps
from scipy.stats import iqr
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import GroupKFold, cross_val_score
from sklearn.dummy import DummyClassifier

FS = 50  # 采样率 50 Hz，手机常见
rng = np.random.default_rng(0)

def gen_session(activity, secs=60, sess_seed=0):
    """生成一段某活动的三轴加速度（单位 g）。走~2Hz、跑~3Hz、静止无周期。"""
    r = np.random.default_rng(sess_seed)
    n = FS * secs; t = np.arange(n) / FS
    if activity == "still":
        base = np.array([0.02, 0.02, 1.0])  # 静止：z≈重力
        sig = base + r.normal(0, 0.015, (n, 3))
    elif activity == "walk":
        f = r.uniform(1.8, 2.2)             # 步频 ~2 Hz
        amp = r.uniform(0.25, 0.4)
        phase = r.uniform(0, 2*np.pi, 3)
        sig = np.stack([amp*np.sin(2*np.pi*f*t + phase[i]) for i in range(3)], 1)
        sig[:, 2] += 1.0
        sig += r.normal(0, 0.05, (n, 3))
    else:  # run
        f = r.uniform(2.6, 3.4)             # 步频 ~3 Hz，幅度更大、含二次谐波
        amp = r.uniform(0.7, 1.1)
        phase = r.uniform(0, 2*np.pi, 3)
        sig = np.stack([amp*(np.sin(2*np.pi*f*t+phase[i]) + 0.3*np.sin(4*np.pi*f*t)) for i in range(3)], 1)
        sig[:, 2] += 1.0
        sig += r.normal(0, 0.12, (n, 3))
    return sig

def features(win):
    """从一个窗口（win: 点数×3）抽 时域+频域 特征。"""
    mag = np.linalg.norm(win, axis=1)
    feats = []
    for col in [win[:,0], win[:,1], win[:,2], mag]:
        feats += [col.mean(), col.std(), iqr(col), np.sqrt((col**2).mean())]  # 均值/标准差/IQR/RMS
        f, pxx = sps.welch(col - col.mean(), fs=FS, nperseg=min(64, len(col)))
        if pxx.sum() > 0:
            feats += [f[np.argmax(pxx)], pxx.max()/pxx.sum(),                     # 主频、主频占比
                      (f*pxx).sum()/pxx.sum()]                                    # 频谱质心
        else:
            feats += [0, 0, 0]
    return feats

WIN, STEP = FS*2, FS   # 2 秒窗、1 秒步进（50% 重叠）
X, y, groups = [], [], []
gid = 0
for activity in ["still", "walk", "run"]:
    for s in range(6):                     # 每类 6 段独立 session
        sig = gen_session(activity, 60, sess_seed=100*gid + 7)
        for st in range(0, len(sig)-WIN, STEP):
            X.append(features(sig[st:st+WIN])); y.append(activity); groups.append(gid)
        gid += 1
X = np.array(X); y = np.array(y); groups = np.array(groups)
print("窗口样本数 =", len(y), " 特征维度 =", X.shape[1], " session 数 =", len(set(groups)))
print("类别分布：", {a: int((y==a).sum()) for a in ["still","walk","run"]})

# 关键：GroupKFold —— 同一 session 不同时落在训练和测试，杜绝「同段泄漏」
cv = GroupKFold(n_splits=6)
dummy = cross_val_score(DummyClassifier(strategy="most_frequent"), X, y, cv=cv, groups=groups)
rf = RandomForestClassifier(n_estimators=200, random_state=0, n_jobs=2)
scores = cross_val_score(rf, X, y, cv=cv, groups=groups)

print("\n=== 结果（走/跑/静止 三分类，按 session 分组验证）===")
print("瞎猜基线准确率 : %.1f%%" % (100*dummy.mean()))
print("RandomForest   : %.1f%%  (± %.1f%%)" % (100*scores.mean(), 100*scores.std()))
print("逐折           :", " ".join("%.0f" % (100*s) for s in scores))
