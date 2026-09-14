#!/usr/bin/env python3

import argparse
import glob
import json
import os
import sqlite3
from typing import Dict, Iterable, Optional, Tuple

CATEGORY_WEIGHTS: Dict[str, int] = {
    "airport": 32,
    "subway_station": 30,
    "metro_station": 30,
    "train_station": 28,
    "hospital": 28,
    "pharmacy": 25,
    "clinic": 24,
    "bus_station": 24,
    "ferry_terminal": 23,
    "grocery": 22,
    "supermarket": 22,
    "museum": 21,
    "restaurant": 20,
    "hotel": 20,
    "convenience": 20,
    "cafe": 19,
    "park": 19,
    "hostel": 18,
    "marketplace": 18,
    "mall": 18,
    "fuel": 18,
    "university": 18,
    "bank": 17,
    "motel": 17,
    "fast_food": 17,
    "bakery": 16,
    "atm": 16,
    "college": 16,
    "department_store": 16,
    "theatre": 16,
    "theater": 16,
    "bar": 15,
    "school": 15,
    "car_rental": 15,
    "historic": 15,
    "pub": 14,
    "leisure": 14,
    "shop": 12,
    "parking": 12,
    "car_wash": 12,
    "amenity": 11,
}

IMPORTANT_CATEGORY_KEYWORDS = (
    "school",
    "high_school",
    "university",
    "college",
    "park",
    "nature",
    "forest",
    "reserve",
    "beach",
    "lake",
    "mountain",
    "peak",
    "viewpoint",
    "landmark",
    "memorial",
    "museum",
    "historic",
    "restaurant",
    "cafe",
    "bakery",
    "food",
)

EXCLUDED_CATEGORY_KEYWORDS = (
    "bench",
    "waste",
    "toilets",
    "parking_entrance",
    "hydrant",
    "street_lamp",
    "traffic_signals",
    "post_box",
    "vending_machine",
)


def norm_name(value: str) -> str:
    return " ".join((value or "").strip().lower().split())


def norm_category(value: str) -> str:
    return norm_name(value).replace(" ", "_")


def score_bonus_for_importance(category: str, name: str) -> int:
    cat = norm_category(category)
    n = norm_name(name)
    if not cat and not n:
        return -9999

    for bad in EXCLUDED_CATEGORY_KEYWORDS:
        if bad in cat:
            return -9999

    bonus = 0
    if any(key in cat for key in IMPORTANT_CATEGORY_KEYWORDS):
        bonus += 140

    if "high_school" in cat or ("school" in cat and "high" in n):
        bonus += 120
    if "university" in cat or "college" in cat:
        bonus += 130
    if "restaurant" in cat or "cafe" in cat or "bakery" in cat:
        bonus += 90
    if "park" in cat or "nature" in cat or "reserve" in cat or "forest" in cat:
        bonus += 100
    if "landmark" in cat or "historic" in cat or "memorial" in cat or "museum" in cat:
        bonus += 110

    if len(n) <= 2:
        bonus -= 100

    return bonus


def cell_key(lat: float, lon: float, cell_deg: float) -> Tuple[int, int]:
    return (int(lat / cell_deg), int(lon / cell_deg))


def stream_global_rows(db_path: str, limit: int) -> Iterable[Tuple[str, str, float, float, int]]:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute(
        """
        SELECT name, category, latitude, longitude, score
        FROM pois
        WHERE name IS NOT NULL AND TRIM(name) != ''
        ORDER BY score DESC, name ASC
        LIMIT ?
        """,
        (limit,),
    )
    for name, category, lat, lon, score in cur:
        yield str(name), str(category), float(lat), float(lon), int(score)
    conn.close()


def stream_state_rows(db_path: str, limit: int) -> Iterable[Tuple[str, str, float, float, int]]:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    # Fetch top records by computed category quality per state DB.
    cases = " ".join([f"WHEN LOWER(category) = '{k}' THEN {v}" for k, v in CATEGORY_WEIGHTS.items()])
    query = f"""
        SELECT name, category, latitude, longitude,
               CASE {cases} ELSE 8 END AS score
        FROM pois
        WHERE name IS NOT NULL AND TRIM(name) != ''
        ORDER BY score DESC, name ASC
        LIMIT ?
    """

    cur.execute(query, (limit,))
    for name, category, lat, lon, score in cur:
        yield str(name), str(category), float(lat), float(lon), int(score)
    conn.close()


