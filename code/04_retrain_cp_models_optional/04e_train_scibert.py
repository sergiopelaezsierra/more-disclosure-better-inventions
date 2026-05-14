"""
04e_train_scibert.py — Fine-tune the three temporal SciBERT classifiers.

Each model is trained on publications strictly older than the prediction
window, and the binary label (cited by a renewed U.S. patent) only counts
renewals observed before a cutoff year that precedes the prediction window
by a 4-year safety gap. This prevents the model from "seeing the future"
when scoring publications in the prediction window.

Specifications (matching Masclans et al. 2025, adapted):

  model_2019_2020 — trained on 2000-2015 papers, renewal cutoff 2018
  model_2021_2022 — trained on 2000-2017 papers, renewal cutoff 2020
  model_2023_2025 — trained on 2000-2019 papers, renewal cutoff 2022

For each model, 50k positives and 50k negatives are sampled, split 75/12.5/
12.5 into train/val/test (stratified), and a SciBERT base is fine-tuned
with mixed precision, gradient accumulation, and early stopping on F1.

Inputs:
  REPL_TRAINING_SET     Default: ../Data/Processed/6_USPTO+RO+OA.csv  (from 04d)
  REPL_MODELS_DIR       Default: ../Trained models  (output dir)

Outputs (one subdirectory per temporal model):
  <REPL_MODELS_DIR>/model_2019_2020/
    config.json, model.safetensors, tokenizer.json, ..., test_metrics.json,
    training_history.json, model_config.json
  ... and likewise for model_2021_2022 and model_2023_2025.

Hardware: GPU strongly recommended. ~1 hour per model on a T4.
"""

from __future__ import annotations

import gc
import json
import logging
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd
import torch
from sklearn.metrics import (
    accuracy_score, confusion_matrix, precision_recall_fscore_support, roc_auc_score
)
from sklearn.model_selection import train_test_split
from torch.cuda.amp import GradScaler, autocast
from torch.optim import AdamW
from torch.utils.data import DataLoader, Dataset
from tqdm.auto import tqdm
from transformers import (
    AutoModelForSequenceClassification, AutoTokenizer,
    get_linear_schedule_with_warmup,
)


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
PACKAGE_ROOT = Path(__file__).resolve().parents[2]


def _path(env_var: str, default_relative: str) -> Path:
    v = os.environ.get(env_var, "")
    return Path(v).expanduser().resolve() if v else (PACKAGE_ROOT / default_relative).resolve()


TRAINING_CSV = _path("REPL_TRAINING_SET", "../Data/Processed/6_USPTO+RO+OA.csv")
OUTPUT_DIR   = _path("REPL_MODELS_DIR",   "../Trained models")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


@dataclass
class TemporalSpec:
    name: str
    train_years: tuple[int, int]   # inclusive
    predict_years: tuple[int, int]
    renewal_cutoff: int            # max renewal year that may be observed
    label_column: str              # column added to the training frame


TEMPORAL_SPECS = [
    TemporalSpec("model_2019_2020", (2000, 2015), (2019, 2020), 2018, "label_2018_cutoff"),
    TemporalSpec("model_2021_2022", (2000, 2017), (2021, 2022), 2020, "label_2020_cutoff"),
    TemporalSpec("model_2023_2025", (2000, 2019), (2023, 2025), 2022, "label_2022_cutoff"),
]

BASE_MODEL          = "allenai/scibert_scivocab_uncased"
SAMPLES_PER_CLASS   = 50_000
TRAIN_SPLIT         = 0.75
VAL_SPLIT           = 0.125
TEST_SPLIT          = 0.125
BATCH_SIZE          = 128
GRAD_ACCUM_STEPS    = 4
LEARNING_RATE       = 2e-5
MAX_EPOCHS          = 5
EARLY_STOP_PATIENCE = 2
MAX_LENGTH          = 512
NUM_WORKERS         = 2
RANDOM_SEED         = 42

