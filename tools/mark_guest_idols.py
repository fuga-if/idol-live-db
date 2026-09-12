#!/usr/bin/env python3
"""mark_guest_idols.py — ブランド `other` のアイドルを正しく分類し直す。

Usage:
    python3 tools/mark_guest_idols.py            # 何が起きるか見るだけ
    python3 tools/mark_guest_idols.py --apply    # master.sqlite に反映し db/master.sql を書き直す

## なぜ要るか

アイドル一覧 (/idols/ とアプリの一覧) に、ラブライブのキャラクターが「Other」として
並んでいた。合同ライブにゲストで出ただけの人で、持ち曲は 1 曲も無い。

`idols.is_external` が**まさにこのための札**で、「外部ゲスト演者。一覧・検索・統計から
除く」と定義してある。にもかかわらず 1 人も立っておらず、規則があるのに使われていなかった。
出面側で `brand_id = 'other'` を弾く手もあるが、それだと同じ判断が
Web・アプリ・クイズ・検索に散る。**札を正しく立てるのが根っこの修正。**

## 2 種類が混ざっている

`other` の 51 人は中身が違うので、同じ扱いにはできない:

- **ラブライブの 48 人** … 出演記録だけ (公演 1〜3 件)、持ち曲 0。外部ゲスト → `is_external = 1`。
  個別ページと公演の出演者一覧には残る (出たのは事実なので消さない)。
- **シンデレラガールズ韓国版の 3 人** (ジュニー / リュ・ヘナ / イム・ユジン) …
  アイマスのアイドルなので外部ゲストではない。id も `cg_` で始まる。
  ブランドが未分類だっただけなので `cg` に移す。

結果として `other` に属するアイドルは 0 人になる。
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

# シンデレラガールズ韓国版限定アイドル。外部ゲストではないのでブランドを直す。
KR_IDOL_IDS = ["cg_ジュニー", "cg_リュ_ヘナ", "cg_イム_ユジン"]
KR_BRAND_ID = "cg"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    conn = sqlite3.connect(DB_PATH)

    missing = [
        i for i in KR_IDOL_IDS
        if not conn.execute("SELECT 1 FROM idols WHERE id = ?", (i,)).fetchone()
    ]
    if missing:
        print("✗ 存在しない idol id:", ", ".join(missing), file=sys.stderr)
        sys.exit(1)

    guests = conn.execute(
        """SELECT id, name FROM idols
           WHERE brand_id = 'other' AND id NOT IN (?, ?, ?)
           ORDER BY id""",
        KR_IDOL_IDS,
    ).fetchall()

    # 持ち曲があるなら外部ゲストではない。取りこぼしを黙って通さない。
    with_songs = [
        (i, n) for i, n in guests
        if conn.execute(
            "SELECT 1 FROM song_artists WHERE idol_id = ? AND role = 'original'", (i,)
        ).fetchone()
    ]
    if with_songs:
        print("✗ 持ち曲があるので外部ゲストにできない:", with_songs, file=sys.stderr)
        sys.exit(1)

    print(f"外部ゲストにする ({len(guests)} 人):")
    for _, name in guests[:5]:
        print(f"  {name}")
    print(f"  … 他 {max(0, len(guests) - 5)} 人")
    print(f"\n{KR_BRAND_ID} に移す ({len(KR_IDOL_IDS)} 人):")
    for i in KR_IDOL_IDS:
        print(f"  {conn.execute('SELECT name FROM idols WHERE id = ?', (i,)).fetchone()[0]}")

    conn.executemany("UPDATE idols SET is_external = 1 WHERE id = ?", [(i,) for i, _ in guests])
    for table, column in (("idols", "brand_id"), ("idol_brands", "brand_id")):
        conn.executemany(
            f"UPDATE {table} SET {column} = ? WHERE idol_id = ?" if table == "idol_brands"
            else f"UPDATE {table} SET {column} = ? WHERE id = ?",
            [(KR_BRAND_ID, i) for i in KR_IDOL_IDS],
        )

    left = conn.execute("SELECT COUNT(*) FROM idols WHERE brand_id = 'other'").fetchone()[0]
    print(f"\nブランド other のアイドル: {left} 人")

    if not args.apply:
        conn.rollback()
        print("\n(反映するには --apply)")
        return

    # 既存ユーザの端末に配るため data_version を上げる (tools/build_db.sh の検査も見る)。
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
