#!/usr/bin/env python3
"""
check_fk_integrity.py — master.sqlite の外部キー制約違反を一覧する。

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


def main() -> None:
    path = sys.argv[1] if len(sys.argv) > 1 else DB_PATH
    if not os.path.exists(path):
        print(f"ERROR: DB not found: {path}")
        sys.exit(1)
    print(f"Checking: {path}\n")
    violations = check_fk_integrity(path)
    sys.exit(0 if violations == 0 else 1)


if __name__ == "__main__":
    main()
