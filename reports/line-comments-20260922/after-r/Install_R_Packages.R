# Install the quant / data-science R package set, one package at a time.
#
# WHY ONE AT A TIME, NOT pak::pkg_install(c(...)):
#   pak's dependency solver is global. A single package that CRAN has archived
#   (qs, vip, fastshap are archived as of 2026-09) makes pak mark the whole
#   batch as "dependency conflict", and the error message looks like an R
#   version problem or a broken mirror. install.packages() in a loop fails only
#   the one package that is actually broken.
#
# RUN THIS FROM A NORMAL R / RStudio SESSION, not from inside the Claude app:
#   the R user library lives under %LOCALAPPDATA%, which the Claude desktop app
#   redirects into its own MSIX container. Packages installed from there are
#   invisible to your real R.
#
#   "C:/Program Files/R/R-4.6.1/bin/x64/Rscript.exe" Install_R_Packages.R
#
# Results are written to R_package_install_report.csv next to this script.

# 调用 options，使用本行列出的输入完成对应操作。
options(repos = c(CRAN = "https://cloud.r-project.org"))
# 调用 options，使用本行列出的输入完成对应操作。
options(timeout = 900)
# 安装本行指定的 R 套件。
options(install.packages.check.source = "no")
# 调用 options，使用本行列出的输入完成对应操作。
options(Ncpus = 10)

# ---- sandbox guard --------------------------------------------------------
# 构造或计算 lib，保存本行指定的集合或索引结果。
lib <- .libPaths()[1]
# 计算本行表达式并设置 probe，供后续步骤使用。
probe <- file.path(dirname(lib), paste0("_probe_", as.integer(Sys.time()), ".tmp"))
# 输出一行文本；将文本逐行写入目标文件。
writeLines("probe", probe)
# 读取 R 进程的环境变量，并保存到 pkgroot。
pkgroot <- file.path(Sys.getenv("LOCALAPPDATA"), "Packages")
# 计算本行表达式并设置 shadowed，供后续步骤使用。
shadowed <- FALSE
# 检查本行条件；满足时执行对应分支。
if (dir.exists(pkgroot)) {
  # 按本行的迭代范围或条件重复执行循环体。
  for (d in list.dirs(pkgroot, recursive = FALSE)) {
    # 计算本行表达式并设置 cand，供后续步骤使用。
    cand <- file.path(d, "LocalCache", "Local", "R", basename(probe))
    # 检查本行条件；满足时执行对应分支。
    if (file.exists(cand)) shadowed <- TRUE
  # 结束此处的代码块、参数列表或集合定义。
  }
# 结束此处的代码块、参数列表或集合定义。
}
# 调用 unlink，使用本行列出的输入完成对应操作。
unlink(probe)
# 检查本行条件；满足时执行对应分支。
if (shadowed) {
  # 报告本行指定的错误并中止当前执行路径。
  stop("Writes to the R library are being redirected into an app sandbox. ",
       # 提供当前表达式所需的文本、字段名称或列表元素。
       "Run this from a normal R session instead.")
# 结束此处的代码块、参数列表或集合定义。
}
# 输出本行的状态信息或计算结果。
cat("Library target:", lib, "\n\n")

