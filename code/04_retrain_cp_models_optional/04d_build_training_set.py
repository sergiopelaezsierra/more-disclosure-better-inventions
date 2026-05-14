"""
04d_build_training_set.py — Assemble the SciBERT training file.

For each OpenAlex publication, attach an indicator for whether it was
cited by at least one renewed U.S. patent (plus per-stage renewal flags
and the earliest issue date of any citing renewed patent). This produces
the file that 04e_train_scibert.py consumes.

Inputs:
  REPL_OA_COMBINED       OpenAlex master file built by 04a.
                         Default: ../Data/Input/OA/OpenAlexData.csv
  REPL_ROS_USPTO_OUT     Paper-to-renewed-patent matches from 04c.
                         Default: ../Data/Processed/5_papers_cited_by_renewed_patents.csv

Output:
  REPL_TRAINING_SET      Default: ../Data/Processed/6_USPTO+RO+OA.csv
                         One row per OpenAlex publication, with added
                         renewal-citation columns. This is the file
                         04e_train_scibert.py reads.
"""

from __future__ import annotations

import logging
import os
import sys
from pathlib import Path

import pandas as pd
from tqdm import tqdm


PACKAGE_ROOT = Path(__file__).resolve().parents[2]


def _path(env_var: str, default_relative: str) -> Path:
    v = os.environ.get(env_var, "")
    return Path(v).expanduser().resolve() if v else (PACKAGE_ROOT / default_relative).resolve()


OPENALEX_CSV   = _path("REPL_OA_COMBINED",  "../Data/Input/OA/OpenAlexData.csv")
ROS_USPTO_CSV  = _path("REPL_ROS_USPTO_OUT","../Data/Processed/5_papers_cited_by_renewed_patents.csv")
OUTPUT_CSV     = _path("REPL_TRAINING_SET", "../Data/Processed/6_USPTO+RO+OA.csv")
OUTPUT_CSV.parent.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger(__name__)


def clean_openalex_id(series: pd.Series) -> pd.Series:
    """Strip the OpenAlex URL prefix and the `W` letter, then coerce to int.

    OpenAlex IDs look like `https://openalex.org/W2103017472`. The numeric
    suffix is the canonical identifier and is what the citation file's
    `oaid` column uses (without prefix).
    """
    cleaned = (series.astype(str)
               .str.replace(r"https://openalex\.org/", "", regex=True)
               .str.replace("W", "", regex=False))
    return pd.to_numeric(cleaned, errors="coerce")


def main() -> None:
    if not OPENALEX_CSV.exists():
        sys.exit(f"OpenAlex file not found: {OPENALEX_CSV}\nRun 04a first.")
    if not ROS_USPTO_CSV.exists():
        sys.exit(f"Citation file not found: {ROS_USPTO_CSV}\nRun 04c first.")

    log.info("Loading OpenAlex: %s", OPENALEX_CSV)
    openalex = pd.read_csv(OPENALEX_CSV, low_memory=False)
    log.info("OpenAlex rows: %s", f"{len(openalex):,}")

    log.info("Loading citation file: %s", ROS_USPTO_CSV)
    citations = pd.read_csv(ROS_USPTO_CSV)
    log.info("Citation rows: %s", f"{len(citations):,}")

    # Aggregate citations to one row per OpenAlex paper.
    log.info("Aggregating citation rows to publication level...")
    aggregated = citations.groupby("oaid").agg(
        renewed_patent_count   = ("patent", "nunique"),
        avg_confscore          = ("confscore", "mean"),
        earliest_issue_date    = ("issue_date", "min"),
        has_4th_year_renewal   = ("renewal_4th_date",  lambda x: x.notna().any()),
        has_8th_year_renewal   = ("renewal_8th_date",  lambda x: x.notna().any()),
        has_12th_year_renewal  = ("renewal_12th_date", lambda x: x.notna().any()),
    ).reset_index()
    aggregated["cited_by_renewed_patent"] = True
    log.info("Aggregated to %s publications cited by a renewed patent.",
             f"{len(aggregated):,}")

    log.info("Standardizing join IDs...")
    openalex["join_id"]    = clean_openalex_id(openalex["id"])
    aggregated["join_id"]  = clean_openalex_id(aggregated["oaid"])

    log.info("Merging citation aggregates into OpenAlex...")
    merged = pd.merge(openalex, aggregated, on="join_id", how="left")

    # Publications with no citation rows get explicit False/0 flags.
    bool_cols = ["cited_by_renewed_patent", "has_4th_year_renewal",
                 "has_8th_year_renewal",    "has_12th_year_renewal"]
    merged[bool_cols] = merged[bool_cols].fillna(False)
    merged["renewed_patent_count"] = merged["renewed_patent_count"].fillna(0)
    merged.drop(columns="join_id", inplace=True)

    log.info("Writing training file: %s", OUTPUT_CSV)
    merged.to_csv(OUTPUT_CSV, index=False)
    n_pos = int(merged["cited_by_renewed_patent"].sum())
    log.info("Saved %s rows (%s positives, %.1f%% prevalence).",
             f"{len(merged):,}", f"{n_pos:,}", 100 * n_pos / len(merged))


if __name__ == "__main__":
    main()
