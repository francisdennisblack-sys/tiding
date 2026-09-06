#!/usr/bin/env python3

import json
import os
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

# Category importance scoring (1-5 star scale)
CATEGORY_PRIORITY = {
    # 5 Stars: Cities, Admin regions & Capitals, Towns, Villages, Suburbs, Neighborhoods
    "city": 5, "town": 5, "village": 5, "hamlet": 5, "suburb": 5, "neighbourhood": 5, "administrative": 5, "capital": 5,

    # 4 Stars: Parks, Reserves, Trails, Beaches, Lakes, Mountain Peaks & Natural Landmarks
    "park": 4, "national_park": 4, "state_park": 4, "city_park": 4,
    "nature_reserve": 4, "protected_area": 4, "trail": 4, "hiking_trail": 4,
    "path": 4, "footway": 4, "garden": 4, "recreation_ground": 4,
    "beach": 4, "lake": 4, "peak": 4, "mountain": 4, "viewpoint": 4,
    "overlook": 4, "volcano": 4, "waterfall": 4, "bay": 4, "coast": 4,
    "university": 4, "college": 4, "school": 4, "campus": 4,

    # 3 Stars: Venues, Culture, Restaurants, Cafes, Bars, Museums, Shopping & Entertainment
    "museum": 3, "stadium": 3, "arena": 3, "sports_centre": 3,
    "restaurant": 3, "cafe": 3, "fast_food": 3, "bar": 3, "pub": 3,
    "nightclub": 3, "theatre": 3, "cinema": 3, "attraction": 3, "historic": 3,
    "mall": 3, "marketplace": 3, "theme_park": 3, "zoo": 3, "aquarium": 3,

    # 2 Stars: Essential Travel, Transport & Community
    "airport": 2, "station": 2, "ferry_terminal": 2, "hotel": 2, "library": 2, "townhall": 2
}

# Exclusion list eliminating major junk categories
EXCLUDED_CATEGORIES = {
    "industrial", "power", "man_made", "pipeline", "substation", "generator",
    "solar_array", "telecom", "antenna", "cell_tower", "utility", "water_works",
    "pumping_station", "reservoir_drain", "sewage_plant", "construction",
    "bus_stop", "tram_stop", "stop_sign", "traffic_signals", "speed_camera",
    "railway_switch", "siding", "buffer_stop", "level_crossing", "railyard",
    "parking", "parking_space", "parking_entrance", "parking_meter",
    "charging_station", "bicycle_parking", "car_wash",
    "warehouse", "storage", "storage_locker", "factory", "scrap_yard",
    "quarry", "mine", "office", "office_park", "commercial", "wholesale",
    "cargo_terminal", "auto_repair", "garage", "tire_shop", "towing_yard",
    "bench", "waste_basket", "trash_bin", "recycling", "dog_waste",
    "vending_machine", "atm", "gate", "bollard", "barrier", "fence",
    "surveillance", "camera", "toilets", "porta_potty"
}

def compact_record(name, subtitle, lat, lon, tier):
    return [
        name.strip(),
        subtitle.strip(),
        round(float(lat), 4),
        round(float(lon), 4),
        int(tier)
    ]

def generate_tiles():
    tiles = []

    # High-density Metro Regions prioritized sequentially for rich regional grouping
    regions = [
        # 1. US & Canada Major Metro Corridors
        ("US_Northeast_Corridor", 38.0, -77.5, 43.5, -70.0),
        ("US_California_Coast", 32.5, -124.5, 39.0, -116.5),
        ("US_Texas_Triangle", 28.5, -100.0, 33.5, -94.0),
        ("US_Midwest_GreatLakes", 40.0, -90.0, 46.0, -80.0),
        ("US_Pacific_NW", 44.0, -124.5, 49.0, -121.0),
        ("US_Florida_Georgia", 24.5, -87.5, 32.0, -79.5),
        ("US_Mountain_West", 32.0, -114.0, 44.0, -104.0),

        # 2. Western Europe Metro Hubs
        ("Europe_UK_Ireland", 50.0, -10.5, 59.0, 2.0),
        ("Europe_France_Benelux", 43.0, -4.5, 53.5, 7.5),
        ("Europe_DACH_Germany", 47.0, 5.5, 55.0, 15.0),
        ("Europe_Italy_Alps", 37.0, 6.5, 47.0, 18.5),
        ("Europe_Iberia_Spain_Portugal", 36.0, -9.5, 43.5, 3.5),

        # 3. Asia-Pacific Major Metros
        ("Asia_Japan_Kanto_Kansai", 33.0, 134.0, 37.5, 141.0),
        ("Asia_Korea", 34.0, 126.0, 38.5, 129.5),
        ("Asia_SE_Singapore_Malaysia", 1.0, 100.0, 7.0, 104.5),
        ("Asia_Taiwan", 21.8, 119.8, 25.5, 122.2),
        ("Australia_East_Sydney_Melb", -39.0, 143.0, -27.0, 154.0),
    ]

    for name, s, w, n, e in regions:
        lat_step = 1.5
        lon_step = 1.5
        lat = s
        while lat < n:
            lon = w
            while lon < e:
                lat2 = min(lat + lat_step, n)
                lon2 = min(lon + lon_step, e)
                tiles.append((f"{name}_{lat:.1f}_{lon:.1f}", [round(lat, 2), round(lon, 2), round(lat2, 2), round(lon2, 2)]))
                lon += lon_step
            lat += lat_step

    return tiles

