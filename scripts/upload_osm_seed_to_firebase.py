#!/usr/bin/env python3

import argparse
import csv
import json
import os
import re
import sys
from pathlib import Path

REQUIRED_PROJECT_ID = "tiding-506722"
DEFAULT_COLLECTION = "osm_places"


def sanitize_document_id(raw: str) -> str:
    text = (raw or "place").strip()
    text = text.replace("/", "_")
    text = text.replace(" ", "_")
    text = re.sub(r"[^A-Za-z0-9_-]", "_", text)
    text = text.strip("_")
    return text or "place"


def determine_place_type(record: dict) -> str:
    kind = str(record.get("kind") or "poi").strip().lower()
    if kind in {"city", "town", "village", "hamlet", "suburb", "neighbourhood", "quarter", "district", "locality", "borough"}:
        return "place"
    return "poi"


def normalize_record(record: dict) -> dict:
    name = (record.get("name") or "").strip()
    if not name:
        return None

    kind = str(record.get("kind") or "poi").strip().lower()
    if kind in {"address"}:
        return None

    lat = float(record.get("latitude"))
    lng = float(record.get("longitude"))
    place_type = determine_place_type(record)

    doc_id = sanitize_document_id(f"{kind}:{name}:{lat}:{lng}")
    return {
        "document_id": doc_id,
        "name": name,
        "kind": kind,
        "placeType": place_type,
        "category": (record.get("category") or "other").strip() or "other",
        "latitude": lat,
        "longitude": lng,
        "source": "osm",
        "searchText": name.lower(),
    }


def load_seed_records(path: Path):
    records = []
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            normalized = normalize_record(row)
            if normalized:
                records.append(normalized)
    return records


def initialize_firebase(credentials_path: str):
    try:
        import firebase_admin
        from firebase_admin import credentials, firestore
    except ImportError as exc:
        raise RuntimeError("firebase-admin is not installed. Install it with: pip install firebase-admin") from exc

    if not os.path.exists(credentials_path):
        raise FileNotFoundError(f"Firebase credentials not found: {credentials_path}")

    with open(credentials_path, "r", encoding="utf-8") as handle:
        data = json.load(handle)

    project_id = (data.get("project_id") or "").strip()
    if project_id != REQUIRED_PROJECT_ID:
        raise ValueError(
            f"Credential project mismatch. Expected '{REQUIRED_PROJECT_ID}', got '{project_id or 'unknown'}'."
        )

    if not firebase_admin._apps:
        cred = credentials.Certificate(credentials_path)
        firebase_admin.initialize_app(cred)

    return firestore.client()


def upload_records(db, records, collection_name: str):
    uploaded = 0
    for record in records:
        db.collection(collection_name).document(record["document_id"]).set({
            "name": record["name"],
            "kind": record["kind"],
            "placeType": record["placeType"],
            "category": record["category"],
            "latitude": record["latitude"],
            "longitude": record["longitude"],
            "source": record["source"],
            "searchText": record["searchText"],
        }, merge=True)
        uploaded += 1
    return uploaded


def main():
    parser = argparse.ArgumentParser(description="Upload OSM place + POI seed data to Firestore.")
    parser.add_argument("--input", type=str, required=True, help="CSV file produced by the OSM seed script.")
    parser.add_argument("--credentials", type=str, required=True, help="Path to Firebase service account JSON.")
    parser.add_argument("--collection", type=str, default=DEFAULT_COLLECTION, help="Firestore collection name to upload into.")
    args = parser.parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")

    db = initialize_firebase(os.path.abspath(args.credentials))
    records = load_seed_records(input_path)
    uploaded = upload_records(db, records, args.collection)
    print(f"Uploaded {uploaded} OSM place records to Firestore collection '{args.collection}'")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Upload failed: {exc}", file=sys.stderr)
        sys.exit(1)
