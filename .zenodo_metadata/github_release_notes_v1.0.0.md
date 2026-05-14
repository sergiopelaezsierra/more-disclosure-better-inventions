# GitHub release v1.0.0 — paste this into the "Describe this release" field

When you publish this release on GitHub, Zenodo will auto-archive the
repository at this tag and mint a DOI for the code. The notes below are
what reviewers and readers see on the GitHub release page (and what
Zenodo records as the description for the v1.0.0 archive).

---

## Title
**v1.0.0 — Initial submission release**

## Body

> First public release of the replication package for "More Disclosure,
> Better Inventions? Commercial Potential in University Invention
> Disclosures."
>
> ### What's included
> - End-to-end code for the analysis: data construction (R + Python),
>   commercial-potential scoring (Python + the trained SciBERT models),
>   and all paper outputs (R — one script per Table or Figure).
> - A `run_all.R` wrapper that reproduces Tables 3–7 and Figures 3–7 of
>   the manuscript in ~5 minutes on a single machine (no GPU required for
>   this stage; only `R 4.4+` and a handful of CRAN packages).
> - Optional re-training scripts that rebuild the three temporal SciBERT
>   classifiers from public data (OpenAlex + USPTO Maintenance Fee Events +
>   Marx & Fuegi's Reliance on Science citations).
>
> ### What's NOT included
> - The publication-level analytical dataset (built from confidential OTL
>   exports and a licensed Web of Science query); see `DATA_AVAILABILITY.md`.
> - The trained SciBERT model weights (~1.3 GB). These are released as a
>   separate Zenodo deposit; see `DATA_AVAILABILITY.md` for the DOI.
>
> ### Verification
> All 10 paper-output scripts have been verified end-to-end to reproduce
> the manuscript numbers exactly (see commit history and per-script logs).
>
> ### How to cite
> When citing this software, please use the Zenodo DOI minted on this
> release. The corresponding paper is forthcoming; preprint and journal
> DOI will be added on acceptance.
