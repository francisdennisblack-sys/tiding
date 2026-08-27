#!/usr/bin/env python3

import argparse
import csv
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

OVERPASS_URL = "https://overpass-api.de/api/interpreter"

# Start with a realistic, non-China expansion set. This is intentionally weighted toward the
# countries with the highest POI density and user demand, while keeping China excluded.
COUNTRY_BOUNDS = {
    "united_states": {"bounds": [24.39, -124.79, 49.38, -66.95], "priority": 100, "target": 250000},
    "canada": {"bounds": [41.68, -141.0, 83.11, -52.65], "priority": 80, "target": 180000},
    "mexico": {"bounds": [14.53, -117.13, 32.72, -86.70], "priority": 60, "target": 140000},
    "brazil": {"bounds": [-33.75, -73.99, 5.27, -34.79], "priority": 75, "target": 170000},
    "argentina": {"bounds": [-55.05, -73.58, -21.78, -53.65], "priority": 45, "target": 110000},
    "chile": {"bounds": [-56.0, -75.0, -17.5, -66.5], "priority": 30, "target": 70000},
    "colombia": {"bounds": [-4.23, -81.72, 13.39, -66.87], "priority": 32, "target": 75000},
    "peru": {"bounds": [-18.35, -81.33, 0.06, -68.65], "priority": 30, "target": 70000},
    "united_kingdom": {"bounds": [49.86, -7.57, 60.86, 1.77], "priority": 55, "target": 120000},
    "france": {"bounds": [41.33, -5.14, 51.09, 9.56], "priority": 55, "target": 120000},
    "germany": {"bounds": [47.27, 5.87, 55.06, 15.04], "priority": 55, "target": 120000},
    "spain": {"bounds": [27.64, -18.16, 43.79, 4.33], "priority": 50, "target": 110000},
    "italy": {"bounds": [36.63, 6.62, 47.09, 18.52], "priority": 50, "target": 110000},
    "netherlands": {"bounds": [51.30, 3.34, 53.55, 7.23], "priority": 30, "target": 70000},
    "belgium": {"bounds": [49.50, 2.54, 51.50, 6.40], "priority": 25, "target": 60000},
    "sweden": {"bounds": [55.34, 11.11, 69.06, 24.18], "priority": 30, "target": 70000},
    "norway": {"bounds": [57.98, 4.99, 71.18, 31.15], "priority": 30, "target": 70000},
    "finland": {"bounds": [59.85, 20.55, 70.09, 31.59], "priority": 25, "target": 60000},
    "poland": {"bounds": [49.00, 14.12, 54.84, 24.15], "priority": 35, "target": 80000},
    "czech_republic": {"bounds": [48.55, 12.09, 51.06, 18.86], "priority": 22, "target": 50000},
    "austria": {"bounds": [46.37, 9.48, 49.02, 17.16], "priority": 22, "target": 50000},
    "switzerland": {"bounds": [45.82, 5.96, 47.81, 10.50], "priority": 22, "target": 50000},
    "portugal": {"bounds": [36.95, -9.53, 42.15, -6.18], "priority": 25, "target": 60000},
    "greece": {"bounds": [34.80, 19.37, 41.75, 29.65], "priority": 28, "target": 65000},
    "india": {"bounds": [6.75, 68.18, 35.50, 97.40], "priority": 100, "target": 250000},
    "indonesia": {"bounds": [-11.00, 95.00, 6.00, 141.00], "priority": 75, "target": 170000},
    "japan": {"bounds": [24.25, 122.94, 45.52, 146.18], "priority": 70, "target": 160000},
    "south_korea": {"bounds": [33.10, 124.06, 38.62, 131.87], "priority": 50, "target": 110000},
    "thailand": {"bounds": [5.62, 97.35, 20.46, 105.64], "priority": 45, "target": 100000},
    "vietnam": {"bounds": [8.18, 102.14, 23.39, 109.47], "priority": 45, "target": 100000},
    "philippines": {"bounds": [4.64, 116.93, 21.12, 126.60], "priority": 45, "target": 100000},
    "malaysia": {"bounds": [0.85, 100.09, 7.38, 119.27], "priority": 35, "target": 80000},
    "singapore": {"bounds": [1.16, 103.60, 1.47, 104.03], "priority": 15, "target": 20000},
    "australia": {"bounds": [-43.65, 112.92, -10.66, 153.64], "priority": 55, "target": 120000},
    "new_zealand": {"bounds": [-47.76, 166.28, -34.39, 178.55], "priority": 25, "target": 60000},
    "nigeria": {"bounds": [4.27, 2.69, 13.89, 14.68], "priority": 40, "target": 90000},
    "kenya": {"bounds": [-4.68, 33.89, 4.63, 41.90], "priority": 28, "target": 65000},
    "south_africa": {"bounds": [-34.83, 16.45, -22.12, 32.89], "priority": 35, "target": 80000},
    "egypt": {"bounds": [22.00, 24.70, 31.67, 36.90], "priority": 32, "target": 75000},
    "morocco": {"bounds": [27.67, -17.02, 35.93, -1.03], "priority": 30, "target": 70000},
    "saudi_arabia": {"bounds": [16.35, 34.48, 32.15, 55.67], "priority": 35, "target": 80000},
    "united_arab_emirates": {"bounds": [22.63, 51.54, 26.53, 56.39], "priority": 20, "target": 45000},
    "turkey": {"bounds": [35.82, 26.04, 42.11, 44.82], "priority": 45, "target": 100000},
    "uae": {"bounds": [22.63, 51.54, 26.53, 56.39], "priority": 20, "target": 45000},
    "israel": {"bounds": [29.45, 34.27, 33.30, 35.84], "priority": 22, "target": 50000},
    "iran": {"bounds": [25.06, 44.04, 39.78, 63.32], "priority": 30, "target": 70000},
    "pakistan": {"bounds": [23.70, 60.87, 37.07, 77.84], "priority": 32, "target": 75000},
    "bangladesh": {"bounds": [20.59, 88.01, 26.64, 92.68], "priority": 25, "target": 60000},
}

