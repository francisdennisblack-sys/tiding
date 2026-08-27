#!/usr/bin/env python3

import argparse
import time
from pathlib import Path

from download_osm_pois import fetch_overpass_pois, normalize_element, save_csv, save_sqlite

STATES = [
    {"name": "alabama", "south": 30.18, "west": -88.47, "north": 35.01, "east": -84.89},
    {"name": "alaska", "south": 51.21, "west": -179.15, "north": 71.39, "east": -129.98},
    {"name": "arizona", "south": 31.33, "west": -114.82, "north": 37.00, "east": -109.05},
    {"name": "arkansas", "south": 33.00, "west": -94.62, "north": 36.50, "east": -89.64},
    {"name": "california", "south": 32.53, "west": -124.48, "north": 42.01, "east": -114.13},
    {"name": "colorado", "south": 36.99, "west": -109.05, "north": 41.00, "east": -102.05},
    {"name": "connecticut", "south": 40.96, "west": -73.73, "north": 42.05, "east": -71.79},
    {"name": "delaware", "south": 38.45, "west": -75.79, "north": 39.84, "east": -75.04},
    {"name": "florida", "south": 24.39, "west": -87.63, "north": 31.00, "east": -80.03},
    {"name": "georgia", "south": 30.35, "west": -85.61, "north": 35.00, "east": -81.00},
    {"name": "hawaii", "south": 18.91, "west": -160.30, "north": 22.23, "east": -154.80},
    {"name": "idaho", "south": 41.99, "west": -117.24, "north": 49.00, "east": -111.04},
    {"name": "illinois", "south": 36.97, "west": -91.52, "north": 42.51, "east": -87.02},
    {"name": "indiana", "south": 37.77, "west": -88.09, "north": 41.76, "east": -84.81},
    {"name": "iowa", "south": 40.37, "west": -96.64, "north": 43.50, "east": -90.14},
    {"name": "kansas", "south": 36.99, "west": -102.05, "north": 40.00, "east": -94.59},
    {"name": "kentucky", "south": 36.49, "west": -89.57, "north": 39.15, "east": -81.97},
    {"name": "louisiana", "south": 28.92, "west": -94.04, "north": 33.03, "east": -88.76},
    {"name": "maine", "south": 43.06, "west": -71.08, "north": 47.46, "east": -66.95},
    {"name": "maryland", "south": 37.91, "west": -79.49, "north": 39.72, "east": -75.04},
    {"name": "massachusetts", "south": 41.24, "west": -73.51, "north": 42.89, "east": -69.86},
    {"name": "michigan", "south": 41.70, "west": -90.42, "north": 48.30, "east": -82.12},
    {"name": "minnesota", "south": 43.49, "west": -97.24, "north": 49.38, "east": -89.49},
    {"name": "mississippi", "south": 30.17, "west": -91.65, "north": 35.00, "east": -88.09},
    {"name": "missouri", "south": 35.99, "west": -95.77, "north": 40.61, "east": -89.10},
    {"name": "montana", "south": 44.36, "west": -116.05, "north": 49.00, "east": -104.04},
    {"name": "nebraska", "south": 40.00, "west": -104.05, "north": 43.00, "east": -95.31},
    {"name": "nevada", "south": 35.00, "west": -120.01, "north": 42.00, "east": -114.04},
    {"name": "new_hampshire", "south": 42.70, "west": -72.56, "north": 45.30, "east": -70.56},
    {"name": "new_jersey", "south": 38.92, "west": -75.56, "north": 41.36, "east": -73.89},
    {"name": "new_mexico", "south": 31.33, "west": -109.05, "north": 36.99, "east": -103.00},
    {"name": "new_york", "south": 40.48, "west": -79.76, "north": 45.02, "east": -71.86},
    {"name": "north_carolina", "south": 33.84, "west": -84.32, "north": 36.59, "east": -75.46},
    {"name": "north_dakota", "south": 45.94, "west": -104.05, "north": 49.00, "east": -96.56},
    {"name": "ohio", "south": 38.40, "west": -84.82, "north": 42.32, "east": -80.52},
    {"name": "oklahoma", "south": 33.64, "west": -103.00, "north": 37.00, "east": -94.43},
    {"name": "oregon", "south": 41.99, "west": -124.57, "north": 46.29, "east": -116.46},
    {"name": "pennsylvania", "south": 39.72, "west": -80.52, "north": 42.27, "east": -74.69},
    {"name": "rhode_island", "south": 41.15, "west": -71.90, "north": 42.02, "east": -71.13},
    {"name": "south_carolina", "south": 32.03, "west": -83.35, "north": 35.22, "east": -78.54},
    {"name": "south_dakota", "south": 42.48, "west": -104.06, "north": 45.95, "east": -96.44},
    {"name": "tennessee", "south": 34.98, "west": -90.31, "north": 36.68, "east": -81.65},
    {"name": "texas", "south": 25.84, "west": -106.65, "north": 36.50, "east": -93.51},
    {"name": "utah", "south": 36.99, "west": -114.05, "north": 42.00, "east": -109.04},
    {"name": "vermont", "south": 42.73, "west": -73.44, "north": 45.02, "east": -71.47},
    {"name": "virginia", "south": 36.54, "west": -83.67, "north": 39.46, "east": -75.24},
    {"name": "washington", "south": 45.54, "west": -124.79, "north": 49.00, "east": -116.91},
    {"name": "west_virginia", "south": 37.20, "west": -82.65, "north": 40.64, "east": -77.72},
    {"name": "wisconsin", "south": 42.49, "west": -92.89, "north": 47.30, "east": -86.80},
    {"name": "wyoming", "south": 41.00, "west": -111.06, "north": 45.00, "east": -104.05},
    {"name": "district_of_columbia", "south": 38.80, "west": -77.12, "north": 38.99, "east": -76.89},
]

