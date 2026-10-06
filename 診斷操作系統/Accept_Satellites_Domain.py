"""Domain-level acceptance for the satellite envs: each one must do real work in its
own field, not merely import. Offline-only by design -- anything needing a model
download or a live API is reported as SKIP(network) rather than silently passing."""
import sys, numpy as np

g = sys.argv[1]
rows = []
def chk(name, fn):
    try:
        rows.append((name, 'PASS', str(fn())[:95]))
    except Exception as e:
        rows.append((name, 'FAIL', f'{type(e).__name__}: {e}'[:120]))

if g == 'xai':
    def t():
        import dalex, pandas as pd
        from sklearn.ensemble import RandomForestRegressor
        rng = np.random.default_rng(0)
        X = pd.DataFrame(rng.normal(size=(400, 4)), columns=list('abcd'))
        y = 3 * X['a'] - 2 * X['b'] + rng.normal(scale=.2, size=400)
        m = RandomForestRegressor(n_estimators=40, random_state=0).fit(X, y)
        exp = dalex.Explainer(m, X, y, verbose=False)
        vi = exp.model_parts(random_state=0).result
        top = vi[vi.variable.isin(list('abcd'))].sort_values('dropout_loss', ascending=False)
        return 'most important var=' + str(top.iloc[0]['variable'])
    chk('dalex Explainer + variable importance', t)

elif g == 'mlops':
    def t():
        import pandas as pd
        from evidently import Report
        from evidently.presets import DataDriftPreset
        rng = np.random.default_rng(0)
        ref = pd.DataFrame({'x': rng.normal(0, 1, 800), 'y': rng.normal(5, 2, 800)})
        cur = pd.DataFrame({'x': rng.normal(1.4, 1, 800), 'y': rng.normal(5, 2, 800)})
        r = Report(metrics=[DataDriftPreset()]).run(reference_data=ref, current_data=cur)
        d = r.dict()
        return 'report produced, top-level keys=' + str(list(d.keys())[:3])
    chk('evidently DataDriftPreset report', t)
    def t2():
        import nannyml, pandas as pd
        rng = np.random.default_rng(0)
        ref = pd.DataFrame({'f': rng.normal(0, 1, 600)})
        ana = pd.DataFrame({'f': rng.normal(1.2, 1, 600)})
        calc = nannyml.UnivariateDriftCalculator(column_names=['f']).fit(ref)
        res = calc.calculate(ana)
        return 'nannyml drift computed, rows=' + str(len(res.to_df()))
    chk('nannyml univariate drift', t2)

elif g == 'rl':
    def t():
        import gluonts
        from gluonts.dataset.common import ListDataset
        from gluonts.model.seasonal_naive import SeasonalNaivePredictor
        ds = ListDataset([{'start': '2024-01-01', 'target': list(np.arange(100.0))}], freq='D')
        p = SeasonalNaivePredictor(prediction_length=7, season_length=7)
        f = next(iter(p.predict(ds)))
        return f'gluonts {gluonts.__version__} forecast len={len(f.mean):d} mean0={f.mean[0]:.1f}'
    chk('gluonts SeasonalNaive forecast', t)
    def t2():
        import gevent
        from gevent import spawn
        out = []
        def w(i):
            gevent.sleep(0)
            out.append(i * i)
        gevent.joinall([spawn(w, i) for i in range(5)])
        return 'greenlets ran, squares=' + str(sorted(out))
    chk('gevent greenlets', t2)
    def t3():
        import tianshou, torch
        from tianshou.data import Batch
        b = Batch(obs=np.zeros((4, 3)), act=np.arange(4))
        return f'tianshou {tianshou.__version__} Batch shape={b.obs.shape} torch={torch.__version__}'
    chk('tianshou Batch', t3)

elif g == 'fin':
    def t():
        from openbb import obb
        cov = obb.coverage.providers
        n = len(cov) if hasattr(cov, '__len__') else 0
        return f'openbb loaded, providers registered={n:d}'
    chk('openbb provider coverage (offline)', t)
    def t2():
        from pypfopt import EfficientFrontier, risk_models, expected_returns
        import pandas as pd
        rng = np.random.default_rng(0)
        px = pd.DataFrame(np.exp(np.cumsum(rng.normal(0.0004, 0.01, (500, 4)), axis=0)),
                          columns=list('ABCD'))
        mu = expected_returns.mean_historical_return(px)
        S = risk_models.sample_cov(px)
        w = EfficientFrontier(mu, S).max_sharpe()
        return 'pypfopt weights sum=' + f'{sum(w.values()):.4f}'
    chk('PyPortfolioOpt max_sharpe', t2)

elif g == 'nlp':
    def t():
        from flair.data import Sentence
        s = Sentence('Taipei is the capital of Taiwan .')
        return f'flair tokenised {len(s.tokens):d} tokens, first={s.tokens[0].text}'
    chk('flair tokenisation (no model download)', t)
    rows.append(('flair NER tagging', 'SKIP(network)',
                 'needs a ~400MB model download; not attempted offline'))

print(f'--- {g} ---')
for n, s, d in rows:
    print(f'  {n:40} {s:14} {d}')
bad = [r for r in rows if r[1] == 'FAIL']
print('  ' + ('OK' if not bad else f'{len(bad)} FAILURE(S)'))
sys.exit(1 if bad else 0)
