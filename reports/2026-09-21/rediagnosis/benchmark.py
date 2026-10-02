"""Synthetic current-state baseline; not evidence of an improvement vs an earlier run."""
import json, statistics, time
from pathlib import Path
import numpy as np
import polars as pl
import duckdb
from threadpoolctl import threadpool_limits
import psutil

out=Path(__file__).parent
n=1_000_000
df=pl.DataFrame({'group':np.arange(n,dtype=np.int64)%100,'value':np.arange(n,dtype=np.int64)})
pq=out/'benchmark.parquet'
df.write_parquet(pq)
expected=n*(n-1)//2
rows={}
def measure(label, fn):
    fn()  # warmup
    samples=[]
    for _ in range(5):
        start=time.perf_counter();fn();samples.append(time.perf_counter()-start)
    rows[label]={'seconds':samples,'median_seconds':statistics.median(samples)}
with duckdb.connect(config={'threads':6,'memory_limit':'2GB'}) as con:
    def sql():
        r=con.execute('SELECT "group", sum(value) FROM read_parquet(?) GROUP BY 1',[str(pq)]).fetchall()
        assert len(r)==100 and sum(x[1] for x in r)==expected
    measure('duckdb_1m_parquet_groupby',sql)
def lazy():
    result=pl.scan_parquet(pq).group_by('group').agg(pl.col('value').sum()).collect()
    assert result.height==100 and result['value'].sum()==expected
measure('polars_1m_parquet_groupby',lazy)
rng=np.random.default_rng(0);a=rng.normal(size=(512,512))
with threadpool_limits(limits=6):
    reference=a@a.T
    def matrix():
        assert np.allclose(a@a.T,reference)
    measure('numpy_512_matrix_product_with_validation',matrix)
report={'purpose':'Current synthetic baseline only; no pre-update timings available',
        'rows':n,'parquet_bytes':pq.stat().st_size,'tests':rows,
        'available_memory_bytes':psutil.virtual_memory().available,
        'process_rss_bytes':psutil.Process().memory_info().rss}
(out/'performance-baseline.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report))
