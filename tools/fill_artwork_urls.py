#!/usr/bin/env python3
"""fill_artwork_urls.py — apple_music_id は埋まっているのに artwork_url が
空の曲を iTunes Lookup API で補完する。

Usage:
    python3 tools/fill_artwork_urls.py             # dry-run
    python3 tools/fill_artwork_urls.py --apply

note:
  - artworkUrl100 を 600x600bb に置換して保存
  - fill_apple_music_ids.py で apple_music_id だけ書いた曲が artwork 抜けに
    なりがちなので、 セット運用する
"""

import argparse
import json
import sqlite3
import sys
import time
import urllib.request
from pathlib import Path
from typing import Optional

DB = Path(__file__).parent.parent / "ImasLiveDB/Resources/master.sqlite"


def itunes_lookup(track_id: str) -> Optional[dict]:
    url = f"https://itunes.apple.com/lookup?id={track_id}&country=jp"
    req = urllib.request.Request(url, headers={"User-Agent": "ImasLiveDB-artwork/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.load(resp)
            r = data.get("results", [])
            return r[0] if r else None
    except Exception as e:
        print(f"  ERROR: lookup {track_id} failed: {e}", file=sys.stderr)
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        """
        SELECT id, title, apple_music_id FROM songs
        WHERE apple_music_id IS NOT NULL AND apple_music_id != ''
          AND (artwork_url IS NULL OR artwork_url = ''
            OR apple_music_album_id IS NULL OR apple_music_album_id = ''
            OR cd_series IS NULL OR cd_series = '')
        """
    ).fetchall()

    print(f"Targets: {len(rows)} songs missing artwork/album metadata")
    updated = 0
    cur = conn.cursor()
    for row in rows:
        result = itunes_lookup(row["apple_music_id"])
        if not result:
            print(f"  ✗ {row['id']}: not found in iTunes ({row['apple_music_id']})")
            continue
        artwork = (result.get("artworkUrl100") or "").replace("100x100bb", "600x600bb")
        album_id = result.get("collectionId")
        album_name = result.get("collectionName")
        if not artwork and not album_id:
            print(f"  ✗ {row['id']}: no artwork/album in result")
            continue
        print(f"  ✓ {row['id']}: '{row['title']}' -> artwork+album")
        updated += 1
        if args.apply:
            cur.execute(
                """UPDATE songs SET artwork_url=COALESCE(?, artwork_url),
                   apple_music_album_id=COALESCE(?, apple_music_album_id),
                   cd_series=COALESCE(?, cd_series)
                   WHERE id=?""",
                (artwork or None, str(album_id) if album_id else None, album_name, row["id"]),
            )
        time.sleep(0.3)

    if args.apply:
        conn.commit()
        print(f"\nUpdated: {updated} (committed)")
    else:
        print(f"\nUpdated: {updated} (DRY-RUN)")


if __name__ == "__main__":
    main()
