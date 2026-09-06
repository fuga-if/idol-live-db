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
        "同じ曲の二重登録。歌詞サイトは英字表記 (song/371743) だが、Apple Music "
        "(1725264451) も CD 名もカタカナなので、メタの揃っているカタカナ側を残す。"
        "消す側は brand=other・配信日/配信ID/CD すべて無しのセトリ由来レコード。",
    ),
    (
        "cg_sun_high_gold", "cg_sunhighgold",
        "同じ曲の二重登録 (半角/全角の違い)。歌詞サイト (song/280408) が全角表記なので"
        "全角側を残す。song_artists は 5 件とも同一。",
    ),
    (
        "cg_cookie_dough", "cg_cookiedough",
        "同じ曲の二重登録。曲名・ブランド・配信日 (2026-08-13)・原唱者 (三船美優・"
        "大和亜季・高垣楓) がすべて同じで、どちらも Pop'n ToyBox!! の会場 CD。"
        "残す側はセトリ 4 件から参照されており、消す側はどこからも参照が無い。"
        "id の綴りは消す側 (cg_cookie_dough) の方が命名規則に沿っているが、"
        "**参照のある方を残す**。id を揃えるために参照を付け替えるのは、"
        "得るものが綴りだけで、セトリを壊す危険に見合わない。",
    ),
]


def counts(db, song_id):
    return {
        t: db.execute(f"SELECT count(*) FROM {t} WHERE song_id=?", (song_id,)).fetchone()[0]
        for t in ("setlist_items", "song_artists", "song_units")
    }


def normalize_master_sql(path):
    """sqlite3 CLI の .dump が吐く unistr() を素の SQL リテラルに戻す。

    3.49+ の .dump は改行入りの文字列を unistr('…\\u000a…') で書くが、この関数は
    それより古い sqlite3 に無い。db/master.sql は CI や他環境の sqlite3 も読む正本
    なので、手元の版に依存しない形にしてから置く。詳細は
    tools/normalize_master_sql.py。
    """
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from normalize_master_sql import normalize
    with open(path, encoding="utf-8") as f:
        text = f.read()
    out, n = normalize(text)
    if n:
        with open(path, "w", encoding="utf-8") as f:
            f.write(out)
        print(f"  unistr() を {n} 箇所ほどいた (古い sqlite3 でも読めるように)")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="master.sqlite に反映する")
    args = ap.parse_args()

    db = sqlite3.connect(DB_PATH)
    db.execute("PRAGMA foreign_keys = ON")
    deletions: list[tuple[str, str]] = []

    for dup, keep, why in MERGES:
        exists = lambda sid: db.execute("SELECT 1 FROM songs WHERE id=?", (sid,)).fetchone()
        # MERGES は「何を統合したか」の履歴も兼ねるので、適用済みの行はここに残り続ける。
        # 消す側がもう居ないなら統合は済んでいる。落とさずに飛ばす
        # (落とすと、新しく足した 1 件を試すたびに過去分を消して回ることになる)。
        if not exists(dup):
            if not exists(keep):
                raise SystemExit(f"消す側も残す側も songs に無い: {dup} / {keep}")
            print(f"済: {dup} → {keep}")
            continue
        if not exists(keep):
            raise SystemExit(f"残す側が songs に無い: {keep}")

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
    # ⚠️ sqlite3 3.49+ の .dump は制御文字を含む文字列を unistr('…\\u000a…') で書く。
    #    それより古い sqlite3 では読めず、CI (core-guard / Android の generateSeedDb) が
    #    「no such function: unistr」で落ちる。正本は誰でも読める形で置く。
    normalize_master_sql(DUMP_PATH)



if __name__ == "__main__":
    main()
