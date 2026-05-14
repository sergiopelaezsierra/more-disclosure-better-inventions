# ============================================================================
# Table 4 — Main LPM regressions (progressive specifications)
# ----------------------------------------------------------------------------
# Estimates the linear probability model:
#   disclosed_i = a + b1*CP_i + b2*Post2022_i + b3*CP_i*Post2022_i
#                 + controls + FEs + e_i
# in 5 progressive columns:
#   I   : CP only
#   II  : CP + Post-2022 indicator
#   III : CP * Post-2022 (interaction added)
#   IV  : III + controls + field FE + journal FE
#   V   : IV + year FE
#
# All standard errors are robust (HC1).
#
# Outputs:
#   outputs/tables/table4_main_lpm.csv  — formatted table for the manuscript
#   outputs/tables/table4_main_lpm_raw.csv — coefficients & SEs by model
# ============================================================================

# --- Locate the package root and load shared helpers --------------------
.args <- commandArgs(trailingOnly = FALSE)
.this <- sub("^--file=", "", .args[grep("^--file=", .args)[1]])
if (is.na(.this) || !nzchar(.this)) .this <- sys.frame(1)$ofile
source(file.path(dirname(.this), "..", "_helpers", "setup.R"))
source(file.path(HELPERS_DIR, "load_analytical_data.R"))

suppressPackageStartupMessages({
  library(dplyr)
  library(fixest)
  library(sandwich)
  library(lmtest)
})

# --- Load and prepare ----------------------------------------------------
d <- load_publication_level()

cat(sprintf("Estimation sample: %s publications (%d unique journals)\n",
            format(nrow(d), big.mark = ","), n_distinct(d$journal)))

# --- Estimate models -----------------------------------------------------
# Columns I-III use plain OLS with HC1 robust SEs.
# Columns IV-V use fixest with absorbed field/journal/year FEs.

m1 <- lm(disclosed ~ commercial_potential_score, data = d)
m2 <- lm(disclosed ~ commercial_potential_score + post_2022, data = d)
m3 <- lm(disclosed ~ commercial_potential_score * post_2022, data = d)

m4 <- feols(
  disclosed ~ commercial_potential_score * post_2022 +
    author_count + cited_ref_count + has_funding |
    field_consolidated + journal,
  data = d, vcov = "HC1"
)

m5 <- feols(
  disclosed ~ commercial_potential_score +
    commercial_potential_score:post_2022 +
    author_count + cited_ref_count + has_funding |
    field_consolidated + journal + pub_fiscal_year,
  data = d, vcov = "HC1"
)

# --- Extract coefficient tables with HC1 SEs -----------------------------
get_ols_hc1 <- function(model) {
  ct <- coeftest(model, vcov = vcovHC(model, type = "HC1"))
  data.frame(
    term     = rownames(ct),
    estimate = ct[, "Estimate"],
    std_err  = ct[, "Std. Error"],
    p_value  = ct[, "Pr(>|t|)"],
    row.names = NULL, stringsAsFactors = FALSE
  )
}

get_feols_hc1 <- function(model) {
  ct <- summary(model)$coeftable
  data.frame(
    term     = rownames(ct),
    estimate = ct[, "Estimate"],
    std_err  = ct[, "Std. Error"],
    p_value  = ct[, ncol(ct)],   # last column is p-value
    row.names = NULL, stringsAsFactors = FALSE
  )
}

c1 <- get_ols_hc1(m1)
c2 <- get_ols_hc1(m2)
c3 <- get_ols_hc1(m3)
c4 <- get_feols_hc1(m4)
c5 <- get_feols_hc1(m5)

# --- Build the formatted Table 4 -----------------------------------------
star <- function(p) {
  if (is.na(p)) "" else
  if (p < 0.001) "***" else
  if (p < 0.01)  "**"  else
  if (p < 0.05)  "*"   else ""
}

cell <- function(coef_df, term) {
  r <- coef_df[coef_df$term == term, , drop = FALSE]
  if (nrow(r) == 0) return(c("", ""))
  c(sprintf("%.4f%s", r$estimate, star(r$p_value)),
    sprintf("(%.4f)",  r$std_err))
}

# Helper: get the CP slope when Post-2022 = 1 (= b1 + b3 from the interaction)
cp_effect_post <- function(model, vcv = NULL) {
  if (inherits(model, "fixest")) {
    co <- coef(model)
    vc <- vcov(model)
  } else {
    co <- coef(model)
    vc <- if (!is.null(vcv)) vcv else vcovHC(model, type = "HC1")
  }
  b1 <- co["commercial_potential_score"]
  b3_name <- intersect(
    c("commercial_potential_score:post_2022", "post_2022:commercial_potential_score"),
    names(co)
  )
  if (length(b3_name) == 0) return(c("", ""))
  b3 <- co[b3_name]
  est <- unname(b1 + b3)
  var <- vc["commercial_potential_score", "commercial_potential_score"] +
         vc[b3_name, b3_name] +
         2 * vc["commercial_potential_score", b3_name]
  se <- sqrt(var)
  z <- est / se
  p <- 2 * pnorm(-abs(z))
  c(sprintf("%.4f%s", est, star(p)),
    sprintf("(%.4f)", se))
}

