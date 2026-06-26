#!/usr/bin/env python3
"""
seed_cloudkit.py — ImasLiveDB SQLite → CloudKit Public Database seeder.

Usage:
    python3 tools/seed_cloudkit.py [--dry-run] [--verify] \
        [--key-file tools/eckey.pem] [--key-id KEY_ID]

Auth:
    Uses Server-to-Server JWT authentication (ES256).
    Set CLOUDKIT_KEY_ID env var, or pass --key-id.
    Pass the EC private key PEM file via --key-file.
"""

import argparse
import json
import os
import sqlite3
import sys
import time
import requests
import hashlib
import base64
from ecdsa import SigningKey
from ecdsa.util import sigencode_der
import urllib.request
import urllib.error
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

BASE_URL = "https://api.apple-cloudkit.com"
CONTAINER = "iCloud.com.fugaif.ImasLiveDB"
ENVIRONMENT = "development"
DB_PATH = Path(__file__).parent.parent / "ImasLiveDB" / "Resources" / "master.sqlite"

# These are set after arg parsing (may be overridden by --environment / --production)
MODIFY_PATH = ""
QUERY_PATH = ""


def _build_paths(env: str) -> None:
    global MODIFY_PATH, QUERY_PATH
    MODIFY_PATH = f"/database/1/{CONTAINER}/{env}/public/records/modify"
    QUERY_PATH = f"/database/1/{CONTAINER}/{env}/public/records/query"


_build_paths(ENVIRONMENT)

BATCH_SIZE = 200
MAX_RETRIES = 5
INITIAL_BACKOFF = 1.0  # seconds
DEFAULT_KEY_FILE = Path(__file__).parent / "eckey.pem"

# ---------------------------------------------------------------------------
# Record type mapping (SQL table → CloudKit record type)
# ---------------------------------------------------------------------------

TABLE_ORDER = [
    "brands",
    "idols",
    "events",
    "units",
    "songs",
    "shows",
    "idol_brands",
    "unit_members",
    "song_artists",
    "setlist_items",
    "setlist_performers",
    "show_cast",
    "meta",
]

RECORD_TYPE_MAP = {
    "brands": "Brand",
    "songs": "Song",
    "events": "Event",
    "shows": "Show",
    "setlist_items": "SetlistItem",
    "setlist_performers": "SetlistPerformer",
    "cast": "CastMember",
    "idols": "Idol",
    "idol_cast": "IdolCast",
    "idol_brands": "IdolBrand",
    "units": "ImasUnit",
    "unit_members": "UnitMember",
    "song_artists": "SongArtist",
    "show_cast": "ShowCast",
    "meta": "MetaData",
}

# ---------------------------------------------------------------------------
# Schema introspection helpers
# ---------------------------------------------------------------------------

def get_column_info(conn: sqlite3.Connection, table: str) -> list[dict]:
    """Return list of {name, type} for each column in table."""
    cur = conn.execute(f"PRAGMA table_info({table})")
    return [{"name": row[1], "type": row[2].upper()} for row in cur.fetchall()]


def snake_to_camel(name: str) -> str:
    """Convert snake_case to camelCase."""
    parts = name.split("_")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])


def sql_type_to_cloudkit(sql_type: str) -> str:
    """Map SQLite affinity to CloudKit field type."""
    if "INT" in sql_type:
        return "INT64"
    if "REAL" in sql_type or "FLOAT" in sql_type or "DOUBLE" in sql_type:
        return "DOUBLE"
    # TEXT, BLOB, and anything else → STRING
    return "STRING"


# ---------------------------------------------------------------------------
# Primary key helpers
# ---------------------------------------------------------------------------

def get_primary_keys(conn: sqlite3.Connection, table: str) -> list[str]:
    """Return list of primary key column names for the table."""
    cur = conn.execute(f"PRAGMA table_info({table})")
    pks = [(row[5], row[1]) for row in cur.fetchall() if row[5] > 0]
    pks.sort()
    return [name for _, name in pks]


