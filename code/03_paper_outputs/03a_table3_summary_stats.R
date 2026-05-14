# ============================================================================
# Table 3 — Summary statistics
# ----------------------------------------------------------------------------
# Reproduces the "Summary statistics" table in the manuscript: means and
# standard deviations for the analytical variables, computed over the full
# sample and the disclosed/undisclosed and pre/post-2022 subsamples.
#
# Output:
#   outputs/tables/table3_summary_stats.csv
# ============================================================================

# --- Locate the package root and load shared helpers --------------------
.args <- commandArgs(trailingOnly = FALSE)
.this <- sub("^--file=", "", .args[grep("^--file=", .args)[1]])
if (is.na(.this) || !nzchar(.this)) .this <- sys.frame(1)$ofile
source(file.path(dirname(.this), "..", "_helpers", "setup.R"))
source(file.path(HELPERS_DIR, "load_analytical_data.R"))

suppressPackageStartupMessages({
  library(dplyr)
  library(knitr)
})

# --- Load ----------------------------------------------------------------
d <- load_publication_level()

# --- Build subsamples ----------------------------------------------------
samp <- list(
  Full          = d,
  Disclosed     = filter(d, disclosed == 1),
  Not_Disclosed = filter(d, disclosed == 0),
  Pre_2022      = filter(d, post_2022 == 0),
  Post_2022     = filter(d, post_2022 == 1)
)

# --- Format mean (sd) ----------------------------------------------------
fmt_mean_sd <- function(x) {
  m <- mean(x, na.rm = TRUE)
  s <- sd(x,   na.rm = TRUE)
  sprintf("%.3f (%.3f)", m, s)
}

vars <- list(
  list(col = "commercial_potential_score", label = "Commercial Potential Score"),
  list(col = "disclosed",                  label = "Disclosed = 1"),
  list(col = "cited_ref_count",            label = "Cited Reference Count"),
  list(col = "log_times_cited_all",        label = "Log(Times Cited)"),
  list(col = "author_count",               label = "Author Count"),
  list(col = "has_funding",                label = "Has Funding = 1")
)

rows <- lapply(vars, function(v) {
  data.frame(
    Variable      = v$label,
    Full_Sample   = fmt_mean_sd(samp$Full[[v$col]]),
    Disclosed     = fmt_mean_sd(samp$Disclosed[[v$col]]),
    Not_Disclosed = fmt_mean_sd(samp$Not_Disclosed[[v$col]]),
    Pre_2022      = fmt_mean_sd(samp$Pre_2022[[v$col]]),
    Post_2022     = fmt_mean_sd(samp$Post_2022[[v$col]]),
    stringsAsFactors = FALSE
  )
})
tbl <- do.call(rbind, rows)

n_row <- data.frame(
  Variable      = "N",
  Full_Sample   = format(nrow(samp$Full),          big.mark = ","),
  Disclosed     = format(nrow(samp$Disclosed),     big.mark = ","),
  Not_Disclosed = format(nrow(samp$Not_Disclosed), big.mark = ","),
  Pre_2022      = format(nrow(samp$Pre_2022),      big.mark = ","),
  Post_2022     = format(nrow(samp$Post_2022),     big.mark = ","),
  stringsAsFactors = FALSE
)
tbl <- rbind(n_row, tbl)
colnames(tbl) <- c("Variable", "Full Sample", "Disclosed", "Not Disclosed",
                   "Pre-2022", "Post-2022")

# --- Save and print ------------------------------------------------------
out_path <- file.path(OUT_TABLES_DIR, "table3_summary_stats.csv")
write.csv(tbl, out_path, row.names = FALSE)

cat("Table 3 — Summary statistics\n")
cat("Unit of observation: publication\n\n")
print(knitr::kable(tbl, align = c("l", rep("r", 5)), row.names = FALSE))
cat(sprintf("\nSaved: %s\n", out_path))
