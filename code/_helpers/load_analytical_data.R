# ============================================================================
# load_analytical_data.R — shared dataset loaders.
# ----------------------------------------------------------------------------
# Centralizes the I/O and variable construction used by every paper-output
# script so that Tables 3-7 and Figures 3-7 always work from a single
# consistent publication-level view. See `CODEBOOK.md` for variable
# definitions.
#
# Three loaders are exported:
#
#   load_publication_level()
#       One row per publication (UT_wos). Filters to rows with non-missing
#       commercial-potential score, fiscal year, broad field, and authors;
#       constructs the regression covariates (post_2022, log citations,
#       author count, has_funding, field_consolidated, field_short, journal).
#       This is the canonical input for the regression-based artifacts
#       (Tables 3-5, Figures 5-7).
#
#   load_publication_for_inventor_panel()
#       One row per publication with the minimum columns needed to build
#       the inventor-year panel (UT_wos, disclosed, commercial_potential_score,
#       pub_fiscal_year, Authors_wos, Times.Cited..WoS.Core_wos). Filters
#       are looser than load_publication_level() so that inventors whose
#       publications lack the regression covariates still appear in the
#       panel. Used by Tables 6 and 7 (Section 5.4 of the paper).
#
#   load_disclosure_long()
#       The raw long-format rows, preserving one row per disclosure-
#       publication pair (and one row per unmatched disclosure or
#       unmatched publication). Used by Figure 3 to count disclosures by
#       fiscal year of disclosure (fiscal_year.disc_otl).
# ============================================================================

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
  library(tidyr)
})

source(file.path(HELPERS_DIR, "wos_category_consolidation.R"))

load_publication_level <- function(path = DATA_ANALYTICAL_PATH) {

  if (!file.exists(path)) {
    stop(sprintf(
      "Analytical dataset not found at:\n  %s\n",
      path
    ), call. = FALSE)
  }

  raw <- read_csv(
    path,
    col_types     = cols(.default = col_character()),
    na            = c("", "NA", "N/A"),
    trim_ws       = TRUE,
    show_col_types = FALSE
  )

  raw <- raw %>%
    mutate(
      disclosed                   = as.numeric(disclosed),
      pub_fiscal_year             = as.numeric(Publication.Fiscal.Year_wos),
      commercial_potential_score  = as.numeric(commercial_potential_score)
    )

  raw <- add_broad_field(raw,
                         wos_column = "WoS.Categories_wos",
                         new_column_name = "broad_field")

  long <- raw %>%
    filter(
      !is.na(commercial_potential_score),
      !is.na(pub_fiscal_year),
      !is.na(broad_field) & broad_field != "",
      !is.na(Authors_wos) & Authors_wos != ""
    ) %>%
    mutate(
      post_2022           = ifelse(pub_fiscal_year >= POST_THRESHOLD_FY, 1L, 0L),
      cited_ref_count     = as.numeric(Cited.Reference.Count_wos),
      times_cited_all     = as.numeric(`Times.Cited..All.Databases_wos`),
      log_times_cited_all = log(ifelse(is.na(times_cited_all), 0, times_cited_all) + 1),
      author_count        = stringr::str_count(Authors_wos, ";") + 1,
      has_funding         = as.numeric(
        (!is.na(Funding.Orgs_wos) & Funding.Orgs_wos != "") |
          (!is.na(Funding.Text_wos) & Funding.Text_wos != "")
      ),
      field_consolidated = dplyr::case_when(
        broad_field == "Engineering"                ~ "Engineering",
        broad_field == "Computer sciences"          ~ "Computer sciences",
        broad_field == "Chemistry"                  ~ "Chemistry",
        broad_field == "Biological sciences"        ~ "Biological sciences",
        broad_field == "Medical sciences"           ~ "Medical sciences",
        broad_field == "Physics"                    ~ "Physics",
        broad_field == "Multidisciplinary Sciences" ~ "Multidisciplinary Sciences",
        broad_field == "Geosciences"                ~ "Geosciences",
        TRUE                                        ~ "Other"
      ),
      field_consolidated = relevel(factor(field_consolidated), ref = "Engineering"),
      field_short = dplyr::if_else(
        broad_field %in% names(FIELD_NAME_SHORT),
        unname(FIELD_NAME_SHORT[broad_field]),
        broad_field
      ),
      journal = ifelse(is.na(Source.Title_wos) | Source.Title_wos == "",
                       "Other/Conference", Source.Title_wos)
    )

  # Collapse to publication level (one row per UT_wos).
  pub <- long %>%
    filter(!is.na(UT_wos)) %>%
    group_by(UT_wos) %>%
    summarise(
      disclosed                  = as.numeric(max(disclosed, na.rm = TRUE)),
      commercial_potential_score = dplyr::first(commercial_potential_score),
      pub_fiscal_year            = dplyr::first(pub_fiscal_year),
      post_2022                  = dplyr::first(post_2022),
      cited_ref_count            = dplyr::first(cited_ref_count),
      times_cited_all            = dplyr::first(times_cited_all),
      log_times_cited_all        = dplyr::first(log_times_cited_all),
      author_count               = dplyr::first(author_count),
      has_funding                = dplyr::first(has_funding),
      broad_field                = dplyr::first(broad_field),
      field_consolidated         = dplyr::first(field_consolidated),
      field_short                = dplyr::first(field_short),
      journal                    = dplyr::first(journal),
      Authors_wos                = dplyr::first(Authors_wos),
      `Times.Cited..WoS.Core_wos` = dplyr::first(`Times.Cited..WoS.Core_wos`),
      .groups = "drop"
    ) %>%
    filter(complete.cases(disclosed, commercial_potential_score, post_2022,
                          cited_ref_count, author_count, has_funding,
                          field_consolidated))

  pub
}

