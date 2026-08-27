#!/usr/bin/env python3

import argparse
import json
from pathlib import Path
from typing import Iterable

from download_osm_pois import download_region


DEFAULT_REGIONS = [
    {
        "name": "tokyo",
        "south": 35.64,
        "west": 139.68,
        "north": 35.72,
        "east": 139.79,
    },
    {
        "name": "new_york",
        "south": 40.68,
        "west": -74.05,
        "north": 40.82,
        "east": -73.86,
    },
    {
        "name": "london",
        "south": 51.48,
        "west": -0.25,
        "north": 51.55,
        "east": 0.05,
    },
    {
        "name": "paris",
        "south": 48.82,
        "west": 2.20,
        "north": 48.90,
        "east": 2.45,
    },
]


def iter_regions(items: Iterable[dict]) -> Iterable[dict]:
    for item in items:
        yield item


def main():
    parser = argparse.ArgumentParser(description="Download POIs for multiple OSM regions in a batch.")
    parser.add_argument("--regions-file", type=str, default=None)
    parser.add_argument("--output-dir", type=str, default="data/batches")
    args = parser.parse_args()

    if args.regions_file:
        with open(args.regions_file, "r", encoding="utf-8") as handle:
            regions = json.load(handle)
    else:
        regions = DEFAULT_REGIONS

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    total = 0
    for region in iter_regions(regions):
        name = region["name"]
        out_csv = output_dir / f"{name}.csv"
        out_sqlite = output_dir / f"{name}.db"
        print(f"Downloading region: {name}")
        count = download_region(
            region["south"],
            region["west"],
            region["north"],
            region["east"],
            out_csv,
            out_sqlite,
        )
        total += count
        print(f"Region {name} complete: {count} POIs")

    print(f"Total POIs downloaded: {total}")


if __name__ == "__main__":
    main()
