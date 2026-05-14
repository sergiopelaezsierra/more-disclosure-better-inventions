# ============================================================================
# run_all.R — run every paper-output script in order, log to outputs/logs/.
#
# Usage:
#   Rscript code/03_paper_outputs/run_all.R
#
# Or from inside R:
#   source("code/03_paper_outputs/run_all.R")
#
# Each script is executed in its own R subprocess so package loads and
# global state stay isolated. The script's stdout/stderr are tee'd to a
# per-script log file under outputs/logs/.
# ============================================================================

# --- Locate the package root and load shared helpers --------------------
.args <- commandArgs(trailingOnly = FALSE)
.this <- sub("^--file=", "", .args[grep("^--file=", .args)[1]])
if (is.na(.this) || !nzchar(.this)) .this <- sys.frame(1)$ofile
source(file.path(dirname(.this), "..", "_helpers", "setup.R"))

scripts <- list.files(
  file.path(REPL_PACKAGE_ROOT, "code", "03_paper_outputs"),
  pattern = "^03[a-z]_.*\\.R$",
  full.names = TRUE
)
scripts <- scripts[!grepl("run_all", scripts)]
scripts <- sort(scripts)

cat(sprintf("Running %d paper-output scripts\n", length(scripts)))

rscript_bin <- file.path(R.home("bin"), if (.Platform$OS.type == "windows")
  "Rscript.exe" else "Rscript")

results <- data.frame(script = character(), status = character(),
                      seconds = numeric(), log = character(),
                      stringsAsFactors = FALSE)

for (s in scripts) {
  base <- tools::file_path_sans_ext(basename(s))
  log_path <- file.path(OUT_LOGS_DIR, paste0(base, ".log"))
  cat(sprintf("\n[%s] -> %s\n", base, log_path))

  t0 <- Sys.time()
  status <- system2(rscript_bin, args = shQuote(s),
                    stdout = log_path, stderr = log_path)
  t1 <- Sys.time()

  results <- rbind(results, data.frame(
    script = base, status = ifelse(status == 0, "OK", "FAIL"),
    seconds = round(as.numeric(difftime(t1, t0, units = "secs")), 1),
    log = log_path, stringsAsFactors = FALSE
  ))

  cat(sprintf("  -> %s in %.1fs\n", ifelse(status == 0, "OK", "FAIL"),
              as.numeric(difftime(t1, t0, units = "secs"))))
}

cat("\nSummary:\n")
print(results, row.names = FALSE)
ok <- sum(results$status == "OK")
cat(sprintf("\n%d / %d scripts succeeded.\n", ok, nrow(results)))

if (ok < nrow(results)) quit(save = "no", status = 1)