torch.manual_seed(RANDOM_SEED)
np.random.seed(RANDOM_SEED)
if torch.cuda.is_available():
    torch.cuda.manual_seed_all(RANDOM_SEED)

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger(__name__)


# -----------------------------------------------------------------------------
# Label construction with temporal cutoffs
# -----------------------------------------------------------------------------
def estimate_renewal_year(row: pd.Series) -> float:
    """Estimate when the patent's first observed renewal occurred.

    The maintenance fee schedule is roughly 4, 8, and 12 years after issue,
    so the midpoints (~3.5y, 7.5y, 11.5y) give a fair point estimate for the
    earliest renewal.
    """
    if pd.isna(row["issue_year"]):
        return np.nan
    if row["has_4th_year_renewal"]:
        return row["issue_year"] + 3.5
    if row["has_8th_year_renewal"]:
        return row["issue_year"] + 7.5
    if row["has_12th_year_renewal"]:
        return row["issue_year"] + 11.5
    return np.nan


def load_training_frame() -> pd.DataFrame:
    if not TRAINING_CSV.exists():
        sys.exit(f"Training file not found: {TRAINING_CSV}\nRun 04d first.")

    log.info("Loading training data: %s", TRAINING_CSV)
    df = pd.read_csv(
        TRAINING_CSV,
        usecols=["publication_year", "abstract", "cited_by_renewed_patent",
                 "earliest_issue_date", "has_4th_year_renewal",
                 "has_8th_year_renewal", "has_12th_year_renewal"],
    )

    df["issue_year"] = pd.to_datetime(
        df["earliest_issue_date"], errors="coerce"
    ).dt.year
    df["estimated_renewal_year"] = df.apply(estimate_renewal_year, axis=1)

    # Label = positive only if cited by a renewed patent AND the renewal
    # was observed by the cutoff year (avoids leakage from future renewals).
    for cutoff in {s.renewal_cutoff for s in TEMPORAL_SPECS}:
        df[f"label_{cutoff}_cutoff"] = (
            df["cited_by_renewed_patent"]
            & df["estimated_renewal_year"].notna()
            & (df["estimated_renewal_year"] <= cutoff)
        )

    n0 = len(df)
    df = df[df["abstract"].notna() & df["abstract"].str.strip().ne("")].copy()
    df["publication_year"] = df["publication_year"].astype(int)
    log.info("Dropped %d rows with missing abstracts; %d remain.",
             n0 - len(df), len(df))

    return df[["publication_year", "abstract",
               "label_2018_cutoff", "label_2020_cutoff", "label_2022_cutoff"]]


def sample_balanced(df: pd.DataFrame, spec: TemporalSpec) -> pd.DataFrame:
    """Return a balanced (50k positives + 50k negatives) training frame for `spec`."""
    in_window = df[(df["publication_year"] >= spec.train_years[0]) &
                   (df["publication_year"] <= spec.train_years[1])]
    pos = in_window[in_window[spec.label_column]]
    neg = in_window[~in_window[spec.label_column]]
    n   = min(SAMPLES_PER_CLASS, len(pos), len(neg))
    if n < SAMPLES_PER_CLASS:
        log.warning("%s: limited to %d samples per class.", spec.name, n)
    sampled = pd.concat([
        pos.sample(n, random_state=RANDOM_SEED),
        neg.sample(n, random_state=RANDOM_SEED),
    ]).sample(frac=1, random_state=RANDOM_SEED).reset_index(drop=True)
    sampled["label"] = sampled[spec.label_column].astype(int)
    return sampled


