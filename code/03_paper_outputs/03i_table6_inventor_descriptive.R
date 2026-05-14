# ============================================================================
# Table 6 — Inventor-level descriptive 2 x 2 x 2
# ----------------------------------------------------------------------------
# Disclosure rates by Star × High-CP × Prior-disclosure × Period (pre vs post
# 2022). Panel A covers researchers who had never disclosed before 2022
# (extensive margin). Panel B covers researchers who had disclosed at least
# once before 2022 (intensive margin).
#
# Output:
#   outputs/tables/table6_inventor_descriptive.csv
# ============================================================================

# --- Locate the package root and load shared helpers --------------------
.args <- commandArgs(trailingOnly = FALSE)
.this <- sub("^--file=", "", .args[grep("^--file=", .args)[1]])
if (is.na(.this) || !nzchar(.this)) .this <- sys.frame(1)$ofile
source(file.path(dirname(.this), "..", "_helpers", "setup.R"))
source(file.path(HELPERS_DIR, "load_analytical_data.R"))
source(file.path(HELPERS_DIR, "build_inventor_panel.R"))

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(knitr)
})

# --- Build the inventor-year panel --------------------------------------
# Use the looser inventor-panel loader (no covariate filters) so the
# researcher counts match the paper's Section 5.4 sample.
d <- load_publication_for_inventor_panel()
inv <- build_inventor_panel(d)

cat(sprintf("Star (top 10%% citations) threshold: %.0f total citations\n",
            inv$citation_p90))
cat(sprintf("High-CP (top 25%%) threshold: %.3f avg CP score\n", inv$cp_p75))

panel <- inv$panel

# --- 2 x 2 x 2 cell builder ----------------------------------------------
make_cells <- function(panel_df, group_filter, label_for) {
  panel_df %>%
    filter(group_filter(.)) %>%
    mutate(period = ifelse(post_2022 == 1, "Post-2022", "Pre-2022")) %>%
    group_by(star, high_cp, period) %>%
    summarise(
      n_inventors   = n_distinct(inventor_name),
      avg_disc_rate = mean(disclosure_rate, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    pivot_wider(names_from = period,
                values_from = c(n_inventors, avg_disc_rate)) %>%
    transmute(
      panel       = label_for,
      star_status = ifelse(star,   "Star",    "Non-star"),
      cp_group    = ifelse(high_cp, "High CP", "Lower CP"),
      n           = `n_inventors_Pre-2022`,
      pre_rate    = `avg_disc_rate_Pre-2022`,
      post_rate   = `avg_disc_rate_Post-2022`,
      change_pp   = 100 * (post_rate - pre_rate)
    ) %>%
    arrange(desc(star_status == "Star"), desc(cp_group == "High CP"))
}

panelA <- make_cells(panel, function(d) !d$has_disclosed,
                     "A: Extensive (non-disclosers)")
panelB <- make_cells(panel, function(d) d$has_disclosed,
                     "B: Intensive (active disclosers)")

# --- Format combined table ----------------------------------------------
fmt <- function(df) df %>%
  mutate(
    n         = format(n, big.mark = ","),
    pre_rate  = sprintf("%.1f%%", 100 * pre_rate),
    post_rate = sprintf("%.1f%%", 100 * post_rate),
    change_pp = sprintf("%+.1f", change_pp)
  )

table6 <- bind_rows(fmt(panelA), fmt(panelB))
colnames(table6) <- c("Panel", "Star Status", "CP Group", "N",
                      "Pre-2022", "Post-2022", "Change (pp)")

# --- Save and print -----------------------------------------------------
out_path <- file.path(OUT_TABLES_DIR, "table6_inventor_descriptive.csv")
write.csv(table6, out_path, row.names = FALSE)

cat("\nTable 6 — Disclosure rates by star × CP × prior disclosure × period\n\n")
print(kable(table6, align = c("l", "l", "l", "r", "r", "r", "r"),
            row.names = FALSE))
cat(sprintf("\nSaved: %s\n", out_path))
