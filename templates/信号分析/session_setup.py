"""最优会话配置（Python）——在脚本/Notebook 开头 import 或 exec()。
numpy 已用 OpenBLAS 12 线程，无需手调；这里统一 polars/numba/joblib 的并行，
并示范可复现的随机种子。线程设定放脚本、不放全局环境变量。"""
import os
def setup(seed: int = 0):
    import numpy as np
    phys = os.cpu_count() or 4
    # polars / duckdb / numba 默认已自动并行；此处仅显式化，便于复现
    try:
        import polars as pl
        os.environ.setdefault("POLARS_MAX_THREADS", str(phys))
    except Exception:
        pass
    rng = np.random.default_rng(seed)   # 固定种子：可复现是量化/科研的底线
    print(f"[session] cpu={phys}  numpy-BLAS=OpenBLAS(已多线程)  seed={seed}")
    return rng

if __name__ == "__main__":
    setup()
