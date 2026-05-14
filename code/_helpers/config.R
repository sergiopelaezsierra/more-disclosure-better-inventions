# ============================================================================
# config.R — single source of truth for paths and cohort constants.
# ----------------------------------------------------------------------------
# Loaded indirectly by every R script in the package: each script sources
# `_helpers/setup.R`, which sets REPL_PACKAGE_ROOT and then sources this
# file. This file therefore expects REPL_PACKAGE_ROOT to already exist; it
# is not meant to be sourced on its own.
#
# Any of the REPL_* environment variables below can be set before launching
# R to override the default file locations (useful when data lives
# elsewhere or you want to write outputs to a separate directory):
#
#   REPL_DATA_ANALYTICAL  -> publication-level analytical dataset
#   REPL_DATA_AUTM        -> AUTM Licensing Survey CSV (Figure 4 only)
#   REPL_MODELS_DIR       -> directory containing the trained SciBERT models
# ============================================================================

stopifnot(exists("REPL_PACKAGE_ROOT"),
          is.character(REPL_PACKAGE_ROOT),
          nzchar(REPL_PACKAGE_ROOT))

# --- Data paths (restricted unless noted) ---------------------------------
DATA_ANALYTICAL_PATH <- Sys.getenv(
  "REPL_DATA_ANALYTICAL",
  unset = file.path(REPL_PACKAGE_ROOT, "..", "Data", "Processed",
                    "7_disclosure_otl_and_pubs_wos_matched_with_predictions.csv")
)

DATA_AUTM_PATH <- Sys.getenv(
  "REPL_DATA_AUTM",
  unset = file.path(REPL_PACKAGE_ROOT, "..", "Data", "AUTM Survey",
                    "AUTM_1991_2023_survey.csv")
)

MODELS_DIR <- Sys.getenv(
  "REPL_MODELS_DIR",
  unset = file.path(REPL_PACKAGE_ROOT, "..", "Trained models")
)

# --- Output destinations --------------------------------------------------
OUT_FIGURES_DIR <- file.path(REPL_PACKAGE_ROOT, "outputs", "figures")
OUT_TABLES_DIR  <- file.path(REPL_PACKAGE_ROOT, "outputs", "tables")
OUT_LOGS_DIR    <- file.path(REPL_PACKAGE_ROOT, "outputs", "logs")
HELPERS_DIR     <- file.path(REPL_PACKAGE_ROOT, "code", "_helpers")

for (d in c(OUT_FIGURES_DIR, OUT_TABLES_DIR, OUT_LOGS_DIR)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

# --- Cohort definitions ---------------------------------------------------
FOCAL_INSTITUTION_LABEL <- "the focal university"
POST_THRESHOLD_FY       <- 2023  # publication FY >= 2023 -> Post-2022 indicator
PRE_PERIOD_LABEL        <- "Pre-2022 (FY2019–FY2022)"
POST_PERIOD_LABEL       <- "Post-2022 (FY2023–FY2025)"

# --- Standardized field-name shortenings (used by Figure 7) ---------------
FIELD_NAME_SHORT <- c(
  "Engineering"                = "Engineering",
  "Computer sciences"          = "Comp Sci",
  "Chemistry"                  = "Chemistry",
  "Biological sciences"        = "Bio Sci",
  "Medical sciences"           = "Med Sci",
  "Physics"                    = "Physics",
  "Multidisciplinary Sciences" = "Multidisc",
  "Geosciences"                = "Geosciences",
  "Mathematics"                = "Math",
  "Mathematical sciences"      = "Math Sci",
  "Agricultural sciences"      = "Agri Sci",
  "Materials Science"          = "Materials",
  "Environmental Sciences"     = "Environ Sci",
  "Social Sciences"            = "Social Sci",
  "Social sciences"            = "Social Sci",
  "Economics"                  = "Economics",
  "Psychology"                 = "Psychology",
  "Astronomy"                  = "Astronomy",
  "Professional fields"        = "Professional",
  "Uncategorized"              = "Uncategorized",
  "Humanities"                 = "Humanities"
)