# -----------------------------------------------------------------------------
# Dataset and training
# -----------------------------------------------------------------------------
class AbstractDataset(Dataset):
    """Pre-tokenized abstracts. Tokenizing once up front avoids re-doing it
    every epoch."""

    def __init__(self, texts: list[str], labels: list[int], tokenizer):
        self.labels = torch.tensor(labels, dtype=torch.long)
        enc = tokenizer(
            list(texts), add_special_tokens=True, max_length=MAX_LENGTH,
            padding="max_length", truncation=True,
            return_attention_mask=True, return_tensors="pt",
        )
        self.input_ids = enc["input_ids"]
        self.attention_mask = enc["attention_mask"]

    def __len__(self) -> int:
        return len(self.labels)

    def __getitem__(self, idx: int):
        return {"input_ids": self.input_ids[idx],
                "attention_mask": self.attention_mask[idx],
                "label": self.labels[idx]}


def split_datasets(df: pd.DataFrame, tokenizer):
    """Stratified 75/12.5/12.5 split, returning three tokenized datasets."""
    train_df, temp_df = train_test_split(
        df, test_size=VAL_SPLIT + TEST_SPLIT,
        random_state=RANDOM_SEED, stratify=df["label"],
    )
    val_df, test_df = train_test_split(
        temp_df, test_size=TEST_SPLIT / (VAL_SPLIT + TEST_SPLIT),
        random_state=RANDOM_SEED, stratify=temp_df["label"],
    )
    return (
        AbstractDataset(train_df["abstract"].tolist(), train_df["label"].tolist(), tokenizer),
        AbstractDataset(val_df["abstract"].tolist(),   val_df["label"].tolist(),   tokenizer),
        AbstractDataset(test_df["abstract"].tolist(),  test_df["label"].tolist(),  tokenizer),
    )


def evaluate(model, loader) -> dict:
    model.eval()
    losses, preds, labels, probs = [], [], [], []
    with torch.no_grad():
        for batch in tqdm(loader, desc="evaluating", leave=False):
            ids = batch["input_ids"].to(DEVICE)
            mask = batch["attention_mask"].to(DEVICE)
            y = batch["label"].to(DEVICE)
            with autocast():
                out = model(input_ids=ids, attention_mask=mask, labels=y)
            losses.append(out.loss.item())
            p = torch.softmax(out.logits, dim=1)
            preds.extend(torch.argmax(p, dim=1).cpu().numpy())
            labels.extend(y.cpu().numpy())
            probs.extend(p[:, 1].cpu().numpy())
    pr, rc, f1, _ = precision_recall_fscore_support(labels, preds, average="binary")
    return {
        "loss":      float(np.mean(losses)),
        "accuracy":  float(accuracy_score(labels, preds)),
        "precision": float(pr),
        "recall":    float(rc),
        "f1":        float(f1),
        "auc":       float(roc_auc_score(labels, probs)),
        "confusion_matrix": confusion_matrix(labels, preds).tolist(),
    }


