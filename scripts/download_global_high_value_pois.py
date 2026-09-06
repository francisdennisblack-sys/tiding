#!/usr/bin/env python3

import argparse
import csv
import gzip
import json
import sqlite3
import time
import urllib.parse
import urllib.request
from pathlib import Path

OVERPASS_ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]

CATEGORY_WEIGHTS = {
    "restaurant": 20,
    "cafe": 19,
    "bakery": 16,
    "bar": 15,
    "pub": 14,
    "fast_food": 17,
    "grocery": 22,
    "supermarket": 22,
    "convenience": 20,
    "pharmacy": 25,
    "hospital": 28,
    "clinic": 24,
    "bank": 17,
    "atm": 16,
    "hotel": 20,
    "hostel": 18,
    "motel": 17,
    "train_station": 28,
    "subway_station": 30,
    "metro_station": 30,
    "bus_station": 24,
    "airport": 32,
    "ferry_terminal": 23,
    "museum": 21,
    "park": 19,
    "zoo": 18,
    "cinema": 17,
    "theatre": 16,
    "theater": 16,
    "university": 18,
    "college": 16,
    "school": 15,
    "marketplace": 18,
    "mall": 18,
    "department_store": 16,
    "fuel": 18,
    "parking": 12,
    "car_rental": 15,
    "car_wash": 12,
    "tourism": 15,
    "amenity": 11,
    "shop": 12,
    "public_transport": 18,
    "historic": 15,
    "leisure": 14,
    "office": 10,
}

HIGH_VALUE_VALUES = {
    "restaurant",
    "cafe",
    "bakery",
    "bar",
    "pub",
    "fast_food",
    "grocery_or_supermarket",
    "grocery",
    "supermarket",
    "convenience",
    "pharmacy",
    "hospital",
    "clinic",
    "bank",
    "atm",
    "hotel",
    "hostel",
    "motel",
    "train_station",
    "subway_station",
    "metro_station",
    "bus_station",
    "airport",
    "ferry_terminal",
    "museum",
    "park",
    "zoo",
    "cinema",
    "theatre",
    "theater",
    "university",
    "college",
    "school",
    "marketplace",
    "mall",
    "department_store",
    "fuel",
    "car_rental",
    "tourist_attraction",
    "viewpoint",
    "stadium",
    "library",
    "community_centre",
    "townhall",
    "courthouse",
    "police",
}

EXCLUDED_VALUES = {
    "bench",
    "waste_basket",
    "toilets",
    "parking_entrance",
    "drinking_water",
    "fountain",
    "bicycle_parking",
    "post_box",
    "phone",
    "shelter",
    "fire_hydrant",
    "vending_machine",
    "traffic_signals",
    "street_lamp",
    "bus_stop",
    "taxi",
    "place",
    "building",
    "yes",
    "no",
    "none",
}

