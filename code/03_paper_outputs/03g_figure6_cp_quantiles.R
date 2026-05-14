# ============================================================================
# Figure 6 — Disclosure rates by commercial-potential quantile × period
# ----------------------------------------------------------------------------
# Grouped bar chart: three CP quantile bins (Bottom 10%, Middle 80%, Top 10%)
# × two periods (Pre-2022 = FY2019-FY2022, Post-2022 = FY2023-FY2025).
# Quantile cuts are computed on the full publication-level sample.
#
# Output:
#   outputs/figures/figure6_cp_quantiles.png
#   outputs/tables/figure6_cp_quantiles.csv  (the underlying counts and rates)
# ============================================================================

# --- Locate the package root and load shared helpers --------------------
.args <- commandArgs(trailingOnly = FALSE)
.this <- sub("^--file=", "", .args[grep("^--file=", .args)[1]])
if (is.na(.this) || !nzchar(.this)) .this <- sys.frame(1)$ofile
source(file.path(dirname(.this), "..", "_helpers", "setup.R"))
source(file.path(HELPERS_DIR, "load_analytical_data.R"))

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

# --- Load ----------------------------------------------------------------
d <- load_publication_level()

q10 <- quantile(d$commercial_potential_score, 0.10, na.rm = TRUE)
q90 <- quantile(d$commercial_potential_score, 0.90, na.rm = TRUE)

panel <- d %>%
  mutate(
    cp_group = case_when(
      commercial_potential_score <= q10 ~ "Bottom 10%",
      commercial_potential_score >= q90 ~ "Top 10%",
      TRUE                              ~ "Middle 80%"
    ),
    cp_group = factor(cp_group,
                      levels = c("Bottom 10%", "Middle 80%", "Top 10%")),
    period   = factor(ifelse(post_2022 == 1, "Post-2022", "Pre-2022"),
                      levels = c("Pre-2022", "Post-2022"))
  )

agg <- panel %>%
  group_by(cp_group, period) %>%
  summarise(
    n_total       = n(),
    n_disclosed   = sum(disclosed),
    pct_disclosed = 100 * mean(disclosed),
    .groups = "drop"
  )

cat("Disclosure rates by CP quantile and period:\n")
print(as.data.frame(agg))

# --- Save underlying counts ---------------------------------------------
write.csv(agg, file.path(OUT_TABLES_DIR, "figure6_cp_quantiles.csv"),
          row.names = FALSE)

# --- Plot ---------------------------------------------------------------
p <- ggplot(agg, aes(x = cp_group, y = pct_disclosed, fill = period)) +
  geom_col(position = position_dodge(width = 0.8), alpha = 0.9, width = 0.7) +
  geom_text(aes(label = sprintf("%.1f%%", pct_disclosed)),
            position = position_dodge(width = 0.8),
            vjust = -0.3, size = 5, fontface = "bold") +
  scale_fill_manual(values = c("Pre-2022" = "#2C5F8D", "Post-2022" = "#D95F02"),
                    name = "Period") +
  labs(x = "Commercial potential quantile",
       y = "Disclosure rate (%)") +
  theme_minimal(base_size = 16) +
  theme(
    axis.title = element_text(size = 18, face = "bold"),
    axis.text  = element_text(size = 16),
    legend.title = element_text(size = 16, face = "bold"),
    legend.text  = element_text(size = 14),
    legend.position = "top",
    panel.grid.major.y = element_line(color = "gray80"),
    panel.grid.major.x = element_blank(),
    plot.background = element_rect(fill = "white", color = NA)
  ) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.12)),
                     breaks = seq(0, 50, 5))

fig_path <- file.path(OUT_FIGURES_DIR, "figure6_cp_quantiles.png")
ggsave(fig_path, plot = p, width = 11, height = 6, dpi = 300, bg = "white")
cat(sprintf("\nSaved figure: %s\n", fig_path))
cat(sprintf("Saved data:   %s\n",
            file.path(OUT_TABLES_DIR, "figure6_cp_quantiles.csv")))