LARGEST_STATES = {
    "alaska", "california", "texas", "montana", "wyoming", "nevada", "oregon", "washington", "idaho",
    "arizona", "new_mexico", "colorado", "utah", "florida", "georgia", "north_carolina", "michigan",
    "pennsylvania", "new_york", "virginia"
}
LARGE_STATES = {
    "alabama", "arkansas", "iowa", "kansas", "kentucky", "louisiana", "maine", "maryland",
    "massachusetts", "minnesota", "mississippi", "missouri", "nebraska", "new_hampshire",
    "new_jersey", "north_dakota", "ohio", "oklahoma", "rhode_island", "south_carolina",
    "south_dakota", "tennessee", "vermont", "west_virginia", "wisconsin"
}


def state_target_count(state_name: str) -> int:
    if state_name in LARGEST_STATES:
        return 15000
    if state_name in LARGE_STATES:
        return 12500
    return 10000


def download_state(state: dict, output_dir: Path):
    name = state["name"]
    target = state_target_count(name)
    south, west, north, east = state["south"], state["west"], state["north"], state["east"]
    out_csv = output_dir / f"{name}.csv"
    out_sqlite = output_dir / f"{name}.db"
    print(f"Downloading {name} ({south},{west}) -> ({north},{east}) target={target}")

    records = []
    for attempt in range(1, 6):
        result = fetch_overpass_pois(south, west, north, east)
        elements = result.get("elements", [])
        records = []
        seen = set()

        for element in elements:
            record = normalize_element(element)
            if record is None:
                continue
            if record["poi_id"] in seen:
                continue
            seen.add(record["poi_id"])
            records.append(record)

        if len(records) >= target:
            save_csv(records, out_csv)
            save_sqlite(records, out_sqlite)
            print(f"Saved {len(records)} POIs for {name} to {out_csv} (target={target})")
            return len(records)

        if attempt < 5:
            padding = 0.12 * attempt
            south = max(-90, south - padding)
            west = max(-180, west - padding)
            north = min(90, north + padding)
            east = min(180, east + padding)
            print(f"Retrying {name} with expanded bbox attempt {attempt + 1}: ({south},{west}) -> ({north},{east})")
            time.sleep(1.0)

    if not records:
        print(f"No POIs found for {name}.")
        return 0

    save_csv(records, out_csv)
    save_sqlite(records, out_sqlite)
    print(f"Saved {len(records)} POIs for {name} to {out_csv} (below target {target}, but final batch available)")
    return len(records)


def main():
    parser = argparse.ArgumentParser(description="Download POIs for all U.S. states and DC.")
    parser.add_argument("--output-dir", type=str, default="../data/us_state_pois")
    parser.add_argument("--delay", type=float, default=2.0)
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    total = 0
    for state in STATES:
        try:
            count = download_state(state, output_dir)
            total += count
        except Exception as exc:
            print(f"Failed for {state['name']}: {exc}")
        time.sleep(args.delay)

    print(f"Finished bulk download: total POIs saved = {total}")


if __name__ == "__main__":
    main()