COUNTRY_AREAS = {
    "uk": [
        {"name": "london", "south": 51.28, "west": -0.52, "north": 51.67, "east": 0.33},
        {"name": "manchester", "south": 53.34, "west": -2.40, "north": 53.56, "east": -2.12},
        {"name": "birmingham", "south": 52.39, "west": -1.98, "north": 52.58, "east": -1.76},
        {"name": "glasgow", "south": 55.78, "west": -4.36, "north": 55.95, "east": -4.12},
        {"name": "paris", "south": 48.82, "west": 2.20, "north": 48.90, "east": 2.45},
    ],
    "france": [
        {"name": "paris", "south": 48.82, "west": 2.20, "north": 48.90, "east": 2.45},
        {"name": "lyon", "south": 45.72, "west": 4.75, "north": 45.82, "east": 4.92},
        {"name": "marseille", "south": 43.26, "west": 5.32, "north": 43.38, "east": 5.48},
        {"name": "nice", "south": 43.68, "west": 7.18, "north": 43.77, "east": 7.31},
        {"name": "barcelona", "south": 41.34, "west": 2.08, "north": 41.46, "east": 2.22},
    ],
    "germany": [
        {"name": "berlin", "south": 52.47, "west": 13.27, "north": 52.55, "east": 13.50},
        {"name": "munich", "south": 48.10, "west": 11.48, "north": 48.18, "east": 11.63},
        {"name": "hamburg", "south": 53.52, "west": 9.90, "north": 53.62, "east": 10.08},
        {"name": "frankfurt", "south": 50.05, "west": 8.57, "north": 50.14, "east": 8.73},
    ],
    "spain": [
        {"name": "madrid", "south": 40.38, "west": -3.78, "north": 40.52, "east": -3.58},
        {"name": "barcelona", "south": 41.34, "west": 2.08, "north": 41.46, "east": 2.22},
        {"name": "valencia", "south": 39.43, "west": -0.39, "north": 39.52, "east": -0.27},
        {"name": "seville", "south": 37.34, "west": -5.98, "north": 37.44, "east": -5.85},
    ],
    "italy": [
        {"name": "rome", "south": 41.84, "west": 12.42, "north": 41.94, "east": 12.58},
        {"name": "milan", "south": 45.44, "west": 9.10, "north": 45.52, "east": 9.24},
        {"name": "florence", "south": 43.76, "west": 11.22, "north": 43.80, "east": 11.30},
        {"name": "naples", "south": 40.82, "west": 14.18, "north": 40.90, "east": 14.33},
    ],
    "netherlands": [
        {"name": "amsterdam", "south": 52.33, "west": 4.80, "north": 52.42, "east": 4.97},
        {"name": "rotterdam", "south": 51.90, "west": 4.42, "north": 51.99, "east": 4.58},
        {"name": "utrecht", "south": 52.05, "west": 5.09, "north": 52.12, "east": 5.18},
    ],
    "belgium": [
        {"name": "brussels", "south": 50.81, "west": 4.31, "north": 50.88, "east": 4.45},
        {"name": "antwerp", "south": 51.18, "west": 4.37, "north": 51.27, "east": 4.51},
    ],
    "sweden": [
        {"name": "stockholm", "south": 59.28, "west": 17.94, "north": 59.38, "east": 18.12},
        {"name": "gothenburg", "south": 57.68, "west": 11.91, "north": 57.75, "east": 12.06},
    ],
    "norway": [
        {"name": "oslo", "south": 59.88, "west": 10.68, "north": 59.96, "east": 10.89},
        {"name": "bergen", "south": 60.36, "west": 5.31, "north": 60.44, "east": 5.46},
    ],
    "japan": [
        {"name": "tokyo", "south": 35.64, "west": 139.68, "north": 35.72, "east": 139.79},
        {"name": "osaka", "south": 34.64, "west": 135.40, "north": 34.75, "east": 135.55},
        {"name": "kyoto", "south": 34.95, "west": 135.69, "north": 35.05, "east": 135.82},
        {"name": "fukuoka", "south": 33.56, "west": 130.35, "north": 33.66, "east": 130.47},
    ],
    "south_korea": [
        {"name": "seoul", "south": 37.48, "west": 126.86, "north": 37.60, "east": 127.03},
        {"name": "busan", "south": 35.08, "west": 128.96, "north": 35.21, "east": 129.13},
    ],
    "singapore": [
        {"name": "singapore", "south": 1.25, "west": 103.73, "north": 1.43, "east": 104.03},
    ],
    "australia": [
        {"name": "sydney", "south": -33.90, "west": 151.18, "north": -33.82, "east": 151.30},
        {"name": "melbourne", "south": -37.84, "west": 144.90, "north": -37.75, "east": 145.05},
        {"name": "brisbane", "south": -27.47, "west": 153.00, "north": -27.37, "east": 153.12},
    ],
    "india": [
        {"name": "mumbai", "south": 18.92, "west": 72.80, "north": 19.12, "east": 73.02},
        {"name": "delhi", "south": 28.55, "west": 77.08, "north": 28.72, "east": 77.25},
        {"name": "bengaluru", "south": 12.94, "west": 77.51, "north": 13.06, "east": 77.66},
    ],
    "mexico": [
        {"name": "mexico_city", "south": 19.33, "west": -99.25, "north": 19.52, "east": -98.95},
        {"name": "guadalajara", "south": 20.60, "west": -103.38, "north": 20.78, "east": -103.20},
    ],
    "brazil": [
        {"name": "sao_paulo", "south": -23.86, "west": -46.80, "north": -23.47, "east": -46.37},
        {"name": "rio", "south": -22.98, "west": -43.38, "north": -22.86, "east": -43.18},
    ],
    "uae": [
        {"name": "dubai", "south": 25.18, "west": 55.23, "north": 25.31, "east": 55.42},
        {"name": "abu_dhabi", "south": 24.38, "west": 54.42, "north": 24.53, "east": 54.56},
    ],
    "south_africa": [
        {"name": "johannesburg", "south": -26.23, "west": 27.97, "north": -26.08, "east": 28.13},
        {"name": "cape_town", "south": -33.98, "west": 18.36, "north": -33.85, "east": 18.53},
    ],
    "turkey": [
        {"name": "istanbul", "south": 41.00, "west": 28.90, "north": 41.14, "east": 29.08},
        {"name": "ankara", "south": 39.85, "west": 32.80, "north": 39.96, "east": 32.95},
    ],
    "egypt": [
        {"name": "cairo", "south": 29.95, "west": 31.18, "north": 30.11, "east": 31.40},
        {"name": "alexandria", "south": 31.16, "west": 29.86, "north": 31.24, "east": 29.97},
    ],
}

