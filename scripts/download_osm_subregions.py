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


def fetch_overpass_subregions(south, west, north, east):
    query = f"""
    [out:json][timeout:180];
    (
      node["place"="neighbourhood"]({south},{west},{north},{east});
      way["place"="neighbourhood"]({south},{west},{north},{east});
      relation["place"="neighbourhood"]({south},{west},{north},{east});
      node["boundary"="administrative"]["admin_level"~"^(8|9|10)$"]({south},{west},{north},{east});
      way["boundary"="administrative"]["admin_level"~"^(8|9|10)$"]({south},{west},{north},{east});
      relation["boundary"="administrative"]["admin_level"~"^(8|9|10)$"]({south},{west},{north},{east});
    );
    out center;
    """.strip()

    payload = urllib.parse.urlencode({"data": query}).encode("utf-8")
    request = urllib.request.Request(
        OVERPASS_URL,
        data=payload,
        headers={"User-Agent": "Spot-Subregion-Downloader/1.0"},
    )

    with urllib.request.urlopen(request, timeout=300) as response:
        payload = response.read().decode("utf-8")
        return json.loads(payload)


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

    admin_level = tags.get("admin_level")
    place = tags.get("place")
    return {
        "subregion_id": f"{element['type']}/{element['id']}",
        "name": name,
        "latitude": float(latitude),
        "longitude": float(longitude),
        "admin_level": admin_level or place or "unknown",
        "country": tags.get("country") or tags.get("addr:country") or "",
        "state": tags.get("state") or tags.get("is_in:state") or tags.get("addr:state") or "",
        "city": tags.get("city") or tags.get("is_in:city") or tags.get("addr:city") or "",
    }


def save_csv(records, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["subregion_id", "name", "latitude", "longitude", "admin_level", "country", "state", "city"],
        )
        writer.writeheader()
        writer.writerows(records)


def save_sqlite(records, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS subregions (
            subregion_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            admin_level TEXT,
            country TEXT,
            state TEXT,
            city TEXT
        )
        """
    )
    conn.execute("DELETE FROM subregions")
    conn.executemany(
        "INSERT INTO subregions (subregion_id, name, latitude, longitude, admin_level, country, state, city) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        [
            (
                record["subregion_id"],
                record["name"],
                record["latitude"],
                record["longitude"],
                record["admin_level"],
                record["country"],
                record["state"],
                record["city"],
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


def download_region(south, west, north, east, output_csv, output_sqlite, output_json):
    result = fetch_overpass_subregions(south, west, north, east)
    elements = result.get("elements", [])
    records = []
    for element in elements:
        record = normalize_element(element)
        if record is not None:
            records.append(record)

    if not records:
        print("No subregions found for that bounding box.")
        return 0

    save_csv(records, output_csv)
    save_sqlite(records, output_sqlite)
    save_json(records, output_json)

    print(f"Downloaded {len(records)} subregions")
    print(f"CSV: {output_csv}")
    print(f"SQLite: {output_sqlite}")
    print(f"JSON: {output_json}")
    return len(records)


def parse_args():
    parser = argparse.ArgumentParser(description="Download minimal OSM subregions for a region.")
    parser.add_argument("--south", type=float, required=True)
    parser.add_argument("--west", type=float, required=True)
    parser.add_argument("--north", type=float, required=True)
    parser.add_argument("--east", type=float, required=True)
    parser.add_argument("--csv", type=str, default="data/subregions.csv")
    parser.add_argument("--sqlite", type=str, default="data/subregions.db")
    parser.add_argument("--json", type=str, default="data/subregions.json")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    if args.south >= args.north or args.west >= args.east:
        print("Invalid bounding box. Ensure south < north and west < east.")
        sys.exit(1)

    try:
        count = download_region(args.south, args.west, args.north, args.east, Path(args.csv), Path(args.sqlite), Path(args.json))
        sys.exit(0 if count > 0 else 1)
    except Exception as exc:
        print(f"Failed to download subregions: {exc}", file=sys.stderr)
        sys.exit(1)
