#!/usr/bin/env python3

import argparse
import csv
import json
import sqlite3
import sys
import time
import urllib.error
from pathlib import Path

from download_osm_pois import fetch_overpass_pois, normalize_element, save_csv, save_sqlite

DEFAULT_REGIONS = [
    {"name": "tokyo", "south": 35.64, "west": 139.68, "north": 35.72, "east": 139.79},
    {"name": "new_york", "south": 40.68, "west": -74.05, "north": 40.82, "east": -73.86},
    {"name": "london", "south": 51.48, "west": -0.25, "north": 51.55, "east": 0.05},
    {"name": "paris", "south": 48.82, "west": 2.20, "north": 48.90, "east": 2.45},
    {"name": "berlin", "south": 52.47, "west": 13.30, "north": 52.55, "east": 13.50},
    {"name": "sydney", "south": -33.90, "west": 151.18, "north": -33.82, "east": 151.30},
]


def safe_download_region(south, west, north, east, output_csv, output_sqlite, retries=4, delay_seconds=5):
    for attempt in range(1, retries + 1):
        try:
            result = fetch_overpass_pois(south, west, north, east)
            elements = result.get("elements", [])
            records = []
            for element in elements:
                record = normalize_element(element)
                if record is not None:
                    records.append(record)

            if not records:
                print(f"No POIs found for region on attempt {attempt}; continuing.")
                return 0

            save_csv(records, output_csv)
            save_sqlite(records, output_sqlite)
            print(f"Downloaded {len(records)} POIs to {output_csv}")
            return len(records)
        except urllib.error.HTTPError as exc:
            print(f"Attempt {attempt}/{retries} failed with HTTP {exc.code}. Retrying in {delay_seconds}s...")
            if attempt == retries:
                raise
            time.sleep(delay_seconds)
            delay_seconds *= 2
        except Exception as exc:
            print(f"Attempt {attempt}/{retries} failed with unexpected error: {exc}")
            if attempt == retries:
                raise
            time.sleep(delay_seconds)
            delay_seconds *= 2


def main():
    parser = argparse.ArgumentParser(description="Download POIs for multiple OSM regions with retry logic.")
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
    for region in regions:
        name = region["name"]
        out_csv = output_dir / f"{name}.csv"
        out_sqlite = output_dir / f"{name}.db"
        print(f"Downloading region: {name}")
        count = safe_download_region(
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