COUNTRY_ORDER = [
    "uk", "france", "germany", "spain", "italy", "netherlands", "belgium", "sweden", "norway",
    "japan", "south_korea", "singapore", "australia", "india", "mexico", "brazil", "uae",
    "south_africa", "turkey", "egypt"
]


def get_category_value(tags):
    for key in ["amenity", "tourism", "shop", "historic", "leisure", "natural", "office", "public_transport"]:
        value = tags.get(key)
        if value:
            return value
    return "other"


def score_record(tags, name):
    category_value = get_category_value(tags)
    if category_value in EXCLUDED_VALUES:
        return -9999
    if category_value in HIGH_VALUE_VALUES:
        return CATEGORY_WEIGHTS.get(category_value, 12)
    if category_value in CATEGORY_WEIGHTS:
        return CATEGORY_WEIGHTS.get(category_value, 10)
    if name and len(name) >= 4:
        return 8
    return 0


def normalize_element(element):
    tags = element.get("tags", {})
    name = tags.get("name") or tags.get("display_name")
    if not name:
        return None
    if "center" in element:
        lat = element["center"]["lat"]
        lon = element["center"]["lon"]
    else:
        lat = element.get("lat")
        lon = element.get("lon")
    if lat is None or lon is None:
        return None

    category_value = get_category_value(tags)
    if category_value in EXCLUDED_VALUES:
        return None

    score = score_record(tags, name)
    if score <= 0:
        return None

    return {
        "poi_id": f"{element['type']}/{element['id']}",
        "name": str(name),
        "latitude": float(lat),
        "longitude": float(lon),
        "category": category_value,
        "score": int(score),
    }


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
    delay = backoff
    for attempt in range(retries + 1):
        for endpoint in OVERPASS_ENDPOINTS:
            request = urllib.request.Request(
                endpoint,
                data=payload,
                headers={"User-Agent": "Spot-Global-High-Value-POI/1.0"},
            )
            try:
                with urllib.request.urlopen(request, timeout=300) as response:
                    return json.loads(response.read().decode("utf-8"))
            except Exception as exc:
                print(f"Endpoint {endpoint} failed for bbox ({south},{west}) -> ({north},{east}): {exc}")
        if attempt < retries:
            print(f"Retrying bbox ({south},{west}) -> ({north},{east}) in {delay}s")
            time.sleep(delay)
            delay *= 1.7
            continue
        raise RuntimeError(f"All Overpass endpoints failed for bbox ({south},{west}) -> ({north},{east})")


