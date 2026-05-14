# ============================================================================
# 04b_download_uspto_renewal.R
# ----------------------------------------------------------------------------
# Parse the USPTO Maintenance Fee Events bulk text file into one row per
# granted patent, with renewal-event flags at the 4th, 8th, and 12th year.
#
# A U.S. utility patent must pay maintenance fees at roughly 4, 8, and 12
# years after grant to remain in force. The presence of a fee-paid event
# code in the bulk file is therefore an observable signal that the patent
# was renewed at that stage. Following Masclans et al. (2025), we use
# renewal as a proxy for the patent's economic value.
#
# Inputs:
#   REPL_USPTO_MAINTFEE   path to the USPTO maintenance-fee events file
#                         (default: ../Data/Input/USPTO/MaintFeeEvents_*.txt)
#                         Download from
#                         https://bulkdata.uspto.gov/data/patent/maintenancefee/
#
# Output:
#   REPL_USPTO_RENEWAL_OUT   default: ../Data/Input/USPTO/patent_renewal_data.csv
# ============================================================================

# Resolve the package root from this script's own location so paths work
# regardless of the user's working directory.
.script_path <- (function() {
  a <- commandArgs(trailingOnly = FALSE)
  h <- a[grepl("^--file=", a)]
  if (length(h) > 0) return(normalizePath(sub("^--file=", "", h[1]), mustWork = FALSE))
  for (n in seq_len(sys.nframe())) {
    f <- sys.frame(n); if (!is.null(f$ofile)) return(normalizePath(f$ofile, mustWork = FALSE))
  }
  file.path(getwd(), "this_script.R")
})()
REPL_PACKAGE_ROOT <- normalizePath(file.path(dirname(.script_path), "..", ".."),
                                   mustWork = FALSE)

suppressPackageStartupMessages({
  library(readr)
  library(data.table)
})

# Inputs and outputs, overridable via environment variables.
default_input_dir <- file.path(REPL_PACKAGE_ROOT, "..", "Data", "Input", "USPTO")
maintfee_path <- Sys.getenv("REPL_USPTO_MAINTFEE", unset = "")
if (!nzchar(maintfee_path)) {
  candidates <- list.files(default_input_dir,
                           pattern = "^MaintFeeEvents_.*\\.txt$",
                           full.names = TRUE)
  if (length(candidates) == 0) {
    stop("No USPTO maintenance-fee events file found.\n",
         "Set REPL_USPTO_MAINTFEE or place MaintFeeEvents_*.txt under\n",
         default_input_dir, call. = FALSE)
  }
  maintfee_path <- candidates[which.max(file.info(candidates)$mtime)]
}
output_path <- Sys.getenv(
  "REPL_USPTO_RENEWAL_OUT",
  unset = file.path(default_input_dir, "patent_renewal_data.csv")
)

cat(sprintf("Reading: %s\n", maintfee_path))

# The USPTO file is fixed-width; column positions documented in
# MaintFeeEventsDesc_*.txt that ships alongside it.
cols_positions <- fwf_positions(
  start     = c(1, 15, 24, 26, 35, 44, 53),
  end       = c(13, 22, 24, 33, 42, 51, 57),
  col_names = c("patent_number", "application_number", "entity_status",
                "filing_date", "issue_date", "event_date", "event_code")
)

all_events <- read_fwf(
  maintfee_path,
  col_positions = cols_positions,
  col_types = cols(
    patent_number      = col_character(),
    application_number = col_character(),
    entity_status      = col_character(),
    filing_date        = col_date(format = "%Y%m%d"),
    issue_date         = col_date(format = "%Y%m%d"),
    event_date         = col_date(format = "%Y%m%d"),
    event_code         = col_character()
  ),
  trim_ws = TRUE
)
setDT(all_events)

# Strip leading zeros so that patent and application numbers join cleanly
# against records from other sources.
all_events[, patent_number      := sub("^0+", "", patent_number)]
all_events[, application_number := sub("^0+", "", application_number)]

# Event codes signalling that a maintenance fee was paid (i.e., the patent
# was renewed) at each maintenance window. Codes come from the USPTO data
# description.
renewal_codes_4th  <- c("M1551", "M2551", "M3551",
                        "F170", "F173", "F273",
                        "M170", "M173", "M183", "M273", "M283")
renewal_codes_8th  <- c("M1552", "M2552", "M3552",
                        "F171", "F174", "F274",
                        "M171", "M174", "M184", "M274", "M284")
renewal_codes_12th <- c("M1553", "M2553", "M3553",
                        "F172", "F175", "F275",
                        "M172", "M175", "M185", "M275", "M285")

all_events[, renewal_period := fcase(
  event_code %in% renewal_codes_4th,  "4th_year",
  event_code %in% renewal_codes_8th,  "8th_year",
  event_code %in% renewal_codes_12th, "12th_year",
  default = NA_character_
)]

# Static patent info — issue date, filing date, application number — taken
# from the first event row for each patent.
static_info <- all_events[, .(
  application_number = first(application_number),
  issue_date         = first(issue_date),
  filing_date        = first(filing_date)
), by = patent_number]

# Earliest renewal-event date per (patent, renewal window), pivoted wide.
renewals_only <- all_events[!is.na(renewal_period)]
renewal_dates <- dcast(
  renewals_only,
  patent_number ~ renewal_period,
  value.var      = "event_date",
  fun.aggregate  = min,
  fill           = NA
)
setnames(renewal_dates,
         old = c("4th_year", "8th_year", "12th_year"),
         new = c("renewal_4th_date", "renewal_8th_date", "renewal_12th_date"),
         skip_absent = TRUE)

renewal_summary <- renewals_only[, .(
  earliest_renewal_date = min(event_date, na.rm = TRUE),
  latest_renewal_date   = max(event_date, na.rm = TRUE)
), by = patent_number]

# Merge into a single patent-level table with boolean renewal flags.
patent_renewals <- merge(static_info,     renewal_dates,   by = "patent_number", all.x = TRUE)
patent_renewals <- merge(patent_renewals, renewal_summary, by = "patent_number", all.x = TRUE)

patent_renewals[, `:=`(
  renewed_4th  = !is.na(renewal_4th_date),
  renewed_8th  = !is.na(renewal_8th_date),
  renewed_12th = !is.na(renewal_12th_date),
  any_renewal  = !is.na(earliest_renewal_date)
)]

setcolorder(patent_renewals, c(
  "patent_number", "application_number", "issue_date", "filing_date",
  "renewal_4th_date", "renewal_8th_date", "renewal_12th_date",
  "renewed_4th", "renewed_8th", "renewed_12th", "any_renewal",
  "earliest_renewal_date", "latest_renewal_date"
))

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
write_csv(patent_renewals, output_path)
cat(sprintf("Saved %s patent records to: %s\n",
            format(nrow(patent_renewals), big.mark = ","), output_path))
