# ============================================================================
# build_inventor_panel.R — builds the inventor-year panel used by Tables 6/7
# ----------------------------------------------------------------------------
# Construction:
#   - For each publication, split Authors_wos on ";", trim, and treat each
#     name as a separate inventor-publication pair.
#   - Aggregate to (inventor, pub_year) cells: number of publications,
#     number disclosed, mean commercial-potential score in that year.
#   - Classify researchers on three pre-2022 dimensions:
#       star      = top 10% by total pre-2022 WoS citations
#       high_cp   = top 25% by mean pre-2022 CP score
#       has_disclosed = >0 disclosed publications pre-2022
#   - Restrict to researchers with >= 2 pre-2022 publications (the mechanism
#     subsample used in Tables 6/7 of the paper).
#
# Exposed object:
#   build_inventor_panel(...) returns a list with elements:
#       $pairs        - inventor-publication pairs
#       $inv_year     - inventor-year panel (one row per inventor-year)
#       $classifications - one row per inventor, with star / high_cp /
#                         has_disclosed / total_citations
#       $panel        - inv_year inner-joined to classifications +
#                       post_2022 indicator (the analytical panel)
#       $citation_p90 - the star threshold
#       $cp_p75       - the high-CP threshold
# ============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(stringr)
})

build_inventor_panel <- function(d_publication) {

  # --- 1. inventor-publication pairs --------------------------------------
  pairs <- d_publication %>%
    filter(!is.na(Authors_wos) & Authors_wos != "") %>%
    select(UT_wos, Authors_wos, pub_year = pub_fiscal_year, disclosed,
           commercial_potential_score,
           times_cited = `Times.Cited..WoS.Core_wos`) %>%
    mutate(times_cited = suppressWarnings(as.numeric(times_cited))) %>%
    distinct() %>%
    mutate(author_list = str_split(Authors_wos, ";")) %>%
    unnest(author_list) %>%
    mutate(inventor_name = str_trim(author_list)) %>%
    select(inventor_name, UT_wos, pub_year, disclosed,
           commercial_potential_score, times_cited) %>%
    filter(!is.na(pub_year), !is.na(inventor_name), inventor_name != "")

  # --- 2. inventor-year aggregation ---------------------------------------
  inv_year <- pairs %>%
    group_by(inventor_name, pub_year) %>%
    summarise(
      n_pubs          = n_distinct(UT_wos),
      n_disclosed     = sum(disclosed == 1, na.rm = TRUE),
      disclosure_rate = n_disclosed / n_pubs,
      mean_cp         = mean(commercial_potential_score, na.rm = TRUE),
      .groups = "drop"
    )

  # --- 3. pre-2022 classifications ---------------------------------------
  pre_stats <- inv_year %>%
    filter(pub_year < POST_THRESHOLD_FY) %>%
    group_by(inventor_name) %>%
    summarise(
      total_pubs_pre      = sum(n_pubs),
      total_disclosed_pre = sum(n_disclosed),
      avg_mean_cp_pre     = mean(mean_cp, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    filter(total_pubs_pre >= 2)

  citations <- pairs %>%
    filter(pub_year < POST_THRESHOLD_FY) %>%
    group_by(inventor_name) %>%
    summarise(total_citations = sum(times_cited, na.rm = TRUE),
              .groups = "drop")

  pre_stats <- pre_stats %>% left_join(citations, by = "inventor_name")

  citation_p90 <- quantile(pre_stats$total_citations, 0.90, na.rm = TRUE)
  cp_p75       <- quantile(pre_stats$avg_mean_cp_pre, 0.75, na.rm = TRUE)

  pre_stats <- pre_stats %>%
    mutate(
      star          = total_citations >= citation_p90,
      high_cp       = avg_mean_cp_pre >= cp_p75,
      has_disclosed = total_disclosed_pre > 0
    )

  # --- 4. analytical panel ------------------------------------------------
  panel <- inv_year %>%
    inner_join(
      pre_stats %>% select(inventor_name, star, high_cp, has_disclosed,
                           total_citations),
      by = "inventor_name"
    ) %>%
    mutate(post_2022 = ifelse(pub_year >= POST_THRESHOLD_FY, 1L, 0L))

  list(
    pairs           = pairs,
    inv_year        = inv_year,
    classifications = pre_stats,
    panel           = panel,
    citation_p90    = unname(citation_p90),
    cp_p75          = unname(cp_p75)
  )
}
