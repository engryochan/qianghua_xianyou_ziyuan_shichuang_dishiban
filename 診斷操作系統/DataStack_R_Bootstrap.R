# Called only by Setup_DataStack_v2.ps1 -Apply -SetupR.
# Uses a managed project and private bootstrap/cache; never changes the user's .Rprofile.
# 计算本行表达式并设置 args，供后续步骤使用。
args <- commandArgs(trailingOnly = TRUE)
# 断言本行条件成立；不满足时中止验收并报错。
stopifnot(length(args) == 2L)
# 构造或计算 root，保存本行指定的集合或索引结果。
root <- normalizePath(args[[1]], winslash = "/", mustWork = TRUE)
# 构造或计算 results，保存本行指定的集合或索引结果。
results <- normalizePath(args[[2]], winslash = "/", mustWork = TRUE)
# 计算本行表达式并设置 project，供后续步骤使用。
project <- file.path(root, "r-project")
# 计算本行表达式并设置 bootstrap，供后续步骤使用。
bootstrap <- file.path(root, "r-bootstrap", paste(R.version$major, R.version$minor, sep = "."))
# 调用 dir.create，使用本行列出的输入完成对应操作。
dir.create(bootstrap, recursive = TRUE, showWarnings = FALSE)
# 设置当前 R 进程的环境变量。
Sys.setenv(RENV_PATHS_CACHE = file.path(root, "cache", "renv"),
           # 计算本行表达式并设置 RENV_CONFIG_AUTO_SNAPSHOT，供后续步骤使用。
           RENV_CONFIG_AUTO_SNAPSHOT = "FALSE")
# 调用 options，使用本行列出的输入完成对应操作。
options(repos = c(CRAN = "https://cloud.r-project.org"), timeout = 600,
        # 安装本行指定的 R 套件，并保存到 pkgType。
        pkgType = "binary", install.packages.check.source = "no", Ncpus = 2L)