DEFAULT_COUNTRIES = [
    "united_states",
    "canada",
    "mexico",
    "brazil",
    "argentina",
    "chile",
    "colombia",
    "peru",
    "united_kingdom",
    "france",
    "germany",
    "spain",
    "italy",
    "netherlands",
    "belgium",
    "sweden",
    "norway",
    "finland",
    "poland",
    "czech_republic",
    "austria",
    "switzerland",
    "portugal",
    "greece",
    "india",
    "indonesia",
    "japan",
    "south_korea",
    "thailand",
    "vietnam",
    "philippines",
    "malaysia",
    "singapore",
    "australia",
    "new_zealand",
    "nigeria",
    "kenya",
    "south_africa",
    "egypt",
    "morocco",
    "saudi_arabia",
    "united_arab_emirates",
    "turkey",
    "israel",
    "iran",
    "pakistan",
    "bangladesh",
]


def fetch_overpass_pois(south, west, north, east, retries=5, backoff=2.0):
    query = f"""
    [out:json][timeout:180];
    (
      node["name"]({south},{west},{north},{east});
      way["name"]({south},{west},{north},{east});
      relation["name"]({south},{west},{north},{east});
    );
    out center;
    """.strip()

    payload = urllib.parse.urlencode({"data": query}).encode("utf-8")
    request = urllib.request.Request(
        OVERPASS_URL,
        data=payload,
        headers={"User-Agent": "Spot-Global-POI-Downloader/1.0"},
    )

    delay = backoff
    for attempt in range(retries + 1):
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code in (429, 500, 502, 503, 504) and attempt < retries:
                print(f"Overpass throttled for bbox ({south},{west}) -> ({north},{east}); retrying in {delay}s (attempt {attempt + 1}/{retries})")
                time.sleep(delay)
                delay *= 2
                continue
            raise
        except urllib.error.URLError:
            if attempt < retries:
                time.sleep(delay)
                delay *= 2
                continue
            raise


def get_category(tags):
    for key in ["amenity", "tourism", "shop", "historic", "leisure", "natural", "office", "public_transport"]:
        value = tags.get(key)
        if value:
            return value
    return "other"


def normalize_element(element):
    tags = element.get("tags", {})
    name = tags.get("name") or tags.get("display_name")
    if not name:
        return None

    if "center" in element:
        latitude = element["center"]["lat"]
        longitude = element["center"]["lon"]
    else:
        latitude = element.get("lat")
        longitude = element.get("lon")

    if latitude is None or longitude is None:
        return None

    return {
        "poi_id": f"{element['type']}/{element['id']}",
        "name": name,
        "latitude": float(latitude),
        "longitude": float(longitude),
        "category": get_category(tags),
    }


def export_csv(records, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["poi_id", "name", "latitude", "longitude", "category"])
        writer.writeheader()
        writer.writerows(records)


def download_country(country_name, bounds, output_dir, max_per_country):
    south, west, north, east = bounds
    result = fetch_overpass_pois(south, west, north, east)
    unique = {}

    for element in result.get("elements", []):
        record = normalize_element(element)
        if record is None:
            continue
        unique[record["poi_id"]] = record

    records = list(unique.values())
    records.sort(key=lambda r: r["name"].lower())
    if max_per_country and len(records) > max_per_country:
        records = records[:max_per_country]

    country_dir = output_dir / country_name
    country_dir.mkdir(parents=True, exist_ok=True)
    csv_path = country_dir / f"{country_name}.csv"
    export_csv(records, csv_path)

    manifest = {
        "country": country_name,
        "bounds": bounds,
        "record_count": len(records),
        "source": "overpass",
        "excluded": ["china"],
    }
    (country_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    return len(records)


def parse_args():
    parser = argparse.ArgumentParser(description="Download a weighted, non-China POI expansion dataset for major countries.")
    parser.add_argument("--output-dir", type=str, default="../data/global_non_china_pois")
    parser.add_argument("--countries", type=str, nargs="*", default=DEFAULT_COUNTRIES)
    parser.add_argument("--max-per-country", type=int, default=250000)
    parser.add_argument("--delay", type=float, default=1.0)
    return parser.parse_args()


def main():
    args = parse_args()
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    selected = []
    for country in args.countries:
        if country.lower() == "china":
            continue
        if country.lower() in COUNTRY_BOUNDS:
            selected.append(country.lower())
        else:
            print(f"Unknown country: {country}. Available: {sorted(COUNTRY_BOUNDS.keys())[:10]} ...", file=sys.stderr)

    if not selected:
        print("No valid countries selected. China is excluded by default.", file=sys.stderr)
        return 1

    total = 0
    manifest = {"countries": []}

    for country in selected:
        bounds = COUNTRY_BOUNDS[country]["bounds"]
        try:
            count = download_country(country, bounds, output_dir, args.max_per_country)
            total += count
            manifest["countries"].append({"country": country, "record_count": count})
        except Exception as exc:
            print(f"Failed for {country}: {exc}", file=sys.stderr)
        time.sleep(args.delay)

    (output_dir / "manifest.json").write_text(json.dumps({
        "excluded_countries": ["china"],
        "total_records": total,
        "countries": manifest["countries"],
    }, indent=2), encoding="utf-8")

    print(f"Finished non-China POI download: {total} records")
    return 0


if __name__ == "__main__":
    sys.exit(main())
