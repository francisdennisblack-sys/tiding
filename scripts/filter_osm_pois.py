#!/usr/bin/env python3

import argparse
import sqlite3
from pathlib import Path

ALLOWED_CATEGORIES = {
    "cafe",
    "coffee",
    "restaurant",
    "food",
    "bakery",
    "park",
    "museum",
    "school",
    "college",
    "library",
    "hospital",
    "clinic",
    "hotel",
    "bar",
    "pub",
    "theatre",
    "cinema",
    "landmark",
    "monument",
    "tourism",
    "attraction",
    "bus_station",
    "subway_station",
    "station",
    "railway_station",
    "terminal",
    "tram_stop",
    "taxi",
    "market",
    "supermarket",
    "grocer",
    "pharmacy",
    "bank",
    "atm",
    "post_office",
    "police",
    "fire_station",
    "airport",
    "stadium",
    "sports_centre",
    "gym",
    "university",
    "church",
    "mosque",
    "synagogue",
    "temple",
    "place_of_worship",
    "beach",
    "garden",
    "playground",
    "viewpoint",
    "observatory",
    "shopping_mall",
    "mall",
    "bookstore",
    "hotel",
    "hostel",
}

IGNORED_CONTEXT_WORDS = (
    "district",
    "neighborhood",
    "suburb",
    "village",
    "city",
    "square",
    "way",
    "corner",
    "street",
    "avenue",
    "boulevard",
    "parkway",
    "road",
    "lane",
    "block",
    "terminal",
)


def is_useful_poi(name, category):
    if category in {"other", "yes", "no", "stop_position"}:
        return False
    category_lower = (category or "").lower()
    if category_lower not in ALLOWED_CATEGORIES and category_lower not in {"station", "terminal", "landmark", "park", "museum"}:
        return False
    lowered = name.lower()
    if any(word in lowered for word in IGNORED_CONTEXT_WORDS):
        return False
    return True


def dedupe_rows(rows):
    seen = set()
    deduped = []
    for row in rows:
        key = (row[1], round(float(row[2]), 5), round(float(row[3]), 5))
        if key in seen:
            continue
        seen.add(key)
        deduped.append(row)
    return deduped


def migrate_db(input_db, output_db):
    src = sqlite3.connect(input_db)
    dst = sqlite3.connect(output_db)
    src.row_factory = sqlite3.Row

    rows = src.execute('SELECT poi_id, name, latitude, longitude, category FROM pois').fetchall()
    filtered = []
    for row in rows:
        if is_useful_poi(row['name'], row['category']):
            filtered.append((row['poi_id'], row['name'], row['latitude'], row['longitude'], row['category']))

    deduped = dedupe_rows(filtered)

    dst.execute('DROP TABLE IF EXISTS pois')
    dst.execute('''
        CREATE TABLE pois (
            poi_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            category TEXT NOT NULL
        )
    ''')

    dst.executemany(
        'INSERT INTO pois (poi_id, name, latitude, longitude, category) VALUES (?, ?, ?, ?, ?)',
        deduped,
    )
    dst.commit()
    src.close()
    dst.close()
    return len(deduped)


def main():
    parser = argparse.ArgumentParser(description="Filter OSM POIs to a useful, app-ready category set.")
    parser.add_argument("--input", type=str, required=True)
    parser.add_argument("--output", type=str, required=True)
    args = parser.parse_args()

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    count = migrate_db(args.input, args.output)
    print(f"Filtered and deduped POIs: {count}")


if __name__ == "__main__":
    main()
