#!/usr/bin/env python3
"""
check_fk_integrity.py — master.sqlite の参照の壊れを一覧する。

使い方:
    python3 tools/check_fk_integrity.py [path/to/master.sqlite]

デフォルトは ImasLiveDB/Resources/master.sqlite を参照。
"""

import sqlite3
import sys
import os

DB_PATH = os.path.join(
    os.path.dirname(__file__),
    "..", "ImasLiveDB", "Resources", "master.sqlite"
)

def check_fk_integrity(db_path: str) -> int:
    """外部キー違反行を出力し、違反数を返す。"""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    cur.execute("PRAGMA foreign_key_check")
    violations = cur.fetchall()

    if not violations:
        print("✅ 外部キー違反: 0件")
        conn.close()
        return 0

    print(f"❌ 外部キー違反: {len(violations)}件\n")
    print(f"{'table':<30} {'rowid':<10} {'parent':<30} {'fkid':<6}")
    print("-" * 80)
    for row in violations:
        print(f"{row['table']:<30} {str(row['rowid']):<10} {row['parent']:<30} {str(row['fkid']):<6}")

    conn.close()
    return len(violations)


# FK 制約が宣言されていない親子の対 (子テーブル, 子の列, 親テーブル)。
#
# `PRAGMA foreign_key_check` は **宣言された FK しか見ない**。setlist_items は
# `song_id TEXT NOT NULL` と書いてあるだけで REFERENCES が無いので、指す先の曲が
# 消えても違反として出てこない。実際にすり抜けた: 二重登録の統合で曲を消したとき、
# 子の付け替えが CloudKit に届かず 9 行が宙に浮いたまま同梱 DB に入っていた。
#
# 宙に浮いた行は**経路によって扱いが違う**のが厄介で、コアのスナップショットは
# 読み込み時に落とすが SQL 経路は残す。同じセトリの曲数が画面によって食い違う。
UNDECLARED_REFS = [
    ("setlist_items", "song_id", "songs"),
    ("setlist_items", "show_id", "shows"),
    ("setlist_performers", "setlist_item_id", "setlist_items"),
    ("song_artists", "song_id", "songs"),
    ("show_cast", "show_id", "shows"),
    ("shows", "event_id", "events"),
    ("unit_members", "unit_id", "units"),
    ("unit_members", "idol_id", "idols"),
    ("idol_brands", "idol_id", "idols"),
    ("song_units", "song_id", "songs"),
]


def check_undeclared_refs(db_path: str) -> int:
    """FK 宣言の無い参照の壊れを出力し、件数を返す。"""
    conn = sqlite3.connect(db_path)
    total = 0
    for child, col, parent in UNDECLARED_REFS:
        rows = conn.execute(
            f"SELECT c.{col}, count(*) FROM {child} c"
            f" LEFT JOIN {parent} p ON p.id = c.{col}"
            f" WHERE c.{col} IS NOT NULL AND p.id IS NULL"
            f" GROUP BY c.{col}"
        ).fetchall()
        for value, n in rows:
            total += n
            print(f"❌ {child}.{col} → {parent} に無い: {value} ({n} 行)")
    conn.close()
    if total == 0:
        print("✅ 宣言の無い参照の壊れ: 0件")
    return total


def main() -> None:
    path = sys.argv[1] if len(sys.argv) > 1 else DB_PATH
    if not os.path.exists(path):
        print(f"ERROR: DB not found: {path}")
        sys.exit(1)
    print(f"Checking: {path}\n")
    violations = check_fk_integrity(path) + check_undeclared_refs(path)
    sys.exit(0 if violations == 0 else 1)


if __name__ == "__main__":
    main()
