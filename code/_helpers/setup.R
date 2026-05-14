# ============================================================================
# setup.R — locate the package root and load shared configuration.
# ----------------------------------------------------------------------------
# Every R script in this package sources this file at the top:
#
#     # at the top of the calling script:
#     .args <- commandArgs(trailingOnly = FALSE)
#     .this <- sub("^--file=", "", .args[grep("^--file=", .args)[1]])
#     if (is.na(.this) || !nzchar(.this)) .this <- sys.frame(1)$ofile
#     source(file.path(dirname(.this), "..", "_helpers", "setup.R"))
#
# After sourcing, REPL_PACKAGE_ROOT, OUT_FIGURES_DIR / OUT_TABLES_DIR /
# OUT_LOGS_DIR, DATA_ANALYTICAL_PATH, and the other path constants defined
# in config.R are available. Scripts that also need the analytical-dataset
# loader should additionally source `load_analytical_data.R` afterwards.
# ============================================================================

# Locate this file. It is always sourced (never run directly), so its own
# path appears as `ofile` in one of the call frames.
.setup_path <- NULL
for (.n in seq_len(sys.nframe())) {
  .f <- sys.frame(.n)
  if (!is.null(.f$ofile)) {
    .p <- normalizePath(.f$ofile, mustWork = FALSE)
    if (endsWith(.p, "setup.R")) { .setup_path <- .p; break }
  }
}
if (is.null(.setup_path)) {
  stop("_helpers/setup.R must be loaded via source().", call. = FALSE)
}

REPL_PACKAGE_ROOT <- normalizePath(
  file.path(dirname(.setup_path), "..", ".."),
  mustWork = FALSE
)

source(file.path(REPL_PACKAGE_ROOT, "code", "_helpers", "config.R"))
