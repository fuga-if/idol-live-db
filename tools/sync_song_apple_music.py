#!/usr/bin/env python3
"""
sync_song_apple_music.py — ローカル songs の Apple Music 関連フィールドを
CloudKit Public Database に partial update で反映する。

対象フィールド (CloudKit キー):
  - appleMusicId
  - appleMusicAlbumId
  - artworkUrl
  - previewUrl
  - cdSeries

他のフィールドには触らない。ローカル値が NULL の場合はそのフィールドを送らない。

Usage:
    python3 tools/sync_song_apple_music.py [--env development|production] \\
        [--dry-run] [--key-file tools/eckey.pem] [--key-id KEY_ID] \\
        [--brand BRAND_ID] [--ids id1,id2,...] [--ids-file path]

--ids / --ids-file を指定すると、その song id だけを push する (modifiedAt の全件 bump を避ける)。
daily-data-crawl ルーティンが「今日補完した行だけ」を反映するのに使う。
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import sqlite3
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import requests
from ecdsa import SigningKey
from ecdsa.util import sigencode_der


BASE_URL = "https://api.apple-cloudkit.com"
CONTAINER = "iCloud.com.fugaif.ImasLiveDB"
DB_PATH = Path(__file__).resolve().parent.parent / "ImasLiveDB" / "Resources" / "master.sqlite"
DEFAULT_KEY_FILE = Path(__file__).resolve().parent / "eckey.pem"

BATCH_SIZE = 100
MAX_RETRIES = 5
INITIAL_BACKOFF = 1.0

FIELD_MAP = {
    "apple_music_id": ("appleMusicId", "STRING"),
    "apple_music_album_id": ("appleMusicAlbumId", "STRING"),
    "artwork_url": ("artworkUrl", "STRING"),
    "preview_url": ("previewUrl", "STRING"),
    "cd_series": ("cdSeries", "STRING"),
}

_signing_key = None
_key_id = ""


def sign_headers(body: bytes, subpath: str) -> dict:
    date_str = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    body_hash = base64.b64encode(hashlib.sha256(body).digest()).decode()
    message = f"{date_str}:{body_hash}:{subpath}"
    signature = base64.b64encode(
        _signing_key.sign(message.encode(), hashfunc=hashlib.sha256, sigencode=sigencode_der)
    ).decode()
    return {
        "Content-Type": "application/json",
        "X-Apple-CloudKit-Request-KeyID": _key_id,
        "X-Apple-CloudKit-Request-ISO8601Date": date_str,
        "X-Apple-CloudKit-Request-SignatureV1": signature,
    }


def post_modify(env: str, payload: dict) -> dict:
    subpath = f"/database/1/{CONTAINER}/{env}/public/records/modify"
    url = BASE_URL + subpath
    body = json.dumps(payload).encode("utf-8")
    headers = sign_headers(body, subpath)
    for attempt in range(MAX_RETRIES):
        resp = requests.post(url, data=body, headers=headers)
        if resp.status_code == 200:
            return resp.json()
        if resp.status_code == 429:
            wait = INITIAL_BACKOFF * (2 ** attempt)
            print(f"  rate-limited; sleeping {wait:.1f}s", file=sys.stderr)
            time.sleep(wait)
            headers = sign_headers(body, subpath)
            continue
        resp.raise_for_status()
    raise RuntimeError("max retries exceeded")


def build_operation(song_id: str, row: sqlite3.Row) -> dict:
    fields: dict = {}
    for col, (ck_name, ck_type) in FIELD_MAP.items():
        val = row[col]
        if val in (None, ""):
            continue
        fields[ck_name] = {"value": val, "type": ck_type}
    fields["modifiedAt"] = {
        "value": int(datetime.now(timezone.utc).timestamp() * 1000),
        "type": "TIMESTAMP",
    }
    return {
        "operationType": "forceUpdate",
        "record": {
            "recordType": "Song",
            "recordName": song_id,
            "fields": fields,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", choices=["development", "production"], default="development")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--key-file", type=Path, default=DEFAULT_KEY_FILE)
    parser.add_argument("--key-id", default=os.environ.get("CLOUDKIT_KEY_ID", ""))
    parser.add_argument("--brand", help="filter by brand_id (e.g. gakuen)")
    parser.add_argument("--ids", help="comma-separated song id allowlist (これだけ push)")
    parser.add_argument("--ids-file", type=Path, help="1 行 1 song id のファイル (--ids と同義)")
    args = parser.parse_args()

    id_filter: list[str] = []
    if args.ids:
        id_filter += [s.strip() for s in args.ids.split(",") if s.strip()]
    if args.ids_file:
        id_filter += [ln.strip() for ln in args.ids_file.read_text().splitlines() if ln.strip()]

    if not args.dry_run and not args.key_id:
        print("Error: --key-id (or CLOUDKIT_KEY_ID env) required", file=sys.stderr)
        sys.exit(1)
    if not args.dry_run:
        global _signing_key, _key_id
        _key_id = args.key_id
        _signing_key = SigningKey.from_pem(args.key_file.read_text())

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    where = """WHERE ((apple_music_id IS NOT NULL AND apple_music_id != '')
                   OR (cd_series IS NOT NULL AND cd_series != '')
                   OR (artwork_url IS NOT NULL AND artwork_url != ''))"""
    params: list = []
    if args.brand:
        where += " AND brand_id = ?"
        params.append(args.brand)
    if id_filter:
        placeholders = ",".join("?" for _ in id_filter)
        where += f" AND id IN ({placeholders})"
        params += id_filter
    rows = conn.execute(f"SELECT * FROM songs {where}", params).fetchall()
    scope = f"ids={len(id_filter)}" if id_filter else f"brand={args.brand or 'all'}"
    print(f"target songs: {len(rows)}  env={args.env}  {scope}")

    ops = [build_operation(row["id"], row) for row in rows]
    total_success = 0
    total_failure = 0

    for i in range(0, len(ops), BATCH_SIZE):
        batch = ops[i : i + BATCH_SIZE]
        if args.dry_run:
            print(f"  [dry-run] batch {i // BATCH_SIZE + 1}: {len(batch)} records")
            total_success += len(batch)
            continue
        resp = post_modify(args.env, {"operations": batch})
        for r in resp.get("records", []):
            if r.get("serverErrorCode"):
                total_failure += 1
                print(f"  ✗ {r.get('recordName')}: {r.get('serverErrorCode')} / {r.get('reason')}", file=sys.stderr)
            else:
                total_success += 1
        print(f"  batch {i // BATCH_SIZE + 1}/{(len(ops) + BATCH_SIZE - 1) // BATCH_SIZE}: OK {total_success}  FAIL {total_failure}")
        time.sleep(0.2)

    print(f"\ndone. success={total_success}  failure={total_failure}")


if __name__ == "__main__":
    main()
