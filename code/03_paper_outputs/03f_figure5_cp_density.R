# ============================================================================
# Figure 5 — Density distribution of commercial potential score
# ----------------------------------------------------------------------------
# Overlaid kernel-density estimates of the commercial-potential score for
# disclosed vs. undisclosed publications. One panel only (the published
# figure corresponds to Panel A of the original analysis; the period-by-
# period panels in the original script are not in the manuscript).
#
# Output:
#   outputs/figures/figure5_cp_density.png
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
  library(scales)
})

# --- Load ----------------------------------------------------------------
d <- load_publication_level()

sample_sizes <- d %>%
  group_by(disclosed) %>%
  summarise(n = n(), .groups = "drop")

legend_labels <- c(
  paste0("Not disclosed (n = ",
         comma(sample_sizes$n[sample_sizes$disclosed == 0]), ")"),
  paste0("Disclosed (n = ",
         comma(sample_sizes$n[sample_sizes$disclosed == 1]), ")")
)

cat("Sample sizes:\n")
print(sample_sizes)

# --- Plot ---------------------------------------------------------------
p <- ggplot(d, aes(x = commercial_potential_score,
                   fill = factor(disclosed))) +
  geom_density(alpha = 0.5, adjust = 1.5) +
  scale_fill_viridis_d(option = "D", begin = 0.3, end = 0.7,
                       name = "Status", labels = legend_labels) +
  labs(x = "Commercial potential score", y = "Density") +
  theme_minimal(base_size = 16) +
  theme(
    axis.text  = element_text(size = 14),
    axis.title = element_text(size = 16, face = "bold"),
    legend.text = element_text(size = 12),
    legend.title = element_text(size = 14, face = "bold"),
    legend.position = c(0.35, 0.85),
    legend.background = element_rect(fill = "white", color = NA),
    plot.background = element_rect(fill = "white", color = NA)
  ) +
  scale_x_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.25))

fig_path <- file.path(OUT_FIGURES_DIR, "figure5_cp_density.png")
ggsave(fig_path, plot = p, width = 9, height = 5, dpi = 300, bg = "white")
cat(sprintf("\nSaved figure: %s\n", fig_path))
