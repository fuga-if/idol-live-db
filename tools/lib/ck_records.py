"""SQLite の行 → CloudKit のレコード (操作) を組み立てる。標準ライブラリだけで書く。

seed_cloudkit.py から移したもの (中身は変えていない)。seed_cloudkit.py からも同じ名前で
読める (手元のスクリプトが使っている)。modifiedAt の単調増加 (next_modified_ms) の状態は
このモジュールに 1 つだけ持つので、どこから呼んでも同じ時計を進める。
"""
from __future__ import annotations

import re
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from lib.ck_tables import ID_FILTER_COLUMN, RECORD_TYPE_MAP


def has_table(conn: sqlite3.Connection, table: str) -> bool:
    return conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)
    ).fetchone() is not None


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


def sent_columns(
    col_info: list[dict],
    pk_cols: list[str],
    exclude_fields: Optional[set] = None,
    include_fields: Optional[set] = None,
) -> list[tuple[dict, str]]:
    """CloudKit に送る列を (列情報, camelCase 名) で返す。

    - 単一 PK は recordName に使うので送らない
    - exclude_fields: camelCase フィールド名を除外 (Production に未デプロイな列を飛ばす用途)
    - include_fields: camelCase フィールド名のホワイトリスト (指定時はそれ以外を飛ばす)
    """
    out = []
    for col in col_info:
        if len(pk_cols) == 1 and col["name"] == pk_cols[0]:
            continue
        ck_name = snake_to_camel(col["name"])
        if include_fields is not None and ck_name not in include_fields:
            continue
        if exclude_fields and ck_name in exclude_fields:
            continue
        out.append((col, ck_name))
    return out


def build_fields(
    row: dict,
    col_info: list[dict],
    pk_cols: list[str],
    exclude_fields: Optional[set] = None,
    include_fields: Optional[set] = None,
) -> dict:
    """Convert a SQLite row dict to CloudKit fields dict.

    送る列は sent_columns で決める。値が NULL の列は送らない (forceUpdate では CloudKit 側の
    値が残る。消したいときは forceReplace = rows_to_operations の replace)。
    """
    fields = {}
    for col, ck_name in sent_columns(col_info, pk_cols, exclude_fields, include_fields):
        value = row.get(col["name"])
        if value is None:
            continue  # omit NULL fields
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
    replace: bool = False,
) -> list[dict]:
    """Convert SQLite rows to CloudKit upsert operations.

    既定は forceUpdate: 送った列だけを書き換え、送らなかった列は CloudKit 側の値が残る。
    NULL 列は build_fields が省くので、**ローカルで NULL にした修正は forceUpdate では伝わらない**
    (翌日の CloudKit → db/master.sql の export で巻き戻る)。
    replace=True は forceReplace: レコードを送った列だけで置き換えるので NULL 化も伝わる。
    代わりに送らなかった列は消えるため、CLI では assert_replace_safe を通した対象にしか使わない。
    """
    record_type = RECORD_TYPE_MAP[table]
    ops = []
    for row in rows:
        record_name = make_record_name(table, row, pk_cols)
        fields = build_fields(row, col_info, pk_cols, exclude_fields, include_fields)
        ops.append(
            {
                "operationType": "forceReplace" if replace else "forceUpdate",
                "record": {
                    "recordType": record_type,
                    "recordName": record_name,
                    "fields": fields,
                },
            }
        )
    return ops


SCHEMA_PATH = Path(__file__).resolve().parent.parent / "cloudkit_schema.ckdb"
# CloudKit 側だけが持つ運用列。forceReplace で送らなくても意味が変わらない
# (deletedAt 無し = 生存、modifiedAt は build_fields が毎回付ける)。
SCHEMA_MANAGED_FIELDS = {"deletedAt", "modifiedAt"}


def schema_fields(record_type: str) -> set[str]:
    """tools/cloudkit_schema.ckdb (CloudKit コンソールの export) から record type の列名を読む。

    列は `name TYPE ...` の行。システム列は `"___createTime"` のように引用符つき、
    GRANT 行は大文字始まりなので、小文字始まりの語だけ拾えば列名になる。
    """
    text = SCHEMA_PATH.read_text(encoding="utf-8")
    m = re.search(r"RECORD TYPE %s \((.*?)\n\s*\);" % re.escape(record_type), text, re.S)
    if not m:
        raise SystemExit(f"Error: {SCHEMA_PATH.name} に RECORD TYPE {record_type} が無い")
    return set(re.findall(r"^\s+([a-z]\w*)\s", m.group(1), re.M))


def assert_replace_safe(
    conn: sqlite3.Connection,
    table: str,
    exclude_fields: Optional[set],
    include_fields: Optional[set],
) -> None:
    """forceReplace (--replace) がこのテーブルに安全かを、push を始める前に確かめる。

    - id で絞れるテーブルに限る。全件 replace は、ダンプの後に CloudKit 側で入った投稿を
      「ローカルでは NULL の列」として消してしまう。
    - CloudKit の列 (システム列と運用列を除く) が、送る列に収まっていること。
      収まらない列は forceReplace で黙って消えるので止める。

    main が対象テーブル全部をこの順で通してから push を始める (途中のテーブルで止まると
    その前のテーブルだけ送られた状態になるため)。
    """
    if table not in ID_FILTER_COLUMN:
        raise SystemExit(f"Error: --replace は {table} では使えない (--ids で絞れないテーブル)")
    col_info, _ = push_columns(conn, table)
    sent = {ck for _, ck in sent_columns(col_info, get_primary_keys(conn, table), exclude_fields, include_fields)}
    missing = schema_fields(RECORD_TYPE_MAP[table]) - SCHEMA_MANAGED_FIELDS - sent
    if missing:
        raise SystemExit(
            f"Error: --replace は {table} に使えない。CloudKit 側の列 {sorted(missing)} を"
            f" ローカルが持っていないので、forceReplace すると消える。"
        )


def push_columns(conn: sqlite3.Connection, table: str) -> tuple[list[dict], str]:
    """push する列 (get_column_info の形) と、それを引く SELECT 句。

    idols.voice_actors は idol_voice_actors (期間つき履歴) へ移して列を消したが、
    CloudKit にはしばらく送り続ける。旧アプリの CKRecordMapper は voiceActors を
    読んでモデルを組み立てており、フィールドが消えると nil になって upsert のたびに
    ローカル列が NULL 上書きされる = 更新していない人の CV 表示が全部消える。
    全ユーザーが新版に移ったらこの導出ごと外す。
    """
    col_info = get_column_info(conn, table)
    select = "*"
    if table == "idols" and has_table(conn, "idol_voice_actors"):
        select = ("*, (SELECT group_concat(name, ',') FROM idol_voice_actors v"
                  " WHERE v.idol_id = idols.id AND v.valid_to IS NULL) AS voice_actors")
        # get_column_info と同じ形 ({name, type}) にすること。type が無いと
        # rows_to_operations が KeyError で落ちる。
        col_info = col_info + [{"name": "voice_actors", "type": "TEXT"}]
    return col_info, select