def write_compact_json_with_size_cap(
    output_path: str,
    target_bytes: int,
    global_db: str,
    state_dir: str,
    global_limit: int,
    per_state_limit: int,
    max_per_cell: int,
    cell_deg: float,
    source_weight: int,
) -> Tuple[int, int, Dict[str, int]]:
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    written = 0
    used_bytes = 2
    seen = set()
    per_cell_counts: Dict[Tuple[int, int], int] = {}
    stats = {
        "global_examined": 0,
        "state_examined": 0,
        "important_written": 0,
        "fallback_written": 0,
    }

    def try_emit_row(name: str, category: str, lat: float, lon: float, base_score: int, important_only: bool) -> Optional[bool]:
        nonlocal written, used_bytes

        name_norm = norm_name(name)
        if not name_norm:
            return False

        bonus = score_bonus_for_importance(category, name)
        if bonus <= -9999:
            return False

        is_important = bonus > 0
        if important_only and not is_important:
            return False

        boosted_score = int(base_score * source_weight + bonus)

        key = f"{name_norm}|{round(lat, 4)}|{round(lon, 4)}"
        if key in seen:
            return False

        bucket = cell_key(lat, lon, cell_deg)
        if per_cell_counts.get(bucket, 0) >= max_per_cell:
            return False

        payload = [name.strip(), category.strip(), round(lat, 6), round(lon, 6), boosted_score]
        encoded = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
        extra = len(encoded.encode("utf-8")) + (1 if written > 0 else 0)

        if used_bytes + extra > target_bytes:
            return None

        if written > 0:
            f.write(",")
        f.write(encoded)

        used_bytes += extra
        written += 1
        seen.add(key)
        per_cell_counts[bucket] = per_cell_counts.get(bucket, 0) + 1
        if is_important:
            stats["important_written"] += 1
        else:
            stats["fallback_written"] += 1
        return True

    def process_stream(important_only: bool) -> bool:
        for name, category, lat, lon, score in stream_global_rows(global_db, global_limit):
            stats["global_examined"] += 1
            status = try_emit_row(name, category, lat, lon, score, important_only=important_only)
            if status is None:
                return False

        for db in sorted(glob.glob(os.path.join(state_dir, "*.db"))):
            for name, category, lat, lon, score in stream_state_rows(db, per_state_limit):
                stats["state_examined"] += 1
                status = try_emit_row(name, category, lat, lon, score, important_only=important_only)
                if status is None:
                    return False

        return True

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("[")

        # Pass 1: important categories first.
        fully_processed = process_stream(important_only=True)

        # Pass 2: fill remaining size with best non-important POIs.
        if fully_processed and used_bytes < target_bytes:
            process_stream(important_only=False)

        f.write("]")

    return written, used_bytes, stats, stats, stats, stats, stats, stats, stats, stats, stats, stats, stats, stats, stats, stats, stats, stats, stats


def main() -> None:
    parser = argparse.ArgumentParser(description="Build a curated, high-value on-device POI bundle with a file-size cap.")
    parser.add_argument("--global-db", default="data/global_high_value/global_high_value_pois.db")
    parser.add_argument("--state-dir", default="data/us_state_pois")
    parser.add_argument("--output", default="data/curated_pois_100mb.json")
    parser.add_argument("--target-mb", type=int, default=100)
    parser.add_argument("--global-limit", type=int, default=700000)
    parser.add_argument("--per-state-limit", type=int, default=20000)
    parser.add_argument("--max-per-cell", type=int, default=8)
    parser.add_argument("--cell-deg", type=float, default=0.03)
    parser.add_argument("--source-weight", type=int, default=10, help="Multiplier applied to source score before importance bonuses.")
    args = parser.parse_args()

    target_bytes = args.target_mb * 1024 * 1024

    written, used_bytes, stats = write_compact_json_with_size_cap(
        output_path=args.output,
        target_bytes=target_bytes,
        global_db=args.global_db,
        state_dir=args.state_dir,
        global_limit=args.global_limit,
        per_state_limit=args.per_state_limit,
        max_per_cell=args.max_per_cell,
        cell_deg=args.cell_deg,
        source_weight=args.source_weight,
    )

    print(f"Global rows examined: {stats['global_examined']}")
    print(f"State rows examined: {stats['state_examined']}")
    print(f"Important rows written: {stats['important_written']}")
    print(f"Fallback rows written: {stats['fallback_written']}")
    print(f"Rows written: {written}")
    print(f"File size: {used_bytes / (1024 * 1024):.2f} MB")
    print(f"Output: {args.output}")


if __name__ == "__main__":
    main()
