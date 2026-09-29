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

署名・送信・429 の待ち・エラーの数え方は tools/lib/cloudkit.py (seed_cloudkit.py と共有)。
レコード単位のエラーが 1 件でもあれば exit 1。
"""

from __future__ import annotations

import argparse
import os
import sqlite3
import sys
from pathlib import Path

from lib import cloudkit as ck
from lib.ck_records import next_modified_ms

DB_PATH = Path(__file__).resolve().parent.parent / "ImasLiveDB" / "Resources" / "master.sqlite"
DEFAULT_KEY_FILE = Path(__file__).resolve().parent / "eckey.pem"

BATCH_SIZE = 100

FIELD_MAP = {
    "apple_music_id": ("appleMusicId", "STRING"),
    "apple_music_album_id": ("appleMusicAlbumId", "STRING"),
    "artwork_url": ("artworkUrl", "STRING"),
    "preview_url": ("previewUrl", "STRING"),
    "cd_series": ("cdSeries", "STRING"),
}


def build_operation(song_id: str, row: sqlite3.Row) -> dict:
    fields: dict = {}
    for col, (ck_name, ck_type) in FIELD_MAP.items():
        val = row[col]
        if val in (None, ""):
            continue
        fields[ck_name] = {"value": val, "type": ck_type}
    fields["modifiedAt"] = {"value": next_modified_ms(), "type": "TIMESTAMP"}
    return {
        "operationType": "forceUpdate",
        "record": {
            "recordType": "Song",
            "recordName": song_id,
            "fields": fields,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", choices=["development", "production"], default="development")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--key-file", type=Path, default=DEFAULT_KEY_FILE)
    parser.add_argument("--key-id", default=os.environ.get("CLOUDKIT_KEY_ID", ""))
    # 既定は同梱 master.sqlite。手元の master.sqlite に無く db/master.sql にだけ在る曲
    # (既知の乖離分) を押し出すときは、master.sql から起こした DB をここで指す。
    parser.add_argument("--db", type=Path, default=DB_PATH, help="読み出す SQLite (既定: 同梱 master.sqlite)")
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
        return 1
    signer = None if args.dry_run else ck.load_signer(args.key_id, args.key_file)

    conn = sqlite3.connect(args.db)
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
    url = ck.BASE_URL + ck.records_path(args.env, "modify")
    total_success, total_failure = ck.upload_operations(
        ops, url, args.dry_run, "Song", post=lambda u, p: ck.post_json(u, p, signer),
        batch_size=BATCH_SIZE, pause=0.2)

    print(f"\ndone. success={total_success}  failure={total_failure}")
    return 1 if total_failure else 0


if __name__ == "__main__":
    sys.exit(main())