def fetch_tile_overpass(bounds, retries=2):
    south, west, north, east = bounds
    # Multi-tier expanded query to harvest deep venue & regional dataset
    query = f"""[out:json][timeout:90];
    (
      node["place"~"city|town|village|hamlet|suburb|neighbourhood"]({south},{west},{north},{east});
      node["leisure"~"park|nature_reserve|garden|recreation_ground"]({south},{west},{north},{east});
      node["natural"~"beach|peak|volcano|bay|waterfall"]({south},{west},{north},{east});
      node["tourism"~"viewpoint|museum|attraction|zoo|theme_park|aquarium"]({south},{west},{north},{east});
      node["amenity"~"university|college|school|restaurant|cafe|bar|pub|stadium|library|marketplace"]({south},{west},{north},{east});
    );
    out center 6000;"""

    url = "https://overpass-api.de/api/interpreter?data=" + urllib.parse.quote(query)
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Spot-Global-Expanded-Downloader/5.0",
            "Accept": "application/json"
        }
    )

    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=45) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                return data.get("elements", [])
        except Exception as e:
            time.sleep(2 * (attempt + 1))
    return []

def get_tier_and_subtitle(tags):
    name = tags.get("name") or tags.get("name:en")
    if not name:
        return None, None, None

    place = tags.get("place")
    amenity = tags.get("amenity")
    leisure = tags.get("leisure")
    natural = tags.get("natural")
    tourism = tags.get("tourism")

    # Tier 5: Cities, Towns, Suburbs, Neighborhoods
    if place in ["city", "town", "village", "hamlet", "suburb", "neighbourhood"]:
        state = tags.get("addr:state") or tags.get("is_in:state") or tags.get("is_in:country") or "Location"
        return name, state, CATEGORY_PRIORITY.get(place, 5)

    # Tier 4: Parks, Reserves, Gardens
    if leisure in ["park", "nature_reserve", "garden", "recreation_ground"]:
        city = tags.get("addr:city") or tags.get("is_in:city") or "Park"
        return name, city, CATEGORY_PRIORITY.get(leisure, 4)

    # Tier 4: Campuses & Schools
    if amenity in ["university", "college", "school"]:
        city = tags.get("addr:city") or tags.get("is_in:city") or "Campus"
        return name, city, CATEGORY_PRIORITY.get(amenity, 4)

    # Tier 4: Beaches, Peaks, Volcanos
    if natural in ["beach", "peak", "volcano", "bay", "waterfall"]:
        region = tags.get("addr:city") or tags.get("is_in:state") or "Nature"
        return name, region, CATEGORY_PRIORITY.get(natural, 4)

    # Tier 3: Venues, Museums, Dining & Culture
    if tourism in ["viewpoint", "museum", "attraction", "zoo", "theme_park", "aquarium"] or amenity in ["restaurant", "cafe", "bar", "pub", "stadium", "library", "marketplace"]:
        sub = tags.get("addr:city") or tags.get("is_in:city") or amenity or tourism or "Venue"
        sub = sub.capitalize()
        tier = CATEGORY_PRIORITY.get(tourism, CATEGORY_PRIORITY.get(amenity, 3))
        return name, sub, tier

    return None, None, None

