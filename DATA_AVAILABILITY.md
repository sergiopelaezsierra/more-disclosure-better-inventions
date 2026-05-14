# Data availability statement

The empirical analysis combines four data sources with different access
regimes. This package adopts an "as-open-as-permissible" strategy: code
and trained-model artifacts are released openly, the underlying licensed
or confidential inputs are not redistributed but are documented here so
that researchers with appropriate access can reproduce the pipeline.

## Inputs

| Source | What it is | Status | What this package provides |
|---|---|---|---|
| **Office of Technology Licensing (OTL) records** | Internal disclosure, IP application, license, and provisional records of the focal university (FY2020–FY2025). Includes inventor names, abstracts, agreement metadata. | **Confidential.** Cannot be redistributed. Available via direct request to the focal university's OTL. | The harmonization scripts (`code/01_build_analytical_dataset/01b_merge_otl.R`, `01c_fix_fy25_otl.R`) operate on the OTL's standard fiscal-year Excel exports. Schema documented inline. |
| **Web of Science** | Publication records for the focal university (FY2017–FY2025): bibliographic metadata, abstracts, citations, funding text, addresses. | **Licensed.** Clarivate terms forbid redistribution. Available to subscribing institutions via Clarivate WoS. | The cleaning script (`code/01_build_analytical_dataset/01a_clean_wos.R`) and the matching script (`01d_match_otl_wos.py`) reproduce the analytical WoS subset from a fresh export. The query string used was an OR over name variants of the focal university restricted to fiscal years 2017–2025. |
| **AUTM Licensing Survey (1991–2023)** | Yearly institution-level disclosure, R&D, patenting and licensing statistics. | **Subscription/licensed.** AUTM grants access to member institutions and qualified researchers. | The Figure 4 script (`code/03_paper_outputs/03e_figure4_autm_trend.R`) reads `AUTM_1991_2023_survey.csv` and reproduces the three series shown in Figure 4. The aggregated publication counts used in Figure 4 panel (c), which come from the same Web of Science query above, are shipped as `data/public/figure4_publications_per_year.csv`. |
| **OpenAlex (publications)** | ~1M US-affiliated publications 2000–2019, with abstracts. Used to build the SciBERT training set. | **Public (CC0).** | `code/04_retrain_cp_models_optional/04a_download_openalex.ipynb` reproduces the download. Re-downloading is the recommended path (avoids the ~1.5 GB CSV redistribution); allow ~17 minutes. |
| **USPTO Maintenance Fee Events** | Patent renewal records (whether each granted U.S. patent has paid its 4th-, 8th-, and 12th-year maintenance fees). | **Public.** Available via the USPTO bulk-data site. | `code/04_retrain_cp_models_optional/04b_download_uspto_renewal.R` parses the bulk text file into structured records. |
| **Reliance on Science** (Marx & Fuegi 2020, 2022) | Patent-to-paper citation dataset linking USPTO patents to DOIs of cited publications. | **Public, CC-BY.** Available on Zenodo (DOI 10.5281/zenodo.4778878). | `code/04_retrain_cp_models_optional/04c_merge_ros_uspto.ipynb` joins it to USPTO renewal records. |

## Bundled and externally deposited artifacts

The replication code is on GitHub and archived on Zenodo on each tagged
release; the trained SciBERT classifiers are released as a separate Zenodo
deposit because of their size (~1.3 GB).

| Artifact | Where | Size | License |
|---|---|---|---|
| Replication code (this package) | GitHub: <https://github.com/sergiopelaezsierra/more-disclosure-better-inventions> · Zenodo: *DOI pending* | <2 MB | MIT |
| Three temporal SciBERT classifiers (`model_2019_2020`, `model_2021_2022`, `model_2023_2025`) | Zenodo: *DOI pending* (also mirrored locally for development at `trained_models/` or `../Trained models/`) | ~1.3 GB total | Apache 2.0 (derived from `allenai/scibert_scivocab_uncased`) |
| Yearly publication counts used by Figure 4 | `data/public/figure4_publications_per_year.csv` | ~1 KB | CC0 |

## Anonymization

The paper does not name the focal university. This replication package is
consistent with that decision: code, README, and inline documentation refer
generically to "the focal university." File names and column labels that
originate in the OTL's internal database (e.g. `Invention::Title.disc`) are
unchanged because changing them would diverge from the schema of files a
future researcher with OTL access would receive.

Inventor full names are present in OTL records. They are also present in
Web of Science author lists (and therefore in the wider scientific
record), so they are not redacted by the OTL. None of this information is
shipped in the replication package.
