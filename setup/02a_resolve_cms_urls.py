#!/usr/bin/env python3
"""Resolve current CMS Part D / Part B CSV URLs from the CMS data catalog.

CMS publishes a full data.json catalog at https://data.cms.gov/data.json.
The catalog lists every dataset and every distribution (download URL) with
structured metadata including title and resource description. Direct CSV
URLs include a release-month directory and a per-resource UUID — both
change when CMS publishes a new vintage, which means the hardcoded URLs
in setup/03_load_to_snowflake.py will 404 once 2024 data drops.

This script looks up Part D and Part B datasets by title, extracts the
most recent CSV per dataset, and writes setup/data_manifest.json. Re-run
when CMS publishes a new vintage — the loader can then be pointed at the
fresh URLs, or you can wire the loader to read directly from the manifest.

Usage:
    .venv/bin/python setup/02a_resolve_cms_urls.py            # write manifest
    .venv/bin/python setup/02a_resolve_cms_urls.py --print    # print to stdout
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
import urllib.request
from pathlib import Path

CATALOG_URL = "https://data.cms.gov/data.json"
MANIFEST_PATH = Path(__file__).resolve().parent / "data_manifest.json"

# Title matching is the stable identifier — UUIDs and paths change every release.
DATASET_TITLES = {
    "part_d_prescribers": "Medicare Part D Prescribers - by Provider and Drug",
    "part_b_provider_service": "Medicare Physician & Other Practitioners - by Provider and Service",
}

# Distribution titles embed data year as "YYYY-MM" (e.g. "Medicare Part D
# Prescribers - by Provider and Drug : 2023-12"). Use that to sort.
YEAR_PAT = re.compile(r"\b(\d{4})-\d{2}\b")


def fetch_catalog() -> dict:
    print(f"Fetching {CATALOG_URL} ...", file=sys.stderr)
    with urllib.request.urlopen(CATALOG_URL, timeout=30) as resp:
        return json.load(resp)


def best_csv_distribution(dataset: dict) -> dict | None:
    """Return the most-recent CSV distribution for a dataset, or None."""
    candidates = []
    for dist in dataset.get("distribution", []):
        url = (dist.get("downloadURL") or dist.get("accessURL") or "").strip()
        if not url.endswith(".csv"):
            continue
        title = (dist.get("title") or "").strip()
        m = YEAR_PAT.search(title)
        year = int(m.group(1)) if m else 0
        candidates.append((year, title, url, dist))
    if not candidates:
        return None
    candidates.sort(reverse=True)  # newest year first
    year, title, url, dist = candidates[0]
    return {
        "data_year": year if year else None,
        "csv_url": url,
        "distribution_title": title,
        "media_type": dist.get("mediaType"),
        "description": (dist.get("description") or "")[:200],
    }


def head_size(url: str) -> int | None:
    """Try a HEAD request to surface the file size without downloading."""
    try:
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req, timeout=10) as resp:
            return int(resp.headers.get("Content-Length", 0)) or None
    except Exception:
        return None


def build_manifest(catalog: dict) -> dict:
    by_title = {d.get("title", "").strip(): d for d in catalog.get("dataset", [])}
    out = {}
    for key, title in DATASET_TITLES.items():
        dataset = by_title.get(title)
        if dataset is None:
            print(f"ERROR: dataset not found: {title!r}", file=sys.stderr)
            sys.exit(2)
        dist = best_csv_distribution(dataset)
        if dist is None:
            print(f"ERROR: no CSV distribution for {title!r}", file=sys.stderr)
            sys.exit(2)
        size = head_size(dist["csv_url"])
        if size:
            dist["size_bytes"] = size
            dist["size_human"] = f"{size / 1e9:.2f} GB"
        dist["dataset_title"] = title
        dist["dataset_modified"] = dataset.get("modified", "")
        out[key] = dist

    # NPPES isn't in data.cms.gov — it's at download.cms.gov/nppes with a
    # predictable monthly file-name pattern. We can resolve it by HEAD-probing
    # the last few months.
    out["nppes"] = resolve_nppes()
    return out


def resolve_nppes() -> dict:
    """Probe the well-known NPPES URL pattern for the most recent monthly file."""
    today = dt.date.today()
    months = ["January", "February", "March", "April", "May", "June",
              "July", "August", "September", "October", "November", "December"]
    # Try the current month and previous 3 months — NPPES drops one full file
    # per month in the second week.
    for offset in range(0, 4):
        year = today.year
        idx = today.month - 1 - offset
        if idx < 0:
            idx += 12
            year -= 1
        month = months[idx]
        url = f"https://download.cms.gov/nppes/NPPES_Data_Dissemination_{month}_{year}_V2.zip"
        size = head_size(url)
        if size:
            return {
                "data_year": year,
                "month": month,
                "csv_url": url,
                "size_bytes": size,
                "size_human": f"{size / 1e9:.2f} GB",
                "dataset_title": "NPPES Data Dissemination V2 (monthly full)",
            }
    print("WARNING: could not resolve a current NPPES monthly URL", file=sys.stderr)
    return {"csv_url": None, "error": "No NPPES file found in last 4 months"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--print", action="store_true",
                        help="Print to stdout instead of writing manifest file")
    args = parser.parse_args()

    catalog = fetch_catalog()
    manifest = {
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "catalog_source": CATALOG_URL,
        "datasets": build_manifest(catalog),
    }
    body = json.dumps(manifest, indent=2)
    if args.print:
        print(body)
    else:
        MANIFEST_PATH.write_text(body + "\n")
        print(f"Wrote {MANIFEST_PATH}")
        for key, info in manifest["datasets"].items():
            yr = info.get("data_year")
            size = info.get("size_human", "?")
            print(f"  {key:<25} {yr} {size:>10}  {info.get('csv_url', '')[:90]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
