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
import os
import sqlite3
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

_TOOLS_DIR = str(Path(__file__).resolve().parent)
if _TOOLS_DIR not in sys.path:
    sys.path.insert(0, _TOOLS_DIR)

# 表の知識・レコードの組み立て・通信は lib/ に置いてある。手元のスクリプトがこの
# ファイルの名前で import しているので、ここからも同じ名前で読めるようにしておく
# (名前を消したり変えたりしない)。
from lib import cloudkit as _ck  # noqa: E402
from lib.ck_records import (  # noqa: E402,F401
    SCHEMA_MANAGED_FIELDS,
    SCHEMA_PATH,
    assert_replace_safe,
    build_fields,
    get_column_info,
    get_primary_keys,
    has_table,
    make_record_name,
    next_modified_ms,
    push_columns,
    rows_to_operations,
    schema_fields,
    sent_columns,
    snake_to_camel,
    sql_type_to_cloudkit,
)
from lib.ck_tables import (  # noqa: E402,F401
    ID_FILTER_COLUMN,
    RECORD_TYPE_MAP,
    SCOPED_ID_SPACE,
    TABLE_ORDER,
    scope_id,
)


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

BASE_URL = _ck.BASE_URL
CONTAINER = _ck.CONTAINER
ENVIRONMENT = "development"
DB_PATH = Path(__file__).parent.parent / "ImasLiveDB" / "Resources" / "master.sqlite"

# These are set after arg parsing (may be overridden by --environment / --production)
MODIFY_PATH = ""
QUERY_PATH = ""


def _build_paths(env: str) -> None:
    global MODIFY_PATH, QUERY_PATH
    MODIFY_PATH = _ck.records_path(env, "modify")
    QUERY_PATH = _ck.records_path(env, "query")


_build_paths(ENVIRONMENT)

BATCH_SIZE = _ck.BATCH_SIZE
MAX_RETRIES = _ck.MAX_RETRIES
INITIAL_BACKOFF = _ck.INITIAL_BACKOFF  # seconds
DEFAULT_KEY_FILE = Path(__file__).parent / "eckey.pem"

# 互換のため NOW_MS は seed 全体で 1 つの代表値を持つが、 個別 push では next_modified_ms()
# を使うので影響なし (event_merges 等で modifiedAt をその場で複数 push する箇所のみ参照)。
NOW_MS = int(datetime.now(timezone.utc).timestamp() * 1000)


# ---------------------------------------------------------------------------
# CloudKit S2S Auth (実体は lib/cloudkit.py)
# ---------------------------------------------------------------------------

_signing_key = None  # lib.cloudkit.Signer。init_session で作る
_key_id = ""


def init_session(key_id: str, key_file: Path) -> None:
    global _signing_key, _key_id
    _key_id = key_id
    _signing_key = _ck.load_signer(key_id, key_file)
    print(f"  [auth] CloudKit S2S auth initialized")


def post_json(url: str, payload: dict, auth=None) -> dict:
    """init_session の鍵で署名して POST する (429 は待って再署名し、やり直す)。"""
    return _ck.post_json(url, payload, _signing_key)


def get_json(url: str, payload: dict, auth=None) -> dict:
    """POST a query request (CloudKit uses POST for queries too)."""
    return post_json(url, payload, auth)


# ---------------------------------------------------------------------------
# Upload logic
# ---------------------------------------------------------------------------

def upload_operations(
    ops: list[dict], dry_run: bool, label: str
) -> tuple[int, int]:
    """Upload operations in batches. Returns (succeeded_count, error_count).

    送り先は _build_paths で決めた環境 (呼んだ時点の MODIFY_PATH)。
    """
    return _ck.upload_operations(ops, BASE_URL + MODIFY_PATH, dry_run, label, post=post_json)


def seed_table(
    conn: sqlite3.Connection,
    table: str,
    dry_run: bool,
    exclude_fields: Optional[set] = None,
    include_fields: Optional[set] = None,
    song_ids: Optional[list] = None,
    replace: bool = False,
) -> tuple[int, int]:
    """Read a table from SQLite and upload all records to CloudKit.

    song_ids が指定された場合、songs は id、song_artists は song_id でその集合に絞る
    (新曲だけを full push する用)。それ以外のテーブルでは無視される。

    replace=True は forceReplace で送る (意味と使いどころは rows_to_operations)。
    安全かどうかは呼び出し側が assert_replace_safe で先に確かめる。

    Returns (succeeded, errors).
    """
    record_type = RECORD_TYPE_MAP[table]
    col_info, select = push_columns(conn, table)
    pk_cols = get_primary_keys(conn, table)

    where, params = "", []
    id_col = ID_FILTER_COLUMN.get(table)
    if song_ids and id_col:
        where = f" WHERE {id_col} IN ({','.join('?' for _ in song_ids)})"
        params = song_ids
    cur = conn.execute(f"SELECT {select} FROM {table}{where}", params)
    cur.row_factory = None
    cols = [d[0] for d in cur.description]
    rows = [dict(zip(cols, row)) for row in cur.fetchall()]

    if not rows:
        if where:
            # 渡した id が 1 つも当たらないのは、id の種類の取り違えが多い
            # (shows は event_id で絞る、など)。黙って 0 件で終わらせない。
            print(f"  ⚠️ {table}: --ids で絞ったら 0 行 ({id_col} に渡した {len(song_ids)} 件の"
                  f" id が 1 つも無い)。id の種類と表の組み合わせを確かめること", file=sys.stderr)
        else:
            print(f"  (empty table, skipping)")
        return (0, 0)

    ops = rows_to_operations(table, rows, col_info, pk_cols, exclude_fields, include_fields, replace)
    return upload_operations(ops, dry_run, record_type)


