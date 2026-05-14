"""
01d_match_otl_wos.py — Match OTL disclosures to WoS publications.

Implements the Masclans et al. (2025) hybrid matching procedure adapted for
this study:
  Step 0 — Pre-filter to (inventor, author) name pairs that fuzzy-match at
           >= 85% (token-by-token), so the heavy comparisons only run on
           candidate pairs that share at least one researcher.
  Step 1 — Build candidate (disclosure, publication) pairs that share at
           least one researcher.
  Step 2 — Apply the temporal window: publication FY must be in
           [disclosure FY - 1, disclosure FY + 3].
  Step 3 — Compute SciBERT cosine similarity AND fuzzy token-set similarity
           on the (disclosure title, publication title) pair. Retain pairs
           satisfying BOTH thresholds:
             SciBERT cosine >= 0.7
             fuzzy token-set ratio >= 0.5

The hybrid filter (vs. SciBERT-only) reduces the match explosion that
SciBERT-only matching produces on this dataset (median 23 papers per
disclosure -> 3) while preserving the high invention-match rate documented
in the paper.

Output:
  data/Processed/2_disclosure_otl_and_pubs_wos_matched.csv
    Publication-level long-format dataset: matched disclosure-publication
    pairs + unmatched publications + unmatched disclosures.

Requires a GPU for tractable runtimes on the SciBERT encoding step.
"""

from __future__ import annotations

import logging
import os
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import torch
from fuzzywuzzy import fuzz
from tqdm import tqdm
from transformers import AutoModel, AutoTokenizer


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
PACKAGE_ROOT = Path(__file__).resolve().parents[2]


def _from_env(env_var: str, default_relative: str) -> Path:
    v = os.environ.get(env_var, "")
    if v:
        return Path(v).expanduser().resolve()
    return (PACKAGE_ROOT / default_relative).resolve()


OTL_INPUT = _from_env("REPL_OTL_MERGED",
                      "../Data/Processed/1_disclosure_otl_data_output.csv")
WOS_INPUT = _from_env("REPL_WOS_CLEAN",
                      "../Data/Input/WOS/combined_wos_data_2019_2025FY.csv")
OUTPUT    = _from_env("REPL_MATCH_OUTPUT",
                      "../Data/Processed/2_disclosure_otl_and_pubs_wos_matched.csv")

OUTPUT.parent.mkdir(parents=True, exist_ok=True)

# Thresholds — fixed per the paper (see Section 4.4).
TIME_WINDOW_START          = -1
TIME_WINDOW_END            = 3
BERT_SIMILARITY_THRESHOLD  = 0.7   # SciBERT cosine similarity
FUZZY_SIMILARITY_THRESHOLD = 0.5   # fuzz.token_set_ratio (rescaled to 0-1)
NAME_THRESHOLD             = 85    # fuzz.ratio for (inventor, author) pairs
MAX_AUTHORS_PER_PAPER      = 50    # drop very-high-author collaborations

MODEL_NAME = "allenai/scibert_scivocab_uncased"
BATCH_SIZE = 32

# Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger(__name__)


# -----------------------------------------------------------------------------
# Name standardization
# -----------------------------------------------------------------------------
def standardize_name(name: str | float) -> str:
    """Lower-case, sort name tokens, handle 'Last, First' format."""
    if pd.isna(name) or name == "":
        return ""
    n = " ".join(str(name).strip().lower().split())
    if "," in n:
        last, _, first = n.partition(",")
        first = first.strip().split(" ")[0] if first.strip() else ""
        n = f"{first.strip()} {last.strip()}"
    n = n.replace(",", "").strip()
    return " ".join(sorted(n.split()))


def extract_names(s: str | float, sep: str = ";") -> list[str]:
    if pd.isna(s):
        return []
    return [x for x in (standardize_name(p) for p in str(s).split(sep)) if x]


# -----------------------------------------------------------------------------
# Load inputs
# -----------------------------------------------------------------------------
log.info("Reading OTL: %s", OTL_INPUT)
otl_df = pd.read_csv(OTL_INPUT)
log.info("Reading WoS: %s", WOS_INPUT)
wos_df = pd.read_csv(WOS_INPUT, encoding="latin1", low_memory=False)

otl_df = otl_df.dropna(subset=["invention_id", "inventors",
                               "Invention::Title.disc", "fiscal_year.disc"])
wos_df = wos_df.dropna(subset=["UT", "Author.Full.Names",
                               "Article.Title", "Publication.Fiscal.Year"])

