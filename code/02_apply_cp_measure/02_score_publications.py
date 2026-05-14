"""
02_score_publications.py — Apply the trained SciBERT models to score
publications on the ex-ante commercial-potential measure.

For each publication, this script:
  1. Reads the integrated long-format dataset produced by
     01d_match_otl_wos.py.
  2. Picks the temporal SciBERT model whose prediction window covers the
     publication's fiscal year (see TEMPORAL_MODELS below).
  3. Tokenizes the abstract and runs the model in inference mode.
  4. Records the predicted probability of citation by a renewed patent --
     the commercial-potential score used throughout the paper.

The three temporal models were trained by 04_retrain_cp_models_optional/
and are deposited on Zenodo:

  https://doi.org/10.5281/zenodo.20184929

Download `commercial_potential_scibert_v1.0.0.zip`, extract it, and point
REPL_MODELS_DIR at the resulting directory (or place the three model
folders next to the package as `../Trained models/`).

Output:
  data/Processed/7_disclosure_otl_and_pubs_wos_matched_with_predictions.csv
    Long-format dataset with two added columns:
      commercial_potential_score : float in [0, 1]
      model_used                 : which temporal model produced the score
"""

from __future__ import annotations

import logging
import os
import re
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import torch
from torch.utils.data import DataLoader, Dataset
from tqdm.auto import tqdm
from transformers import AutoModelForSequenceClassification, AutoTokenizer


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
PACKAGE_ROOT = Path(__file__).resolve().parents[2]


def _from_env(env_var: str, default_relative: str) -> Path:
    v = os.environ.get(env_var, "")
    if v:
        return Path(v).expanduser().resolve()
    return (PACKAGE_ROOT / default_relative).resolve()


MODELS_DIR = _from_env("REPL_MODELS_DIR", "../Trained models")
INPUT_CSV  = _from_env("REPL_MATCH_OUTPUT",
                       "../Data/Processed/2_disclosure_otl_and_pubs_wos_matched.csv")
OUTPUT_CSV = _from_env(
    "REPL_PUBLICATIONS_SCORED",
    "../Data/Processed/7_disclosure_otl_and_pubs_wos_matched_with_predictions.csv",
)

OUTPUT_CSV.parent.mkdir(parents=True, exist_ok=True)

# Each temporal model predicts publications whose fiscal year falls in its
# `predict_years` range. The 4-year gap between training cutoff and
# prediction window prevents leakage from future renewals.
TEMPORAL_MODELS = [
    {"name": "model_2019_2020", "predict_years": (2019, 2020)},
    {"name": "model_2021_2022", "predict_years": (2021, 2022)},
    {"name": "model_2023_2025", "predict_years": (2023, 2025)},
]
BATCH_SIZE  = 128
MAX_LENGTH  = 512
TOKENIZER_NAME = "allenai/scibert_scivocab_uncased"

# Match the original training-time abstract preprocessing exactly.
_NON_TEXT = re.compile(r"[^\w\s\.\,\;\:\-\(\)]")
_WHITESPACE = re.compile(r"\s+")


def preprocess_abstract(s: str | float) -> str:
    if pd.isna(s):
        return ""
    t = _NON_TEXT.sub(" ", str(s))
    return _WHITESPACE.sub(" ", t).strip()


def assign_model_for_year(year: float | int | None) -> str | None:
    """Return the model name whose prediction window contains `year`.

    Edge cases: years earlier than the earliest model use the earliest model
    (rare); years later than the last model use the last model.
    """
    if pd.isna(year):
        return None
    y = int(year)
    for cfg in TEMPORAL_MODELS:
        lo, hi = cfg["predict_years"]
        if lo <= y <= hi:
            return cfg["name"]
    return TEMPORAL_MODELS[0]["name"] if y < TEMPORAL_MODELS[0]["predict_years"][0] \
        else TEMPORAL_MODELS[-1]["name"]


# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger(__name__)