def make_record_name(table: str, row: dict, pk_cols: list[str]) -> str:
    """Build a stable CloudKit record name from primary key values."""
    if len(pk_cols) == 1:
        return str(row[pk_cols[0]])
    # Composite PK: prefix with table abbreviation to avoid collisions
    parts = [table] + [str(row[col]) for col in pk_cols]
    return "-".join(parts)


# ---------------------------------------------------------------------------
# Record building
# ---------------------------------------------------------------------------

# モジュール読込時の基準時刻 (ms)。record ごとに +1ms ずつずらして使う。
# modifiedAt は「呼び出し時の実時刻 ms」 をベースに単調増加でユニークに割り当てる。
# プロセス開始時刻固定だと、 seed 実行中にユーザ端末側が incremental sync を完了して
# lastSync を更新した場合、 seed 完了後の sync で「lastSync > 全レコードの modifiedAt」
# となって新規 push がまるごと拾えなくなる ( "modifiedAt > lastSync" で 0 件)。
# 実時刻ベースに切り替えることで「push されたレコードは push 時刻以降」 が保証され、
# 任意のタイミングでアプリが incremental sync しても取りこぼされない。
_last_returned_ms = 0


def next_modified_ms() -> int:
    global _last_returned_ms
    now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
    if now_ms <= _last_returned_ms:
        now_ms = _last_returned_ms + 1
    _last_returned_ms = now_ms
    return now_ms


# 互換のため NOW_MS は seed 全体で 1 つの代表値を持つが、 個別 push では next_modified_ms()
# を使うので影響なし (event_merges 等で modifiedAt をその場で複数 push する箇所のみ参照)。
NOW_MS = int(datetime.now(timezone.utc).timestamp() * 1000)


def build_fields(
    row: dict,
    col_info: list[dict],
    pk_cols: list[str],
    exclude_fields: Optional[set] = None,
    include_fields: Optional[set] = None,
) -> dict:
    """Convert a SQLite row dict to CloudKit fields dict.

    - exclude_fields: camelCase フィールド名を除外 (Production に未デプロイな列を飛ばす用途)
    - include_fields: camelCase フィールド名をホワイトリスト (指定時はそれ以外を飛ばす)
    """
    fields = {}
    for col in col_info:
        raw_name = col["name"]
        # 単一PKはrecordNameに使うのでフィールドに含めない
        if len(pk_cols) == 1 and raw_name == pk_cols[0]:
            continue
        value = row.get(raw_name)
        if value is None:
            continue  # omit NULL fields
        ck_name = snake_to_camel(raw_name)
        if include_fields is not None and ck_name not in include_fields:
            continue
        if exclude_fields and ck_name in exclude_fields:
            continue
        ck_type = sql_type_to_cloudkit(col["type"])
        fields[ck_name] = {"value": value, "type": ck_type}
    # Add modifiedAt timestamp (milliseconds since epoch)
    fields["modifiedAt"] = {"value": next_modified_ms(), "type": "TIMESTAMP"}
    return fields


def rows_to_operations(
    table: str,
    rows: list[dict],
    col_info: list[dict],
    pk_cols: list[str],
    exclude_fields: Optional[set] = None,
    include_fields: Optional[set] = None,
) -> list[dict]:
    """Convert SQLite rows to CloudKit forceReplace operations."""
    record_type = RECORD_TYPE_MAP[table]
    ops = []
    for row in rows:
        record_name = make_record_name(table, row, pk_cols)
        fields = build_fields(row, col_info, pk_cols, exclude_fields, include_fields)
        ops.append(
            {
                "operationType": "forceUpdate",
                "record": {
                    "recordType": record_type,
                    "recordName": record_name,
                    "fields": fields,
                },
            }
        )
    return ops


# ---------------------------------------------------------------------------
# CloudKit S2S Auth (manual implementation)
# ---------------------------------------------------------------------------

_signing_key = None
_key_id = ""


