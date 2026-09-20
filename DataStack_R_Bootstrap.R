# Called only by Setup_DataStack_v2.ps1 -Apply -SetupR.
# Uses a managed project and private bootstrap/cache; never changes the user's .Rprofile.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L)
root <- normalizePath(args[[1]], winslash = "/", mustWork = TRUE)
results <- normalizePath(args[[2]], winslash = "/", mustWork = TRUE)
project <- file.path(root, "r-project")
bootstrap <- file.path(root, "r-bootstrap", paste(R.version$major, R.version$minor, sep = "."))
dir.create(bootstrap, recursive = TRUE, showWarnings = FALSE)
Sys.setenv(RENV_PATHS_CACHE = file.path(root, "cache", "renv"),
           RENV_CONFIG_AUTO_SNAPSHOT = "FALSE")
options(repos = c(CRAN = "https://cloud.r-project.org"), timeout = 600,
        pkgType = "binary", install.packages.check.source = "no", Ncpus = 2L)
.libPaths(c(bootstrap, .Library))
if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv", lib = bootstrap, type = "binary")
}
stopifnot(requireNamespace("renv", quietly = TRUE))
marker <- file.path(project, ".datastack-managed")
if (dir.exists(project) && !file.exists(marker)) {
  stop("Existing unmanaged r-project: select another WorkRoot; no files were overwritten.")
}
dir.create(project, recursive = TRUE, showWarnings = FALSE)
writeLines("DataStack-v2", marker)
if (file.exists(file.path(project, "renv", "activate.R"))) {
  renv::load(project = project)
} else {
  renv::consent(provided = TRUE)
  renv::init(project = project, bare = TRUE, restart = FALSE)
}
if (file.exists(file.path(project, "renv.lock"))) {
  file.copy(file.path(project, "renv.lock"), file.path(results, "renv.before.lock"), overwrite = FALSE)
  renv::restore(project = project, prompt = FALSE)
}
wanted <- c("data.table", "dplyr", "tidyr", "readr", "ggplot2", "readxl", "writexl", "DBI", "RSQLite", "duckdb", "arrow", "survival", "jsonlite", "renv")
lib <- renv::paths$library(project = project)
existing <- rownames(installed.packages(lib.loc = lib))
missing <- setdiff(wanted, existing)
if (length(missing)) install.packages(missing, lib = lib, type = "binary")
missing <- setdiff(wanted, rownames(installed.packages(lib.loc = lib)))
if (length(missing)) stop("Missing binary packages: ", paste(missing, collapse = ", "))
renv::snapshot(project = project, type = "all", prompt = FALSE)
tab <- data.table::data.table(g = c("A", "B", "A", "B"), v = 1:4)
stopifnot(identical(tab[, sum(v)], 10L))
excel <- file.path(results, "r-example.xlsx")
writexl::write_xlsx(as.data.frame(tab), excel)
stopifnot(sum(readxl::read_xlsx(excel)$v) == 10)
con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
DBI::dbWriteTable(con, "sample", as.data.frame(tab))
stopifnot(DBI::dbGetQuery(con, "SELECT SUM(v) AS total FROM sample")$total == 10)
DBI::dbDisconnect(con)
parquet <- file.path(results, "r-example.parquet")
arrow::write_parquet(as.data.frame(tab), parquet)
stopifnot(sum(arrow::read_parquet(parquet)$v) == 10)
con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
DBI::dbWriteTable(con, "sample", as.data.frame(tab))
stopifnot(DBI::dbGetQuery(con, "SELECT SUM(v) AS total FROM sample")$total == 10)
DBI::dbDisconnect(con, shutdown = TRUE)
stopifnot(inherits(survival::Surv(1:4, c(1, 0, 1, 1)), "Surv"))
write.csv(as.data.frame(installed.packages(lib.loc = lib)[, c("Package", "Version", "LibPath")]),
          file.path(results, "r-packages.csv"), row.names = FALSE)
writeLines(capture.output(sessionInfo()), file.path(results, "r-session-info.txt"))
cat("R project checks PASSED: data.table, Excel, SQLite, DuckDB, Arrow/Parquet, survival, renv snapshot\n")