# Inventor-panel loader: returns publication-level rows with only the
# columns needed for the inventor-year panel construction. Filters are
# minimal (non-missing Authors_wos and pub_year) so that the resulting
# inventor classifications can include researchers whose publications would
# otherwise be dropped from the regression sample (e.g., missing covariates).
# This matches the paper's Section 5.4 (Tables 6 & 7).
load_publication_for_inventor_panel <- function(path = DATA_ANALYTICAL_PATH) {

  if (!file.exists(path)) {
    stop(sprintf("Analytical dataset not found at:\n  %s\n", path),
         call. = FALSE)
  }

  raw <- read_csv(
    path,
    col_types      = cols(.default = col_character()),
    na             = c("", "NA", "N/A"),
    trim_ws        = TRUE,
    show_col_types = FALSE
  ) %>%
    mutate(
      disclosed                  = as.numeric(disclosed),
      pub_fiscal_year            = as.numeric(Publication.Fiscal.Year_wos),
      commercial_potential_score = as.numeric(commercial_potential_score)
    )

  # Collapse to publication level. Only require Authors_wos and pub_year.
  raw %>%
    filter(!is.na(Authors_wos) & Authors_wos != "",
           !is.na(pub_fiscal_year),
           !is.na(UT_wos)) %>%
    group_by(UT_wos) %>%
    summarise(
      disclosed                  = as.numeric(max(disclosed, na.rm = TRUE)),
      commercial_potential_score = dplyr::first(commercial_potential_score),
      pub_fiscal_year            = dplyr::first(pub_fiscal_year),
      Authors_wos                = dplyr::first(Authors_wos),
      `Times.Cited..WoS.Core_wos` = dplyr::first(`Times.Cited..WoS.Core_wos`),
      .groups = "drop"
    )
}

# Disclosure-level loader: returns the raw long-format rows for figures
# (e.g. Figure 3) that aggregate over disclosure_id rather than publication.
load_disclosure_long <- function(path = DATA_ANALYTICAL_PATH) {

  if (!file.exists(path)) {
    stop(sprintf("Analytical dataset not found at:\n  %s\n", path),
         call. = FALSE)
  }

  read_csv(
    path,
    col_types      = cols(.default = col_character()),
    na             = c("", "NA", "N/A"),
    trim_ws        = TRUE,
    show_col_types = FALSE
  ) %>%
    mutate(
      disclosed              = as.numeric(disclosed),
      fiscal_year.disc_otl   = as.numeric(fiscal_year.disc_otl),
      pub_fiscal_year        = as.numeric(Publication.Fiscal.Year_wos),
      commercial_potential_score = as.numeric(commercial_potential_score)
    )
}