# Drop very-high-author papers (e.g. high-energy physics consortia where
# author lists run into the hundreds and overwhelm the name-matching step).
wos_df["num_authors"] = wos_df["Author.Full.Names"].apply(
    lambda s: len([n for n in str(s).split(";") if n.strip()])
)
n_before = len(wos_df)
wos_df = wos_df[wos_df["num_authors"] <= MAX_AUTHORS_PER_PAPER].copy()
log.info("Dropped %d papers with > %d authors (e.g. consortia).",
         n_before - len(wos_df), MAX_AUTHORS_PER_PAPER)

# -----------------------------------------------------------------------------
# Step 0 — pre-filter to (inventor, author) name pairs that fuzzy-match
# -----------------------------------------------------------------------------
log.info("Extracting unique inventors and authors...")
all_inventors = set()
for s in tqdm(otl_df["inventors"].dropna(), desc="inventors"):
    all_inventors.update(extract_names(s))
all_authors = set()
for s in tqdm(wos_df["Author.Full.Names"].dropna(), desc="authors"):
    all_authors.update(extract_names(s))
all_inventors.discard("")
all_authors.discard("")
log.info("Unique inventors: %d | unique authors: %d",
         len(all_inventors), len(all_authors))

log.info("Matching inventors to authors (fuzzy >= %d)...", NAME_THRESHOLD)
matches = []
for inv in tqdm(list(all_inventors), desc="researcher matching"):
    for auth in all_authors:
        if fuzz.ratio(inv, auth) >= NAME_THRESHOLD:
            matches.append((inv, auth))
researcher_matches = pd.DataFrame(matches,
                                  columns=["inventor_name", "author_name"])
matched_inventors = set(researcher_matches["inventor_name"])
matched_authors   = set(researcher_matches["author_name"])
log.info("Researcher pairs matched: %d (%d inventors <-> %d authors)",
         len(researcher_matches), len(matched_inventors), len(matched_authors))

# Attach standardized researcher sets to each row.
otl_df["researcher_set"] = otl_df["inventors"].apply(
    lambda s: set(extract_names(s)) & matched_inventors
)
wos_df["researcher_set"] = wos_df["Author.Full.Names"].apply(
    lambda s: set(extract_names(s)) & matched_authors
)
otl_f = otl_df[otl_df["researcher_set"].apply(bool)].copy()
wos_f = wos_df[wos_df["researcher_set"].apply(bool)].copy()
log.info("After researcher pre-filter: %d disclosures, %d papers",
         len(otl_f), len(wos_f))


# -----------------------------------------------------------------------------
# Step 1 — candidate (disclosure, paper) pairs that share >= 1 researcher
# -----------------------------------------------------------------------------
log.info("Finding candidate (disclosure, paper) pairs...")
candidates = []
for _, disc in tqdm(otl_f.iterrows(), total=len(otl_f), desc="candidates"):
    for _, paper in wos_f.iterrows():
        shared = disc["researcher_set"] & paper["researcher_set"]
        if shared:
            candidates.append({
                "invention_id":           disc["invention_id"],
                "UT":                     paper["UT"],
                "disclosure_year":        disc["fiscal_year.disc"],
                "paper_year":             paper["Publication.Fiscal.Year"],
                "num_shared_researchers": len(shared),
            })
cand = pd.DataFrame(candidates)
log.info("Candidate pairs (shared researcher): %d", len(cand))


# -----------------------------------------------------------------------------
# Step 2 — temporal window
# -----------------------------------------------------------------------------
cand["time_gap"] = cand["paper_year"] - cand["disclosure_year"]
cand = cand[(cand["time_gap"] >= TIME_WINDOW_START) &
            (cand["time_gap"] <= TIME_WINDOW_END)].copy()
log.info("After temporal filter [%d, %d]: %d pairs",
         TIME_WINDOW_START, TIME_WINDOW_END, len(cand))


# -----------------------------------------------------------------------------
# Step 3 — fuzzy + SciBERT title similarity
# -----------------------------------------------------------------------------
pairs = cand.merge(
    otl_f[["invention_id", "Invention::Title.disc"]],
    on="invention_id", how="left",
).merge(
    wos_f[["UT", "Article.Title"]], on="UT", how="left",
)

log.info("Computing fuzzy title similarities...")
pairs["fuzzy_similarity"] = [
    fuzz.token_set_ratio(str(t1), str(t2)) / 100.0 if pd.notna(t1) and pd.notna(t2)
    else 0.0
    for t1, t2 in zip(pairs["Invention::Title.disc"], pairs["Article.Title"])
]