def save_csv(records, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["poi_id", "name", "latitude", "longitude", "category", "score"])
        writer.writeheader()
        for record in records:
            writer.writerow({
                "poi_id": record["poi_id"],
                "name": record["name"],
                "latitude": record["latitude"],
                "longitude": record["longitude"],
                "category": record["category"],
                "score": record["score"],
            })


def save_sqlite(records, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.execute("CREATE TABLE IF NOT EXISTS pois (poi_id TEXT PRIMARY KEY, name TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, category TEXT NOT NULL, score INTEGER NOT NULL)")
    conn.execute("DELETE FROM pois")
    conn.executemany(
        "INSERT INTO pois (poi_id, name, latitude, longitude, category, score) VALUES (?, ?, ?, ?, ?, ?)",
        [(r["poi_id"], r["name"], r["latitude"], r["longitude"], r["category"], r["score"]) for r in records],
    )
    conn.commit()
    conn.close()


def cell_key(lat, lon, cell_size_km=1.0):
    lat_step = 1.0 / 111.0
    lon_step = 1.0 / (111.0 * 0.9)
    return (round(lat / (cell_size_km * lat_step), 6), round(lon / (cell_size_km * lon_step), 6))


def cap_density(records, max_per_cell=2):
    best_by_cell = {}
    for record in sorted(records, key=lambda r: r["score"], reverse=True):
        key = cell_key(record["latitude"], record["longitude"])
        bucket = best_by_cell.setdefault(key, [])
        if len(bucket) < max_per_cell:
            bucket.append(record)
    kept = []
    for bucket in best_by_cell.values():
        kept.extend(bucket)
    kept.sort(key=lambda r: r["score"], reverse=True)
    return kept


def global_total_records(path: Path):
    if not path.exists():
        return 0
    with gzip.open(path, "rb") as handle:
        body = handle.read()
    return len(body)


def download_area(area, out_dir, max_per_cell=2, max_total=120000):
    south, west, north, east = area["south"], area["west"], area["north"], area["east"]
    result = fetch_overpass_pois(south, west, north, east)
    records = []
    seen = set()
    for element in result.get("elements", []):
        record = normalize_element(element)
        if record is None:
            continue
        if record["poi_id"] in seen:
            continue
        seen.add(record["poi_id"])
        records.append(record)

    capped = cap_density(records, max_per_cell=max_per_cell)
    if not capped:
        return []
    capped.sort(key=lambda r: r["score"], reverse=True)
    return capped[:max_total]


def main():
    parser = argparse.ArgumentParser(description="Download high-value global POIs outside the U.S. with local density caps.")
    parser.add_argument("--output-dir", type=str, default="data/global_high_value")
    parser.add_argument("--max-per-cell", type=int, default=2)
    parser.add_argument("--target-total", type=int, default=1000000)
    parser.add_argument("--sleep", type=float, default=1.0)
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    csv_path = output_dir / "global_high_value_pois.csv"
    sqlite_path = output_dir / "global_high_value_pois.db"

    all_records = []
    seen = set()
    country_count = 0
    total_added = 0

    for country in COUNTRY_ORDER:
        for area in COUNTRY_AREAS[country]:
            area_records = download_area(area, output_dir, max_per_cell=args.max_per_cell, max_total=40000)
            for record in area_records:
                if record["poi_id"] in seen:
                    continue
                seen.add(record["poi_id"])
                all_records.append(record)
                total_added += 1
            if total_added >= args.target_total:
                break
        country_count += 1
        if total_added >= args.target_total:
            break
        time.sleep(args.sleep)

    all_records.sort(key=lambda r: r["score"], reverse=True)
    if len(all_records) > args.target_total:
        all_records = all_records[:args.target_total]

    print(f"Collected {len(all_records)} high-value records")
    save_csv(all_records, csv_path)
    save_sqlite(all_records, sqlite_path)
    print(f"Saved to {csv_path} and {sqlite_path}")


if __name__ == "__main__":
    main()
