# ============================================================================
# Figure 7 — Field-specific CP × Post-2022 interaction effects
# ----------------------------------------------------------------------------
# Estimates a three-way interaction LPM
#     disclosed ~ CP * Post-2022 * Field + controls | journal + pub_fiscal_year
# and extracts the CP × Post-2022 effect for each broad field (relative to
# the reference field, which is the most populous one — Engineering). The
# combined effect for each non-reference field is base coefficient plus the
# three-way interaction; its standard error is obtained via the delta method
# using the model's HC1 robust variance-covariance matrix.
#
# A joint Wald test on the three-way interaction terms tests whether the
# CP × Post-2022 effect differs significantly across fields.
#
# Outputs:
#   outputs/figures/figure7_field_heterogeneity.png
#   outputs/tables/figure7_field_heterogeneity.csv
# ============================================================================

# --- Locate the package root and load shared helpers --------------------
.args <- commandArgs(trailingOnly = FALSE)
.this <- sub("^--file=", "", .args[grep("^--file=", .args)[1]])
if (is.na(.this) || !nzchar(.this)) .this <- sys.frame(1)$ofile
source(file.path(dirname(.this), "..", "_helpers", "setup.R"))
source(file.path(HELPERS_DIR, "load_analytical_data.R"))

suppressPackageStartupMessages({
  library(dplyr)
  library(forcats)
  library(ggplot2)
  library(fixest)
  library(car)
})

# --- Load and prepare ----------------------------------------------------
# Figure 7 uses the FIELD_SHORT mapping (not field_consolidated) so all
# broad fields are present, including the smaller ones. Reference field is
# the largest one in the sample (Engineering).
d <- load_publication_level()

ref_field <- d %>% count(field_short, sort = TRUE) %>% slice(1) %>% pull(field_short)
cat(sprintf("Reference field (largest): %s\n", ref_field))

d <- d %>% mutate(field_short = relevel(factor(field_short), ref = ref_field))

# --- Estimate three-way interaction model -------------------------------
m <- feols(
  disclosed ~ commercial_potential_score * post_2022 * field_short +
    cited_ref_count + author_count + has_funding |
    journal + pub_fiscal_year,
  data = d, vcov = "HC1"
)

cat(sprintf("Observations: %s, adj. R-sq: %.4f\n",
            format(nobs(m), big.mark = ","), fixest::r2(m, "ar2")))

co <- coef(m)
vc <- vcov(m)

# --- Field-specific CP × Post-2022 effects ------------------------------
fields <- levels(d$field_short)

compute_field_effect <- function(field) {
  if (field == ref_field) {
    nm <- "commercial_potential_score:post_2022"
    if (!nm %in% names(co)) return(NULL)
    est <- unname(co[nm])
    se  <- sqrt(vc[nm, nm])
  } else {
    base <- "commercial_potential_score:post_2022"
    inter <- paste0("commercial_potential_score:post_2022:field_short", field)
    if (!(base %in% names(co)) || !(inter %in% names(co))) return(NULL)
    est <- unname(co[base] + co[inter])
    se  <- sqrt(vc[base, base] + vc[inter, inter] +
                  2 * vc[base, inter])
  }
  z  <- est / se
  p  <- 2 * pnorm(-abs(z))
  data.frame(field = field, estimate = est, std_err = se, p_value = p,
             ci_lower = est - 1.96 * se, ci_upper = est + 1.96 * se,
             significant = ifelse(p < 0.05, "Yes", "No"),
             stringsAsFactors = FALSE)
}

effects <- do.call(rbind, lapply(fields, compute_field_effect))

# --- Joint Wald test ----------------------------------------------------
threeway <- grep("commercial_potential_score:post_2022:field_short",
                 names(co), value = TRUE)

wald <- car::linearHypothesis(m, threeway, vcov = vc)
wald_F <- wald$F[2]
wald_p <- wald$`Pr(>F)`[2]
if (is.null(wald_F) || is.na(wald_F)) {
  # Older car versions return Chisq instead of F
  wald_F <- wald$Chisq[2]
  wald_p <- wald$`Pr(>Chisq)`[2]
}

cat(sprintf("\nJoint Wald test (H0: CP×Post-2022 effects equal across fields):\n"))
cat(sprintf("  Statistic: %.4f\n", wald_F))
cat(sprintf("  p-value:   %.4f\n", wald_p))
if (wald_p > 0.05) {
  cat("  -> Cannot reject the null of equality across fields.\n")
} else {
  cat("  -> Reject equality: at least one field's effect differs.\n")
}

# --- Save and print -----------------------------------------------------
write.csv(effects,
          file.path(OUT_TABLES_DIR, "figure7_field_heterogeneity.csv"),
          row.names = FALSE)

cat("\nField-specific CP × Post-2022 interaction coefficients:\n")
print(effects %>% arrange(desc(estimate)) %>%
        mutate(coef = sprintf("%.4f", estimate),
               se   = sprintf("(%.4f)", std_err),
               p    = sprintf("%.4f", p_value)) %>%
        select(field, coef, se, p, significant))

# --- Plot ---------------------------------------------------------------
plot_df <- effects %>% mutate(field = fct_reorder(field, estimate))

p <- ggplot(plot_df, aes(x = estimate, y = field)) +
  geom_vline(xintercept = 0, linetype = "dashed",
             color = "gray50", linewidth = 0.8) +
  geom_errorbarh(aes(xmin = ci_lower, xmax = ci_upper, color = significant),
                 height = 0.3, linewidth = 1) +
  geom_point(aes(color = significant), size = 3.5) +
  scale_color_manual(values = c("No" = "gray60", "Yes" = "#D95F02"),
                     name = "Significant at p<0.05") +
  labs(x = "CP × Post-2022 interaction coefficient", y = NULL) +
  theme_minimal(base_size = 14) +
  theme(
    axis.title.x = element_text(face = "bold"),
    axis.text.y  = element_text(size = 11),
    legend.position = "top",
    legend.title = element_text(face = "bold"),
    panel.grid.major.y = element_blank(),
    panel.grid.major.x = element_line(color = "gray85"),
    plot.background = element_rect(fill = "white", color = NA)
  )

fig_path <- file.path(OUT_FIGURES_DIR, "figure7_field_heterogeneity.png")
ggsave(fig_path, plot = p, width = 9, height = 6, dpi = 300, bg = "white")
cat(sprintf("\nSaved figure: %s\n", fig_path))
cat(sprintf("Saved data:   %s\n",
            file.path(OUT_TABLES_DIR, "figure7_field_heterogeneity.csv")))
