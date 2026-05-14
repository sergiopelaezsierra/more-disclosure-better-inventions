# Zenodo deposit — Trained commercial-potential SciBERT classifiers

**Status: published.** DOI: [10.5281/zenodo.20184929](https://doi.org/10.5281/zenodo.20184929)

The fields below are kept for provenance: they document what was deposited
under this DOI and what metadata fields it carries on Zenodo. To deposit
a new version (e.g., retrained models), open the deposit page on Zenodo
and click "New version" — Zenodo will pre-fill these fields and issue a
new version DOI while preserving the concept DOI above.

---

## Upload type
**Software** *(or "Dataset" if you prefer — both are reasonable; Software
is slightly more accurate since these are model weights)*

## Files to upload
Three folders (or one zip of them):

```
model_2019_2020/   ~420 MB  (config.json, model.safetensors, tokenizer.json,
                              tokenizer_config.json, special_tokens_map.json,
                              vocab.txt, model_config.json, test_metrics.json,
                              training_history.json)
model_2021_2022/   ~420 MB  (same file set, different weights)
model_2023_2025/   ~420 MB  (same file set, different weights)
```

A single zip keeps the deposit tidy and uploads with a single progress bar.
It is already prepared on your machine at:

```
c:\Users\sergiopel\Dropbox\GT Disclosures & Licensing\commercial_potential_scibert_v1.0.0.zip   (≈1.17 GB)
```

Drag that file onto the Zenodo upload form's "Add files" area.

## Title
Commercial Potential of Science — Three temporal SciBERT classifiers

## Authors
- Pelaez, Sergio · ORCID *(add yours)* · Affiliation *(add)*
- Yang, Jeongyoon J. · ORCID *(add yours/coauthor)* · Affiliation *(add)*
- Walsh, John P. · ORCID *(add)* · Affiliation: Georgia Institute of Technology
- Ceccagnoli, Marco · ORCID *(add)* · Affiliation: Georgia Institute of Technology

## Description (paste into the "Description" field)

> Three fine-tuned SciBERT classifiers that predict, from a publication's
> abstract, the probability that the publication will be cited by a
> renewed U.S. patent. The probability serves as an ex-ante, publication-
> level measure of the *commercial potential* of scientific research.
>
> The three models are temporally isolated, each trained on publications
> strictly older than its prediction window and labelled using only
> patent-renewal events observed before a cutoff year that precedes the
> prediction window by a four-year safety gap:
>
> | Model | Predict window | Trained on | Renewal cutoff |
> |---|---|---|---|
> | `model_2019_2020` | publications 2019–2020 | 2000–2015 | 2018 |
> | `model_2021_2022` | publications 2021–2022 | 2000–2017 | 2020 |
> | `model_2023_2025` | publications 2023–2025 | 2000–2019 | 2022 |
>
> Each model was fine-tuned from `allenai/scibert_scivocab_uncased` on a
> balanced 100,000-publication training set (50,000 cited by a renewed
> patent, 50,000 not), with stratified 75/12.5/12.5 train/val/test splits,
> mixed-precision training, gradient accumulation, and early stopping on
> validation F1. Held-out test accuracy averages 0.770; AUC averages 0.854
> (per-model metrics are in each model directory's `test_metrics.json`).
>
> The training procedure adapts Masclans, Hasan & Cohen (2025, *Strategic
> Management Journal*) with temporal-cutoff labels and larger training
> samples; see the replication-package release for the training code
> (`code/04_retrain_cp_models_optional/04e_train_scibert.py`).
>
> To score new publications: use `code/02_apply_cp_measure/02_score_publications.py`
> from the replication code release (linked in *Related identifiers*).
> Each model is loaded via `AutoModelForSequenceClassification.from_pretrained`.

## Keywords
`SciBERT` · `commercial potential` · `university technology transfer` ·
`patent renewal` · `science of science` · `invention disclosure` ·
`text classification` · `transfer learning`

## License
**Apache License 2.0** *(matches the SciBERT base model license)*

## Version
`1.0.0`

## Related identifiers (add these in "Related/alternate identifiers")

| Relation | Identifier | Resource type |
|---|---|---|
| `is supplement to` | https://github.com/sergiopelaezsierra/more-disclosure-better-inventions | Software |
| `is supplement to` | *(the paper's DOI once accepted)* | Publication: Article |
| `is derived from` | https://huggingface.co/allenai/scibert_scivocab_uncased | Software |

## Communities
*(optional)* Search for and add any topical communities such as `zenodo`,
`open-data`, or a specific Anthropic / NSF / Georgia Tech community if
relevant.

## Funding *(optional)*
Add the relevant grant numbers if any.

---

## After publishing

Zenodo emails you the DOI immediately. The DOI looks like
`10.5281/zenodo.1234567`. Send it to me and I'll bake it into the
replication package's README and DATA_AVAILABILITY.md.
