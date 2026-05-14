"""
04a_download_openalex.py — Build the US-publication training pool.

Downloads ~1,000,000 US-affiliated publications (2000–2019) from the
OpenAlex API and writes a single CSV used by 04c, 04d, and 04e to build
the SciBERT training data. Samples are allocated to each year in
proportion to that year's US publication count, so the resulting pool
preserves the temporal distribution of US science output.

Inputs (environment variables, all optional):
  REPL_OA_OUT_DIR     output directory.
                      Default: <package>/../Data/Input/OA
  REPL_OA_EMAIL       contact email for the OpenAlex polite pool.
                      Required by OpenAlex for higher-rate access.
                      No default — set this before running.
  REPL_OA_TOTAL       total number of papers to download
                      (default: 1,000,000).
  REPL_OA_START_YEAR  earliest publication year (default: 2000).
  REPL_OA_END_YEAR    latest publication year (default: 2019).

Output:
  <out_dir>/us_papers_<YEAR>.csv     one CSV per year
  <out_dir>/OpenAlexData.csv         concatenated file used by step 04c
"""

from __future__ import annotations

import concurrent.futures
import logging
import os
import sys
import time
from pathlib import Path
from threading import Lock

import pandas as pd
import requests
from tqdm import tqdm


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
PACKAGE_ROOT = Path(__file__).resolve().parents[2]

OUT_DIR     = Path(os.environ.get("REPL_OA_OUT_DIR",
                                  PACKAGE_ROOT / ".." / "Data" / "Input" / "OA")).resolve()
EMAIL       = os.environ.get("REPL_OA_EMAIL", "")
TOTAL       = int(os.environ.get("REPL_OA_TOTAL",      "1000000"))
START_YEAR  = int(os.environ.get("REPL_OA_START_YEAR", "2000"))
END_YEAR    = int(os.environ.get("REPL_OA_END_YEAR",   "2019"))
COMBINED    = OUT_DIR / "OpenAlexData.csv"

BASE_URL  = "https://api.openalex.org/works"
PER_PAGE  = 200
WORKERS   = 5  # safe for the OpenAlex polite pool (~10 req/s ceiling)
CHUNK     = 200_000  # rows per intermediate aggregation chunk

if not EMAIL:
    sys.exit(
        "REPL_OA_EMAIL is not set. The OpenAlex polite pool requires a contact\n"
        "email so that requests can be deprioritized rather than blocked under\n"
        "load. See https://docs.openalex.org/how-to-use-the-api/rate-limits-and-authentication"
    )

OUT_DIR.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger(__name__)

_progress_lock = Lock()


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
def safe_nested(obj, *keys, default=None):
    """Walk a chain of `.get(key)` calls, returning `default` on any miss."""
    cur = obj
    for k in keys:
        if cur is None:
            return default
        cur = cur.get(k) if isinstance(cur, dict) else None
    return cur if cur is not None else default


def decode_abstract(inverted_index: dict[str, list[int]] | None) -> str | None:
    """Reconstruct the abstract text from OpenAlex's inverted-index encoding.

    OpenAlex returns abstracts as {word: [position1, position2, ...]} to avoid
    redistributing copyrighted text directly. Rebuild the original word order
    by inverting that map.
    """
    if not inverted_index:
        return None
    try:
        positions: dict[int, str] = {}
        for word, indices in inverted_index.items():
            for idx in indices:
                positions[idx] = word
        return " ".join(positions[i] for i in sorted(positions))
    except Exception:
        return None


def counts_by_year(start: int, end: int) -> dict[int, int]:
    """Return total US-affiliated publication counts per year (cheap one-page queries)."""
    out: dict[int, int] = {}
    headers = {"User-Agent": f"mailto:{EMAIL}"}
    for year in tqdm(range(start, end + 1), desc="Fetching yearly counts"):
        params = {
            "filter": f"publication_year:{year},authorships.institutions.country_code:US",
            "per-page": 1,
            "select": "id",
        }
        try:
            r = requests.get(BASE_URL, params=params, headers=headers, timeout=60)
            r.raise_for_status()
            out[year] = r.json().get("meta", {}).get("count", 0)
        except Exception as e:
            log.warning("Year %d count failed: %s", year, e)
            out[year] = 0
    return out


def samples_per_year(counts: dict[int, int], total: int) -> dict[int, int]:
    """Allocate `total` samples to years in proportion to their US-publication counts."""
    grand = sum(counts.values()) or 1
    out = {y: int(c / grand * total) for y, c in counts.items()}
    diff = total - sum(out.values())
    if diff and out:
        # Push rounding remainder onto the most-populous year.
        top = max(out, key=out.get)
        out[top] += diff
    return out