# -----------------------------------------------------------------------------
# Resolve model paths (allow both nested and flat layouts)
# -----------------------------------------------------------------------------
def _resolve_model_path(name: str) -> Path:
    candidates = [
        MODELS_DIR / name,
        MODELS_DIR / name / name,   # legacy nested layout from training
    ]
    for c in candidates:
        if (c / "model.safetensors").exists() or (c / "pytorch_model.bin").exists():
            return c
    raise FileNotFoundError(
        f"Could not find weights for {name!r} under {MODELS_DIR}. "
        f"Tried: {[str(c) for c in candidates]}"
    )


# -----------------------------------------------------------------------------
# Inference dataset
# -----------------------------------------------------------------------------
class AbstractDataset(Dataset):
    def __init__(self, texts: list[str], tokenizer):
        enc = tokenizer(
            texts, add_special_tokens=True, max_length=MAX_LENGTH,
            padding="max_length", truncation=True,
            return_attention_mask=True, return_tensors="pt",
        )
        self.input_ids = enc["input_ids"]
        self.attention_mask = enc["attention_mask"]

    def __len__(self) -> int:
        return self.input_ids.size(0)

    def __getitem__(self, idx: int) -> dict[str, torch.Tensor]:
        return {"input_ids": self.input_ids[idx],
                "attention_mask": self.attention_mask[idx]}


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
def main() -> None:
    if not INPUT_CSV.exists():
        raise FileNotFoundError(f"Input CSV not found: {INPUT_CSV}")

    log.info("Reading %s", INPUT_CSV)
    df = pd.read_csv(INPUT_CSV, low_memory=False)
    log.info("Loaded %d rows x %d columns", len(df), df.shape[1])

    # Determine abstract and year columns.
    abstract_col = "Abstract_wos" if "Abstract_wos" in df.columns else "Abstract"
    year_col = (
        "Publication.Fiscal.Year_wos"
        if "Publication.Fiscal.Year_wos" in df.columns
        else "Publication.Fiscal.Year"
    )
    log.info("Using abstract column %r and year column %r",
             abstract_col, year_col)

    df["commercial_potential_score"] = np.nan
    df["model_used"] = None
    df["__assigned"] = df[year_col].apply(assign_model_for_year)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    log.info("Device: %s", device)

    tokenizer = AutoTokenizer.from_pretrained(TOKENIZER_NAME)

    for cfg in TEMPORAL_MODELS:
        name = cfg["name"]
        mask = df["__assigned"] == name
        if not mask.any():
            log.info("%s: no rows assigned; skipping.", name)
            continue

        model_path = _resolve_model_path(name)
        log.info("Loading %s from %s", name, model_path)
        model = (
            AutoModelForSequenceClassification.from_pretrained(model_path)
            .to(device).eval()
        )

        idxs = df.index[mask].tolist()
        abstracts = [preprocess_abstract(a) for a in df.loc[idxs, abstract_col]]
        ds = AbstractDataset(abstracts, tokenizer)
        dl = DataLoader(ds, batch_size=BATCH_SIZE, shuffle=False)

        out = np.empty(len(idxs), dtype=np.float32)
        cur = 0
        with torch.no_grad():
            for batch in tqdm(dl, desc=f"{name} ({mask.sum()} rows)"):
                input_ids = batch["input_ids"].to(device)
                attn = batch["attention_mask"].to(device)
                logits = model(input_ids=input_ids, attention_mask=attn).logits
                probs = torch.softmax(logits, dim=1)[:, 1].cpu().numpy()
                out[cur:cur + len(probs)] = probs
                cur += len(probs)

        df.loc[idxs, "commercial_potential_score"] = out
        df.loc[idxs, "model_used"] = name

        del model
        if torch.cuda.is_available():
            torch.cuda.empty_cache()

    df.drop(columns="__assigned", inplace=True)

    n_scored = df["commercial_potential_score"].notna().sum()
    log.info("Scored %d / %d rows (%.1f%%)",
             n_scored, len(df), 100 * n_scored / len(df))
    df.to_csv(OUTPUT_CSV, index=False)
    log.info("Saved: %s", OUTPUT_CSV)


if __name__ == "__main__":
    main()
