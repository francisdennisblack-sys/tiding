#!/usr/bin/env python3

import csv
import json
import sqlite3
import urllib.parse
import urllib.request
from pathlib import Path

OVERPASS_URL = "https://overpass-api.de/api/interpreter"

SOUTH = 40.64
WEST = -112.12
NORTH = 40.84
EAST = -111.78


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
        headers={"User-Agent": "Spot-SLC-POI-Downloader/1.0"},
    )

    with urllib.request.urlopen(request, timeout=300) as response:
        return json.loads(response.read().decode("utf-8"))


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


def write_csv(records, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["poi_id", "name", "latitude", "longitude", "category"])
        writer.writeheader()
        writer.writerows(records)


def write_sqlite(records, path):
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


def write_json(records, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(records, handle, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    result = fetch_overpass_pois(SOUTH, WEST, NORTH, EAST)
    records = []
    for element in result.get("elements", []):
        record = normalize_element(element)
        if record is not None:
            records.append(record)

    print(f"Downloaded {len(records)} POIs for Salt Lake City")
    write_csv(records, Path("data/salt_lake_city_pois.csv"))
    write_sqlite(records, Path("data/salt_lake_city_pois.db"))
    write_json(records, Path("data/salt_lake_city_pois.json"))
