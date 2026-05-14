# ============================================================================
# Table 7 — Inventor-level disclosure regressions
# ----------------------------------------------------------------------------
# Two columns, both estimated with the same triple-interaction specification:
#   disclosure_rate ~ post_2022 * high_cp * star + mean_cp + n_pubs
#                     + factor(pub_year)
# Column (1) restricts the sample to researchers with zero pre-2022
# disclosures (extensive margin, N = 12,946). Column (2) restricts to
# researchers with > 0 pre-2022 disclosures (intensive margin, N = 3,354).
# Standard errors are HC1 robust.
#
# Output:
#   outputs/tables/table7_inventor_regressions.csv
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
  library(sandwich)
  library(lmtest)
  library(knitr)
})

# --- Build the inventor-year panel --------------------------------------
d   <- load_publication_for_inventor_panel()
inv <- build_inventor_panel(d)

panel_ext <- inv$panel %>% filter(!has_disclosed)
panel_int <- inv$panel %>% filter( has_disclosed)

cat(sprintf("Extensive-margin sample: %s obs, %s researchers\n",
            format(nrow(panel_ext), big.mark = ","),
            format(n_distinct(panel_ext$inventor_name), big.mark = ",")))
cat(sprintf("Intensive-margin sample: %s obs, %s researchers\n",
            format(nrow(panel_int), big.mark = ","),
            format(n_distinct(panel_int$inventor_name), big.mark = ",")))

# --- Estimate both columns ----------------------------------------------
specification <- disclosure_rate ~ post_2022 * high_cp * star +
                                   mean_cp + n_pubs + as.factor(pub_year)

m_ext <- lm(specification, data = panel_ext)
m_int <- lm(specification, data = panel_int)

ct_ext <- coeftest(m_ext, vcov = vcovHC(m_ext, type = "HC1"))
ct_int <- coeftest(m_int, vcov = vcovHC(m_int, type = "HC1"))

# --- Helper to format one cell ------------------------------------------
star_sym <- function(p) {
  if (is.na(p)) "" else
  if (p < 0.001) "***" else
  if (p < 0.01)  "**"  else
  if (p < 0.05)  "*"   else
  if (p < 0.10)  "†" else ""
}

cell <- function(ct, term) {
  if (!(term %in% rownames(ct))) return(c("", ""))
  c(sprintf("%.4f%s", ct[term, "Estimate"], star_sym(ct[term, "Pr(>|t|)"])),
    sprintf("(%.4f)", ct[term, "Std. Error"]))
}

# --- Build the formatted table ------------------------------------------
rows <- list(
  list(label = "Post-2022",                 term = "post_2022"),
  list(label = "High-CP",                   term = "high_cpTRUE"),
  list(label = "Star",                      term = "starTRUE"),
  list(label = "Post-2022 × High-CP",       term = "post_2022:high_cpTRUE"),
  list(label = "Post-2022 × Star",          term = "post_2022:starTRUE"),
  list(label = "High-CP × Star",            term = "high_cpTRUE:starTRUE"),
  list(label = "Post-2022 × Star × High-CP",term = "post_2022:high_cpTRUE:starTRUE"),
  list(label = "Commercial potential",      term = "mean_cp"),
  list(label = "Publications count",        term = "n_pubs")
)

table_body <- list()
for (r in rows) {
  ext <- cell(ct_ext, r$term)
  int <- cell(ct_int, r$term)
  table_body[[length(table_body) + 1]] <- c(r$label,           ext[1], int[1])
  table_body[[length(table_body) + 1]] <- c("",                ext[2], int[2])
}

footer <- list(
  c("Year fixed effects", "Yes", "Yes"),
  c("Observations",
    format(nobs(m_ext), big.mark = ","), format(nobs(m_int), big.mark = ",")),
  c("Researchers",
    format(n_distinct(panel_ext$inventor_name), big.mark = ","),
    format(n_distinct(panel_int$inventor_name), big.mark = ",")),
  c("R-squared",
    sprintf("%.4f", summary(m_ext)$r.squared),
    sprintf("%.4f", summary(m_int)$r.squared))
)

table7 <- do.call(rbind, c(table_body, footer))
colnames(table7) <- c("Variable", "(1) Extensive: non-disclosers",
                      "(2) Intensive: active disclosers")
rownames(table7) <- NULL

# --- Save and print -----------------------------------------------------
out_path <- file.path(OUT_TABLES_DIR, "table7_inventor_regressions.csv")
write.csv(table7, out_path, row.names = FALSE)

cat("\nTable 7 — Inventor-level disclosure regressions\n")
cat("Dependent variable: Disclosure rate (publications disclosed / publications)\n")
cat("Robust HC1 SEs in parentheses. *** p<0.001, ** p<0.01, * p<0.05, † p<0.10\n\n")
print(kable(table7, align = c("l", "r", "r"), row.names = FALSE))
cat(sprintf("\nSaved: %s\n", out_path))
