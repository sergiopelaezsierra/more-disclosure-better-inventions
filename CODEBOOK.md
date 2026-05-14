# Codebook — analytical dataset

The publication-level analytical dataset is built by
`code/01_build_analytical_dataset/` and scored by
`code/02_apply_cp_measure/02_score_publications.py`. The final file used by
all paper-output scripts is

```
7_disclosure_otl_and_pubs_wos_matched_with_predictions.csv
```

After construction it has one row per publication–disclosure pair (long
format). The scripts in `code/03_paper_outputs/` collapse it to one row per
publication (`UT_wos`) via the shared loader
`code/_helpers/load_analytical_data.R`. The columns below are the ones the
analysis uses.

## Outcome and predictor

| Column | Type | Description |
|---|---|---|
| `disclosed` | 0/1 | 1 if the publication is matched to at least one OTL invention disclosure. |
| `commercial_potential_score` | float in [0, 1] | Probability that the publication's abstract would be cited by a renewed U.S. patent, as predicted by the temporal SciBERT model whose window covers the publication's fiscal year. Computed at the publication level. |

## Period and identifiers

| Column | Type | Description |
|---|---|---|
| `UT_wos` | string | Web of Science accession number — unique publication ID. |
| `invention_id_otl` | string | OTL invention identifier (NA on rows representing unmatched publications). |
| `fiscal_year.disc_otl` | int | Fiscal year of the disclosure (NA for unmatched). |
| `Publication.Fiscal.Year_wos` | int | Fiscal year of the publication (July of t-1 through June of t). |
| `pub_fiscal_year` | int | Same as above, retyped for use in regressions. |
| `post_2022` | 0/1 | 1 if `pub_fiscal_year` ≥ 2023 (the post-reform window FY2023–FY2025). |

## Match metadata (only on matched rows)

| Column | Type | Description |
|---|---|---|
| `bert_similarity` | float | SciBERT cosine similarity between disclosure and publication titles. Hybrid threshold: ≥ 0.7. |
| `fuzzy_similarity` | float | `fuzz.token_set_ratio` over the same title pair, rescaled to [0, 1]. Hybrid threshold: ≥ 0.5. |
| `time_gap` | int | Publication FY − Disclosure FY. Constrained to [−1, +3]. |
| `num_shared_researchers` | int | Number of fuzzy-matched (inventor, author) pairs the disclosure–publication pair has in common. |
| `pubs_matched_to_discs` | 0/1 | 1 if this row represents a matched pair; 0 if it is an unmatched publication or unmatched disclosure. |

## Regression covariates

| Column | Type | Description |
|---|---|---|
| `cited_ref_count` | int | Number of references the publication cites (WoS field `Cited.Reference.Count`). |
| `times_cited_all` | int | Forward citation count to the publication (WoS field `Times.Cited..All.Databases`). |
| `log_times_cited_all` | float | log1p of the above. Not used in regressions but kept in Table 3. |
| `author_count` | int | Number of authors on the publication (count of `;`-delimited entries in `Authors_wos`). |
| `has_funding` | 0/1 | 1 if either `Funding.Orgs_wos` or `Funding.Text_wos` is non-empty. |
| `Authors_wos` | string | Semicolon-delimited author list (used to build the inventor-year panel). |
| `Times.Cited..WoS.Core_wos` | int | Total citations from WoS Core Collection (used to build the inventor-level "star" indicator). |

## Field categories (Figure 7)

`broad_field` is the consolidated 15-field label produced by
`code/_helpers/wos_category_consolidation.R` (following Milojević 2020),
applied to the publication's `WoS.Categories_wos`.

`field_consolidated` (used in Tables 4 and 5) keeps the 8 most populous
broad fields in their own categories and groups smaller ones into `"Other"`.
The reference category is `"Engineering"`.

`field_short` (used in Figure 7) maps each broad field to a shorter display
label per `FIELD_NAME_SHORT` in `code/_helpers/config.R`.

## Inventor-year panel (Tables 6 and 7)

Built by `code/_helpers/build_inventor_panel.R` from the publication-level
data and the pre-2022 inventor classifications:

| Column | Type | Description |
|---|---|---|
| `inventor_name` | string | Standardized author/inventor name (semicolon-split `Authors_wos`, trimmed and lower-cased). |
| `pub_year` | int | Fiscal year of the publication (from `Publication.Fiscal.Year_wos`). |
| `n_pubs` | int | Number of distinct publications by this inventor in this fiscal year. |
| `n_disclosed` | int | Of those, the number disclosed. |
| `disclosure_rate` | float in [0, 1] | `n_disclosed / n_pubs` (the dependent variable in Table 7). |
| `mean_cp` | float | Mean commercial-potential score across this inventor-year's publications. |
| `star` | logical | True if total pre-2022 WoS citations ≥ the 90th percentile across inventors (≥ 455 in the focal-university sample). |
| `high_cp` | logical | True if mean pre-2022 commercial potential ≥ the 75th percentile (≥ 0.362). |
| `has_disclosed` | logical | True if the inventor had > 0 pre-2022 disclosures. Defines the Panel A vs. Panel B split in Table 6. |
| `post_2022` | 0/1 | Same as on the publication-level dataset. |

The mechanism subsample further restricts to inventors with ≥ 2 pre-2022
publications (N = 12,946 non-disclosers + 3,354 active disclosers; the
extensive and intensive margins of Table 7).

## Cohort definitions (centralized)

These are set once in `code/_helpers/config.R`:

- `POST_THRESHOLD_FY = 2023` — `pub_fiscal_year ≥ 2023` defines `post_2022 = 1`.
- The pre-period is FY2019–FY2022; the post-period is FY2023–FY2025.
