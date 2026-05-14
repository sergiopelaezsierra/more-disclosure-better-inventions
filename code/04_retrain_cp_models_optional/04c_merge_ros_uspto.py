"""
04c_merge_ros_uspto.py — Link the Reliance on Science paper-to-patent
citations to USPTO patent-renewal events.

Inputs:
  REPL_ROS_CSV               Reliance on Science `_pcs_oa.csv` (Marx & Fuegi).
                             Default: ../Data/Input/ROS/_pcs_oa.csv
                             Download from https://doi.org/10.5281/zenodo.4778878
  REPL_USPTO_RENEWAL_OUT     Renewal-events table produced by 04b.
                             Default: ../Data/Input/USPTO/patent_renewal_data.csv

Output:
  REPL_ROS_USPTO_OUT  default: ../Data/Processed/5_papers_cited_by_renewed_patents.csv
    One row per (OpenAlex paper id, renewed patent) citation, with each
    patent's filing/issue date and renewal dates attached.

Processing strategy:
  - Reliance on Science is ~48M rows. Load it in chunks (1M rows each)
    to keep peak memory bounded.
  - For each chunk, filter to US patents, parse the patent number,
    inner-join against the renewed-patent table (indexed for speed).
  - Concatenate the kept rows and write.
"""

from __future__ import annotations

import logging
import math
import os
import sys
from pathlib import Path

import pandas as pd
from tqdm import tqdm


PACKAGE_ROOT = Path(__file__).resolve().parents[2]


def _path(env_var: str, default_relative: str) -> Path:
    v = os.environ.get(env_var, "")
    return Path(v).expanduser().resolve() if v else (PACKAGE_ROOT / default_relative).resolve()


ROS_CSV     = _path("REPL_ROS_CSV",          "../Data/Input/ROS/_pcs_oa.csv")
RENEWAL_CSV = _path("REPL_USPTO_RENEWAL_OUT","../Data/Input/USPTO/patent_renewal_data.csv")
OUT_CSV     = _path("REPL_ROS_USPTO_OUT",
                    "../Data/Processed/5_papers_cited_by_renewed_patents.csv")
OUT_CSV.parent.mkdir(parents=True, exist_ok=True)

CHUNK_SIZE = 1_000_000

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger(__name__)


def estimate_chunks(path: Path, chunk_size: int) -> int:
    """Rough chunk count for a tqdm progress bar; assumes ~150 bytes per row."""
    return max(1, math.ceil(path.stat().st_size / 150 / chunk_size))


def main() -> None:
    if not RENEWAL_CSV.exists():
        sys.exit(f"Renewal table not found: {RENEWAL_CSV}\nRun 04b first.")
    if not ROS_CSV.exists():
        sys.exit(f"Reliance on Science CSV not found: {ROS_CSV}\n"
                 "Download from https://doi.org/10.5281/zenodo.4778878")

    log.info("Loading renewal table: %s", RENEWAL_CSV)
    renewal_df = pd.read_csv(
        RENEWAL_CSV,
        usecols=[
            "patent_number", "filing_date", "issue_date",
            "renewal_4th_date", "renewal_8th_date", "renewal_12th_date",
            "earliest_renewal_date", "any_renewal",
        ],
        dtype={"patent_number": str, "any_renewal": bool},
        low_memory=False,
    )

    # Keep only patents that paid at least one maintenance fee; coerce the
    # patent number to int64 so the chunked merge below can use a fast
    # index-based join.
    renewal_df = renewal_df.loc[renewal_df["any_renewal"]].copy()
    renewal_df["patent_number"] = pd.to_numeric(
        renewal_df["patent_number"], errors="coerce"
    )
    renewal_df = renewal_df.dropna(subset=["patent_number"]).copy()
    renewal_df["patent_number"] = renewal_df["patent_number"].astype("int64")
    renewal_df.set_index("patent_number", inplace=True)
    log.info("Indexed %s renewed patents.", f"{len(renewal_df):,}")

    log.info("Streaming citation data in %d-row chunks...", CHUNK_SIZE)
    reader = pd.read_csv(
        ROS_CSV,
        usecols=lambda c: c in {"patent", "oaid", "confscore"},
        dtype={"patent": str, "oaid": str, "confscore": float},
        chunksize=CHUNK_SIZE,
    )

    keep_cols = [
        "oaid", "patent", "confscore",
        "issue_date", "filing_date",
        "renewal_4th_date", "renewal_8th_date", "renewal_12th_date",
    ]
    matched_chunks: list[pd.DataFrame] = []

    for chunk in tqdm(reader, total=estimate_chunks(ROS_CSV, CHUNK_SIZE),
                      unit="chunk"):
        chunk = chunk.loc[chunk["patent"].str.startswith("us-", na=False)].copy()
        if chunk.empty:
            continue

        # Patent strings look like "us-11426570-b2"; the middle segment is
        # the integer patent number.
        chunk["patent_int"] = pd.to_numeric(
            chunk["patent"].str.split("-").str[1], errors="coerce"
        )
        chunk = chunk.dropna(subset=["patent_int"]).copy()
        chunk["patent_int"] = chunk["patent_int"].astype("int64")

        merged = chunk.merge(
            renewal_df, left_on="patent_int", right_index=True, how="inner"
        )
        if not merged.empty:
            matched_chunks.append(merged[keep_cols])

    if not matched_chunks:
        log.warning("No citations matched any renewed patent. Nothing to write.")
        return

    log.info("Concatenating and writing output...")
    final_df = pd.concat(matched_chunks, ignore_index=True)
    final_df.to_csv(OUT_CSV, index=False)
    log.info("Wrote %s rows to: %s", f"{len(final_df):,}", OUT_CSV)


if __name__ == "__main__":
    main()
