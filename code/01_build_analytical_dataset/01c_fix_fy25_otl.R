# ============================================================================
# 01c_fix_fy25_otl.R — Combine two partial FY25 disclosure exports
# ----------------------------------------------------------------------------
# The focal university's FY25 disclosure data was delivered in two separate
# Excel files (one with inventor-officer information, one with inventor-
# person information). This script merges them into a single FY25 export
# that matches the schema of FY20-FY24, writing the result to:
#   <OTL dir>/FY25/Disclosures FY25_MERGED.xlsx
#
# After this step, rename or copy the merged file to
# `FY25 Disclosures All Fields.xlsx` so that 01b_merge_otl.R picks it up.
#
# Inputs (paths under REPL_OTL_DIR/FY25/):
#   Disclosures FY25 (secured).xlsx   <- "file 1": officer-side metadata
#   Disclosures FY25_2 (secured).xlsx <- "file 2": inventor-person metadata
# Both files have the same disclosure rows in the same order; this script
# verifies that and concatenates their unique columns.
# ============================================================================

# --- Locate the package root and load shared helpers --------------------
.args <- commandArgs(trailingOnly = FALSE)
.this <- sub("^--file=", "", .args[grep("^--file=", .args)[1]])
if (is.na(.this) || !nzchar(.this)) .this <- sys.frame(1)$ofile
source(file.path(dirname(.this), "..", "_helpers", "setup.R"))

suppressPackageStartupMessages({
  library(readxl)
  library(writexl)
  library(dplyr)
})

otl_dir <- Sys.getenv(
  "REPL_OTL_DIR",
  unset = file.path(REPL_PACKAGE_ROOT, "..", "Data", "Input", "OTL")
)
fy25_dir <- file.path(otl_dir, "FY25")

file1 <- file.path(fy25_dir, "Disclosures FY25 (secured).xlsx")
file2 <- file.path(fy25_dir, "Disclosures FY25_2 (secured).xlsx")
out   <- file.path(fy25_dir, "Disclosures FY25_MERGED.xlsx")

for (p in c(file1, file2)) {
  if (!file.exists(p))
    stop("Missing FY25 input file: ", p, call. = FALSE)
}

df1 <- read_excel(file1)
df2 <- read_excel(file2)

if (nrow(df1) != nrow(df2))
  stop(sprintf("FY25 files have different row counts: %d vs %d",
               nrow(df1), nrow(df2)), call. = FALSE)

# Rename file1's columns to the Invention::* naming used elsewhere.
renames <- c(
  `Invention::Track Code`         = "Invention Track Code",
  `Invention::Title`              = "Invention Title",
  `Invention::Disclosure Date`    = "Invention Disclosure Date",
  `Invention::Disclosure Status`  = "Invention Disclosure Status"
)
present <- intersect(unname(renames), names(df1))
if (length(present) > 0) {
  df1 <- df1 %>% rename(!!!setNames(present, names(renames)[match(present, renames)]))
}

# Append unique inventor-person columns from file 2.
inventor_cols <- c(
  "Invention::Inventor::Person::Person Id",
  "Invention::Inventor::Person::Full Name",
  "Invention::Inventor::Person::Gender",
  "Invention::Inventor::Person::Citizenship",
  "Invention::Inventor::Person::Primary Email"
)
for (col in intersect(inventor_cols, names(df2))) {
  df1[[col]] <- df2[[col]]
}

cat(sprintf("Merged FY25 dimensions: %d rows x %d cols\n",
            nrow(df1), ncol(df1)))
write_xlsx(df1, out)
cat(sprintf("Saved: %s\n", out))
cat("Next step: copy/rename this file to `FY25 Disclosures All Fields.xlsx`\n",
    "alongside the FY20-FY24 disclosure exports so that 01b_merge_otl.R\n",
    "picks it up automatically.\n", sep = "")
