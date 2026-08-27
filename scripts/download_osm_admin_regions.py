#!/usr/bin/env python3

import argparse
import csv
import json
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

OVERPASS_URL = "https://overpass-api.de/api/interpreter"


def fetch_overpass_admin_regions(south, west, north, east, retries=5, base_delay=5, country=None, admin_levels=None):
    level_clause = ""
    if admin_levels:
        levels = "|".join(str(level) for level in admin_levels)
        level_clause = f'["admin_level"~"^({levels})$"]'

    query = f"""
    [out:json][timeout:240];
    (
      node["boundary"="administrative"]{level_clause}({south},{west},{north},{east});
      way["boundary"="administrative"]{level_clause}({south},{west},{north},{east});
      relation["boundary"="administrative"]{level_clause}({south},{west},{north},{east});
      node["place"~"^(city|town|village|hamlet|suburb|neighbourhood|quarter|district)$"]({south},{west},{north},{east});
      way["place"~"^(city|town|village|hamlet|suburb|neighbourhood|quarter|district)$"]({south},{west},{north},{east});
      relation["place"~"^(city|town|village|hamlet|suburb|neighbourhood|quarter|district)$"]({south},{west},{north},{east});
    );
    out center;
    """.strip()

    payload = urllib.parse.urlencode({"data": query}).encode("utf-8")
    request = urllib.request.Request(
        OVERPASS_URL,
        data=payload,
        headers={"User-Agent": "Spot-Admin-Region-Downloader/1.0"},
    )

    for attempt in range(1, retries + 1):
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                page = response.read().decode("utf-8")
                return json.loads(page)
        except urllib.error.HTTPError as exc:
            if exc.code not in (429, 500, 502, 503, 504):
                raise
            if attempt == retries:
                raise
            delay = base_delay * (2 ** (attempt - 1))
            print(f"Overpass rate-limited ({exc.code}); retrying in {delay}s (attempt {attempt}/{retries})")
            time.sleep(delay)
        except urllib.error.URLError as exc:
            if attempt == retries:
                raise
            delay = base_delay * (2 ** (attempt - 1))
            print(f"Overpass network error; retrying in {delay}s (attempt {attempt}/{retries})")
            time.sleep(delay)


def safe_value(mapping, *keys):
    for key in keys:
        value = mapping.get(key)
        if value:
            return value.strip()
    return ""


def normalize_element(element):
    tags = element.get("tags", {})
    name = safe_value(tags, "name", "display_name", "official_name")
    if not name:
        return None

    if "center" in element:
        latitude = element["center"].get("lat")
        longitude = element["center"].get("lon")
    else:
        latitude = element.get("lat")
        longitude = element.get("lon")

    if latitude is None or longitude is None:
        return None

    admin_level = safe_value(tags, "admin_level")
    place = safe_value(tags, "place")
    if not admin_level and place:
        admin_level = place

    record = {
        "region_id": f"{element['type']}/{element['id']}",
        "name": name,
        "latitude": float(latitude),
        "longitude": float(longitude),
        "admin_level": admin_level or "unknown",
        "boundary": safe_value(tags, "boundary"),
        "place": place,
        "country": safe_value(tags, "country", "addr:country", "is_in:country"),
        "state": safe_value(tags, "state", "addr:state", "is_in:state"),
        "county": safe_value(tags, "county", "addr:county", "is_in:county"),
        "city": safe_value(tags, "city", "addr:city", "is_in:city"),
        "parent_name": safe_value(tags, "is_in", "is_in:state", "is_in:country"),
        "source_type": element.get("type", "unknown"),
    }

    if not record["country"] and record["state"] and record["state"].lower() == "new york":
        record["country"] = "United States"

    return record


def save_csv(records, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "region_id",
        "name",
        "latitude",
        "longitude",
        "admin_level",
        "boundary",
        "place",
        "country",
        "state",
        "county",
        "city",
        "parent_name",
        "source_type",
    ]
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(records)


