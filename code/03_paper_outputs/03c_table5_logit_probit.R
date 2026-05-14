# ============================================================================
# Table 5 — Robustness: LPM vs Logit (AMEs) vs Probit (AMEs)
# ----------------------------------------------------------------------------
# Compares the CP-on-disclosure effect across three functional-form
# specifications. Logit and probit average marginal effects (AMEs) are
# computed separately at Post-2022 = 0 and = 1, plus the difference
# (the interaction effect).
#
# Specifications:
#   LPM:        controls + field FE + journal FE + year FE  (HC1)
#   Logit:      controls + field FE                         (HC0/glm default)
#   Probit:     controls + field FE                         (HC0/glm default)
# Logit and probit omit journal FE due to the incidental-parameters problem
# in high-dimensional non-linear models, as noted in the paper.
#
# Outputs:
#   outputs/tables/table5_logit_probit.csv
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
  library(margins)
  library(sandwich)
  library(lmtest)
})

# --- Load ---------------------------------------------------------------
d <- load_publication_level()

# --- LPM (same Column V as Table 4) -------------------------------------
m_lpm <- feols(
  disclosed ~ commercial_potential_score +
    commercial_potential_score:post_2022 +
    author_count + cited_ref_count + has_funding |
    field_consolidated + journal + pub_fiscal_year,
  data = d, vcov = "HC1"
)

# LPM CP effects
lpm_b1   <- coef(m_lpm)["commercial_potential_score"]
lpm_b3   <- coef(m_lpm)["commercial_potential_score:post_2022"]
lpm_vc   <- vcov(m_lpm)
lpm_b1_se <- sqrt(lpm_vc["commercial_potential_score",
                         "commercial_potential_score"])
lpm_b3_se <- sqrt(lpm_vc["commercial_potential_score:post_2022",
                         "commercial_potential_score:post_2022"])
lpm_post  <- lpm_b1 + lpm_b3
lpm_post_se <- sqrt(
  lpm_vc["commercial_potential_score", "commercial_potential_score"] +
  lpm_vc["commercial_potential_score:post_2022",
         "commercial_potential_score:post_2022"] +
  2 * lpm_vc["commercial_potential_score",
             "commercial_potential_score:post_2022"]
)

lpm_r2 <- fixest::r2(m_lpm, "r2")

# --- Logit and Probit (field FE only, AMEs at Post-2022 = 0 / 1) --------
m_logit <- glm(
  disclosed ~ commercial_potential_score * post_2022 +
    cited_ref_count + author_count + has_funding + field_consolidated,
  data = d, family = binomial(link = "logit")
)
m_probit <- glm(
  disclosed ~ commercial_potential_score * post_2022 +
    cited_ref_count + author_count + has_funding + field_consolidated,
  data = d, family = binomial(link = "probit")
)

ames_for <- function(model) {
  ame_pre  <- summary(margins(model, variables = "commercial_potential_score",
                              at = list(post_2022 = 0)))
  ame_post <- summary(margins(model, variables = "commercial_potential_score",
                              at = list(post_2022 = 1)))
  list(
    pre_val  = ame_pre$AME[1],  pre_se  = ame_pre$SE[1],  pre_p  = ame_pre$p[1],
    post_val = ame_post$AME[1], post_se = ame_post$SE[1], post_p = ame_post$p[1]
  )
}

cat("Computing logit AMEs...\n");  a_logit  <- ames_for(m_logit)
cat("Computing probit AMEs...\n"); a_probit <- ames_for(m_probit)

# Difference (interaction effect): conservative SE = sqrt(SE_pre^2 + SE_post^2)
diff_meta <- function(a) {
  est <- a$post_val - a$pre_val
  se  <- sqrt(a$pre_se^2 + a$post_se^2)
  p   <- 2 * pnorm(-abs(est / se))
  list(est = est, se = se, p = p)
}
d_logit  <- diff_meta(a_logit)
d_probit <- diff_meta(a_probit)

# Logit/probit pseudo-R-squared
pseudo_r2 <- function(model) {
  1 - model$deviance / model$null.deviance
}

