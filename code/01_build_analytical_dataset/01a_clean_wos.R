# ============================================================================
# 01a_clean_wos.R — Clean and FY-convert Web of Science publication records
# ----------------------------------------------------------------------------
# Steps:
#   1. Read the raw WoS export (calendar-year publication records for the
#      focal university; obtained via a name-based query in Clarivate WoS).
#   2. Convert calendar publication dates to fiscal years (FY t = Jul (t-1)
#      to Jun t). Publications with month >= July fall into FY year+1.
#   3. Keep FY2019-FY2025 (the empirical window of the paper).
#   4. Drop rows with missing abstracts (required for the CP scoring step).
#   5. Deduplicate on the WoS accession number `UT`.
#
# Inputs (paths configurable via env vars; see code/_helpers/config.R):
#   $REPL_WOS_RAW         raw WoS CSV with calendar dates
#                         (default: ../Data/Input/WOS/combined_wos_data_2017_2025.csv)
#
# Outputs:
#   $REPL_WOS_CLEAN       FY-converted, deduplicated WoS CSV
#                         (default: ../Data/Input/WOS/combined_wos_data_2019_2025FY.csv)
# ============================================================================

# --- Locate the package root and load shared helpers --------------------
.args <- commandArgs(trailingOnly = FALSE)
.this <- sub("^--file=", "", .args[grep("^--file=", .args)[1]])
if (is.na(.this) || !nzchar(.this)) .this <- sys.frame(1)$ofile
source(file.path(dirname(.this), "..", "_helpers", "setup.R"))

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
})

wos_raw_path <- Sys.getenv(
  "REPL_WOS_RAW",
  unset = file.path(REPL_PACKAGE_ROOT, "..", "Data", "Input", "WOS",
                    "combined_wos_data_2017_2025.csv")
)
wos_out_path <- Sys.getenv(
  "REPL_WOS_CLEAN",
  unset = file.path(REPL_PACKAGE_ROOT, "..", "Data", "Input", "WOS",
                    "combined_wos_data_2019_2025FY.csv")
)

if (!file.exists(wos_raw_path)) {
  stop("Raw WoS export not found at: ", wos_raw_path,
       "\nWeb of Science is a licensed dataset and is not bundled. Provide\n",
       "your own raw export at the path above or via REPL_WOS_RAW.",
       call. = FALSE)
}

cat(sprintf("Reading raw WoS file: %s\n", wos_raw_path))
df <- read.csv(wos_raw_path, stringsAsFactors = FALSE,
               na.strings = c("", "NA"), check.names = FALSE)
n_initial <- nrow(df)
cat(sprintf("  initial rows: %s\n", format(n_initial, big.mark = ",")))

# --- 1. Calendar -> fiscal year -----------------------------------------
late_months_regex <- "JUL|AUG|SEP|OCT|NOV|DEC"

df <- df %>%
  mutate(
    publication_year_numeric = suppressWarnings(as.numeric(Publication.Year)),
    Publication.Fiscal.Year  = dplyr::if_else(
      stringr::str_detect(toupper(as.character(Publication.Date)),
                          late_months_regex),
      publication_year_numeric + 1,
      publication_year_numeric,
      missing = publication_year_numeric
    )
  ) %>%
  select(-publication_year_numeric)

cat(sprintf("  rows after FY conversion: %s\n",
            format(nrow(df), big.mark = ",")))

# --- 2. Window filter ---------------------------------------------------
df <- df %>% filter(Publication.Fiscal.Year %in% 2019:2025)
cat(sprintf("  after FY 2019-2025 filter: %s\n",
            format(nrow(df), big.mark = ",")))

# --- 3. Drop missing abstracts ------------------------------------------
df <- df %>% filter(!is.na(Abstract) & Abstract != "")
cat(sprintf("  after dropping missing abstracts: %s\n",
            format(nrow(df), big.mark = ",")))

# --- 4. Deduplicate on UT -----------------------------------------------
n_dup <- sum(duplicated(df$UT))
df <- df %>% distinct(UT, .keep_all = TRUE)
cat(sprintf("  duplicates dropped on UT: %s\n", format(n_dup, big.mark = ",")))
cat(sprintf("  final rows: %s\n", format(nrow(df), big.mark = ",")))

# --- 5. Save ------------------------------------------------------------
dir.create(dirname(wos_out_path), recursive = TRUE, showWarnings = FALSE)
write.csv(df, wos_out_path, row.names = FALSE)
cat(sprintf("\nSaved: %s\n", wos_out_path))
