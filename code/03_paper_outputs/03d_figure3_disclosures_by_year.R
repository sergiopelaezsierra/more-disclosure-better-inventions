# ============================================================================
# Figure 3 — Number of disclosures by fiscal year
# ----------------------------------------------------------------------------
# Counts unique invention disclosures (invention_id_otl) by fiscal year of
# disclosure (fiscal_year.disc_otl). One bar per fiscal year FY2020-FY2025.
#
# Output:
#   outputs/figures/figure3_disclosures_by_year.png
#   outputs/tables/figure3_disclosures_by_year.csv  (data underlying the figure)
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

# --- Disclosure-level count ---------------------------------------------
d <- load_disclosure_long()

counts <- d %>%
  filter(!is.na(invention_id_otl), !is.na(fiscal_year.disc_otl)) %>%
  group_by(fiscal_year.disc_otl) %>%
  summarise(disclosure_count = n_distinct(invention_id_otl), .groups = "drop") %>%
  arrange(fiscal_year.disc_otl)

cat("Disclosure counts by fiscal year:\n")
print(counts)

# --- Plot ---------------------------------------------------------------
p <- ggplot(counts,
            aes(x = factor(fiscal_year.disc_otl), y = disclosure_count)) +
  geom_col(fill = "steelblue", alpha = 0.85, width = 0.7) +
  geom_text(aes(label = disclosure_count),
            vjust = -0.3, size = 6, fontface = "bold") +
  labs(x = "Disclosure fiscal year", y = "Number of disclosures") +
  theme_minimal(base_size = 16) +
  theme(
    axis.title = element_text(size = 18, face = "bold"),
    axis.text  = element_text(size = 16),
    panel.grid.major.y = element_line(color = "gray80"),
    panel.grid.major.x = element_blank(),
    panel.grid.minor   = element_blank(),
    plot.background = element_rect(fill = "white", color = NA)
  ) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.12)),
                     breaks = scales::pretty_breaks(n = 6))

# --- Save ---------------------------------------------------------------
fig_path <- file.path(OUT_FIGURES_DIR, "figure3_disclosures_by_year.png")
ggsave(fig_path, plot = p, width = 10, height = 6, dpi = 300, bg = "white")

write.csv(counts,
          file.path(OUT_TABLES_DIR, "figure3_disclosures_by_year.csv"),
          row.names = FALSE)

cat(sprintf("\nSaved figure: %s\n", fig_path))
cat(sprintf("Saved data:   %s\n",
            file.path(OUT_TABLES_DIR, "figure3_disclosures_by_year.csv")))
