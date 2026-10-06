# cmdstanr is NOT on CRAN; it lives on the Stan r-universe.
# CmdStan itself is compiled from source, so this needs a working toolchain:
# Rtools45 at C:\work\rtools45, with RTOOLS45_HOME set and rtools45\usr\bin on PATH
# FOR THIS PROCESS ONLY (usr\bin shadows the Windows sh/find/sort if made persistent).
options(repos = c(stan = "https://stan-dev.r-universe.dev",
                  CRAN = "https://cloud.r-project.org"),
        timeout = 3600, Ncpus = 6)

cat("make on PATH:", Sys.which("make"), "\n")
cat("RTOOLS45_HOME:", Sys.getenv("RTOOLS45_HOME"), "\n")

if (!requireNamespace("cmdstanr", quietly = TRUE)) {
  install.packages("cmdstanr")
}
cat("cmdstanr installed:", requireNamespace("cmdstanr", quietly = TRUE), "\n")
if (!requireNamespace("cmdstanr", quietly = TRUE)) quit(status = 1)
cat("cmdstanr version:", as.character(utils::packageVersion("cmdstanr")), "\n")

library(cmdstanr)
cat("toolchain check:\n")
print(try(cmdstanr::check_cmdstan_toolchain(fix = FALSE), silent = TRUE))

dir <- "C:/work/cmdstan"
dir.create(dir, showWarnings = FALSE, recursive = TRUE)
cat("building CmdStan into", dir, "...\n")
ok <- tryCatch({
  cmdstanr::install_cmdstan(dir = dir, cores = 6, quiet = TRUE, overwrite = FALSE)
  TRUE
}, error = function(e) { cat("install_cmdstan FAILED:", conditionMessage(e), "\n"); FALSE })

cat("install_cmdstan ok:", ok, "\n")
if (ok) {
  cat("cmdstan path:", cmdstanr::cmdstan_path(), "\n")
  cat("cmdstan version:", cmdstanr::cmdstan_version(), "\n")
}
