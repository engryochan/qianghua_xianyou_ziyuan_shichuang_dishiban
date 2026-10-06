# Frontier R stack for C:\work\R\R-4.6.1 (user-scope install, no admin).
#
# Doctrine carried over from CLAUDE.md, learned the hard way:
#  * Install ONE PACKAGE AT A TIME. pak's dependency solver is global: a single
#    CRAN-archived package marks the entire batch "dependency conflict", and the
#    message reads like an R-version or mirror problem.
#  * Do NOT install 'arrow'. R's arrow and Python's pyarrow each embed their own
#    Arrow C++ binary; whichever loads first makes the other fail to resolve
#    symbols. In a .qmd mixing R and Python chunks knitr runs both in ONE process
#    via reticulate, so this is a guaranteed crash. Use duckdb for Parquet in R.
#  * Archived on CRAN as of 2026-09: qs, vip, fastshap -> use qs2 and shapviz.
#  * Report numbers for machine parsing with scientific = FALSE.

options(repos = c(CRAN = "https://cloud.r-project.org"),
        timeout = 1800,
        install.packages.check.source = "no",
        Ncpus = 6)

pkgs <- c(
  # --- tidy core / utilities
  "data.table","dplyr","tidyr","readr","purrr","stringr","forcats","tibble",
  "ggplot2","lubridate","glue","janitor","withr","here","sessioninfo","fs",
  # --- IO / storage (duckdb instead of arrow, qs2 instead of archived qs)
  "DBI","duckdb","RSQLite","readxl","writexl","openxlsx","jsonlite","qs2",
  "fst","vroom","nanoparquet",
  # --- reproducibility / pipelines
  "renv","targets","tarchetypes",
  # --- reporting
  "knitr","rmarkdown","quarto","gt","tinytable","flextable","DT","kableExtra",
  "patchwork","ggrepel","scales","ggdist","viridis",
  # --- inference / econometrics
  "broom","sandwich","lmtest","car","fixest","estimatr","modelsummary",
  "marginaleffects","emmeans","performance","parameters","insight","see",
  # --- machine learning
  "tidymodels","glmnet","ranger","xgboost","lightgbm","kernlab","iml","shapviz",
  "yardstick","rsample","recipes","parsnip","workflows","tune","dials",
  # --- Bayesian
  "posterior","bayesplot","loo","tidybayes","brms","cmdstanr",
  # --- time series
  "xts","zoo","tsibble","fable","feasts","forecast","tseries","urca","vars",
  # --- quantitative finance
  "quantmod","PerformanceAnalytics","TTR",
  # --- causal inference
  "MatchIt","WeightIt","cobalt","did","grf","DoubleML",
  # --- survival
  "survival","survminer",
  # --- interop / tooling
  "reticulate","languageserver","httpgd","microbenchmark","bench"
)

lib <- .libPaths()[1]
cat("LIB:", lib, "\n")
cat("RVER:", R.version.string, "\n")
cat("NPKG:", format(length(pkgs), scientific = FALSE), "\n")

rows <- list()
for (p in pkgs) {
  if (requireNamespace(p, quietly = TRUE)) {
    rows[[length(rows)+1]] <- data.frame(pkg = p, status = "already",
      version = as.character(utils::packageVersion(p)), stringsAsFactors = FALSE)
    cat("[already]", p, "\n"); next
  }
  ok <- tryCatch({ utils::install.packages(p, lib = lib, quiet = TRUE); TRUE },
                 error = function(e) FALSE, warning = function(w) TRUE)
  got <- requireNamespace(p, quietly = TRUE)
  rows[[length(rows)+1]] <- data.frame(pkg = p,
    status = if (got) "installed" else "FAILED",
    version = if (got) as.character(utils::packageVersion(p)) else NA_character_,
    stringsAsFactors = FALSE)
  cat(if (got) "[ok]" else "[FAIL]", p, "\n")
}

rep <- do.call(rbind, rows)
utils::write.csv(rep, "C:/work/logs/R_package_install_report.csv", row.names = FALSE)
cat("\n=== SUMMARY ===\n")
print(table(rep$status))
f <- rep[rep$status == "FAILED", "pkg"]
cat("FAILEDLIST:", if (length(f)) paste(f, collapse = ",") else "(none)", "\n")