def init_session(key_id: str, key_file: Path) -> None:
    global _signing_key, _key_id
    _key_id = key_id
    _signing_key = SigningKey.from_pem(key_file.read_text())
    print(f"  [auth] CloudKit S2S auth initialized")


def _sign_request(body: bytes, subpath: str) -> dict:
    """Generate CloudKit S2S auth headers."""
    from datetime import datetime, timezone
    date_str = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    body_hash = base64.b64encode(hashlib.sha256(body).digest()).decode()
    message = f"{date_str}:{body_hash}:{subpath}"
    signature = base64.b64encode(_signing_key.sign(message.encode(), hashfunc=hashlib.sha256, sigencode=sigencode_der)).decode()
    return {
        "Content-Type": "application/json",
        "X-Apple-CloudKit-Request-KeyID": _key_id,
        "X-Apple-CloudKit-Request-ISO8601Date": date_str,
        "X-Apple-CloudKit-Request-SignatureV1": signature,
    }


def post_json(url: str, payload: dict, auth=None) -> dict:
    """POST JSON to url with retry/backoff on 429.

    CloudKit API は recordName に非 ASCII 文字 (全角仮名・異体字 等) を含む場合、
    `\\uXXXX` 形式の escape よりも UTF-8 raw を期待するため ensure_ascii=False。
    """
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    # Extract subpath from URL for signing
    subpath = url.replace(BASE_URL, "")
    headers = _sign_request(body, subpath) if _signing_key else {"Content-Type": "application/json"}
    for attempt in range(MAX_RETRIES):
        resp = requests.post(url, data=body, headers=headers)
        if resp.status_code == 200:
            return resp.json()
        if resp.status_code == 429:
            wait = INITIAL_BACKOFF * (2 ** attempt)
            print(f"  [rate limit] sleeping {wait:.1f}s before retry {attempt + 1}/{MAX_RETRIES}")
            time.sleep(wait)
        else:
            print(f"  [HTTP {resp.status_code}] {resp.text[:500]}", file=sys.stderr)
            resp.raise_for_status()
    raise RuntimeError("Max retries exceeded for CloudKit request")


def get_json(url: str, payload: dict, auth=None) -> dict:
    """POST a query request (CloudKit uses POST for queries too)."""
    return post_json(url, payload, auth)


# ---------------------------------------------------------------------------
# Upload logic
# ---------------------------------------------------------------------------

def upload_operations(
    ops: list[dict], dry_run: bool, label: str
) -> tuple[int, int]:
    """Upload operations in batches. Returns (succeeded_count, error_count)."""
    total = len(ops)
    processed = 0
    error_count = 0
    url = BASE_URL + MODIFY_PATH

    for batch_start in range(0, total, BATCH_SIZE):
        batch = ops[batch_start : batch_start + BATCH_SIZE]
        if dry_run:
            print(f"  [dry-run] would upload {len(batch)} records (batch starting at {batch_start})")
            processed += len(batch)
            continue

        payload = {"operations": batch}
        try:
            result = post_json(url, payload)
        except Exception as e:
            print(f"  [error] batch upload failed: {e}", file=sys.stderr)
            raise

        errors = [r for r in result.get("records", []) if "serverErrorCode" in r]
        if errors:
            error_count += len(errors)
            print(f"  [warn] {len(errors)} record errors in batch:", file=sys.stderr)
            for err in errors[:3]:
                print(f"    {err}", file=sys.stderr)

        processed += len(batch)
        print(f"  uploaded {processed}/{total} {label} records")

    return (processed - error_count, error_count)


