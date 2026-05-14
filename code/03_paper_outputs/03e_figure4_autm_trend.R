# ============================================================================
# Figure 4 — Long-run disclosure trend (AUTM + HERD + publications)
# ----------------------------------------------------------------------------
# Three panels using AUTM Licensing Survey data for the focal university:
#   (a) Raw disclosure counts (Inv Dis Rec)
#   (b) Disclosures per US$ million R&D (Inv Dis Rec / Tot Res Exp)
#   (c) Disclosures per 1,000 publications (Inv Dis Rec / focal_publications)
#
# Inputs:
#   - AUTM_1991_2023_survey.csv (LICENSED — not redistributable; provide your
#     own copy and point DATA_AUTM_PATH at it via REPL_DATA_AUTM)
#   - data/public/figure4_publications_per_year.csv (shipped with the package;
#     yearly counts of US-affiliated publications and focal-university
#     publications used to build the per-publication denominator)
#
# Output:
#   outputs/figures/figure4_autm_trend.png
#   outputs/tables/figure4_autm_trend.csv  (the three series, one row per year)
# ============================================================================

# --- Locate the package root and load shared helpers --------------------
.args <- commandArgs(trailingOnly = FALSE)
.this <- sub("^--file=", "", .args[grep("^--file=", .args)[1]])
if (is.na(.this) || !nzchar(.this)) .this <- sys.frame(1)$ofile
source(file.path(dirname(.this), "..", "_helpers", "setup.R"))

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

# --- Locate restricted AUTM CSV -----------------------------------------
if (!file.exists(DATA_AUTM_PATH)) {
  stop(sprintf(
"AUTM survey CSV not found at:
  %s

The AUTM Licensing Survey is a licensed/subscription dataset and is not
shipped with this replication package. To reproduce Figure 4, place
`AUTM_1991_2023_survey.csv` in the path above, or override via the
REPL_DATA_AUTM environment variable.\n",
    DATA_AUTM_PATH), call. = FALSE)
}

# --- Identify the focal institution -------------------------------------
# AUTM has historically recoded some institutions across multiple `[ID]`s
# and spelling variants (typos in the master file), so we match by a regex
# over INSTITUTION rather than by ID and pool any rows that match.
#
# The focal university is anonymized in the manuscript, so this script
# requires the regex to be supplied at run-time via the environment
# variable REPL_FOCAL_INSTITUTION_REGEX (e.g. via
#   Sys.setenv(REPL_FOCAL_INSTITUTION_REGEX = "^My University.*$") ).
focal_regex <- Sys.getenv("REPL_FOCAL_INSTITUTION_REGEX", unset = "")
if (!nzchar(focal_regex)) {
  stop("REPL_FOCAL_INSTITUTION_REGEX is not set.\n",
       "Set it to a regular expression that matches all AUTM INSTITUTION ",
       "variants for the focal university, then re-run.", call. = FALSE)
}

# --- Read AUTM CSV -------------------------------------------------------
autm_raw <- read_csv(DATA_AUTM_PATH, show_col_types = FALSE)
needed   <- c("YEAR", "[ID]", "INSTITUTION", "Tot Res Exp", "Inv Dis Rec")
miss     <- setdiff(needed, names(autm_raw))
if (length(miss) > 0) {
  stop("AUTM CSV is missing expected columns: ",
       paste(miss, collapse = ", "), call. = FALSE)
}

autm <- autm_raw %>%
  rename(year = YEAR, autm_id = `[ID]`, institution = INSTITUTION,
         tot_res_exp = `Tot Res Exp`, inv_dis_rec = `Inv Dis Rec`) %>%
  mutate(across(c(tot_res_exp, inv_dis_rec),
                ~ suppressWarnings(as.numeric(gsub("[\\$,]", "", .x)))))

