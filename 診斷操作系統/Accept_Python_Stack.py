"""Real-computation acceptance for C:\work\envs\ds.
Doctrine from CLAUDE.md: verify by COMPUTING, not by checking versions.
 - DuckDB concatenates strings with || , never +
 - econml's LinearDML cross-fits randomly; unseeded runs drifted 1.82..2.03,
   so the seed is pinned and the assertion is a tolerance band
 - numbers meant for machine parsing are printed without scientific notation
"""
import sys, traceback, numpy as np

R = []
def check(name, fn):
    try:
        v = fn()
        R.append((name, "PASS", str(v)[:90]))
    except Exception as e:
        R.append((name, "FAIL", f"{type(e).__name__}: {e}"[:160]))

def t_numpy():
    a = np.arange(1_000_000, dtype=np.float64)
    return f"sum={a.sum():.0f}"

def t_polars():
    import polars as pl
    df = pl.DataFrame({"g": ["a","b","a","b"], "x": [1.0,2.0,3.0,4.0]})
    out = df.group_by("g").agg(pl.col("x").sum().alias("s")).sort("g")
    return f"v{pl.__version__} {out.to_dicts()}"

def t_duckdb():
    import duckdb
    con = duckdb.connect()
    # string concat MUST be || in DuckDB
    v = con.sql("select 'ab' || 'cd' as s, sum(i) as n from range(100001) t(i)").fetchone()
    return f"concat={v[0]} sum={v[1]:.0f}"

def t_pyarrow():
    import pyarrow as pa, pyarrow.parquet as pq, tempfile, os
    t = pa.table({"i": pa.array(range(100000)), "f": pa.array(np.random.rand(100000))})
    p = os.path.join(tempfile.gettempdir(), "acc_pa.parquet")
    pq.write_table(t, p)
    back = pq.read_table(p)
    return f"v{pa.__version__} rows={back.num_rows:d}"

def t_pandas_excel():
    import pandas as pd, tempfile, os
    df = pd.DataFrame({"a": [1,2,3], "b": ["x","y","z"]})
    p = os.path.join(tempfile.gettempdir(), "acc_xl.xlsx")
    df.to_excel(p, index=False, engine="xlsxwriter")
    back = pd.read_excel(p, engine="openpyxl")
    return f"pandas{pd.__version__} roundtrip_rows={len(back):d} equal={back.equals(df)}"

def t_sklearn():
    from sklearn.ensemble import RandomForestRegressor
    from sklearn.datasets import make_regression
    X, y = make_regression(n_samples=800, n_features=12, noise=0.3, random_state=0)
    m = RandomForestRegressor(n_estimators=60, random_state=0, n_jobs=-1).fit(X, y)
    return f"R2={m.score(X,y):.4f}"

def t_statsmodels():
    import statsmodels.api as sm
    rng = np.random.default_rng(0)
    X = sm.add_constant(rng.normal(size=(500,2)))
    y = X @ np.array([1.0, 2.0, -1.5]) + rng.normal(scale=0.2, size=500)
    r = sm.OLS(y, X).fit()
    return "beta=" + ",".join(f"{b:.3f}" for b in r.params)

def t_lightgbm():
    import lightgbm as lgb
    from sklearn.datasets import make_classification
    X, y = make_classification(n_samples=1500, n_features=20, random_state=0)
    m = lgb.LGBMClassifier(n_estimators=60, verbose=-1, random_state=0).fit(X, y)
    return f"v{lgb.__version__} acc={m.score(X,y):.4f}"

def t_xgboost():
    import xgboost as xgb
    from sklearn.datasets import make_classification
    X, y = make_classification(n_samples=1500, n_features=20, random_state=0)
    m = xgb.XGBClassifier(n_estimators=60, random_state=0, verbosity=0).fit(X, y)
    return f"v{xgb.__version__} acc={m.score(X,y):.4f}"

def t_torch():
    import torch
    torch.manual_seed(0)
    a = torch.randn(600, 600); b = torch.randn(600, 600)
    c = a @ b
    return f"v{torch.__version__} cuda={torch.cuda.is_available()} norm={c.norm().item():.2f}"

def t_jax():
    import jax, jax.numpy as jnp
    f = jax.jit(lambda x: jnp.sum(x ** 2))
    return f"v{jax.__version__} val={float(f(jnp.arange(1000.0))):.0f}"

def t_numpyro():
    import numpyro, numpyro.distributions as dist
    from numpyro.infer import MCMC, NUTS
    import jax.random as jr
    def model(y=None):
        mu = numpyro.sample("mu", dist.Normal(0, 10))
        numpyro.sample("obs", dist.Normal(mu, 1), obs=y)
    y = np.random.default_rng(0).normal(3.0, 1.0, 200)
    mcmc = MCMC(NUTS(model), num_warmup=200, num_samples=300, progress_bar=False)
    mcmc.run(jr.PRNGKey(0), y=y)
    m = float(np.mean(mcmc.get_samples()["mu"]))
    assert 2.5 < m < 3.5, f"posterior mean off: {m}"
    return f"v{numpyro.__version__} post_mu={m:.3f}"

def t_pymc():
    import pymc as pm
    with pm.Model():
        mu = pm.Normal("mu", 0, 10)
        pm.Normal("obs", mu, 1, observed=np.random.default_rng(0).normal(2.0, 1.0, 150))
        idata = pm.sample(draws=200, tune=200, chains=2, cores=1,
                          random_seed=0, progressbar=False)
    m = float(idata.posterior["mu"].mean())
    assert 1.5 < m < 2.5, f"posterior mean off: {m}"
    return f"v{pm.__version__} post_mu={m:.3f}"

def t_econml():
    from econml.dml import LinearDML
    from sklearn.ensemble import GradientBoostingRegressor
    rng = np.random.default_rng(0)
    n = 3000
    X = rng.normal(size=(n, 5))
    T = (X[:, 0] + rng.normal(size=n) > 0).astype(float)
    Y = 2.0 * T + X[:, 1] + rng.normal(scale=0.5, size=n)
    est = LinearDML(model_y=GradientBoostingRegressor(random_state=0),
                    model_t=GradientBoostingRegressor(random_state=0),
                    discrete_treatment=True, random_state=0)
    est.fit(Y, T, X=X, W=None)
    ate = float(est.ate(X))
    assert 1.6 < ate < 2.4, f"ATE outside band: {ate}"
    return f"ATE={ate:.4f} (seeded; unseeded runs drifted 1.82-2.03)"

def t_arrow_interop():
    import polars as pl, pyarrow as pa
    df = pl.DataFrame({"x": [1,2,3]})
    return f"polars->arrow rows={df.to_arrow().num_rows:d}"

for n, f in [("numpy",t_numpy),("polars",t_polars),("duckdb",t_duckdb),
             ("pyarrow",t_pyarrow),("pandas+excel",t_pandas_excel),
             ("scikit-learn",t_sklearn),("statsmodels",t_statsmodels),
             ("lightgbm",t_lightgbm),("xgboost",t_xgboost),("torch",t_torch),
             ("jax",t_jax),("numpyro",t_numpyro),("pymc",t_pymc),
             ("econml",t_econml),("polars/arrow interop",t_arrow_interop)]:
    check(n, f)

print(f"{'CHECK':24} {'RESULT':6} DETAIL")
for n, s, d in R:
    print(f"{n:24} {s:6} {d}")
npass = sum(1 for _,s,_ in R if s=="PASS")
print(f"\nPASS {npass:d} / {len(R):d}")
sys.exit(0 if npass == len(R) else 1)