def download_tiered_global_pois(output_path="data/global_5m_locations.json", target_mb=90.0):
    print(f"Starting expanded global dataset download targeting ~{target_mb} MB...", flush=True)
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)

    records = []
    seen_keys = set()

    # Load existing dataset if available to preserve progress
    if os.path.exists(output_path):
        try:
            with open(output_path, encoding="utf-8") as f:
                existing = json.load(f)
                for item in existing:
                    if isinstance(item, list) and len(item) >= 5:
                        name, sub, lat, lon, tier = item[0], item[1], item[2], item[3], item[4]
                        key = f"{name.lower()}|{round(lat, 4)}|{round(lon, 4)}"
                        if key not in seen_keys:
                            seen_keys.add(key)
                            records.append(item)
            print(f"Resuming with {len(records):,} existing records ({os.path.getsize(output_path) / (1024*1024):.2f} MB)...")
        except Exception as e:
            print(f"Could not load existing file: {e}")

    # Load initial offline seed records
    for seed_file in ["data/seed_new_york.json", "data/salt_lake_city_pois.json"]:
        if os.path.exists(seed_file):
            try:
                with open(seed_file, encoding="utf-8") as f:
                    s_data = json.load(f)
                    for item in s_data:
                        name = item.get("name", "").strip()
                        city = item.get("subtitle", item.get("city", "Location")).strip()
                        lat = item.get("latitude", item.get("lat", 0.0))
                        lon = item.get("longitude", item.get("lon", 0.0))
                        if name and lat and lon:
                            key = f"{name.lower()}|{round(lat, 4)}|{round(lon, 4)}"
                            if key not in seen_keys:
                                seen_keys.add(key)
                                records.append(compact_record(name, city, lat, lon, 4))
            except Exception as e:
                pass

    tiles = generate_tiles()
    print(f"Generated {len(tiles)} geographic grid tiles to process...")

    successful_tiles = 0
    for idx, (tile_name, bounds) in enumerate(tiles, start=1):
        file_size_mb = 0
        if os.path.exists(output_path):
            file_size_mb = os.path.getsize(output_path) / (1024 * 1024)

        if file_size_mb >= target_mb:
            print(f"\nReached target dataset size ({file_size_mb:.2f} MB >= {target_mb} MB)! Stopping download.")
            break

        print(f"[{idx}/{len(tiles)}] Tile {tile_name} {bounds} (Current: {len(records):,} records / {file_size_mb:.2f} MB)...", flush=True)
        elements = fetch_tile_overpass(bounds)

        added_in_tile = 0
        for el in elements:
            tags = el.get("tags", {})
            name, subtitle, tier = get_tier_and_subtitle(tags)
            if not name:
                continue

            lat = el.get("lat") or el.get("center", {}).get("lat")
            lon = el.get("lon") or el.get("center", {}).get("lon")
            if lat is None or lon is None:
                continue

            key = f"{name.lower()}|{round(lat, 4)}|{round(lon, 4)}"
            if key not in seen_keys:
                seen_keys.add(key)
                records.append(compact_record(name, subtitle, lat, lon, tier))
                added_in_tile += 1

        if added_in_tile > 0 or len(elements) > 0:
            successful_tiles += 1

        if idx % 1 == 0:
            records.sort(key=lambda r: r[4], reverse=True)
            with open(output_path, "w", encoding="utf-8") as f:
                json.dump(records, f, separators=(',', ':'))
            current_mb = os.path.getsize(output_path) / (1024 * 1024)
            print(f"  [Checkpoint] Saved {len(records):,} records sorted by priority ({current_mb:.2f} MB)", flush=True)

        time.sleep(0.2)

    # Final save & priority sort
    records.sort(key=lambda r: r[4], reverse=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(records, f, separators=(',', ':'))

    file_size_mb = os.path.getsize(output_path) / (1024 * 1024)
    print(f"\nDownload complete! Saved {len(records):,} records ({file_size_mb:.2f} MB) sorted by rating priority.")

if __name__ == "__main__":
    download_tiered_global_pois()
    records.sort(key=lambda r: r[4], reverse=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(records, f, separators=(',', ':'))

    file_size_mb = os.path.getsize(output_path) / (1024 * 1024)
    print(f"\nDownload complete! Saved {len(records):,} records ({file_size_mb:.2f} MB) sorted by rating priority.")

if __name__ == "__main__":
    download_tiered_global_pois()