# 调用 .libPaths，使用本行列出的输入完成对应操作。
.libPaths(c(bootstrap, .Library))
# 检查本行条件；满足时执行对应分支。
if (!requireNamespace("renv", quietly = TRUE)) {
  # 安装本行指定的 R 套件。
  install.packages("renv", lib = bootstrap, type = "binary")
# 结束此处的代码块、参数列表或集合定义。
}
# 断言本行条件成立；不满足时中止验收并报错。
stopifnot(requireNamespace("renv", quietly = TRUE))
# 计算本行表达式并设置 marker，供后续步骤使用。
marker <- file.path(project, ".datastack-managed")
# 检查本行条件；满足时执行对应分支。
if (dir.exists(project) && !file.exists(marker)) {
  # 报告本行指定的错误并中止当前执行路径。
  stop("Existing unmanaged r-project: select another WorkRoot; no files were overwritten.")
# 结束此处的代码块、参数列表或集合定义。
}
# 调用 dir.create，使用本行列出的输入完成对应操作。
dir.create(project, recursive = TRUE, showWarnings = FALSE)
# 输出一行文本；将文本逐行写入目标文件。
writeLines("DataStack-v2", marker)
# 检查本行条件；满足时执行对应分支。
if (file.exists(file.path(project, "renv", "activate.R"))) {
  # 调用 renv::load，使用本行列出的输入完成对应操作。
  renv::load(project = project)
# 结束上一代码块并进入另一条件分支。
} else {
  # 调用 renv::consent，使用本行列出的输入完成对应操作。
  renv::consent(provided = TRUE)
  # 调用 renv::init，使用本行列出的输入完成对应操作。
  renv::init(project = project, bare = TRUE, restart = FALSE)
# 结束此处的代码块、参数列表或集合定义。
}
# 检查本行条件；满足时执行对应分支。
if (file.exists(file.path(project, "renv.lock"))) {
  # 调用 file.copy，使用本行列出的输入完成对应操作。
  file.copy(file.path(project, "renv.lock"), file.path(results, "renv.before.lock"), overwrite = FALSE)
  # 调用 renv::restore，使用本行列出的输入完成对应操作。
  renv::restore(project = project, prompt = FALSE)
# 结束此处的代码块、参数列表或集合定义。
}
# 构造或计算 wanted，保存本行指定的集合或索引结果。
wanted <- c("data.table", "dplyr", "tidyr", "readr", "ggplot2", "readxl", "writexl", "DBI", "RSQLite", "duckdb", "arrow", "survival", "jsonlite", "renv")
# 加载指定 R 套件，并保存到 lib。
lib <- renv::paths$library(project = project)
# 读取 R 套件安装清单，并保存到 existing。
existing <- rownames(installed.packages(lib.loc = lib))
# 计算本行表达式并设置 missing，供后续步骤使用。
missing <- setdiff(wanted, existing)
# 检查本行条件；满足时执行对应分支。
if (length(missing)) install.packages(missing, lib = lib, type = "binary")
# 读取 R 套件安装清单，并保存到 missing。
missing <- setdiff(wanted, rownames(installed.packages(lib.loc = lib)))
# 检查本行条件；满足时执行对应分支。
if (length(missing)) stop("Missing binary packages: ", paste(missing, collapse = ", "))
# 调用 renv::snapshot，使用本行列出的输入完成对应操作。
renv::snapshot(project = project, type = "all", prompt = FALSE)
# 构造或计算 tab，保存本行指定的集合或索引结果。
tab <- data.table::data.table(g = c("A", "B", "A", "B"), v = 1:4)
# 断言本行条件成立；不满足时中止验收并报错。
stopifnot(identical(tab[, sum(v)], 10L))
# 计算本行表达式并设置 excel，供后续步骤使用。
excel <- file.path(results, "r-example.xlsx")
# 调用 writexl::write_xlsx，使用本行列出的输入完成对应操作。
writexl::write_xlsx(as.data.frame(tab), excel)
# 断言本行条件成立；不满足时中止验收并报错。
stopifnot(sum(readxl::read_xlsx(excel)$v) == 10)
# 建立数据库连接，并保存到 con。
con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
# 调用 DBI::dbWriteTable，使用本行列出的输入完成对应操作。
DBI::dbWriteTable(con, "sample", as.data.frame(tab))
# 断言本行条件成立；不满足时中止验收并报错。
stopifnot(DBI::dbGetQuery(con, "SELECT SUM(v) AS total FROM sample")$total == 10)
# 关闭数据库连接并释放资源。
DBI::dbDisconnect(con)
# 计算本行表达式并设置 parquet，供后续步骤使用。
parquet <- file.path(results, "r-example.parquet")
# 将数据写入 Parquet 文件。
arrow::write_parquet(as.data.frame(tab), parquet)
# 断言本行条件成立；不满足时中止验收并报错。
stopifnot(sum(arrow::read_parquet(parquet)$v) == 10)
# 建立数据库连接，并保存到 con。
con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
# 调用 DBI::dbWriteTable，使用本行列出的输入完成对应操作。
DBI::dbWriteTable(con, "sample", as.data.frame(tab))
# 断言本行条件成立；不满足时中止验收并报错。
stopifnot(DBI::dbGetQuery(con, "SELECT SUM(v) AS total FROM sample")$total == 10)
# 关闭数据库连接并释放资源。
DBI::dbDisconnect(con, shutdown = TRUE)
# 断言本行条件成立；不满足时中止验收并报错。
stopifnot(inherits(survival::Surv(1:4, c(1, 0, 1, 1)), "Surv"))
# 读取 R 套件安装清单；将表格写入 CSV 文件。
write.csv(as.data.frame(installed.packages(lib.loc = lib)[, c("Package", "Version", "LibPath")]),
          # 调用 file.path，使用本行列出的输入完成对应操作。
          file.path(results, "r-packages.csv"), row.names = FALSE)
# 输出一行文本；将文本逐行写入目标文件。
writeLines(capture.output(sessionInfo()), file.path(results, "r-session-info.txt"))
# 输出本行的状态信息或计算结果。
cat("R project checks PASSED: data.table, Excel, SQLite, DuckDB, Arrow/Parquet, survival, renv snapshot\n")
