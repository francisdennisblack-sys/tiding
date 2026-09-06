#!/usr/bin/env python3

import argparse
import json
import os
import sys
from pathlib import Path


import re

EXPECTED_FIREBASE_PROJECT_ID = "tiding-506722"


def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def make_firestore_document_id(region_id):
    cleaned = region_id or "unknown"
    cleaned = cleaned.replace("/", "_")
    cleaned = cleaned.replace(" ", "_")
    cleaned = re.sub(r"[^A-Za-z0-9_-]", "_", cleaned)
    return cleaned.strip("_") or "unknown"


def main():
    parser = argparse.ArgumentParser(description="Upload region JSON to Firebase Firestore.")
    parser.add_argument("--input", type=str, required=True, help="Path to the Firestore-ready JSON export.")
    parser.add_argument("--collection", type=str, default="regions")
    parser.add_argument("--credentials", type=str, default=None, help="Optional path to service account JSON.")
    parser.add_argument("--project-id", type=str, default=EXPECTED_FIREBASE_PROJECT_ID)
    args = parser.parse_args()

    if args.project_id != EXPECTED_FIREBASE_PROJECT_ID:
        print(f"Project mismatch: expected '{EXPECTED_FIREBASE_PROJECT_ID}', got '{args.project_id}'.")
        sys.exit(1)

    if args.credentials:
        credential_path = args.credentials
    else:
        credential_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS") or "firebase-service-account.json"

    if not Path(credential_path).exists():
        print("Firebase credentials were not found.")
        print("Provide --credentials or set GOOGLE_APPLICATION_CREDENTIALS to a valid service account JSON file.")
        print("Example: GOOGLE_APPLICATION_CREDENTIALS=service-account.json python3 scripts/upload_regions_to_firebase.py --input data/regions_firestore.json")
        sys.exit(1)

    try:
        credential_json = load_json(credential_path)
    except Exception as exc:
        print(f"Failed to read credentials JSON: {exc}")
        sys.exit(1)

    credential_project_id = (credential_json.get("project_id") or "").strip()
    if credential_project_id != EXPECTED_FIREBASE_PROJECT_ID:
        print(
            "Credentials project mismatch. "
            f"Expected '{EXPECTED_FIREBASE_PROJECT_ID}', got '{credential_project_id or 'unknown'}'."
        )
        sys.exit(1)

    try:
        import firebase_admin
        from firebase_admin import credentials, firestore
    except ImportError:
        print("The firebase-admin Python SDK is not installed.")
        print("Install it with: pip install firebase-admin")
        sys.exit(1)

    cred = credentials.Certificate(credential_path)
    if not firebase_admin._apps:
        firebase_admin.initialize_app(cred)

    db = firestore.client()
    documents = load_json(args.input)

    for record in documents:
        region_id = record.get("region_id")
        if not region_id:
            continue

        document_id = make_firestore_document_id(region_id)
        payload = dict(record)
        payload["region_id"] = region_id
        payload["firestore_document_id"] = document_id

        db.collection(args.collection).document(document_id).set(payload)
        print(f"Uploaded {document_id} from {region_id}")

    print(f"Uploaded {len(documents)} region documents to Firestore collection '{args.collection}'.")


if __name__ == "__main__":
    main()