def seed_table(
    conn: sqlite3.Connection,
    table: str,
    dry_run: bool,
    exclude_fields: Optional[set] = None,
    include_fields: Optional[set] = None,
    song_ids: Optional[list] = None,
) -> tuple[int, int]:
    """Read a table from SQLite and upload all records to CloudKit.

    song_ids が指定された場合、songs は id、song_artists は song_id でその集合に絞る
    (新曲だけを full push する用)。それ以外のテーブルでは無視される。

    Returns (succeeded, errors).
    """
    record_type = RECORD_TYPE_MAP[table]
    col_info = get_column_info(conn, table)
    pk_cols = get_primary_keys(conn, table)

    where, params = "", []
    if song_ids:
        id_col = {"songs": "id", "song_artists": "song_id", "show_cast": "show_id"}.get(table)
        if id_col:
            where = f" WHERE {id_col} IN ({','.join('?' for _ in song_ids)})"
            params = song_ids
    cur = conn.execute(f"SELECT * FROM {table}{where}", params)
    cur.row_factory = None
    cols = [d[0] for d in cur.description]
    rows = [dict(zip(cols, row)) for row in cur.fetchall()]

    if not rows:
        print(f"  (empty table, skipping)")
        return (0, 0)

    ops = rows_to_operations(table, rows, col_info, pk_cols, exclude_fields, include_fields)
    return upload_operations(ops, dry_run, record_type)


# ---------------------------------------------------------------------------
# Verify logic
# ---------------------------------------------------------------------------

def cloudkit_count(record_type: str) -> int:
    """Query CloudKit for all records of a type and return count."""
    url = BASE_URL + QUERY_PATH
    payload = {
        "query": {"recordType": record_type},
        "resultsLimit": 1,
        "desiredKeys": [],  # fetch no fields, just count
    }
    # CloudKit doesn't have a COUNT endpoint; use resultsLimit+cursor pagination
    # For verification we do a real count by paginating.
    count = 0
    cursor = None
    while True:
        if cursor:
            payload["continuationMarker"] = cursor
        result = get_json(url, payload)
        records = result.get("records", [])
        count += len(records)
        cursor = result.get("moreComing") and result.get("continuationMarker")
        if not cursor:
            break
    return count