def train_one(spec: TemporalSpec, df: pd.DataFrame, tokenizer) -> None:
    """Train one temporal model end-to-end and save it under OUTPUT_DIR/<name>."""
    log.info("=== %s ===", spec.name)
    sampled = sample_balanced(df, spec)
    log.info("Balanced training frame: %d rows (%.1f%% positive)",
             len(sampled), 100 * sampled["label"].mean())

    train_ds, val_ds, test_ds = split_datasets(sampled, tokenizer)
    train_loader = DataLoader(train_ds, batch_size=BATCH_SIZE, shuffle=True,
                              num_workers=NUM_WORKERS, pin_memory=True)
    val_loader   = DataLoader(val_ds,   batch_size=BATCH_SIZE,
                              num_workers=NUM_WORKERS, pin_memory=True)
    test_loader  = DataLoader(test_ds,  batch_size=BATCH_SIZE,
                              num_workers=NUM_WORKERS, pin_memory=True)

    model = AutoModelForSequenceClassification.from_pretrained(
        BASE_MODEL, num_labels=2
    ).to(DEVICE)

    optimizer = AdamW(model.parameters(), lr=LEARNING_RATE)
    total_steps = (len(train_loader) // GRAD_ACCUM_STEPS) * MAX_EPOCHS
    scheduler = get_linear_schedule_with_warmup(
        optimizer, num_warmup_steps=int(0.1 * total_steps),
        num_training_steps=total_steps,
    )
    scaler = GradScaler()

    train_losses, val_metrics = [], []
    best_f1, best_state, patience, best_epoch = 0.0, None, 0, 0

    for epoch in range(MAX_EPOCHS):
        log.info("Epoch %d/%d", epoch + 1, MAX_EPOCHS)
        model.train()
        running_loss = 0.0
        optimizer.zero_grad()
        for step, batch in enumerate(tqdm(train_loader, desc=f"epoch {epoch+1}")):
            ids  = batch["input_ids"].to(DEVICE)
            mask = batch["attention_mask"].to(DEVICE)
            y    = batch["label"].to(DEVICE)
            with autocast():
                out = model(input_ids=ids, attention_mask=mask, labels=y)
                loss = out.loss / GRAD_ACCUM_STEPS
            running_loss += loss.item() * GRAD_ACCUM_STEPS
            scaler.scale(loss).backward()
            if (step + 1) % GRAD_ACCUM_STEPS == 0:
                scaler.unscale_(optimizer)
                torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
                scaler.step(optimizer)
                scaler.update()
                scheduler.step()
                optimizer.zero_grad()
        train_losses.append(running_loss / len(train_loader))

        val = evaluate(model, val_loader)
        val_metrics.append(val)
        log.info("Val: F1=%.4f AUC=%.4f Acc=%.4f", val["f1"], val["auc"], val["accuracy"])

        if val["f1"] > best_f1:
            best_f1, best_state, best_epoch, patience = val["f1"], {
                k: v.detach().cpu().clone() for k, v in model.state_dict().items()
            }, epoch, 0
        else:
            patience += 1
            if patience >= EARLY_STOP_PATIENCE:
                log.info("Early stopping at epoch %d (best F1=%.4f at epoch %d)",
                         epoch + 1, best_f1, best_epoch + 1)
                break

    if best_state is not None:
        model.load_state_dict(best_state)

    log.info("Evaluating on held-out test split...")
    test_metrics = evaluate(model, test_loader)
    log.info("Test: F1=%.4f AUC=%.4f Acc=%.4f",
             test_metrics["f1"], test_metrics["auc"], test_metrics["accuracy"])

    out_dir = OUTPUT_DIR / spec.name
    out_dir.mkdir(parents=True, exist_ok=True)
    model.save_pretrained(out_dir)
    tokenizer.save_pretrained(out_dir)

    with open(out_dir / "test_metrics.json", "w") as f:
        json.dump(test_metrics, f, indent=2)
    with open(out_dir / "training_history.json", "w") as f:
        json.dump({
            "train_losses": train_losses,
            "val_metrics":  val_metrics,
            "best_epoch":   best_epoch + 1,
            "total_epochs": len(train_losses),
        }, f, indent=2, default=str)
    with open(out_dir / "model_config.json", "w") as f:
        json.dump({
            "name":              spec.name,
            "train_years":       spec.train_years,
            "predict_years":     spec.predict_years,
            "renewal_cutoff":    spec.renewal_cutoff,
            "samples_per_class": SAMPLES_PER_CLASS,
            "batch_size":        BATCH_SIZE,
            "grad_accum_steps":  GRAD_ACCUM_STEPS,
            "effective_batch":   BATCH_SIZE * GRAD_ACCUM_STEPS,
            "learning_rate":     LEARNING_RATE,
            "mixed_precision":   True,
            "temporal_cutoff_applied": True,
        }, f, indent=2)
    log.info("Saved %s -> %s", spec.name, out_dir)


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
def main() -> None:
    log.info("Device: %s", DEVICE)
    df = load_training_frame()
    tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL)
    for spec in TEMPORAL_SPECS:
        t0 = time.time()
        train_one(spec, df, tokenizer)
        log.info("%s done in %.1f min", spec.name, (time.time() - t0) / 60)
        gc.collect()
        if torch.cuda.is_available():
            torch.cuda.empty_cache()


if __name__ == "__main__":
    main()