# ---- the package set ------------------------------------------------------
# 构造或计算 sets，保存本行指定的集合或索引结果。
sets <- list(
  # 处理 `stats-econometrics` 所指定的操作或当前表达式的后续部分。
  `stats-econometrics` = c("fixest", "plm", "AER", "estimatr", "marginaleffects",
                           # 提供当前表达式所需的文本、字段名称或列表元素。
                           "emmeans", "glmmTMB", "bbmle", "maxLik", "gmm"),
  # 处理 `nonparam-tests` 所指定的操作或当前表达式的后续部分。
  `nonparam-tests`     = c("coin", "BSDA", "nonpar", "effsize", "perm"),
  # 处理 `roc-auc` 所指定的操作或当前表达式的后续部分。
  `roc-auc`            = c("pROC", "ROCR", "PRROC", "cutpointr", "precrec"),
  # 处理 `survival` 所指定的操作或当前表达式的后续部分。
  `survival`           = c("flexsurv", "rms", "timeROC", "riskRegression",
                           # 提供当前表达式所需的文本、字段名称或列表元素。
                           "randomForestSRC", "mboost", "cmprsk", "muhaz", "joineR"),
  # 处理 `bayesian` 所指定的操作或当前表达式的后续部分。
  `bayesian`           = c("brms", "MCMCpack", "nimble", "BayesFactor", "tidybayes"),
  # 处理 `evt-copula` 所指定的操作或当前表达式的后续部分。
  `evt-copula`         = c("extRemes", "evd", "evir", "ismev", "POT", "texmex",
                           # 提供当前表达式所需的文本、字段名称或列表元素。
                           "fExtremes", "copula", "VineCopula"),
  # 处理 `quant-finance` 所指定的操作或当前表达式的后续部分。
  `quant-finance`      = c("PortfolioAnalytics", "rmgarch", "fGarch", "tseries",
                           # 提供当前表达式所需的文本、字段名称或列表元素。
                           "vars", "MTS", "fPortfolio", "tidyquant",
                           # 提供当前表达式所需的文本、字段名称或列表元素。
                           "RiskPortfolios", "riskParityPortfolio", "highfrequency",
                           # 提供当前表达式所需的文本、字段名称或列表元素。
                           "RQuantLib", "FinTS", "quantreg"),
  # 处理 `credit-risk` 所指定的操作或当前表达式的后续部分。
  `credit-risk`        = c("scorecard", "Information", "woeBinning", "smbinning",
                           # 提供当前表达式所需的文本、字段名称或列表元素。
                           "creditmodel"),
  # 处理 `ml` 所指定的操作或当前表达式的后续部分。
  `ml`                 = c("caret", "mlr3", "mlr3learners", "mlr3tuning",
                           # 准备或执行 Python 套件管理操作。
                           "mlr3pipelines", "mlr3viz", "earth", "gbm", "h2o",
                           # 提供当前表达式所需的文本、字段名称或列表元素。
                           "catboost.utils"),
  # 处理 `explain` 所指定的操作或当前表达式的后续部分。
  `explain`            = c("lime", "modelStudio", "shapper", "ingredients"),
  # 处理 `deep-learning` 所指定的操作或当前表达式的后续部分。
  `deep-learning`      = c("torch", "luz", "torchvision", "brulee", "tabnet", "keras3"),
  # 处理 `time-series` 所指定的操作或当前表达式的后续部分。
  `time-series`        = c("feasts", "modeltime", "bsts", "tsDyn", "seasonal",
                           # 提供当前表达式所需的文本、字段名称或列表元素。
                           "timetk", "fracdiff"),
  # 处理 `causal` 所指定的操作或当前表达式的后续部分。
  `causal`             = c("did", "MatchIt", "WeightIt", "cobalt", "CausalImpact",
                           # 提供当前表达式所需的文本、字段名称或列表元素。
                           "tmle", "EValue", "sensemakr", "rdrobust"),
  # 处理 `viz` 所指定的操作或当前表达式的后续部分。
  `viz`                = c("GGally", "gganimate", "viridis", "ggcorrplot", "ggthemes"),
  # 处理 `performance` 所指定的操作或当前表达式的后续部分。
  `performance`        = c("RhpcBLASctl"),
  # 处理 `reproducibility` 所指定的操作或当前表达式的后续部分。
  `reproducibility`    = c("pointblank", "validate", "assertr"),
  # 处理 `reinforcement` 所指定的操作或当前表达式的后续部分。
  `reinforcement`      = c("ReinforcementLearning", "MDPtoolbox", "contextual", "bandit"),
  # 处理 `db-io` 所指定的操作或当前表达式的后续部分。
  `db-io`              = c("DBI", "RSQLite", "RPostgres", "odbc", "mongolite", "sparklyr")
# 结束此处的代码块、参数列表或集合定义。
)

# Packages CRAN has archived or that never shipped on CRAN. Attempted last, and
# a failure here is expected rather than a problem with your machine.
# 构造或计算 known_hard，保存本行指定的集合或索引结果。
known_hard <- c("qs", "vip", "fastshap", "contextual", "bandit", "catboost.utils",
                # 提供当前表达式所需的文本、字段名称或列表元素。
                "shapper", "nonpar")

# 读取 R 套件安装清单，并保存到 installed_now。
installed_now <- rownames(installed.packages())
# 计算本行表达式并设置 report，供后续步骤使用。
report <- data.frame(domain = character(), package = character(),
                     # 计算本行表达式并设置 status，供后续步骤使用。
                     status = character(), note = character(),
                     # 计算本行表达式并设置 stringsAsFactors，供后续步骤使用。
                     stringsAsFactors = FALSE)