def verify(conn: sqlite3.Connection) -> None:
    print("\n=== Verification ===")
    print(f"{'Table':<24} {'SQLite':>8} {'CloudKit':>10} {'Match':>6}")
    print("-" * 52)
    all_match = True
    for table in TABLE_ORDER:
        record_type = RECORD_TYPE_MAP[table]
        sqlite_count = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        try:
            ck_count = cloudkit_count(record_type)
            match = "OK" if sqlite_count == ck_count else "MISMATCH"
            if match != "OK":
                all_match = False
        except Exception as e:
            ck_count = f"ERROR: {e}"
            match = "ERROR"
            all_match = False
        print(f"  {table:<22} {sqlite_count:>8} {str(ck_count):>10} {match:>6}")
    print()
    if all_match:
        print("All counts match.")
    else:
        print("WARNING: Some counts do not match!", file=sys.stderr)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Seed ImasLiveDB SQLite data into CloudKit Public Database"
    )
    parser.add_argument(
        "--key-file",
        default=str(DEFAULT_KEY_FILE),
        help=f"Path to EC private key PEM (default: {DEFAULT_KEY_FILE})",
    )
    parser.add_argument(
        "--key-id",
        default=os.environ.get("CLOUDKIT_KEY_ID", ""),
        help="CloudKit Server-to-Server key ID (default: $CLOUDKIT_KEY_ID)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview operations without uploading",
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="After seeding, compare record counts between SQLite and CloudKit",
    )
    parser.add_argument(
        "--db",
        default=str(DB_PATH),
        help=f"Path to master.sqlite (default: {DB_PATH})",
    )
    parser.add_argument(
        "--tables",
        nargs="+",
        metavar="TABLE",
        help="Only process these tables (default: all, in dependency order)",
    )
    parser.add_argument(
        "--environment",
        default="development",
        choices=["development", "production"],
        help="CloudKit environment to target (default: development)",
    )
    parser.add_argument(
        "--production",
        action="store_true",
        help="Shorthand for --environment production",
    )
    parser.add_argument(
        "--exclude-fields",
        nargs="+",
        metavar="FIELD",
        default=[],
        help="camelCase フィールド名を push から除外 (Production 未デプロイ列の回避用)",
    )
    parser.add_argument(
        "--fields",
        nargs="+",
        metavar="FIELD",
        default=None,
        help="camelCase フィールド名のホワイトリスト (指定時はそれ以外を全て除外)",
    )
    parser.add_argument(
        "--ids",
        help="songs/song_artists を特定 song id だけに絞って push (カンマ区切り)。"
             "新曲だけを full push する用 (全件 re-bump を避ける)",
    )
    parser.add_argument(
        "--ids-file",
        type=Path,
        help="1 行 1 song id のファイル (--ids と同義)",
    )
    args = parser.parse_args()

    song_ids: list[str] = []
    if args.ids:
        song_ids += [s.strip() for s in args.ids.split(",") if s.strip()]
    if args.ids_file:
        song_ids += [ln.strip() for ln in args.ids_file.read_text().splitlines() if ln.strip()]

    # Resolve environment
    env = "production" if args.production else args.environment
    _build_paths(env)

    # Resolve key file path relative to cwd when not absolute
    key_file = Path(args.key_file)
    if not key_file.is_absolute():
        key_file = Path.cwd() / key_file

    if not args.dry_run:
        if not args.key_id:
            print("Error: --key-id required. Set CLOUDKIT_KEY_ID or pass --key-id.", file=sys.stderr)
            sys.exit(1)
        if not key_file.exists():
            print(f"Error: key file not found at {key_file}", file=sys.stderr)
            sys.exit(1)
        init_session(args.key_id, key_file)

    db_path = Path(args.db)
    if not db_path.exists():
        print(f"Error: database not found at {db_path}", file=sys.stderr)
        sys.exit(1)

    tables_to_process = args.tables if args.tables else TABLE_ORDER
    invalid = [t for t in tables_to_process if t not in RECORD_TYPE_MAP]
    if invalid:
        print(f"Error: unknown table(s): {', '.join(invalid)}", file=sys.stderr)
        print(f"Valid tables: {', '.join(TABLE_ORDER)}", file=sys.stderr)
        sys.exit(1)

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    mode = "DRY-RUN" if args.dry_run else "LIVE"
    print(f"=== ImasLiveDB CloudKit Seeder [{mode}] ===")
    print(f"Database : {db_path}")
    print(f"Container: {CONTAINER} / {env} / public")
    if not args.dry_run:
        print(f"Key ID   : {args.key_id[:16]}...")
    if args.dry_run:
        print("(No data will be uploaded)")
    print()

    exclude_fields = set(args.exclude_fields) if args.exclude_fields else None
    include_fields = set(args.fields) if args.fields else None
    if exclude_fields:
        print(f"Exclude : {sorted(exclude_fields)}")
    if include_fields:
        print(f"Include : {sorted(include_fields)} (+ modifiedAt)")
    print()

    total_succeeded = 0
    total_errors = 0
    start_time = time.time()

    for table in tables_to_process:
        record_type = RECORD_TYPE_MAP[table]
        row_count = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        print(f"[{table}] → {record_type} ({row_count} rows)")
        try:
            succeeded, errors = seed_table(
                conn, table, args.dry_run, exclude_fields, include_fields, song_ids
            )
            total_succeeded += succeeded
            total_errors += errors
        except Exception as e:
            print(f"  [FATAL] {e}", file=sys.stderr)
            conn.close()
            sys.exit(1)

    elapsed = time.time() - start_time
    if total_errors:
        print(
            f"\nDone. {total_succeeded} ok / {total_errors} errors in {elapsed:.1f}s",
            file=sys.stderr,
        )
    else:
        print(f"\nDone. {total_succeeded} records uploaded in {elapsed:.1f}s")

    if args.verify:
        if args.dry_run:
            print("(--verify skipped in dry-run mode)")
        elif _signing_key:
            verify(conn)
        else:
            print("(--verify skipped: no auth configured)", file=sys.stderr)

    conn.close()


if __name__ == "__main__":
    main()
