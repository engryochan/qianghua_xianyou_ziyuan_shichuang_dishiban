# 真实脑机介面实验：想像「左手 vs 右手」运动 → 分类
# 数据：PhysioNet EEG Motor Movement/Imagery（公开，mne 自动下载）
# 管线：原始 EEG → 带通滤波 → CSP 特征 → LDA → 交叉验证（固定种子，可复现）
import warnings, numpy as np
warnings.filterwarnings("ignore")
import mne
from mne.datasets import eegbci
from mne.decoding import CSP
from sklearn.pipeline import Pipeline
from sklearn.discriminant_analysis import LinearDiscriminantAnalysis
from sklearn.model_selection import ShuffleSplit, cross_val_score
from sklearn.dummy import DummyClassifier

mne.set_log_level("ERROR")
rng = 42

# runs 4,8,12 = 想像左拳 vs 右拳（PhysioNet 标准范式）
subject = 1
runs = [4, 8, 12]
files = eegbci.load_data(subject, runs, update_path=True, verbose=False)
raw = mne.concatenate_raws([mne.io.read_raw_edf(f, preload=True, verbose=False) for f in files])
eegbci.standardize(raw)
raw.set_montage(mne.channels.make_standard_montage("standard_1005"), verbose=False)

# 带通 7–30 Hz：mu(8–12) + beta(13–30) 是运动想像的核心频带
raw.filter(7., 30., fir_design="firwin", verbose=False)

events, _ = mne.events_from_annotations(raw, verbose=False)
# T1=左拳, T2=右拳
picks = mne.pick_types(raw.info, eeg=True, exclude="bads")
epochs = mne.Epochs(raw, events, event_id=dict(left=2, right=3),
                    tmin=1., tmax=2., picks=picks, baseline=None, preload=True, verbose=False)
X = epochs.get_data(copy=False)
y = epochs.events[:, -1]
print("样本数 =", len(y), " 通道 =", X.shape[1], " 每段时长点数 =", X.shape[2])
print("类别分布：左 =", int((y==2).sum()), " 右 =", int((y==3).sum()))

cv = ShuffleSplit(10, test_size=0.2, random_state=rng)

# 基线：瞎猜（按多数类）
dummy = DummyClassifier(strategy="most_frequent")
Xflat = X.reshape(len(X), -1)
base = cross_val_score(dummy, Xflat, y, cv=cv)

# 真管线：CSP + LDA
clf = Pipeline([("CSP", CSP(n_components=4, reg=None, log=True)),
                ("LDA", LinearDiscriminantAnalysis())])
scores = cross_val_score(clf, X, y, cv=cv, n_jobs=1)

print("\n=== 结果（受试者 %d，想像左手 vs 右手）===" % subject)
print("瞎猜基线准确率 : %.1f%%" % (100*base.mean()))
print("CSP+LDA 准确率 : %.1f%%  (± %.1f%%)" % (100*scores.mean(), 100*scores.std()))
print("十折逐折       :", " ".join("%.0f" % (100*s) for s in scores))
