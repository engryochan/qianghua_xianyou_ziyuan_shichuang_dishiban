# 公开 EEG 运动想像解码:一步步看「能」与「不能」
# 数据 PhysioNet EEG Motor Movement/Imagery(mne 自动缓存)
import warnings, numpy as np
warnings.filterwarnings("ignore")
import mne
from mne.datasets import eegbci
from mne.decoding import CSP
from sklearn.pipeline import Pipeline
from sklearn.discriminant_analysis import LinearDiscriminantAnalysis
from sklearn.model_selection import ShuffleSplit, cross_val_score
from sklearn.metrics import confusion_matrix
mne.set_log_level("ERROR")

def load(subject, runs, ev):
    files = eegbci.load_data(subject, runs, update_path=True, verbose=False)
    raw = mne.concatenate_raws([mne.io.read_raw_edf(f, preload=True, verbose=False) for f in files])
    eegbci.standardize(raw); raw.set_montage(mne.channels.make_standard_montage("standard_1005"), verbose=False)
    raw.filter(7., 30., fir_design="firwin", verbose=False)
    events,_ = mne.events_from_annotations(raw, verbose=False)
    picks = mne.pick_types(raw.info, eeg=True, exclude="bads")
    ep = mne.Epochs(raw, events, event_id=ev, tmin=0.5, tmax=2.5, picks=picks, baseline=None, preload=True, verbose=False)
    return ep.get_data(copy=False), ep.events[:,-1]

clf = Pipeline([("CSP", CSP(n_components=6, reg="ledoit_wolf", log=True)),
                ("LDA", LinearDiscriminantAnalysis())])
cv = ShuffleSplit(10, test_size=0.2, random_state=42)
subj = 1

print("受试者", subj, "· 每类样本 ~22 · 10 折交叉验证\n" + "="*56)

# 任务 A:想像 左拳 vs 右拳(空间上分得开 → 较易)
XA, yA = load(subj, [4,8,12], dict(left=2, right=3))
accA = cross_val_score(clf, XA, yA, cv=cv, n_jobs=1)
print(f"任务A  想像左拳 vs 右拳(2类)")
print(f"  瞎猜基线 50%%   |  CSP+LDA = {100*accA.mean():.1f}%% (±{100*accA.std():.1f})")

# 任务 B:想像 双拳 vs 双脚(也2类,但脑区差异更微妙 → 参照)
XB, yB = load(subj, [6,10,14], dict(hands=2, feet=3))
accB = cross_val_score(clf, XB, yB, cv=cv, n_jobs=1)
print(f"任务B  想像双拳 vs 双脚(2类)")
print(f"  瞎猜基线 50%%   |  CSP+LDA = {100*accB.mean():.1f}%% (±{100*accB.std():.1f})")

# 任务 C:四类 左拳/右拳/双拳/双脚(难度陡增 → 看准确率怎么掉)
XL,yL = load(subj,[4,8,12],dict(left=2,right=3))
XF,yF = load(subj,[6,10,14],dict(hands=2,feet=3)); yF = yF + 2
X4 = np.concatenate([XL,XF],0); y4 = np.concatenate([yL,yF],0)
acc4 = cross_val_score(clf, X4, y4, cv=cv, n_jobs=1)
print(f"任务C  四类(左拳/右拳/双拳/双脚)")
print(f"  瞎猜基线 25%%   |  CSP+LDA = {100*acc4.mean():.1f}%% (±{100*acc4.std():.1f})")

print("="*56)
print("能:  2类运动想像稳定高于瞎猜(任务A/B)——脑电确实含'想动哪里'的信息")
print("不能:类别一多(任务C 4类),准确率相对瞎猜的优势缩水——")
print("     它读的是粗略的'运动意图区域',不是具体动作、更不是词句或画面")