# --- Format the table ---------------------------------------------------
star <- function(p) {
  if (is.na(p)) "" else
  if (p < 0.001) "***" else
  if (p < 0.01)  "**"  else
  if (p < 0.05)  "*"   else ""
}

cell <- function(est, se, p) {
  c(sprintf("%.4f%s", est, star(p)),
    sprintf("(%.4f)",  se))
}

lpm_z_b1 <- lpm_b1 / lpm_b1_se
lpm_p_b1 <- 2 * pnorm(-abs(lpm_z_b1))
lpm_z_post <- lpm_post / lpm_post_se
lpm_p_post <- 2 * pnorm(-abs(lpm_z_post))
lpm_z_b3 <- lpm_b3 / lpm_b3_se
lpm_p_b3 <- 2 * pnorm(-abs(lpm_z_b3))

row_pre   <- c("Commercial Potential (Pre-2022)",
               cell(lpm_b1,     lpm_b1_se,   lpm_p_b1)[1],
               cell(a_logit$pre_val,  a_logit$pre_se,  a_logit$pre_p)[1],
               cell(a_probit$pre_val, a_probit$pre_se, a_probit$pre_p)[1])
row_pre_se <- c("",
                cell(lpm_b1,     lpm_b1_se,   lpm_p_b1)[2],
                cell(a_logit$pre_val,  a_logit$pre_se,  a_logit$pre_p)[2],
                cell(a_probit$pre_val, a_probit$pre_se, a_probit$pre_p)[2])

row_post   <- c("Commercial Potential (Post-2022)",
                cell(lpm_post,    lpm_post_se,   lpm_p_post)[1],
                cell(a_logit$post_val,  a_logit$post_se,  a_logit$post_p)[1],
                cell(a_probit$post_val, a_probit$post_se, a_probit$post_p)[1])
row_post_se <- c("",
                 cell(lpm_post,    lpm_post_se,   lpm_p_post)[2],
                 cell(a_logit$post_val,  a_logit$post_se,  a_logit$post_p)[2],
                 cell(a_probit$post_val, a_probit$post_se, a_probit$post_p)[2])

row_diff   <- c("Difference (Interaction Effect)",
                cell(lpm_b3,     lpm_b3_se,   lpm_p_b3)[1],
                cell(d_logit$est,  d_logit$se,  d_logit$p)[1],
                cell(d_probit$est, d_probit$se, d_probit$p)[1])
row_diff_se <- c("",
                 cell(lpm_b3,     lpm_b3_se,   lpm_p_b3)[2],
                 cell(d_logit$est,  d_logit$se,  d_logit$p)[2],
                 cell(d_probit$est, d_probit$se, d_probit$p)[2])

footer <- rbind(
  c("Controls",             "Yes", "Yes", "Yes"),
  c("Field FE",             "Yes", "Yes", "Yes"),
  c("Journal FE",           "Yes", "No",  "No"),
  c("Year FE",              "Yes", "No",  "No"),
  c("Observations",
    format(nobs(m_lpm),    big.mark = ","),
    format(nobs(m_logit),  big.mark = ","),
    format(nobs(m_probit), big.mark = ",")),
  c("R-squared / Pseudo R-squared",
    sprintf("%.4f", lpm_r2),
    sprintf("%.4f", pseudo_r2(m_logit)),
    sprintf("%.4f", pseudo_r2(m_probit)))
)

table5 <- rbind(
  row_pre,  row_pre_se,
  row_post, row_post_se,
  row_diff, row_diff_se,
  footer
)
colnames(table5) <- c("Variable: Disclosed = 1", "LPM", "Logit (AME)", "Probit (AME)")
rownames(table5) <- NULL

# --- Save and print -----------------------------------------------------
out_path <- file.path(OUT_TABLES_DIR, "table5_logit_probit.csv")
write.csv(table5, out_path, row.names = FALSE)

cat("\nTable 5 — LPM vs Logit (AME) vs Probit (AME)\n")
cat("HC1 robust SEs (LPM). AME standard errors via the delta method (margins).\n\n")
print(knitr::kable(table5, align = c("l", "r", "r", "r")))
cat(sprintf("\nSaved: %s\n", out_path))