# 按本行的迭代范围或条件重复执行循环体。
for (dom in names(sets)) {
  # 输出本行的状态信息或计算结果。
  cat("=====", dom, "=====\n")
  # 按本行的迭代范围或条件重复执行循环体。
  for (p in sets[[dom]]) {
    # 检查本行条件；满足时执行对应分支。
    if (p %in% installed_now) {
      # 输出本行的状态信息或计算结果。
      cat("  already ", p, "\n", sep = "")
      # 计算本行表达式并设置 report，供后续步骤使用。
      report <- rbind(report, data.frame(domain = dom, package = p,
                                         # 计算本行表达式并设置 status，供后续步骤使用。
                                         status = "ALREADY", note = "",
                                         # 计算本行表达式并设置 stringsAsFactors，供后续步骤使用。
                                         stringsAsFactors = FALSE))
      # 处理 next 所指定的操作或当前表达式的后续部分。
      next
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 计算本行表达式并设置 note，供后续步骤使用。
    note <- ""
    # 计算本行表达式并设置 ok，供后续步骤使用。
    ok <- tryCatch({
      # 安装本行指定的 R 套件。
      suppressWarnings(install.packages(p, quiet = TRUE))
      # 检查指定 R 套件是否可用。
      requireNamespace(p, quietly = TRUE)
    # 继续当前表达式，补充参数、类型转换或结果处理。
    }, error = function(e) { note <<- conditionMessage(e); FALSE })
    # 检查本行条件；满足时执行对应分支。
    if (isTRUE(ok)) {
      # 输出本行的状态信息或计算结果。
      cat("  OK      ", p, "\n", sep = "")
      # 计算本行表达式并设置 st，供后续步骤使用。
      st <- "OK"
    # 结束上一代码块并进入另一条件分支。
    } else {
      # 输出本行的状态信息或计算结果。
      cat("  FAIL    ", p, if (p %in% known_hard) "  (known hard case)" else "", "\n", sep = "")
      # 计算本行表达式并设置 st，供后续步骤使用。
      st <- "FAIL"
      # 检查本行条件；满足时执行对应分支。
      if (p %in% known_hard && note == "") note <- "archived on CRAN or not a CRAN package"
    # 结束此处的代码块、参数列表或集合定义。
    }
    # 计算本行表达式并设置 report，供后续步骤使用。
    report <- rbind(report, data.frame(domain = dom, package = p,
                                       # 计算本行表达式并设置 status，供后续步骤使用。
                                       status = st, note = note,
                                       # 计算本行表达式并设置 stringsAsFactors，供后续步骤使用。
                                       stringsAsFactors = FALSE))
  # 结束此处的代码块、参数列表或集合定义。
  }
# 结束此处的代码块、参数列表或集合定义。
}

# ---- packages that are NOT on CRAN ---------------------------------------
# 输出本行的状态信息或计算结果。
cat("\n===== not on CRAN: install manually if you need them =====\n")
# 输出本行的状态信息或计算结果。
cat("  quantstrat, blotter   -> remotes::install_github('braverock/quantstrat')\n")
# 输出本行的状态信息或计算结果。
cat("  cmdstanr              -> install.packages('cmdstanr', repos = c('https://stan-dev.r-universe.dev', getOption('repos')))\n")
# 输出本行的状态信息或计算结果。
cat("  synthdid              -> remotes::install_github('synth-inference/synthdid')\n")
# 输出本行的状态信息或计算结果。
cat("  INLA                  -> install.packages('INLA', repos = c(INLA = 'https://inla.r-inla-download.org/R/stable'))\n")
# 输出本行的状态信息或计算结果。
cat("  torch backend         -> after installing 'torch', run torch::install_torch() once (downloads libtorch, ~2 GB)\n")
# 输出本行的状态信息或计算结果。
cat("  keras3/tensorflow     -> need a Python backend; point them at C:/work/envs/ds\n")

# 计算本行表达式并设置 out，供后续步骤使用。
out <- "R_package_install_report.csv"
# 将表格写入 CSV 文件。
write.csv(report, out, row.names = FALSE)

# 输出本行的状态信息或计算结果。
cat("\n===== summary =====\n")
# 输出本行的状态信息或计算结果。
print(table(report$status))
# 输出本行的状态信息或计算结果。
cat("report written to:", normalizePath(out, mustWork = FALSE), "\n")
# 输出本行的状态信息或计算结果。
cat("library now holds:", format(length(rownames(installed.packages())), scientific = FALSE), "packages\n")