# ---------------------------------------------------------------------------
# Delete logic (誤データ是正用)
# ---------------------------------------------------------------------------

def delete_records(pairs: list[tuple[str, str]], dry_run: bool) -> tuple[int, int]:
    """(recordType, recordName) のリストを CloudKit から物理削除する。

    物理削除は差分同期 (modifiedAt > lastSync) では既存クライアントに伝わらないが、
    - 日次 cron の export_cloudkit.py に誤レコードが再流入しなくなる
    - クライアントはフル同期完走時の CloudKitSyncEngine の deleteOrphans が掃除する
    - マスタテーブルは bundle data_version bump の reseed でも上書きされる
    の 3 経路で収束する。soft delete (deletedAt) は export が生存扱いで再取込して
    しまうため、マスタ誤データの是正には物理削除を使う。
    """
    known_types = set(RECORD_TYPE_MAP.values())
    unknown = sorted({t for t, _ in pairs if t not in known_types})
    if unknown:
        raise SystemExit(f"Error: unknown record type(s) in delete file: {', '.join(unknown)}")
    ops = [
        {
            "operationType": "forceDelete",
            "record": {"recordType": rtype, "recordName": rname},
        }
        for rtype, rname in pairs
    ]
    return upload_operations(ops, dry_run, "delete")


def parse_delete_file(path: Path) -> list[tuple[str, str]]:
    """'RecordType<TAB>recordName' 形式の TSV を読む (空行・#コメント行は無視)。"""
    pairs = []
    for i, line in enumerate(path.read_text().splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 2 or not parts[0] or not parts[1]:
            raise SystemExit(f"Error: {path}:{i} は 'RecordType<TAB>recordName' 形式ではない: {line!r}")
        pairs.append((parts[0], parts[1]))
    return pairs


# ---------------------------------------------------------------------------
# Verify logic
# ---------------------------------------------------------------------------

def cloudkit_count(record_type: str) -> int:
    """CloudKit にある record type の件数 (soft delete 済みは数えない = export と同じ)。

    CloudKit には件数を返す口が無いので、query_all と同じ条件 (modifiedAt > 0) で
    全ページをめくって数える。フィルタも並びも無い query は CloudKit が受け付けない。
    """
    return _ck.count_live(BASE_URL + QUERY_PATH, record_type, post=get_json)


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
    parser.add_argument(
        "--replace",
        action="store_true",
        help="forceReplace で送る (ローカルで NULL に直した列を CloudKit からも消す)。"
             "--ids/--ids-file で絞った対象にだけ使える。",
    )
    parser.add_argument(
        "--delete-file",
        type=Path,
        help="削除モード: 'RecordType<TAB>recordName' 形式の TSV を読み、該当レコードを "
             "CloudKit から物理削除 (forceDelete)。誤データ是正用。他のシード処理は行わない。"
             "クライアント側はフル同期完走時の deleteOrphans が掃除する前提。",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="--delete-file の実削除を確認なしで実行 (指定が無ければ dry-run 以外は中断)",
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

    # 削除モード: シードは行わず、TSV のレコードを物理削除して終了する。
    if args.delete_file:
        pairs = parse_delete_file(args.delete_file)
        print(f"=== CloudKit Record Deletion [{'DRY-RUN' if args.dry_run else 'LIVE'}] ===")
        print(f"Container: {CONTAINER} / {env} / public")
        print(f"Targets  : {len(pairs)} records from {args.delete_file}")
        by_type: dict[str, int] = {}
        for rtype, _ in pairs:
            by_type[rtype] = by_type.get(rtype, 0) + 1
        for rtype, n in sorted(by_type.items()):
            print(f"  {rtype:<20} {n}")
        if not args.dry_run and not args.yes:
            print("Error: 実削除には --yes が必要 (安全ガード)。まず --dry-run で内容確認を。", file=sys.stderr)
            sys.exit(1)
        succeeded, errors = delete_records(pairs, args.dry_run)
        print(f"\nDone. {succeeded} deleted / {errors} errors")
        sys.exit(1 if errors else 0)

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
    if args.replace:
        if not song_ids:
            print("Error: --replace は --ids / --ids-file で対象を絞ったときだけ使える。", file=sys.stderr)
            sys.exit(1)
        # 途中のテーブルで止まると、その前のテーブルだけ送られた状態になる。先に全部確かめる。
        for table in tables_to_process:
            assert_replace_safe(conn, table, exclude_fields, include_fields)
        print("Mode    : forceReplace")
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
                conn, table, args.dry_run, exclude_fields, include_fields, song_ids, replace=args.replace
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
    # レコード単位のエラーが 1 件でもあれば失敗として終わる (一部だけ送れた push を
    # 「成功」として先へ進めない)。
    if total_errors:
        sys.exit(1)


if __name__ == "__main__":
    main()