focal <- autm %>%
  filter(grepl(focal_regex, institution, ignore.case = TRUE)) %>%
  # AUTM occasionally has multiple rows per year for the same institution
  # (different IDs for the same place); keep one row per year, preferring
  # rows with non-missing disclosure data.
  group_by(year) %>%
  arrange(is.na(inv_dis_rec), is.na(tot_res_exp), .by_group = TRUE) %>%
  slice(1) %>%
  ungroup()

if (nrow(focal) == 0) {
  stop("No AUTM rows matched regex `", focal_regex, "`.", call. = FALSE)
}

cat(sprintf("Focal institution match(es): %s\n",
            paste(unique(focal$institution), collapse = " | ")))
cat(sprintf("Years matched: %d - %d (%d obs)\n",
            min(focal$year), max(focal$year), nrow(focal)))
miss <- setdiff(seq(min(focal$year), max(focal$year)), focal$year)
if (length(miss) > 0)
  cat(sprintf("Years with no AUTM record: %s\n",
              paste(miss, collapse = ", ")))

# --- Load shipped publication counts ------------------------------------
pubs_csv <- file.path(REPL_PACKAGE_ROOT, "data", "public",
                      "figure4_publications_per_year.csv")
pubs <- read_csv(pubs_csv, show_col_types = FALSE)

# --- Merge and compute series -------------------------------------------
series <- focal %>%
  select(year, inv_dis_rec, tot_res_exp) %>%
  left_join(pubs %>% select(year, focal_publications), by = "year") %>%
  arrange(year) %>%
  mutate(
    `Disclosures`                       = inv_dis_rec,
    `Disclosures per $M R&D`            = inv_dis_rec / (tot_res_exp / 1e6),
    `Disclosures per 1,000 publications`= inv_dis_rec / (focal_publications / 1000)
  )

# --- Save underlying data -----------------------------------------------
out_data <- file.path(OUT_TABLES_DIR, "figure4_autm_trend.csv")
write.csv(series %>% select(year, inv_dis_rec, tot_res_exp,
                            focal_publications,
                            `Disclosures`,
                            `Disclosures per $M R&D`,
                            `Disclosures per 1,000 publications`),
          out_data, row.names = FALSE)

# --- Plot (three faceted panels) ----------------------------------------
long <- series %>%
  select(year, `Disclosures`, `Disclosures per $M R&D`,
         `Disclosures per 1,000 publications`) %>%
  pivot_longer(-year, names_to = "metric", values_to = "value") %>%
  filter(!is.na(value)) %>%
  mutate(metric = factor(metric, levels = c(
    "Disclosures",
    "Disclosures per $M R&D",
    "Disclosures per 1,000 publications"
  )))

p <- ggplot(long, aes(x = year, y = value)) +
  geom_line(color = "steelblue", linewidth = 1) +
  geom_point(color = "steelblue", size = 1.5) +
  geom_vline(xintercept = 2022, linetype = "dashed",
             color = "gray40", linewidth = 0.5) +
  facet_wrap(~ metric, ncol = 1, scales = "free_y") +
  labs(x = "Year", y = NULL,
       caption = "Dashed line marks 2022 reforms.") +
  theme_minimal(base_size = 13) +
  theme(
    strip.text = element_text(size = 12, face = "bold"),
    axis.title.x = element_text(size = 13, face = "bold"),
    panel.grid.minor = element_blank(),
    plot.background = element_rect(fill = "white", color = NA)
  )

fig_path <- file.path(OUT_FIGURES_DIR, "figure4_autm_trend.png")
ggsave(fig_path, plot = p, width = 9, height = 9, dpi = 300, bg = "white")

cat("\nFigure 4 — series summary (first and last 5 years):\n")
print(head(series %>%
             select(year,
                    `Disclosures`,
                    `Disclosures per $M R&D`,
                    `Disclosures per 1,000 publications`), 5))
print(tail(series %>%
             select(year,
                    `Disclosures`,
                    `Disclosures per $M R&D`,
                    `Disclosures per 1,000 publications`), 5))

cat(sprintf("\nSaved figure: %s\n", fig_path))
cat(sprintf("Saved data:   %s\n", out_data))
