#!/usr/bin/env python3
"""merge_duplicate_idols.py — 同じ人物が二重登録されているものを統合する。

Usage:
    python3 tools/merge_duplicate_idols.py             # 何が起きるか見るだけ
    python3 tools/merge_duplicate_idols.py --apply     # master.sqlite に反映

`tools/merge_duplicate_songs.py` の idols 版。対象は MERGES に手で書く。

## なぜ二重登録が起きるか

ブランドを兼任するアイドルを、ブランドごとに 1 行ずつ持ってしまう。兼任は
`idol_brands` (idol_id × brand_id) で表す仕組みが既にあり、765AS の面々は
そちらで複数ブランドに属している。行を分けるとその仕組みと二重管理になる。

## 何が壊れるか

`BulkImageImporter` が名前 → id の対応を作るので、「秋月涼」で画像を入れても
**片方の行にしか付かない**。結果、同じ人物なのに画像のある側と無い側に分かれ、
担当画像ウィジェットの候補やギャラリーで別人のように見える。

やること:
    1. 子テーブル (unit_members / idol_voice_actors / song_artists /
       setlist_performers / show_cast / idol_brands) の参照を残す側へ付け替える
    2. 付け替えで主キーが衝突する行 (両方が同じユニットに居る等) は消す側を捨てる
    3. 消す側の idols 行を削除する
    4. CloudKit から物理削除するための TSV を書き出す

⚠️ CloudKit は削除が差分同期に乗らないので、DB から消すだけでは端末に残る。
   出力した TSV を tools/seed_cloudkit.py --production --yes --delete-file に食わせること。
⚠️ 子を先に消す。idols を先に消すと FK 孤児になり、新規インストールで起動クラッシュする。
"""

import argparse
import os
import sqlite3
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DB_PATH = os.path.join(REPO, "ImasLiveDB", "Resources", "master.sqlite")
OUT_TSV = os.path.join(HERE, "pending_cloudkit_deletions_idol_merge.tsv")

# 子テーブルと、そこでの複合キー (付け替え後の衝突判定に使う)。
CHILDREN = {
    "unit_members": ("unit_id", "idol_id"),
    "idol_brands": ("idol_id", "brand_id"),
    "song_artists": ("song_id", "idol_id", "role"),
    "setlist_performers": ("setlist_item_id", "idol_id"),
    "show_cast": ("show_id", "idol_id"),
    "idol_voice_actors": None,  # 単独 PK が無い / 消す側は捨てるだけ
}

# (消す側, 残す側, 根拠)
MERGES = [
    (
        "876_秋月涼", "sidem_秋月涼",
        "ブランド兼任を 2 行で持ってしまっていた。残す側は idol_brands で "
        "876 (is_primary=0) と sidem (is_primary=1) の両方を既に持っており、"
        "曲 89 件・セトリ 259 件もそちら。消す側の参照は unit_members 3 件と "
        "idol_voice_actors 1 件だけ。色・読み・属性は両行とも同じ。",
    ),
]


def counts(db, idol_id):
    out = {}
    for t in CHILDREN:
        out[t] = db.execute(
            f"SELECT count(*) FROM {t} WHERE idol_id=?", (idol_id,)
        ).fetchone()[0]
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="master.sqlite に反映する")
    args = ap.parse_args()

    db = sqlite3.connect(DB_PATH)
    db.execute("PRAGMA foreign_keys = ON")
    deletions: list[tuple[str, str]] = []

    for dup, keep, why in MERGES:
        exists = lambda i: db.execute("SELECT 1 FROM idols WHERE id=?", (i,)).fetchone()
        # MERGES は「何を統合したか」の履歴も兼ねる。適用済みの行は飛ばす。
        if not exists(dup):
            if not exists(keep):
                raise SystemExit(f"消す側も残す側も idols に無い: {dup} / {keep}")
            print(f"済: {dup} → {keep}")
            continue
        if not exists(keep):
            raise SystemExit(f"残す側が idols に無い: {keep}")

        print(f"{dup} → {keep}\n  {why}")
        before = counts(db, dup)

        moved, dropped = {}, {}
        for table, key in CHILDREN.items():
            if before[table] == 0:
                continue
            if key is None:
                # 付け替え先が既に同じ内容を持つので、消す側は捨てる。
                dropped[table] = before[table]
                if args.apply:
                    db.execute(f"DELETE FROM {table} WHERE idol_id=?", (dup,))
                continue
            others = [c for c in key if c != "idol_id"]
            cond = " AND ".join(f"b.{c}=a.{c}" for c in others)
            clash = db.execute(
                f"SELECT count(*) FROM {table} a WHERE a.idol_id=? AND EXISTS"
                f" (SELECT 1 FROM {table} b WHERE b.idol_id=? AND {cond})",
                (dup, keep),
            ).fetchone()[0]
            if clash and args.apply:
                # 両方が同じユニット等に居る行。残す側が既に持っているので捨てる。
                db.execute(
                    f"DELETE FROM {table} WHERE idol_id=? AND EXISTS"
                    f" (SELECT 1 FROM {table} b WHERE b.idol_id=? AND {cond})",
                    (dup, keep),
                )
            if args.apply:
                db.execute(f"UPDATE {table} SET idol_id=? WHERE idol_id=?", (keep, dup))
            moved[table] = before[table] - clash
            if clash:
                dropped[table] = clash

        if moved:
            print("  付け替え: " + " / ".join(f"{t} {n} 件" for t, n in moved.items()))
        if dropped:
            print("  重複で削除: " + " / ".join(f"{t} {n} 件" for t, n in dropped.items()))

        if args.apply:
            db.execute("DELETE FROM idols WHERE id=?", (dup,))
        print("  削除: idols 1 件")
        deletions.append(("Idol", dup))

    if not args.apply:
        print("\n(--apply で master.sqlite に反映する)")
        return
    if not deletions:
        print("\n統合するものは無かった。")
        return

    db.commit()
    db.close()

    with open(OUT_TSV, "w", encoding="utf-8") as w:
        w.write("# 二重登録の統合で不要になったレコード。\n")
        for record_type, name in deletions:
            w.write(f"{record_type}\t{name}\n")
    print(f"\nCloudKit 削除リスト: {OUT_TSV} ({len(deletions)} 件)")

    dump = os.path.join(REPO, "db", "master.sql")
    with open(dump, "w", encoding="utf-8") as w:
        subprocess.run(["sqlite3", DB_PATH, ".dump"], stdout=w, check=True)
    print(f"{dump} を更新した")


if __name__ == "__main__":
    main()
