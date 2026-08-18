#!/usr/bin/env python3
"""merge_duplicate_songs.py — 同じ曲が二重登録されているものを統合する。

Usage:
    python3 tools/merge_duplicate_songs.py             # 何が起きるか見るだけ
    python3 tools/merge_duplicate_songs.py --apply     # master.sqlite に反映

対象は MERGES に手で書く。機械判定で拾える話ではないため:
    歌詞が同じ = 別バージョンのことが多く、二重登録かどうかは曲名・配信ID・CD情報を
    突き合わせて 1 件ずつ判断するしかない。tools/link_song_variants.py が
    「歌詞は同じだが曲名が別系統」として報告したものから、人が選り分けてここに書く。

やること:
    1. 子テーブル (setlist_items / song_units) の参照を残す側へ付け替える
    2. 消す側の song_artists / song_units を削除する
    3. 消す側の songs 行を削除する
    4. CloudKit から物理削除するための TSV を書き出す

⚠️ CloudKit は削除が差分同期に乗らないので、DB から消すだけでは端末に残る。
   出力した TSV を tools/seed_cloudkit.py --delete-file に食わせること。
⚠️ 子 (SongArtist) を先に消す。Song を先に消すと FK 孤児になり、新規インストールで
   起動クラッシュする。
"""

import argparse
import os
import sqlite3
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DB_PATH = os.path.join(REPO, "ImasLiveDB", "Resources", "master.sqlite")
DUMP_PATH = os.path.join(REPO, "db", "master.sql")
OUT_TSV = os.path.join(HERE, "pending_cloudkit_deletions_song_merge.tsv")

# (消す側, 残す側, 根拠)
MERGES = [
    (
        "876_reloading", "876_リローディング",
        "同じ曲の二重登録。歌ネットは英字表記 (song/371743) だが、Apple Music "
        "(1725264451) も CD 名もカタカナなので、メタの揃っているカタカナ側を残す。"
        "消す側は brand=other・配信日/配信ID/CD すべて無しのセトリ由来レコード。",
    ),
    (
        "cg_sun_high_gold", "cg_sunhighgold",
        "同じ曲の二重登録 (半角/全角の違い)。歌ネット (song/280408) が全角表記なので"
        "全角側を残す。song_artists は 5 件とも同一。",
    ),
]


def counts(db, song_id):
    return {
        t: db.execute(f"SELECT count(*) FROM {t} WHERE song_id=?", (song_id,)).fetchone()[0]
        for t in ("setlist_items", "song_artists", "song_units")
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="master.sqlite に反映する")
    args = ap.parse_args()

    db = sqlite3.connect(DB_PATH)
    db.execute("PRAGMA foreign_keys = ON")
    deletions: list[tuple[str, str]] = []

    for dup, keep, why in MERGES:
        for song_id in (dup, keep):
            if not db.execute("SELECT 1 FROM songs WHERE id=?", (song_id,)).fetchone():
                raise SystemExit(f"songs に無い: {song_id}")

        # 同じ公演に両方載っていると付け替えで主キーが衝突する。事前に弾く。
        clash = db.execute(
            "SELECT a.show_id FROM setlist_items a JOIN setlist_items b"
            " ON a.show_id=b.show_id WHERE a.song_id=? AND b.song_id=?",
            (dup, keep),
        ).fetchall()
        if clash:
            raise SystemExit(f"{dup} と {keep} が同じ公演に併載: {clash}。手で解消すること")

        before = counts(db, dup)
        print(f"{dup} → {keep}")
        print(f"  {why}")
        print(f"  付け替え: setlist_items {before['setlist_items']} 件 /"
              f" song_units {before['song_units']} 件")
        print(f"  削除: song_artists {before['song_artists']} 件 + songs 1 件")

        # ⚠️ CloudKit 側の一覧は**削除する前に**作ること。DELETE 後に SELECT すると
        #    0 件になり、SongArtist が CloudKit に孤児として残る (端末で起動クラッシュ)。
        for idol_id, role in db.execute(
            "SELECT idol_id, role FROM song_artists WHERE song_id=?", (dup,)
        ).fetchall():
            deletions.append(("SongArtist", f"song_artists-{dup}-{idol_id}-{role}"))
        deletions.append(("Song", dup))

        if args.apply:
            db.execute("UPDATE setlist_items SET song_id=? WHERE song_id=?", (keep, dup))
            db.execute("UPDATE song_units SET song_id=? WHERE song_id=?", (keep, dup))
            # 残す側に既に同じ紐付けがあるので、消す側の song_artists は移さず消す。
            db.execute("DELETE FROM song_artists WHERE song_id=?", (dup,))
            # 派生曲がこの曲を親にしていたら、残す側へ付け替える。
            db.execute("UPDATE songs SET parent_song_id=? WHERE parent_song_id=?", (keep, dup))
            db.execute("DELETE FROM songs WHERE id=?", (dup,))

    if not args.apply:
        print("\n(--apply で master.sqlite に反映する)")
        return

    db.commit()

    with open(OUT_TSV, "w", encoding="utf-8") as f:
        f.write("# 二重登録の統合で不要になったレコード。子 (SongArtist) を先に消す。\n")
        for rtype, rname in deletions:
            f.write(f"{rtype}\t{rname}\n")
    print(f"\nCloudKit 削除リスト: {OUT_TSV} ({len(deletions)} 件)")

    # db/master.sql を吐き直す (このリポジトリではこちらが正)。
    with open(DUMP_PATH, "w", encoding="utf-8") as f:
        subprocess.run(["sqlite3", DB_PATH, ".dump"], stdout=f, check=True)
    print(f"{DUMP_PATH} を更新した")


if __name__ == "__main__":
    main()