def download_one_year(year: int, target: int, pbar: tqdm) -> int:
    """Download `target` publications for `year`, paginating with a cursor.

    Resumes from a previously saved year-CSV if it already contains enough
    rows; otherwise restarts the year (avoids the complexity of resuming
    from a saved cursor partway through pagination).
    """
    if target <= 0:
        return 0
    year_file = OUT_DIR / f"us_papers_{year}.csv"

    existing: list[dict] = []
    if year_file.exists():
        try:
            existing = pd.read_csv(year_file).to_dict("records")
            with _progress_lock:
                pbar.update(len(existing))
        except Exception:
            existing = []

    if len(existing) >= target:
        return len(existing)
    if existing:
        # Partial file: roll back the progress credit and refetch.
        with _progress_lock:
            pbar.update(-len(existing))
        existing = []

    collected: list[dict] = []
    cursor = "*"
    headers = {"User-Agent": f"mailto:{EMAIL}"}

    while len(collected) < target:
        params = {
            "filter":   f"publication_year:{year},authorships.institutions.country_code:US",
            "per-page": PER_PAGE,
            "cursor":   cursor,
            "select":   ",".join([
                "id", "doi", "title", "publication_year", "publication_date",
                "cited_by_count", "type", "open_access", "primary_location",
                "authorships", "topics", "concepts", "abstract_inverted_index",
            ]),
        }

        for attempt in range(5):
            try:
                r = requests.get(BASE_URL, params=params, headers=headers, timeout=60)
                if r.status_code == 429:
                    time.sleep(int(r.headers.get("Retry-After", 2)) + 1)
                    continue
                r.raise_for_status()
                data = r.json()
                break
            except requests.exceptions.RequestException:
                time.sleep(2 ** attempt)
        else:
            log.warning("Year %d: exhausted retries", year)
            break

        results = data.get("results", [])
        if not results:
            break

        batch: list[dict] = []
        for paper in results:
            if len(collected) + len(batch) >= target:
                break
            batch.append({
                "id":                paper.get("id"),
                "title":             paper.get("title"),
                "doi":               paper.get("doi"),
                "publication_year":  paper.get("publication_year"),
                "publication_date":  paper.get("publication_date"),
                "cited_by_count":    paper.get("cited_by_count"),
                "type":              paper.get("type"),
                "open_access_status": safe_nested(paper, "open_access", "oa_status"),
                "journal":           safe_nested(paper, "primary_location", "source", "display_name"),
                "authors": [
                    safe_nested(a, "author", "display_name", default="Unknown")
                    for a in paper.get("authorships", [])
                ],
                "institutions": [
                    safe_nested(inst, "display_name", default="Unknown")
                    for a in paper.get("authorships", [])
                    for inst in a.get("institutions", [])
                ],
                "abstract": decode_abstract(paper.get("abstract_inverted_index")),
            })
        collected.extend(batch)
        with _progress_lock:
            pbar.update(len(batch))

        cursor = data.get("meta", {}).get("next_cursor")
        if not cursor:
            break

    try:
        pd.DataFrame(collected).to_csv(year_file, index=False)
    except Exception as e:
        log.warning("Year %d: save failed: %s", year, e)

    return len(collected)


def combine_year_csvs(per_year: dict[int, int]) -> None:
    """Concatenate per-year CSVs into the single OpenAlexData.csv."""
    files = [OUT_DIR / f"us_papers_{y}.csv" for y in sorted(per_year)]
    files = [f for f in files if f.exists()]
    if not files:
        log.warning("No per-year files to combine.")
        return

    if COMBINED.exists():
        COMBINED.unlink()

    total = 0
    for i, f in enumerate(tqdm(files, desc="Combining per-year CSVs")):
        df = pd.read_csv(f)
        df.to_csv(COMBINED, index=False, mode=("w" if i == 0 else "a"),
                  header=(i == 0))
        total += len(df)
    log.info("Combined: %s (%d rows)", COMBINED, total)


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
def main() -> None:
    log.info("Downloading ~%s US publications from OpenAlex (%d–%d) to %s",
             f"{TOTAL:,}", START_YEAR, END_YEAR, OUT_DIR)

    counts = counts_by_year(START_YEAR, END_YEAR)
    targets = samples_per_year(counts, TOTAL)
    log.info("Allocated targets: %s", {y: targets[y] for y in sorted(targets)})

    with tqdm(total=sum(targets.values()), unit="paper",
              desc="Total progress") as pbar:
        with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as ex:
            futs = [ex.submit(download_one_year, y, n, pbar)
                    for y, n in targets.items()]
            for fut in concurrent.futures.as_completed(futs):
                try:
                    fut.result()
                except Exception as e:
                    log.error("Year worker failed: %s", e)

    combine_year_csvs(targets)


if __name__ == "__main__":
    main()
