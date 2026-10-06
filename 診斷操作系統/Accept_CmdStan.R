# Acceptance for cmdstanr: compile a real Stan model and fit it, then check the
# posterior actually recovers the parameter. Installing is not passing.
options(repos = c(stan = "https://stan-dev.r-universe.dev",
                  CRAN = "https://cloud.r-project.org"))
library(cmdstanr)
cmdstanr::set_cmdstan_path("C:/work/cmdstan/cmdstan-2.40.0")
cat("cmdstan:", cmdstan_version(), "at", cmdstan_path(), "\n")

code <- '
data {
  int<lower=0> N;
  vector[N] y;
}
parameters {
  real mu;
  real<lower=0> sigma;
}
model {
  mu ~ normal(0, 10);
  sigma ~ exponential(1);
  y ~ normal(mu, sigma);
}
'
f <- file.path("C:/work/cmdstan", "accept_model.stan")
writeLines(code, f)

cat("compiling...\n")
mod <- cmdstan_model(f, quiet = TRUE)
cat("compiled ->", mod$exe_file(), "\n")

set.seed(0)
y <- rnorm(400, mean = 3.5, sd = 1.2)
fit <- mod$sample(data = list(N = length(y), y = y),
                  chains = 2, parallel_chains = 2,
                  iter_warmup = 400, iter_sampling = 600,
                  seed = 0, refresh = 0, show_messages = FALSE)

s  <- fit$summary(c("mu", "sigma"))
mu <- s$mean[s$variable == "mu"]
sg <- s$mean[s$variable == "sigma"]
rh <- max(s$rhat, na.rm = TRUE)

cat("posterior mu   =", format(round(mu, 4), scientific = FALSE), " (true 3.5)\n")
cat("posterior sigma=", format(round(sg, 4), scientific = FALSE), " (true 1.2)\n")
cat("max rhat       =", format(round(rh, 4), scientific = FALSE), "\n")

ok <- abs(mu - 3.5) < 0.2 && abs(sg - 1.2) < 0.2 && rh < 1.05
cat("RESULT:", if (ok) "PASS" else "FAIL", "\n")
if (!ok) quit(status = 1)