log.info("Loading SciBERT (%s)...", MODEL_NAME)
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
log.info("Using device: %s", device)
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
model = AutoModel.from_pretrained(MODEL_NAME).to(device).eval()

unique_titles = set(pairs["Invention::Title.disc"].dropna().unique())
unique_titles.update(pairs["Article.Title"].dropna().unique())
unique_titles = list(unique_titles)
log.info("Encoding %d unique titles with SciBERT...", len(unique_titles))

embeddings: dict[str, np.ndarray] = {}
for i in tqdm(range(0, len(unique_titles), BATCH_SIZE), desc="encode"):
    batch = unique_titles[i:i + BATCH_SIZE]
    enc = tokenizer(batch, return_tensors="pt", padding=True,
                    truncation=True, max_length=512).to(device)
    with torch.no_grad():
        out = model(**enc).last_hidden_state[:, 0, :].cpu().numpy()
    for title, emb in zip(batch, out):
        embeddings[title] = emb

log.info("Computing SciBERT cosine similarities...")
def _cos(a: np.ndarray, b: np.ndarray) -> float:
    n = (np.linalg.norm(a) * np.linalg.norm(b))
    return float(np.dot(a, b) / n) if n > 0 else 0.0

pairs["bert_similarity"] = [
    _cos(embeddings[t1], embeddings[t2])
    if pd.notna(t1) and pd.notna(t2)
       and t1 in embeddings and t2 in embeddings
    else 0.0
    for t1, t2 in zip(pairs["Invention::Title.disc"], pairs["Article.Title"])
]

final = pairs[(pairs["bert_similarity"]  >= BERT_SIMILARITY_THRESHOLD) &
              (pairs["fuzzy_similarity"] >= FUZZY_SIMILARITY_THRESHOLD)].copy()
log.info("After hybrid filter (BERT>=%.2f & fuzzy>=%.2f): %d matches",
         BERT_SIMILARITY_THRESHOLD, FUZZY_SIMILARITY_THRESHOLD, len(final))

log.info("Unique papers matched:     %d", final["UT"].nunique())
log.info("Unique inventions matched: %d", final["invention_id"].nunique())
log.info("Median papers/invention:   %d",
         int(final.groupby("invention_id")["UT"].count().median()))


# -----------------------------------------------------------------------------
# Step 4 — assemble long-format dataset (matched pairs + unmatched rows)
# -----------------------------------------------------------------------------
log.info("Assembling integrated dataset...")
otl_sfx = otl_df.add_suffix("_otl")
wos_sfx = wos_df.add_suffix("_wos")

rows = []
for _, m in tqdm(final.iterrows(), total=len(final), desc="matched"):
    paper = wos_sfx[wos_sfx["UT_wos"] == m["UT"]]
    disc  = otl_sfx[otl_sfx["invention_id_otl"] == m["invention_id"]]
    if len(paper) and len(disc):
        row = {**paper.iloc[0].to_dict(), **disc.iloc[0].to_dict()}
        row.update({
            "disclosed":              1,
            "pubs_matched_to_discs":  1,
            "bert_similarity":        m["bert_similarity"],
            "fuzzy_similarity":       m["fuzzy_similarity"],
            "time_gap":               m["time_gap"],
            "num_shared_researchers": m["num_shared_researchers"],
        })
        rows.append(row)

matched_uts = set(final["UT"])
for _, paper in wos_sfx[~wos_sfx["UT_wos"].isin(matched_uts)].iterrows():
    row = paper.to_dict()
    row.update({c: None for c in otl_sfx.columns})
    row.update({"disclosed": 0, "pubs_matched_to_discs": 0})
    rows.append(row)

matched_invs = set(final["invention_id"])
for _, disc in otl_sfx[~otl_sfx["invention_id_otl"].isin(matched_invs)].iterrows():
    row = disc.to_dict()
    row.update({c: None for c in wos_sfx.columns})
    row.update({"disclosed": 1, "pubs_matched_to_discs": 0})
    rows.append(row)

result = pd.DataFrame(rows)
front = ["pubs_matched_to_discs", "disclosed", "bert_similarity",
         "fuzzy_similarity", "time_gap", "num_shared_researchers"]
other = [c for c in result.columns if c not in front]
result = result[front + other]

result.to_csv(OUTPUT, index=False)
log.info("Saved: %s (%d rows)", OUTPUT, len(result))
