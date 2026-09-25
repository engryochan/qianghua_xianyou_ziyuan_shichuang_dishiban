# Update R packages in the C:\work hub, robust against the three common traps
# seen on 2026-09-25:
#   1) cli/rlang (and other) DLLs locked by a running R / RStudio / Rgui.
#      A loaded package's .dll cannot be overwritten, so update.packages()
#      "restores" the old copy and warns. FIX: close R/RStudio/Rgui and run this
#      from a CLEAN Rscript (this file, invoked by Rscript, loads none of them).
#   2) Large tarballs (e.g. h2o) time out at the default 60s. FIX: timeout=1200.
#   3) update.packages() trying to write base/recommended in Program Files needs
#      admin and should not be done here. FIX: restrict to the writable user hub.
#
# Base/recommended packages (MASS, Matrix, survival, class, lattice, ...) stay as
# shipped with R; bump them only via an elevated R or an R version upgrade.

options(
  timeout = 1200,
  repos   = c(CRAN = "https://cloud.r-project.org"),
  Ncpus   = max(1L, parallel::detectCores() - 2L),
  install.packages.check.source = "no"    # prefer Windows binaries
)

hub <- "C:/work/Rlib"
if (!dir.exists(hub)) stop("hub library not found: ", hub)
cat("Hub library:", hub, "\n")
cat("R_LIBS      :", Sys.getenv("R_LIBS"), "\n")
cat(".libPaths[1]:", .libPaths()[1], "\n\n")

# Guard: warn (do not abort) if another R has key DLLs loaded.
# Rscript itself does not load cli/rlang, so this run is clean; the risk is an
# open RStudio/Rgui holding the files. We cannot detect that from here, so just
# remind and proceed - a locked file will only skip that one package.
cat("If any package is 'restored' with a Permission-denied warning, an R/RStudio\n")
cat("session is still open. Close it and re-run.\n\n")

# Clear stale 00LOCK dirs from a previous failed run (they block reinstalls).
locks <- list.files(hub, pattern = "^00LOCK", full.names = TRUE)
if (length(locks)) {
  cat("Removing stale lock dirs:\n"); print(locks)
  unlink(locks, recursive = TRUE, force = TRUE)
}

cat("\n=== update.packages (hub only, checkBuilt=TRUE) ===\n")
update.packages(lib.loc = hub, ask = FALSE, checkBuilt = TRUE)

# h2o is large and commonly the one that timed out; ensure it is present.
if (!requireNamespace("h2o", quietly = TRUE)) {
  cat("\nh2o not available - installing separately with the long timeout...\n")
  try(install.packages("h2o", lib = hub))
}

cat("\n=== Spot-check: key analysis packages load ===\n")
keys <- c("data.table","dplyr","tidymodels","torch","tensorflow","keras3",
          "xgboost","lightgbm","ranger","brms","rstan","grf","survival",
          "pROC","PerformanceAnalytics","rugarch","extRemes","reticulate")
for (p in keys)
  cat(sprintf("  %-20s %s\n", p, if (requireNamespace(p, quietly = TRUE)) "OK" else "FAIL"))
cat("\nDone.\n")
