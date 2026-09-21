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

options(repos = c(CRAN = "https://cloud.r-project.org"))
options(timeout = 900)
options(install.packages.check.source = "no")
options(Ncpus = 10)

# ---- sandbox guard --------------------------------------------------------
lib <- .libPaths()[1]
probe <- file.path(dirname(lib), paste0("_probe_", as.integer(Sys.time()), ".tmp"))
writeLines("probe", probe)
pkgroot <- file.path(Sys.getenv("LOCALAPPDATA"), "Packages")
shadowed <- FALSE
if (dir.exists(pkgroot)) {
  for (d in list.dirs(pkgroot, recursive = FALSE)) {
    cand <- file.path(d, "LocalCache", "Local", "R", basename(probe))
    if (file.exists(cand)) shadowed <- TRUE
  }
}
unlink(probe)
if (shadowed) {
  stop("Writes to the R library are being redirected into an app sandbox. ",
       "Run this from a normal R session instead.")
}
cat("Library target:", lib, "\n\n")

# ---- the package set ------------------------------------------------------
sets <- list(
  `stats-econometrics` = c("fixest", "plm", "AER", "estimatr", "marginaleffects",
                           "emmeans", "glmmTMB", "bbmle", "maxLik", "gmm"),
  `nonparam-tests`     = c("coin", "BSDA", "nonpar", "effsize", "perm"),
  `roc-auc`            = c("pROC", "ROCR", "PRROC", "cutpointr", "precrec"),
  `survival`           = c("flexsurv", "rms", "timeROC", "riskRegression",
                           "randomForestSRC", "mboost", "cmprsk", "muhaz", "joineR"),
  `bayesian`           = c("brms", "MCMCpack", "nimble", "BayesFactor", "tidybayes"),
  `evt-copula`         = c("extRemes", "evd", "evir", "ismev", "POT", "texmex",
                           "fExtremes", "copula", "VineCopula"),
  `quant-finance`      = c("PortfolioAnalytics", "rmgarch", "fGarch", "tseries",
                           "vars", "MTS", "fPortfolio", "tidyquant",
                           "RiskPortfolios", "riskParityPortfolio", "highfrequency",
                           "RQuantLib", "FinTS", "quantreg"),
  `credit-risk`        = c("scorecard", "Information", "woeBinning", "smbinning",
                           "creditmodel"),
  `ml`                 = c("caret", "mlr3", "mlr3learners", "mlr3tuning",
                           "mlr3pipelines", "mlr3viz", "earth", "gbm", "h2o",
                           "catboost.utils"),
  `explain`            = c("lime", "modelStudio", "shapper", "ingredients"),
  `deep-learning`      = c("torch", "luz", "torchvision", "brulee", "tabnet", "keras3"),
  `time-series`        = c("feasts", "modeltime", "bsts", "tsDyn", "seasonal",
                           "timetk", "fracdiff"),
  `causal`             = c("did", "MatchIt", "WeightIt", "cobalt", "CausalImpact",
                           "tmle", "EValue", "sensemakr", "rdrobust"),
  `viz`                = c("GGally", "gganimate", "viridis", "ggcorrplot", "ggthemes"),
  `performance`        = c("RhpcBLASctl"),
  `reproducibility`    = c("pointblank", "validate", "assertr"),
  `reinforcement`      = c("ReinforcementLearning", "MDPtoolbox", "contextual", "bandit"),
  `db-io`              = c("DBI", "RSQLite", "RPostgres", "odbc", "mongolite", "sparklyr")
)

# Packages CRAN has archived or that never shipped on CRAN. Attempted last, and
# a failure here is expected rather than a problem with your machine.
known_hard <- c("qs", "vip", "fastshap", "contextual", "bandit", "catboost.utils",
                "shapper", "nonpar")

installed_now <- rownames(installed.packages())
report <- data.frame(domain = character(), package = character(),
                     status = character(), note = character(),
                     stringsAsFactors = FALSE)

for (dom in names(sets)) {
  cat("=====", dom, "=====\n")
  for (p in sets[[dom]]) {
    if (p %in% installed_now) {
      cat("  already ", p, "\n", sep = "")
      report <- rbind(report, data.frame(domain = dom, package = p,
                                         status = "ALREADY", note = "",
                                         stringsAsFactors = FALSE))
      next
    }
    note <- ""
    ok <- tryCatch({
      suppressWarnings(install.packages(p, quiet = TRUE))
      requireNamespace(p, quietly = TRUE)
    }, error = function(e) { note <<- conditionMessage(e); FALSE })
    if (isTRUE(ok)) {
      cat("  OK      ", p, "\n", sep = "")
      st <- "OK"
    } else {
      cat("  FAIL    ", p, if (p %in% known_hard) "  (known hard case)" else "", "\n", sep = "")
      st <- "FAIL"
      if (p %in% known_hard && note == "") note <- "archived on CRAN or not a CRAN package"
    }
    report <- rbind(report, data.frame(domain = dom, package = p,
                                       status = st, note = note,
                                       stringsAsFactors = FALSE))
  }
}

# ---- packages that are NOT on CRAN ---------------------------------------
cat("\n===== not on CRAN: install manually if you need them =====\n")
cat("  quantstrat, blotter   -> remotes::install_github('braverock/quantstrat')\n")
cat("  cmdstanr              -> install.packages('cmdstanr', repos = c('https://stan-dev.r-universe.dev', getOption('repos')))\n")
cat("  synthdid              -> remotes::install_github('synth-inference/synthdid')\n")
cat("  INLA                  -> install.packages('INLA', repos = c(INLA = 'https://inla.r-inla-download.org/R/stable'))\n")
cat("  torch backend         -> after installing 'torch', run torch::install_torch() once (downloads libtorch, ~2 GB)\n")
cat("  keras3/tensorflow     -> need a Python backend; point them at C:/work/envs/ds\n")

out <- "R_package_install_report.csv"
write.csv(report, out, row.names = FALSE)

cat("\n===== summary =====\n")
print(table(report$status))
cat("report written to:", normalizePath(out, mustWork = FALSE), "\n")
cat("library now holds:", format(length(rownames(installed.packages())), scientific = FALSE), "packages\n")