def save_sqlite(records, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS regions (
            region_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            admin_level TEXT,
            boundary TEXT,
            place TEXT,
            country TEXT,
            state TEXT,
            county TEXT,
            city TEXT,
            parent_name TEXT,
            source_type TEXT
        )
        """
    )
    conn.execute("DELETE FROM regions")
    conn.executemany(
        """
        INSERT INTO regions (
            region_id, name, latitude, longitude, admin_level, boundary, place,
            country, state, county, city, parent_name, source_type
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
            (
                record["region_id"],
                record["name"],
                record["latitude"],
                record["longitude"],
                record["admin_level"],
                record["boundary"],
                record["place"],
                record["country"],
                record["state"],
                record["county"],
                record["city"],
                record["parent_name"],
                record["source_type"],
            )
            for record in records
        ],
    )
    conn.commit()
    conn.close()


def save_json(records, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(records, handle, ensure_ascii=False, indent=2)


def save_firestore_ready(records, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = [{
        "region_id": record["region_id"],
        "name": record["name"],
        "latitude": record["latitude"],
        "longitude": record["longitude"],
        "admin_level": record["admin_level"],
        "boundary": record["boundary"],
        "place": record["place"],
        "country": record["country"],
        "state": record["state"],
        "county": record["county"],
        "city": record["city"],
        "parent_name": record["parent_name"],
        "source_type": record["source_type"],
    } for record in records]
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)


def passes_country_filter(record, country):
    if not country:
        return True
    country_lower = country.lower()
    candidate_values = [
        record.get("country", ""),
        record.get("state", ""),
        record.get("county", ""),
        record.get("city", ""),
        record.get("parent_name", ""),
    ]
    for value in candidate_values:
        if value and value.lower() == country_lower:
            return True
    if record.get("country") and country_lower in record["country"].lower():
        return True
    return False


def download_admin_regions(south, west, north, east, output_csv, output_sqlite, output_json, output_firestore_json, country=None, admin_levels=None):
    result = fetch_overpass_admin_regions(south, west, north, east, country=country, admin_levels=admin_levels)
    elements = result.get("elements", [])
    seen = set()
    records = []

    for element in elements:
        record = normalize_element(element)
        if not record:
            continue
        if country and not passes_country_filter(record, country):
            continue
        if record["region_id"] in seen:
            continue
        seen.add(record["region_id"])
        records.append(record)

    if not records:
        print("No administrative regions found for that bounding box.")
        return 0

    save_csv(records, output_csv)
    save_sqlite(records, output_sqlite)
    save_json(records, output_json)
    save_firestore_ready(records, output_firestore_json)

    print(f"Downloaded {len(records)} administrative regions")
    print(f"CSV: {output_csv}")
    print(f"SQLite: {output_sqlite}")
    print(f"JSON: {output_json}")
    print(f"Firestore-ready: {output_firestore_json}")
    return len(records)


def parse_args():
    parser = argparse.ArgumentParser(description="Download OSM admin regions and subregions for a bounding box.")
    parser.add_argument("--south", type=float, required=True)
    parser.add_argument("--west", type=float, required=True)
    parser.add_argument("--north", type=float, required=True)
    parser.add_argument("--east", type=float, required=True)
    parser.add_argument("--csv", type=str, default="data/regions.csv")
    parser.add_argument("--sqlite", type=str, default="data/regions.db")
    parser.add_argument("--json", type=str, default="data/regions.json")
    parser.add_argument("--firestore-json", type=str, default="data/regions_firestore.json")
    parser.add_argument("--country", type=str, default=None, help="Optional OSM country filter, e.g. United States.")
    parser.add_argument("--admin-levels", type=str, default=None, help="Optional comma-separated admin levels, e.g. 4,5")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    if args.south >= args.north or args.west >= args.east:
        print("Invalid bounding box. Ensure south < north and west < east.")
        sys.exit(1)

    admin_levels = None
    if args.admin_levels:
        admin_levels = [int(level.strip()) for level in args.admin_levels.split(",") if level.strip()]

    try:
        count = download_admin_regions(
            args.south,
            args.west,
            args.north,
            args.east,
            Path(args.csv),
            Path(args.sqlite),
            Path(args.json),
            Path(args.firestore_json),
            country=args.country,
            admin_levels=admin_levels,
        )
        sys.exit(0 if count > 0 else 1)
    except Exception as exc:
        print(f"Failed to download administrative regions: {exc}", file=sys.stderr)
        sys.exit(1)
