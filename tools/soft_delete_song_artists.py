#!/usr/bin/env python3
"""
soft_delete_song_artists.py — 声なしアイドルを「原曲メンバー(role='original')」から外す。

全体曲 (Take me☆Take you / Absolute NIne / ハイファイ☆デイズ 等) に、CV のいない
(voice_actors が空の) アイドルが原曲メンバーとして登録されている誤りを修正する。
声なしアイドルは公式音源に参加し得ないので original から除外するのが正。

やること:
  1) master.sqlite から「role='original' かつ idol.voice_actors が空」の song_artists を抽出
  2) CloudKit の SongArtist レコードを soft delete (deletedAt + modifiedAt を立てる)
     → iOS/Android の差分同期が拾って全端末から物理削除される
  3) push 成功後、ローカル master.sqlite からも該当行を物理削除 (Bundle スナップショット整合)

Usage:
    # まず確認 (push しない)
    python3 tools/soft_delete_song_artists.py

    # 本番 CloudKit に反映 + ローカル DB も更新
    CLOUDKIT_KEY_ID=XXXX python3 tools/soft_delete_song_artists.py --apply --production

Auth: seed_cloudkit.py と同じ (CLOUDKIT_KEY_ID + tools/eckey.pem)。
"""

import argparse
import sqlite3
import sys
from pathlib import Path

import seed_cloudkit as ck

PK_COLS = ["song_id", "idol_id", "role"]


def fetch_voiceless_original_rows(db_path: Path):
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        """
        SELECT sa.song_id, sa.idol_id, sa.role,
               s.title AS song_title, i.name AS idol_name
        FROM song_artists sa
        JOIN idols i ON i.id = sa.idol_id
        JOIN songs  s ON s.id = sa.song_id
        WHERE sa.role = 'original'
          AND (i.voice_actors IS NULL OR TRIM(i.voice_actors) = '')
        ORDER BY s.title, i.name
        """
    ).fetchall()
    conn.close()
    return rows


def build_soft_delete_op(row) -> dict:
    record_name = ck.make_record_name("song_artists", row, PK_COLS)
    ts = ck.next_modified_ms()
    return {
        "operationType": "forceUpdate",
        "record": {
            "recordType": "SongArtist",
            "recordName": record_name,
            "fields": {
                "deletedAt": {"value": ts, "type": "TIMESTAMP"},
                "modifiedAt": {"value": ts, "type": "TIMESTAMP"},
            },
        },
    }


def delete_local_rows(db_path: Path, rows) -> int:
    conn = sqlite3.connect(str(db_path))
    try:
        cur = conn.executemany(
            "DELETE FROM song_artists WHERE song_id=? AND idol_id=? AND role=?",
            [(r["song_id"], r["idol_id"], r["role"]) for r in rows],
        )
        n = conn.total_changes
        conn.commit()
        return n
    finally:
        conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="実際に CloudKit へ push + ローカル DB 更新 (未指定は確認のみ)")
    parser.add_argument("--environment", choices=["development", "production"], default="development")
    parser.add_argument("--production", action="store_true", help="--environment production の短縮")
    parser.add_argument("--key-file", default=str(ck.DEFAULT_KEY_FILE))
    parser.add_argument("--key-id", default=None)
    args = parser.parse_args()

    env = "production" if args.production else args.environment
    ck._build_paths(env)

    db_path = ck.DB_PATH
    rows = fetch_voiceless_original_rows(db_path)

    # 曲ごとの内訳を表示
    by_song: dict[str, list] = {}
    for r in rows:
        by_song.setdefault(r["song_title"], []).append(r["idol_name"])
    print(f"対象: {len(rows)} 行 / {len(by_song)} 曲 (環境={env})\n")
    for title, names in by_song.items():
        print(f"  ■ {title}  — 声なし {len(names)} 名を original から除外")
        preview = "、".join(names[:8])
        more = f" …他{len(names) - 8}名" if len(names) > 8 else ""
        print(f"     {preview}{more}")
    print()

    if not rows:
        print("対象なし。終了。")
        return

    if not args.apply:
        print("[確認のみ] --apply を付けると CloudKit へ soft delete + ローカル DB 更新します。")
        return

    # 認証
    key_id = args.key_id or __import__("os").environ.get("CLOUDKIT_KEY_ID")
    key_file = Path(args.key_file)
    if not key_file.is_absolute():
        key_file = Path.cwd() / key_file
    if not key_id:
        print("Error: --key-id か CLOUDKIT_KEY_ID が必要", file=sys.stderr)
        sys.exit(1)
    if not key_file.exists():
        print(f"Error: key file not found: {key_file}", file=sys.stderr)
        sys.exit(1)
    ck.init_session(key_id, key_file)

    ops = [build_soft_delete_op(r) for r in rows]
    ok, errs = ck.upload_operations(ops, dry_run=False, label="SongArtist soft delete")
    print(f"\nCloudKit: 成功 {ok} / エラー {errs}")
    if errs:
        print("エラーがあるためローカル DB 更新は中止。", file=sys.stderr)
        sys.exit(1)

    n = delete_local_rows(db_path, rows)
    print(f"ローカル master.sqlite: {n} 行削除")
    print("完了。既存ユーザーは次回の差分同期で原曲メンバーから除外されます。")


if __name__ == "__main__":
    main()
