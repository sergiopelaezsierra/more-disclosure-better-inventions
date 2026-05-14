# ============================================================================
# 01b_merge_otl.R — Combine fiscal-year OTL Excel exports into one CSV
# ----------------------------------------------------------------------------
# Reads the four file types exported yearly by the focal university's Office
# of Technology Licensing (disclosure, IP application, license, provisional)
# for FY20-FY25, harmonizes column names across years, and joins disclosure
# rows with their downstream IP applications and licenses on `invention_id`.
#
# Inputs (CONFIDENTIAL — see DATA_AVAILABILITY.md):
#   $REPL_OTL_DIR  directory of OTL Excel files, named like
#                  "FY20 Disclosures All Fields.xlsx", "FY20 IP Applications
#                  All Fields.xlsx", "FY20 Licenses All Fields.xlsx",
#                  "FY20 Provisionals All Fields.xlsx" — one set per fiscal
#                  year FY20 through FY25.
#
# Output:
#   1_disclosure_otl_data_output.csv in the processed-data directory:
#   one row per invention disclosure, with .disc/.app/.lic column suffixes.
# ============================================================================

# --- Locate the package root and load shared helpers --------------------
.args <- commandArgs(trailingOnly = FALSE)
.this <- sub("^--file=", "", .args[grep("^--file=", .args)[1]])
if (is.na(.this) || !nzchar(.this)) .this <- sys.frame(1)$ofile
source(file.path(dirname(.this), "..", "_helpers", "setup.R"))

suppressPackageStartupMessages({
  library(dplyr)
  library(readxl)
  library(stringr)
})

otl_dir <- Sys.getenv(
  "REPL_OTL_DIR",
  unset = file.path(REPL_PACKAGE_ROOT, "..", "Data", "Input", "OTL")
)
out_csv <- Sys.getenv(
  "REPL_OTL_MERGED",
  unset = file.path(REPL_PACKAGE_ROOT, "..", "Data", "Processed",
                    "1_disclosure_otl_data_output.csv")
)

if (!dir.exists(otl_dir)) {
  stop("OTL directory not found: ", otl_dir,
       "\nInvention disclosures are confidential and are not bundled with\n",
       "this replication package. See DATA_AVAILABILITY.md.", call. = FALSE)
}

# --- 1. Enumerate files -------------------------------------------------
files_df <- data.frame(
  path = list.files(otl_dir, pattern = "*.xlsx", full.names = TRUE,
                    recursive = FALSE),
  stringsAsFactors = FALSE
) %>%
  mutate(
    fiscal_year = stringr::str_extract(path, "FY\\d{2}"),
    filename    = basename(path),
    type        = case_when(
      grepl("IP Applications", filename) ~ "application",
      grepl("Licenses",         filename) ~ "license",
      grepl("Provisionals",     filename) ~ "provisional",
      grepl("Disclosures",      filename) ~ "disclosure",
      TRUE                                ~ "unknown"
    )
  ) %>%
  filter(type != "unknown", !is.na(fiscal_year))

cat(sprintf("Found %d OTL Excel files across %d fiscal years.\n",
            nrow(files_df), n_distinct(files_df$fiscal_year)))

# --- 2. Helpers ---------------------------------------------------------
find_col <- function(cols, patterns) {
  for (p in patterns) {
    m <- grep(p, cols, ignore.case = TRUE, value = TRUE)
    if (length(m) > 0) return(m[1])
  }
  NA
}

read_one <- function(file_path, file_type, fiscal_year) {
  df <- read_excel(file_path)
  cols <- names(df)

  pat_track     <- c("Track Code",     "track.code")
  pat_invention <- c("Invention Id",   "invention.id")
  pat_inventor  <- c("Full Name",      "inventor.*name", "person.*name")

  rename_to <- c(
    track_code   = find_col(cols, pat_track),
    invention_id = find_col(cols, pat_invention)
  )
  if (file_type == "disclosure") {
    rename_to <- c(rename_to,
                   inventor_name = find_col(cols, pat_inventor))
  }
  rename_to <- rename_to[!is.na(rename_to)]

  if (length(rename_to) > 0) {
    df <- df %>% rename(!!!setNames(rename_to, names(rename_to)))
  }

  df %>% mutate(
    fiscal_year = fiscal_year,
    source_type = file_type,
    across(everything(), as.character)
  )
}

# --- 3. Read everything -------------------------------------------------
data_list <- lapply(seq_len(nrow(files_df)), function(i) {
  tryCatch(read_one(files_df$path[i], files_df$type[i], files_df$fiscal_year[i]),
           error = function(e) {
             warning("Failed to read ", basename(files_df$path[i]),
                     ": ", e$message, call. = FALSE)
             NULL
           })
})
data_list <- Filter(Negate(is.null), data_list)
all_data  <- bind_rows(data_list)

cat(sprintf("Total raw OTL rows: %s\n",
            format(nrow(all_data), big.mark = ",")))

# --- 4. Reshape to one row per invention --------------------------------
disclosures <- all_data %>%
  filter(source_type == "disclosure", !is.na(inventor_name)) %>%
  group_by(invention_id) %>%
  mutate(
    inventors      = paste(unique(na.omit(inventor_name)), collapse = "; "),
    inventor_count = n_distinct(inventor_name, na.rm = TRUE)
  ) %>%
  slice(1) %>%
  ungroup() %>%
  select(-inventor_name)

applications <- all_data %>%
  filter(source_type == "application") %>%
  group_by(invention_id) %>% slice(1) %>% ungroup()

licenses <- all_data %>%
  filter(source_type == "license") %>%
  group_by(invention_id) %>% slice(1) %>% ungroup()

merged <- disclosures %>%
  rename_with(~ paste0(.x, ".disc"),
              .cols = -c(invention_id, inventors, inventor_count)) %>%
  left_join(applications %>%
              rename_with(~ paste0(.x, ".app"), .cols = -invention_id),
            by = "invention_id") %>%
  left_join(licenses %>%
              rename_with(~ paste0(.x, ".lic"), .cols = -invention_id),
            by = "invention_id") %>%
  mutate(fiscal_year.disc = paste0("20", str_remove(fiscal_year.disc, "FY")))

# --- 5. Save ------------------------------------------------------------
dir.create(dirname(out_csv), recursive = TRUE, showWarnings = FALSE)
write.csv(merged, out_csv, row.names = FALSE)
cat(sprintf("\nUnique disclosures merged: %s\n",
            format(n_distinct(merged$invention_id), big.mark = ",")))
cat(sprintf("Saved: %s\n", out_csv))
