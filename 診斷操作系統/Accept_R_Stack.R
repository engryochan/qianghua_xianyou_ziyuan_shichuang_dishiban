# Real-computation acceptance for C:\work\R\R-4.6.1.
# Doctrine from CLAUDE.md:
#  * 'arrow' must NOT be installed: R arrow and Python pyarrow each embed their own
#    Arrow C++ runtime and the second to load cannot resolve symbols. knitr runs R
#    and Python chunks in ONE process via reticulate, so a .qmd would crash.
#    Parquet in R therefore goes through duckdb.
#  * reticulate honours RETICULATE_PYTHON only -- never QUARTO_PYTHON. Unset, it
#    silently downloads its own clean Python and every package looks missing.
#  * Print numbers for machine parsing with scientific = FALSE: cat() turns
#    100000 into 1e+05 and a (\d+) regex then captures just the 1.

res <- list()
chk <- function(name, f) {
  out <- tryCatch(list(s = "PASS", d = as.character(f())),
                  error = function(e) list(s = "FAIL", d = conditionMessage(e)))
  res[[length(res) + 1]] <<- data.frame(check = name, status = out$s,
                                        detail = substr(out$d, 1, 95),
                                        stringsAsFactors = FALSE)
}

chk("arrow is absent (required)", function() {
  if (requireNamespace("arrow", quietly = TRUE))
    stop("arrow IS installed - it will break reticulate/pyarrow in the same process")
  "arrow not installed, as intended"
})

chk("data.table aggregate", function() {
  library(data.table)
  dt <- data.table(g = rep(c("a","b"), 50000), x = seq_len(100000))
  s <- dt[, .(n = .N, tot = sum(x)), by = g][order(g)]
  paste0("rows=", format(nrow(s), scientific = FALSE),
         " tot=", format(sum(s$tot), scientific = FALSE))
})

chk("duckdb parquet round-trip", function() {
  library(DBI); library(duckdb)
  dt <- data.frame(i = seq_len(100000), x = runif(100000))
  pq <- file.path(tempdir(), "acc_r.parquet")
  con <- dbConnect(duckdb())
  duckdb_register(con, "dt", dt)
  dbExecute(con, sprintf("copy dt to '%s' (format parquet)", gsub("\\\\", "/", pq)))
  n <- dbGetQuery(con, sprintf("select count(*) n from '%s'", gsub("\\\\", "/", pq)))$n
  cc <- dbGetQuery(con, "select 'ab' || 'cd' as s")$s   # || not +
  dbDisconnect(con, shutdown = TRUE)
  paste0("rows=", format(n, scientific = FALSE), " concat=", cc)
})

chk("fixest high-dim FE regression", function() {
  library(fixest)
  set.seed(0); n <- 20000
  d <- data.frame(id = factor(sample(200, n, TRUE)), yr = factor(sample(10, n, TRUE)),
                  x = rnorm(n))
  d$y <- 1.5 * d$x + rnorm(n)
  m <- feols(y ~ x | id + yr, data = d)
  paste0("beta_x=", format(round(unname(coef(m)["x"]), 4), scientific = FALSE))
})

chk("tidymodels fit", function() {
  suppressPackageStartupMessages(library(tidymodels))
  set.seed(0)
  d <- data.frame(x1 = rnorm(600), x2 = rnorm(600))
  d$y <- as.factor(ifelse(d$x1 + d$x2 + rnorm(600) > 0, "pos", "neg"))
  fit <- logistic_reg() |> set_engine("glm") |> fit(y ~ x1 + x2, data = d)
  acc <- mean(predict(fit, d)$.pred_class == d$y)
  paste0("accuracy=", format(round(acc, 4), scientific = FALSE))
})

chk("ranger + yardstick", function() {
  library(ranger)
  set.seed(0); n <- 2000
  d <- data.frame(x1 = rnorm(n), x2 = rnorm(n)); d$y <- d$x1 * 2 + d$x2 + rnorm(n)
  m <- ranger(y ~ ., data = d, num.trees = 100, seed = 0)
  paste0("r2=", format(round(1 - m$prediction.error / var(d$y), 4), scientific = FALSE))
})

chk("time series: fable forecast", function() {
  suppressPackageStartupMessages({library(tsibble); library(fable); library(dplyr)})
  set.seed(0)
  ts <- tsibble(t = 1:120, y = 10 + sin(seq_len(120)/6) * 3 + rnorm(120, 0, .4), index = t)
  fc <- ts |> model(ar = ARIMA(y)) |> forecast(h = 6)
  paste0("horizons=", format(nrow(fc), scientific = FALSE))
})

chk("quantmod/PerformanceAnalytics loadable", function() {
  suppressPackageStartupMessages({library(xts); library(PerformanceAnalytics)})
  set.seed(0)
  r <- xts(rnorm(250, 0.0004, 0.01), order.by = Sys.Date() - 250:1)
  paste0("sharpe=", format(round(as.numeric(SharpeRatio.annualized(r)), 4),
                           scientific = FALSE))
})

chk("reticulate -> project venv", function() {
  Sys.setenv(RETICULATE_PYTHON = "C:/work/envs/ds/Scripts/python.exe")
  library(reticulate)
  cfg <- py_config()
  if (!grepl("work/envs/ds|work\\envs\\ds", cfg$python, fixed = FALSE))
    stop(paste("reticulate bound to the wrong interpreter:", cfg$python))
  paste0("python=", cfg$version)
})

chk("duckdb loaded FIRST, then pyarrow via reticulate", function() {
  library(reticulate)
  pa <- import("pyarrow")
  pl <- import("polars")
  paste0("pyarrow=", pa$`__version__`, " polars=", pl$`__version__`)
})

rep <- do.call(rbind, res)
cat(sprintf("%-42s %-6s %s\n", "CHECK", "RESULT", "DETAIL"))
for (i in seq_len(nrow(rep)))
  cat(sprintf("%-42s %-6s %s\n", rep$check[i], rep$status[i], rep$detail[i]))
np <- sum(rep$status == "PASS")
cat(sprintf("\nPASS %s / %s\n", format(np, scientific = FALSE),
            format(nrow(rep), scientific = FALSE)))
utils::write.csv(rep, "C:/work/logs/R_acceptance.csv", row.names = FALSE)
if (np != nrow(rep)) quit(status = 1)
