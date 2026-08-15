#!/usr/bin/env python3
"""export_cloudkit.py — CloudKit Public DB (source of truth) → db/master.sql。

seed_cloudkit.py の逆向き。CloudKit の全マスタレコードを query して
ローカル master.sqlite を作り直し、git に載せる db/master.sql に dump する。

主用途: GitHub Actions の日次 cron で実行し、変化があれば db/master.sql を
自動コミット → コントリビューターが常に最新データに対して --check できる。

    CLOUDKIT_KEY_ID=... python3 tools/export_cloudkit.py --production \
        --key-file tools/eckey.pem

スキーマと非同期テーブル(meta / song_units 等)は既存の db/master.sql から引き継ぎ、
CloudKit に存在するテーブルだけ中身を入れ替える (PRESERVED_TABLES 参照)。

マスタに実差分があった回だけ meta.data_version を +1 する。ここが上がらないと
アプリ側の reseed (bundle > 端末) が発火せず、CloudKit に入ったデータが既存
ユーザーに届かない。差分判定は data_version 行を除いて比較する (バンプ自体が
差分になる循環を避けるため)。
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

# CloudKit に RecordType はあるが、master としては既存 dump 側が正のテーブル。
# meta は RECORD_TYPE_MAP に載っているので、外さないと refresh_table の
# DELETE FROM meta で消える。CloudKit 側に MetaData レコードは無いため
# 空のまま dump され、bundle 側 data_version が 0 になって
# AppDatabase.reseedMasterTablesIfNeeded が二度と走らなくなる。
PRESERVED_TABLES = {"meta"}


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
    inserted = skipped = soft_deleted = 0
    for r in recs:
        # soft delete (deletedAt) 済みレコードは「削除」なので master に再取込しない。
        # master 側テーブルに deleted_at 列が無いため、取り込むと生存レコードとして
        # 復活してしまう (是正で消したはずの誤データが cron で蘇る事故の防止)。
        if r.get("fields", {}).get("deletedAt", {}).get("value"):
            soft_deleted += 1
            continue
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
    if soft_deleted:
        note += f" (soft-deleted {soft_deleted})"
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


def dump_text(conn) -> str:
    return "".join(line + "\n" for line in conn.iterdump())


_DATA_VERSION_RE = re.compile(
    r"""^INSERT INTO ["']?meta["']?\s+VALUES\('data_version'.*$\n?""", re.M
)


def data_only(dump: str) -> str:
    """data_version 行を除いた dump。バンプ自体が差分を生む循環を避けて比較するため。"""
    return _DATA_VERSION_RE.sub("", dump)


def comparable(sql_text: str) -> str:
    """dump テキストを比較可能な正規形にする。

    db/master.sql には 2 系統の形式が混在する。オーナーが手で作り直した回は
    sqlite3 CLI の .dump (テーブル名クォート無し・sqlite_master 順)、cron の回は
    iterdump (クォート有り・別順) で、生テキスト比較だと常に「差分あり」になる。
    一度 DB に読み込んで同じ iterdump に通し、書式と行順を揃えてから比べる。
    """
    conn = sqlite3.connect(":memory:")
    try:
        conn.executescript(sql_text)
        return data_only(dump_text(conn))
    finally:
        conn.close()


def read_data_version(conn) -> int:
    row = conn.execute("SELECT value FROM meta WHERE key = 'data_version'").fetchone()
    return int(row[0]) if row and str(row[0]).isdigit() else 0


def bump_data_version(conn) -> int:
    """data_version を +1 する。

    アプリの reseed は bundle 側 data_version > 端末側 のときだけ走る
    (AppDatabase.reseedMasterTablesIfNeeded)。ここを上げないと、CloudKit に入って
    db/master.sql まで来たデータが既存ユーザーに永久に届かない。
    """
    new = read_data_version(conn) + 1
    conn.execute(
        "INSERT INTO meta (key, value) VALUES ('data_version', ?) "
        "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        (str(new),),
    )
    conn.commit()
    return new


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

    before = DUMP_PATH.read_text(encoding="utf-8") if DUMP_PATH.exists() else ""

    conn = build_conn_from_dump()
    conn.execute("PRAGMA foreign_keys = OFF")
    print(f"CloudKit ({env}) から master を取得:")
    total = 0
    for table in sk.TABLE_ORDER:
        if table in PRESERVED_TABLES:
            continue
        if table in sk.RECORD_TYPE_MAP and sk.get_column_info(conn, table):
            total += refresh_table(conn, table)
    conn.commit()

    after = dump_text(conn)
    if data_only(after) != comparable(before):
        new_version = bump_data_version(conn)
        after = dump_text(conn)
        print(f"\nマスタに差分あり → data_version {new_version - 1} → {new_version}")
    else:
        print(f"\nマスタに差分なし → data_version {read_data_version(conn)} 据え置き")

    # data_version が落ちた dump を出すと、既存ユーザーの reseed が bundle=0 で
    # 止まり無言で旧データのまま固定される。書き出す前にここで落とす。
    if read_data_version(conn) <= 0:
        print("✗ meta.data_version が無い/不正。db/master.sql を書き換えず中止。", file=sys.stderr)
        conn.close()
        sys.exit(1)

    DUMP_PATH.parent.mkdir(parents=True, exist_ok=True)
    DUMP_PATH.write_text(after, encoding="utf-8")
    conn.close()
    print(f"✓ {total} 行を db/master.sql に書き出し")


if __name__ == "__main__":
    main()
