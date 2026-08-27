#!/usr/bin/env python3

import argparse
import csv
import json
import sqlite3
import sys
import urllib.parse
import urllib.request
from pathlib import Path


OVERPASS_URL = "https://overpass-api.de/api/interpreter"


def fetch_overpass_pois(south, west, north, east):
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
        headers={"User-Agent": "Spot-POI-Downloader/1.0"},
    )

    with urllib.request.urlopen(request, timeout=300) as response:
        payload = response.read().decode("utf-8")
        return json.loads(payload)


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


def save_csv(records, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["poi_id", "name", "latitude", "longitude", "category"])
        writer.writeheader()
        writer.writerows(records)


def save_sqlite(records, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS pois (
            poi_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            category TEXT NOT NULL
        )
        """
    )

    conn.execute("DELETE FROM pois")
    conn.executemany(
        "INSERT INTO pois (poi_id, name, latitude, longitude, category) VALUES (?, ?, ?, ?, ?)",
        [
            (record["poi_id"], record["name"], record["latitude"], record["longitude"], record["category"])
            for record in records
        ],
    )
    conn.commit()
    conn.close()


def download_region(south, west, north, east, output_csv, output_sqlite):
    result = fetch_overpass_pois(south, west, north, east)
    elements = result.get("elements", [])
    records = []

    for element in elements:
        record = normalize_element(element)
        if record is not None:
            records.append(record)

    if not records:
        print("No POIs found for that bounding box.")
        return 0

    save_csv(records, output_csv)
    save_sqlite(records, output_sqlite)

    print(f"Downloaded {len(records)} POIs")
    print(f"CSV: {output_csv}")
    print(f"SQLite: {output_sqlite}")
    return len(records)


def parse_args():
    parser = argparse.ArgumentParser(description="Download a minimal OSM POI dataset for a region.")
    parser.add_argument("--south", type=float, required=True)
    parser.add_argument("--west", type=float, required=True)
    parser.add_argument("--north", type=float, required=True)
    parser.add_argument("--east", type=float, required=True)
    parser.add_argument("--csv", type=str, default="data/osm_pois.csv")
    parser.add_argument("--sqlite", type=str, default="data/osm_pois.db")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()

    if args.south >= args.north or args.west >= args.east:
        print("Invalid bounding box. Ensure south < north and west < east.")
        sys.exit(1)

    try:
        count = download_region(args.south, args.west, args.north, args.east, Path(args.csv), Path(args.sqlite))
        sys.exit(0 if count > 0 else 1)
    except Exception as exc:
        print(f"Failed to download POIs: {exc}", file=sys.stderr)
        sys.exit(1)