rows_spec <- list(
  list(label = "Constant",                  term = "(Intercept)"),
  list(label = "Commercial Potential (CP)", term = "commercial_potential_score"),
  list(label = "Post-2022",                 term = "post_2022"),
  list(label = "CP × Post-2022",
       term  = c("commercial_potential_score:post_2022",
                 "post_2022:commercial_potential_score")),
  list(label = "Author Count",              term = "author_count"),
  list(label = "Cited Reference Count",     term = "cited_ref_count"),
  list(label = "Has Funding",               term = "has_funding")
)

table_rows <- list()
for (row in rows_spec) {
  terms <- row$term
  cells <- list()
  for (cdf in list(c1, c2, c3, c4, c5)) {
    found <- intersect(terms, cdf$term)
    cells[[length(cells) + 1]] <- if (length(found) > 0) cell(cdf, found[1]) else c("", "")
  }
  coef_row <- c(row$label, sapply(cells, `[`, 1))
  se_row   <- c("",        sapply(cells, `[`, 2))
  table_rows[[length(table_rows) + 1]] <- coef_row
  table_rows[[length(table_rows) + 1]] <- se_row
}

# CP effect by period
cp_pre <- list(
  cell(c1, "commercial_potential_score"),
  cell(c2, "commercial_potential_score"),
  cell(c3, "commercial_potential_score"),
  cell(c4, "commercial_potential_score"),
  cell(c5, "commercial_potential_score")
)
cp_post <- list(
  c("", ""), c("", ""),
  cp_effect_post(m3),
  cp_effect_post(m4),
  cp_effect_post(m5)
)

table_rows[[length(table_rows) + 1]] <- c("CP Effect (Pre-2022)",  sapply(cp_pre,  `[`, 1))
table_rows[[length(table_rows) + 1]] <- c("",                       sapply(cp_pre,  `[`, 2))
table_rows[[length(table_rows) + 1]] <- c("CP Effect (Post-2022)", sapply(cp_post, `[`, 1))
table_rows[[length(table_rows) + 1]] <- c("",                       sapply(cp_post, `[`, 2))

fe_rows <- list(
  c("Field FE",   "No", "No", "No", "Yes", "Yes"),
  c("Journal FE", "No", "No", "No", "Yes", "Yes"),
  c("Year FE",    "No", "No", "No", "No",  "Yes")
)

n_obs <- function(m) format(nobs(m), big.mark = ",")
r2_of <- function(m) {
  if (inherits(m, "fixest")) sprintf("%.4f", fixest::r2(m, "r2"))
  else                       sprintf("%.4f", summary(m)$r.squared)
}

stat_rows <- list(
  c("Observations", n_obs(m1), n_obs(m2), n_obs(m3), n_obs(m4), n_obs(m5)),
  c("R-squared",    r2_of(m1), r2_of(m2), r2_of(m3), r2_of(m4), r2_of(m5))
)

table4 <- do.call(rbind, c(table_rows, fe_rows, stat_rows))
colnames(table4) <- c("Variable", "(I)", "(II)", "(III)", "(IV)", "(V)")
table4 <- as.data.frame(table4, stringsAsFactors = FALSE)

# --- Save and print ------------------------------------------------------
out_main <- file.path(OUT_TABLES_DIR, "table4_main_lpm.csv")
write.csv(table4, out_main, row.names = FALSE)

# Raw coefficient dump (one row per term × model, for audit)
raw <- bind_rows(
  mutate(c1, model = "I"),   mutate(c2, model = "II"),
  mutate(c3, model = "III"), mutate(c4, model = "IV"),
  mutate(c5, model = "V")
) %>% select(model, term, estimate, std_err, p_value)
write.csv(raw, file.path(OUT_TABLES_DIR, "table4_main_lpm_raw.csv"), row.names = FALSE)

cat("\nTable 4 — Effect of commercial potential on disclosure probability\n")
cat("Dependent variable: Disclosed (0/1). LPM. Robust HC1 SEs in parentheses.\n\n")
print(knitr::kable(table4, align = c("l", rep("r", 5))))
cat(sprintf("\nSaved: %s\n", out_main))
cat(sprintf("Saved: %s\n", file.path(OUT_TABLES_DIR, "table4_main_lpm_raw.csv")))
