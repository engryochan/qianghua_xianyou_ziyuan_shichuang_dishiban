# 最优会话配置（R）——在分析脚本开头 source(),不要写进 .Rprofile。
# 原因（本仓库铁律）：.Rprofile 改执行行为会让同一脚本在不同机器出不同结果；
# 线程数属于执行行为，必须放脚本里、随脚本走。
local({
  ncpu <- parallel::detectCores(logical = TRUE)        # 本机 12
  phys <- max(1L, parallel::detectCores(logical = FALSE)) # 本机 6
  if (requireNamespace("data.table", quietly = TRUE))
    data.table::setDTthreads(phys)                     # 数据操作用物理核最稳（内存密集，超线程无益）
  if (requireNamespace("RhpcBLASctl", quietly = TRUE)) {
    RhpcBLASctl::blas_set_num_threads(phys)            # 换成多线程 BLAS 后才生效；参考 BLAS 下无害
    RhpcBLASctl::omp_set_num_threads(phys)
  }
  options(Ncpus = ncpu)                                # 仅影响装包并行，不影响计算结果
  message(sprintf("[session] data.table=%d 线程, BLAS/OMP=%d 线程, 逻辑核=%d",
                  if (requireNamespace("data.table", quietly=TRUE)) data.table::getDTthreads() else 0L,
                  phys, ncpu))
})
