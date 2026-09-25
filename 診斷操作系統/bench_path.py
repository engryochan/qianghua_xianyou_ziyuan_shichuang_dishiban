import time, os, numpy as np
DEEP = r"C:\work\envs\ds\Lib\site-packages\numpy\__init__.py"  # 深层文件夹里的一个文件

def ms(t): return f"{t*1000:.3f} ms"

# 1) 导入成本：只在启动时付一次
t=time.perf_counter(); import pandas; import_ms=(time.perf_counter()-t)
print(f"1) 首次 import pandas（一次性成本）      : {ms(import_ms)}")

t=time.perf_counter(); import pandas as pd2  # 已在内存,第二次
print(f"   第二次 import（已缓存,证明不再读盘） : {ms(time.perf_counter()-t)}")

# 2) 导入后：纯运算,完全不碰文件夹
A=np.random.default_rng(0).normal(size=(1000,1000)); B=A.copy()
t=time.perf_counter()
for _ in range(100): C=A@B   # 100 次矩阵乘
print(f"2) 100 次 1000x1000 矩阵乘（纯 RAM/CPU）: {ms((time.perf_counter()-t)/100)}/次")

# 3) 反复访问深层文件夹里的文件 —— 第一次 vs 之后（证明 OS 缓存目录）
t=time.perf_counter(); os.stat(DEEP); first=(time.perf_counter()-t)
t=time.perf_counter()
for _ in range(100000): os.stat(DEEP)   # 访问同一深层路径 10 万次
cached=(time.perf_counter()-t)/100000
print(f"3) 深层路径首次 stat                    : {ms(first)}")
print(f"   之后每次 stat（OS 已缓存目录）        : {ms(cached)}  ← 微秒级")

# 4) 对比：一次矩阵乘 vs 一次文件夹访问,谁才是瓶颈
one_matmul=0
t=time.perf_counter(); A@B; one_matmul=time.perf_counter()-t
print(f"\n结论对比:")
print(f"   一次矩阵乘(真计算)   : {ms(one_matmul)}")
print(f"   一次文件夹访问(缓存后): {ms(cached)}")
print(f"   计算比文件夹访问慢    : {one_matmul/cached:.0f} 倍")
