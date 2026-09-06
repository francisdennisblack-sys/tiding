#!/usr/bin/env python3

import argparse
import csv
import json
import sys
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

OVERPASS_URL = "https://overpass-api.de/api/interpreter"


def fetch_overpass_points(south, west, north, east):
    query = f"""
    [out:json][timeout:180];
    (
      node["name"]({south},{west},{north},{east});
      way["name"]({south},{west},{north},{east});
      relation["name"]({south},{west},{north},{east});
      node["place"~"^(city|town|village|hamlet|suburb|neighbourhood|quarter|district|locality|borough)$"]({south},{west},{north},{east});
      way["place"~"^(city|town|village|hamlet|suburb|neighbourhood|quarter|district|locality|borough)$"]({south},{west},{north},{east});
      relation["place"~"^(city|town|village|hamlet|suburb|neighbourhood|quarter|district|locality|borough)$"]({south},{west},{north},{east});
      node["boundary"="administrative"]["admin_level"~"^(8|9|10)$"]({south},{west},{north},{east});
      way["boundary"="administrative"]["admin_level"~"^(8|9|10)$"]({south},{west},{north},{east});
      relation["boundary"="administrative"]["admin_level"~"^(8|9|10)$"]({south},{west},{north},{east});
    );
    out center;
    """.strip()

    payload = urlencode({"data": query}).encode("utf-8")
    request = Request(
        OVERPASS_URL,
        data=payload,
        headers={"User-Agent": "Spot-OSM-Seed/1.0"},
    )

    with urlopen(request, timeout=300) as response:
        return json.loads(response.read().decode("utf-8"))


def get_category(tags):
    for key in ["amenity", "tourism", "shop", "historic", "leisure", "natural", "office", "building", "public_transport"]:
        value = tags.get(key)
        if value:
            return value
    return "other"


def normalized_name(tags):
    return (tags.get("name") or "").strip() or None


def normalize_element(element):
    tags = element.get("tags", {})
    name = normalized_name(tags)
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

    place_kind = tags.get("place") or "poi"
    boundary_kind = tags.get("boundary")
    is_admin_boundary = bool(boundary_kind == "administrative")
    kind = "poi" if not (place_kind or is_admin_boundary) else (place_kind if place_kind else "administrative")

    return {
        "id": f"{element.get('type', 'node')}/{element.get('id', 0)}",
        "name": name,
        "latitude": float(latitude),
        "longitude": float(longitude),
        "kind": kind,
        "category": get_category(tags),
        "is_search_only": False,
        "source": "osm",
        "search_text": name.lower(),
    }


def dedupe(records):
    seen = set()
    unique = []
    for record in records:
        key = (record["name"].lower().strip(), round(record["latitude"], 6), round(record["longitude"], 6))
        if key in seen:
            continue
        seen.add(key)
        unique.append(record)
    return unique


def write_csv(records, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = ["id", "name", "latitude", "longitude", "kind", "category", "is_search_only", "source", "search_text"]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for record in records:
            writer.writerow({
                "id": record["id"],
                "name": record["name"],
                "latitude": record["latitude"],
                "longitude": record["longitude"],
                "kind": record["kind"],
                "category": record["category"],
                "is_search_only": "false",
                "source": record["source"],
                "search_text": record["search_text"],
            })


def write_json(records, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(records, handle, ensure_ascii=False, indent=2)


def download_region(south, west, north, east):
    result = fetch_overpass_points(south, west, north, east)
    elements = result.get("elements", [])
    records = []
    for element in elements:
        normalized = normalize_element(element)
        if normalized is not None:
            records.append(normalized)
    return dedupe(records)


def parse_args():
    parser = argparse.ArgumentParser(description="Download a small USA OSM seed dataset with both POIs and address-only search entries.")
    parser.add_argument("--south", type=float, required=True)
    parser.add_argument("--west", type=float, required=True)
    parser.add_argument("--north", type=float, required=True)
    parser.add_argument("--east", type=float, required=True)
    parser.add_argument("--csv", type=str, default="data/osm_seed.csv")
    parser.add_argument("--json", type=str, default="data/osm_seed.json")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    if args.south >= args.north or args.west >= args.east:
        print("Invalid bounding box: south < north and west < east required.")
        sys.exit(1)

    try:
        records = download_region(args.south, args.west, args.north, args.east)
        write_csv(records, Path(args.csv))
        write_json(records, Path(args.json))
        print(f"Downloaded {len(records)} records")
        if records:
            print(f"Example searchable POI: {records[0]['name']} ({records[0]['kind']})")
    except Exception as exc:
        print(f"Download failed: {exc}", file=sys.stderr)
        sys.exit(1)
