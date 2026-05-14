# Optional — Retraining the commercial-potential SciBERT models

These scripts retrain the three temporal SciBERT classifiers used to score
publications on commercial potential. **You do not need to run them to
replicate the paper.** The trained models are released as a separate
artifact (see `DATA_AVAILABILITY.md` at the package root for the deposit
DOI); `code/02_apply_cp_measure/02_score_publications.py` loads those
weights directly.

Run the scripts in this order only if you want to retrain from scratch:

| Script | Output |
|---|---|
| `04a_download_openalex.py` | ~1M US publications with abstracts (2000-2019), assembled from the OpenAlex API. Stored as `OpenAlexData.csv`. |
| `04b_download_uspto_renewal.R` | Parses USPTO Maintenance Fee Events bulk file into per-patent renewal records (`patent_renewal_data.csv`). |
| `04c_merge_ros_uspto.py` | Joins the Reliance on Science (Marx & Fuegi) patent-to-paper citation dataset to USPTO renewal records, producing the list of OpenAlex papers cited by renewed patents. |
| `04d_build_training_set.py` | Merges the three sources into the analysis-ready training file `6_USPTO+RO+OA.csv`. |
| `04e_train_scibert.py` | Fine-tunes three temporal SciBERT classifiers (predict windows 2019-2020, 2021-2022, 2023-2025). Each model is trained on 100k publications with a 4-year temporal gap to prevent leakage from future renewals. |

## Compute requirements

| Step | Notes |
|---|---|
| 04a | ~17 minutes wall time on the OpenAlex polite pool; rate-limited. |
| 04b | ~5 minutes; pure parsing of the USPTO bulk text file. |
| 04c | ~10 minutes; large CSV joins. |
| 04d | ~15 minutes; produces a 1.5 GB training CSV. |
| 04e | ~3 GPU-hours on a Colab T4 (one hour per temporal model). |

## Public-data sources

| Source | URL / DOI |
|---|---|
| OpenAlex API | <https://api.openalex.org/> (CC0, polite pool — provide an email) |
| USPTO Maintenance Fee Events | <https://bulkdata.uspto.gov/data/patent/maintenancefee/> |
| Reliance on Science (Marx & Fuegi) | DOI 10.5281/zenodo.4778878 |

## Configurable paths

Each script reads its inputs and outputs from environment variables (with
sensible defaults that assume the package lives alongside the original
`Data/` and `Trained models/` folders). The relevant variables are:

| Script | Variables it reads | Where the default points |
|---|---|---|
| `04a` | `REPL_OA_EMAIL` (required), `REPL_OA_OUT_DIR`, `REPL_OA_TOTAL`, `REPL_OA_START_YEAR`, `REPL_OA_END_YEAR` | `../Data/Input/OA` |
| `04b` | `REPL_USPTO_MAINTFEE`, `REPL_USPTO_RENEWAL_OUT` | `../Data/Input/USPTO/` |
| `04c` | `REPL_ROS_CSV`, `REPL_USPTO_RENEWAL_OUT`, `REPL_ROS_USPTO_OUT` | `../Data/Processed/5_papers_cited_by_renewed_patents.csv` |
| `04d` | `REPL_OA_COMBINED`, `REPL_ROS_USPTO_OUT`, `REPL_TRAINING_SET` | `../Data/Processed/6_USPTO+RO+OA.csv` |
| `04e` | `REPL_TRAINING_SET`, `REPL_MODELS_DIR` | `../Trained models/` |

## Reference

The training procedure follows Masclans, Hasan & Cohen (2025, *SMJ*) with
the temporal-cutoff and larger-sample modifications documented in the
manuscript (Section 4.4).
