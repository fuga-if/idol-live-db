#!/usr/bin/env python3
"""export_cloudkit.py — CloudKit Public DB (source of truth) → db/master.sql。

seed_cloudkit.py の逆向き。CloudKit の全マスタレコードを query して
ローカル master.sqlite を作り直し、git に載せる db/master.sql に dump する。

主用途: GitHub Actions の日次 cron で実行し、変化があれば db/master.sql を
自動コミット → コントリビューターが常に最新データに対して --check できる。

    CLOUDKIT_KEY_ID=... python3 tools/export_cloudkit.py --production \
        --key-file tools/eckey.pem

スキーマと非同期テーブル(meta / song_units 等)は既存の db/master.sql から引き継ぎ、
CloudKit に存在するテーブルだけ中身を入れ替える。
"""
from __future__ import annotations

import argparse
import os
import re
import sqlite3
import sys
from pathlib import Path

import seed_cloudkit as sk  # 同ディレクトリ。署名・query・テーブルマップを再利用

ROOT = Path(__file__).resolve().parent.parent
DUMP_PATH = ROOT / "db" / "master.sql"
DB_PATH = ROOT / "ImasLiveDB" / "Resources" / "master.sqlite"


def camel_to_snake(name: str) -> str:
    """snake_to_camel の逆 (appleMusicId → apple_music_id)。"""
    return re.sub(r"([A-Z])", r"_\1", name).lower()


def query_all(record_type: str) -> list[dict]:
    """指定 RecordType の全レコードを continuationMarker でページング取得。

    フィルタ無しクエリは recordName 順を要求するが recordName は queryable でない。
    modifiedAt は iOS 差分同期 (modifiedAt > lastSync) が使うため必ず queryable なので、
    modifiedAt > 0 でフィルタ＆ソートして全件を列挙する (全レコードに modifiedAt が入る)。
    """
    url = sk.BASE_URL + sk.QUERY_PATH
    out, cursor = [], None
    while True:
        payload = {
            "query": {
                "recordType": record_type,
                "filterBy": [{
                    "fieldName": "modifiedAt",
                    "comparator": "GREATER_THAN",
                    "fieldValue": {"value": 0, "type": "TIMESTAMP"},
                }],
                "sortBy": [{"fieldName": "modifiedAt", "ascending": True}],
            },
            "resultsLimit": 200,
        }
        if cursor:
            payload["continuationMarker"] = cursor
        result = sk.get_json(url, payload)
        out.extend(result.get("records", []))
        # CloudKit は次ページがある時だけ continuationMarker を返す (無ければ最終ページ)
        cursor = result.get("continuationMarker")
        if not cursor:
            break
    return out


def record_to_row(conn, table, rec, pk_cols, table_cols):
    """CloudKit レコード → SQLite 行 dict。"""
    row = {}
    # 単一PKは recordName が値 (fields に入っていない)
    if len(pk_cols) == 1:
        row[pk_cols[0]] = rec.get("recordName")
    for ck_name, field in rec.get("fields", {}).items():
        if ck_name == "modifiedAt":  # CloudKit 専用・master に列なし
            continue
        col = camel_to_snake(ck_name)
        if col in table_cols:
            row[col] = field.get("value")
    return {k: v for k, v in row.items() if k in table_cols}


def refresh_table(conn, table):
    record_type = sk.RECORD_TYPE_MAP[table]
    table_cols = {c["name"] for c in sk.get_column_info(conn, table)}
    pk_cols = sk.get_primary_keys(conn, table)
    recs = query_all(record_type)

    conn.execute(f"DELETE FROM {table}")
    inserted = skipped = 0
    for r in recs:
        row = record_to_row(conn, table, r, pk_cols, table_cols)
        if not row:
            skipped += 1
            continue
        keys = list(row.keys())
        try:
            conn.execute(
                f"INSERT INTO {table} ({', '.join(keys)}) VALUES ({', '.join('?' for _ in keys)})",
                [row[k] for k in keys],
            )
            inserted += 1
        except sqlite3.IntegrityError as e:
            skipped += 1
            if skipped <= 5:
                print(f"    skip {table} {r.get('recordName')}: {e}", file=sys.stderr)
    note = f" (skip {skipped})" if skipped else ""
    print(f"  {table:<22} CloudKit {len(recs):>6} → 反映 {inserted:>6}{note}")
    return inserted


def build_conn_from_dump() -> sqlite3.Connection:
    """既存 db/master.sql からスキーマ+データを読み込んだ in-file DB を作る。"""
    if not DUMP_PATH.exists():
        print(f"db/master.sql が無い。先にローカル master.sqlite から生成してください。", file=sys.stderr)
        sys.exit(1)
    if DB_PATH.exists():
        DB_PATH.unlink()
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.executescript(DUMP_PATH.read_text(encoding="utf-8"))
    return conn


def write_dump(conn):
    DUMP_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(DUMP_PATH, "w", encoding="utf-8") as f:
        for line in conn.iterdump():
            f.write(line + "\n")


def main():
    ap = argparse.ArgumentParser(description="CloudKit → db/master.sql エクスポート")
    ap.add_argument("--key-file", default=str(sk.DEFAULT_KEY_FILE))
    ap.add_argument("--key-id", default=os.environ.get("CLOUDKIT_KEY_ID", ""))
    ap.add_argument("--environment", default="development", choices=["development", "production"])
    ap.add_argument("--production", action="store_true", help="--environment production の短縮")
    args = ap.parse_args()

    env = "production" if args.production else args.environment
    sk._build_paths(env)
    if not args.key_id:
        print("CLOUDKIT_KEY_ID が必要 (env か --key-id)", file=sys.stderr)
        sys.exit(1)
    sk.init_session(args.key_id, Path(args.key_file))

    conn = build_conn_from_dump()
    conn.execute("PRAGMA foreign_keys = OFF")
    print(f"CloudKit ({env}) から master を取得:")
    total = 0
    for table in sk.TABLE_ORDER:
        if table in sk.RECORD_TYPE_MAP and sk.get_column_info(conn, table):
            total += refresh_table(conn, table)
    conn.commit()
    write_dump(conn)
    conn.close()
    print(f"\n✓ {total} 行を db/master.sql に書き出し")


if __name__ == "__main__":
    main()
