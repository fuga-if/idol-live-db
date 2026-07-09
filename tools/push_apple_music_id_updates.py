#!/usr/bin/env python3
"""apple_music_id を差し替えた曲の Song レコードを CloudKit へ push する。

playability チェックで「サブスク再生不可 (playParameters=nil)」 と判明した曲について、
別の正しい storeID (サブスク再生可能版) に master.sqlite を更新した分を CloudKit Production
に反映する。

入力: Scripts/apply_apple_music_id_updates.py 経由で master.sqlite に反映済みの
       proposed_updates_apply.json (confidence=low_skip と none は自動的に skip された後)。

挙動:
  1. proposed_updates_apply.json を読み、 new_apple_music_id が non-null な song_id を集める
  2. master.sqlite の songs テーブルから該当行を読む
  3. seed_cloudkit.rows_to_operations で Song レコード化
  4. upload_operations で CloudKit に modifyRecords する

使い方:
    # dry-run (件数確認のみ)
    python3 tools/push_apple_music_id_updates.py data/playability_fix/cg_proposed_updates_apply.json --dry-run

    # production へ実 push
    CLOUDKIT_KEY_ID=xxxxx python3 tools/push_apple_music_id_updates.py \\
        data/playability_fix/cg_proposed_updates_apply.json --production
"""
import argparse
import json
import os
import sqlite3
import sys
from pathlib import Path

import seed_cloudkit as sc


def fetch_song_rows(conn: sqlite3.Connection, song_ids: list[str]) -> list[dict]:
    placeholders = ",".join("?" * len(song_ids))
    cols = [c["name"] for c in sc.get_column_info(conn, "songs")]
    sql = f"SELECT * FROM songs WHERE id IN ({placeholders}) ORDER BY id"
    cur = conn.execute(sql, song_ids)
    rows = []
    for r in cur.fetchall():
        row = dict(zip([d[0] for d in cur.description], r))
        rows.append(row)
    return rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("updates_json", type=Path,
                        help="proposed_updates_apply.json (apply 後のもの)")
    parser.add_argument("--dry-run", action="store_true",
                        help="件数表示のみ (CloudKit には送らない)")
    parser.add_argument("--production", action="store_true",
                        help="production 環境へ push (デフォルトは development)")
    parser.add_argument("--key-id", default=os.environ.get("CLOUDKIT_KEY_ID"),
                        help="CloudKit Web Services key ID (env: CLOUDKIT_KEY_ID)")
    parser.add_argument("--key-file", type=Path, default=sc.DEFAULT_KEY_FILE,
                        help=f"S2S 秘密鍵 PEM (default: {sc.DEFAULT_KEY_FILE})")
    args = parser.parse_args()

    env = "production" if args.production else "development"
    sc.ENVIRONMENT = env
    sc._build_paths(env)

    if not args.dry_run:
        if not args.key_id:
            print("ERROR: --key-id required (or set CLOUDKIT_KEY_ID).", file=sys.stderr)
            sys.exit(1)
        if not args.key_file.exists():
            print(f"ERROR: key file not found: {args.key_file}", file=sys.stderr)
            sys.exit(1)
        sc.init_session(args.key_id, args.key_file)

    with open(args.updates_json) as f:
        updates = json.load(f)

    song_ids = sorted({
        u["song_id"] for u in updates
        if u.get("new_apple_music_id") and u.get("confidence") in ("high", "medium", "low")
    })
    print(f"[push] env={env}  target song_ids: {len(song_ids)}")

    conn = sqlite3.connect(sc.DB_PATH)
    try:
        cols = sc.get_column_info(conn, "songs")
        pk = sc.get_primary_keys(conn, "songs")
        rows = fetch_song_rows(conn, song_ids)
    finally:
        conn.close()

    if not rows:
        print("[info] 対象行なし。 終了。")
        return

    print(f"[push] Song レコード {len(rows)} 件:")
    for r in rows[:5]:
        print(f"    {r['id']}  apple_music_id={r.get('apple_music_id')}")
    if len(rows) > 5:
        print(f"    … 他 {len(rows) - 5} 件")

    ops = sc.rows_to_operations("songs", rows, cols, pk)
    ok, err = sc.upload_operations(ops, args.dry_run, "Song(apple_music_id update)")

    if args.dry_run:
        print(f"[dry-run] {len(ops)} 件を push する想定 (実行なし)。")
    else:
        print(f"[done] Song succeeded={ok} errors={err}")
        if err:
            sys.exit(1)


if __name__ == "__main__":
    main()
