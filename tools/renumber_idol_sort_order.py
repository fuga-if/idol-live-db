#!/usr/bin/env python3
"""renumber_idol_sort_order.py — idols.sort_order をブランドごとの番号帯に振り直す。

Usage:
    python3 tools/renumber_idol_sort_order.py            # 何が起きるか見るだけ
    python3 tools/renumber_idol_sort_order.py --apply    # master.sqlite に反映し db/master.sql を書き直す

## なぜ要るか

「公式順」(`idols.sort_order`) がブランド順になっていなかった。ブランドごとの塊には
なっているものの、塊の順が `brands.sort_order` と食い違う:

    765as 1-999 / 961 2,15,20,9999 / ml 1000 / cg 2000 / sidem 3000 /
    sc 4001 / gakuen 5000 / 876 6000

961 の 4 人は 765AS の中に散り、876 は本来 3 番目なのに末尾に来る。このため
「ブランドで並べ替え」に公式順を流用できず、Web のアイドル一覧ではブランドの列を
押せないままにしてあった。

## どう振り直すか

**ブランドごとに自分の番号帯を持たせる。** 帯の先頭は `brands.sort_order * 1000` で、
帯の中は今の並びをそのまま保つ (ブランド内の順番はこの移行で変えない。変えるのは
「どのブランドが先か」だけ)。

    765as 1001-  / 961 2001-  / 876 3001-  / cg 4001-  /
    ml    5001-  / sidem 6001- / sc 7001-  / gakuen 8001- / other 99001-

いちばん人数の多い cg でも 193 人なので、帯の幅 1000 は当分足りる。
これで公式順 = ブランド順 + ブランド内の公式順になり、一覧のブランドの列を
押して並べ替えられるようになる。

コード側は sort_order の値そのものを見ていない (大小比較だけ) ので、
振り直しても壊れるところは無い。
"""

from __future__ import annotations

import argparse
import os
import sqlite3
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DB_PATH = os.path.join(REPO, "ImasLiveDB", "Resources", "master.sqlite")
DUMP_PATH = os.path.join(REPO, "db", "master.sql")

BLOCK = 1000


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    conn = sqlite3.connect(DB_PATH)
    brands = conn.execute("SELECT id, sort_order FROM brands ORDER BY sort_order").fetchall()

    updates: list[tuple[int, str]] = []
    for brand_id, brand_order in brands:
        base = brand_order * BLOCK
        # 帯の中は今の並びのまま (同値は id で決める = 実行のたびに同じ結果)。
        rows = conn.execute(
            "SELECT id, name, sort_order FROM idols WHERE brand_id = ? ORDER BY sort_order, id",
            (brand_id,),
        ).fetchall()
        if not rows:
            continue
        if len(rows) >= BLOCK:
            print(f"✗ {brand_id} が帯の幅 {BLOCK} を超える ({len(rows)} 人)", file=sys.stderr)
            sys.exit(1)
        print(f"{brand_id:<7} {base + 1:>6} - {base + len(rows):<6} ({len(rows)} 人) "
              f"先頭 {rows[0][1]} / 末尾 {rows[-1][1]}")
        for n, (idol_id, _, _) in enumerate(rows, start=1):
            updates.append((base + n, idol_id))

    total = conn.execute("SELECT COUNT(*) FROM idols").fetchone()[0]
    if len(updates) != total:
        print(f"✗ 付番したのは {len(updates)} 人だが idols は {total} 行 "
              f"(ブランドの無いアイドルが居る)", file=sys.stderr)
        sys.exit(1)

    conn.executemany("UPDATE idols SET sort_order = ? WHERE id = ?", updates)

    # 振り直しの後にブランド順が崩れていないことを、実際に並べて確かめる。
    ordered = conn.execute(
        """SELECT b.sort_order FROM idols i JOIN brands b ON b.id = i.brand_id
           ORDER BY i.sort_order"""
    ).fetchall()
    flat = [r[0] for r in ordered]
    if flat != sorted(flat):
        print("✗ 振り直してもブランド順になっていない", file=sys.stderr)
        sys.exit(1)
    print(f"\n✅ 公式順で並べるとブランド順になる ({len(flat)} 人)")

    if not args.apply:
        conn.rollback()
        print("\n(反映するには --apply)")
        return

    version = int(conn.execute("SELECT value FROM meta WHERE key = 'data_version'").fetchone()[0])
    conn.execute("UPDATE meta SET value = ? WHERE key = 'data_version'", (str(version + 1),))
    print(f"data_version {version} → {version + 1}")

    conn.commit()
    conn.close()
    with open(DUMP_PATH, "w", encoding="utf-8") as f:
        subprocess.run(["sqlite3", DB_PATH, ".dump"], stdout=f, check=True)
    sys.path.insert(0, HERE)
    import normalize_master_sql  # noqa: E402

    text = open(DUMP_PATH, encoding="utf-8").read()
    fixed, n = normalize_master_sql.normalize(text)
    if n:
        open(DUMP_PATH, "w", encoding="utf-8").write(fixed)
        print(f"  unistr() を {n} 箇所ほどいた")
    print(f"\n{DUMP_PATH} を更新した")


if __name__ == "__main__":
    main()
