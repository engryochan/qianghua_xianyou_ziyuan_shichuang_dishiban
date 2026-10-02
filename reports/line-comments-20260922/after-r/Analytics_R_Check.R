# 计算本行表达式并设置 args，供后续步骤使用。
args <- commandArgs(trailingOnly=TRUE)
# 断言本行条件成立；不满足时中止验收并报错。
stopifnot(length(args) == 1L, file.exists(args[1]))
# 读取 R 套件安装清单，并保存到 ip。
ip <- installed.packages()
# 将表格写入 CSV 文件。
write.csv(ip[, c('Package', 'Version', 'Built', 'LibPath')], 'r-package-snapshot.csv', row.names=FALSE)
# 构造或计算 required，保存本行指定的集合或索引结果。
required <- c('data.table','duckdb','DBI','xgboost','rugarch','tidymodels','reticulate','targets','renv','grf')
# 断言本行条件成立；不满足时中止验收并报错。
stopifnot(length(setdiff(required, ip[, 'Package'])) == 0L)
# 加载指定 R 套件。
library(data.table)
# 限制 data.table 使用的线程数量。
setDTthreads(6)
# 构造或计算 dt，保存本行指定的集合或索引结果。
dt <- data.table(g=rep(c('a','b'), each=50000), v=1:100000)
# 断言本行条件成立；不满足时中止验收并报错。
stopifnot(sum(dt[, .(s=sum(as.numeric(v))), by=g]$s) == 5000050000)
# 建立数据库连接，并保存到 con。
con <- DBI::dbConnect(duckdb::duckdb(), config=list(threads='6', memory_limit='2GB'))
# 调用 duckdb::duckdb_register，使用本行列出的输入完成对应操作。
duckdb::duckdb_register(con, 'sample', dt)
# 执行指定 SQL 语句。
DBI::dbExecute(con, "COPY sample TO 'r-check.parquet' (FORMAT PARQUET)")
# 断言本行条件成立；不满足时中止验收并报错。
stopifnot(DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM read_parquet('r-check.parquet')")$n == 100000)
# 关闭数据库连接并释放资源。
DBI::dbDisconnect(con, shutdown=TRUE)
# 固定 R 随机种子以便重复验证。
set.seed(1)
# 计算本行表达式并设置 x，供后续步骤使用。
x <- matrix(rnorm(20000*20),20000,20)
# 计算本行表达式并设置 y，供后续步骤使用。
y <- as.integer(x %*% rnorm(20) + rnorm(20000) > 0)
# 构造 XGBoost 使用的数据矩阵，并保存到 dm。
dm <- xgboost::xgb.DMatrix(x,label=y,nthread=6)
# 训练 XGBoost 模型，并保存到 m。
m <- xgboost::xgb.train(params=list(objective='binary:logistic',tree_method='hist',nthread=6,seed=1),
                        # 计算本行表达式并设置 data，供后续步骤使用。
                        data=dm,nrounds=60,verbose=0)
# 计算本行表达式并设置 accuracy，供后续步骤使用。
accuracy <- mean((predict(m,dm) > .5) == y)
# 断言本行条件成立；不满足时中止验收并报错。
stopifnot(accuracy > .9)
# 设置当前 R 进程的环境变量。
Sys.setenv(RETICULATE_PYTHON=args[1])
# 通过 reticulate 导入 Python 模块，并保存到 pl。
pl <- reticulate::import('polars')
# 通过 reticulate 导入 Python 模块，并保存到 pa。
pa <- reticulate::import('pyarrow.parquet')
# 断言本行条件成立；不满足时中止验收并报错。
stopifnot(pa$read_table('r-check.parquet')$num_rows == 100000)
# 构造或计算 result，保存本行指定的集合或索引结果。
result <- list(status='passed', package_count=nrow(ip), xgboost_accuracy=accuracy,
               # 构造或计算 checks，保存本行指定的集合或索引结果。
               checks=c('10-key-packages','data.table','R-duckdb-parquet','R-xgboost','reticulate-pyarrow'))
# 使用 jsonlite 转换或保存 JSON 结果。
jsonlite::write_json(result,'r-result.json',auto_unbox=TRUE,pretty=TRUE)
# 输出本行的状态信息或计算结果。
cat(jsonlite::toJSON(result,auto_unbox=TRUE), '\n')
