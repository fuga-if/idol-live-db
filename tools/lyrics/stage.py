#!/usr/bin/env python3
"""stage.py — 歌詞入力用のローカル作業場を用意する。

Usage:
    python3 tools/lyrics/stage.py                    # 作業リストを表示 (書き込まない)
    python3 tools/lyrics/stage.py --apply            # lyrics_local/ に雛形を作る
    python3 tools/lyrics/stage.py --apply --limit 50 # 上位50曲だけ
    python3 tools/lyrics/stage.py --apply --brand cg

出力先: lyrics_local/  (.gitignore 済み。歌詞は絶対に git に入れない)
    worklist.tsv       作業リスト。曲のメタ情報と進捗
    body/<song_id>.txt 歌詞本文。**中身は人が書く**

このツールは歌詞本文を一切生成しない。空欄の器と、埋めるべき順序を用意するだけ。
歌詞テキストの調達は人の担当:
  - 原盤 (CD ブックレット) からの転記
  - 歌詞配信の許諾を持つ事業者のデータ
歌詞サイトからの複製は各サイトの規約に触れるので使わないこと。
JASRAC の許諾は「掲載する権利」であって、他サイトの規約を上書きしない。

優先順位はセトリ登場回数。コールガイドが求められるのはライブ頻出曲なので、
そこから埋めるのが最も費用対効果が高い。

報告できない曲は既定で除外する。作詞者・作曲者がどちらも空の曲は
JASRAC 年次利用曲目報告の必須項目 (項目10/12 はいずれか必須) を満たせず、
掲載しても報告できない。詳細は docs/JASRAC.md。
"""

import argparse
import os
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
DEFAULT_DB = os.path.join(REPO, "ImasLiveDB", "Resources", "master.sqlite")
STAGE_DIR = os.path.join(REPO, "lyrics_local")
BODY_DIR = os.path.join(STAGE_DIR, "body")
WORKLIST = os.path.join(STAGE_DIR, "worklist.tsv")

COLUMNS = [
    "song_id",
    "title",
    "artist",
    "lyricist",
    "composer",
    "brand_id",
    "setlist_count",
    "reportable",
    "status",       # todo / drafted / reviewed / published
    "source",       # 出典。空のまま投入しないこと
    "note",
]

# 人が編集する列。--apply の再実行で保持する。
MANUAL_COLS = ["status", "source", "note"]


def ensure_gitignored():
    """lyrics_local/ が git 管理外であることを確認する。

    歌詞が公開リポジトリに入ると JASRAC 許諾の条件 (一括ダウンロードできない形での
    配信) を破る。tools/backup_d1.sh と同じガード。
    """
    import subprocess
    rc = subprocess.run(
        ["git", "-C", REPO, "check-ignore", "-q", "lyrics_local"],
        capture_output=True,
    ).returncode
    if rc != 0:
        sys.exit(
            "✗ lyrics_local/ が gitignore されていない。中断する。\n"
            "  .gitignore に /lyrics_local/ を追加してから再実行すること。"
        )


def fetch_songs(db_path, brand=None):
    conn = sqlite3.connect("file:%s?mode=ro" % db_path, uri=True)
    conn.row_factory = sqlite3.Row
    sql = """
        SELECT s.id, s.title, s.brand_id, s.lyricist, s.composer,
               COALESCE(s.singer_label, s.unit_name, '') AS artist,
               (SELECT COUNT(*) FROM setlist_items si WHERE si.song_id = s.id)
                   AS setlist_count
          FROM songs s
    """
    args = []
    if brand:
        sql += " WHERE s.brand_id = ?"
        args.append(brand)
    sql += " ORDER BY setlist_count DESC, s.id"
    rows = conn.execute(sql, args).fetchall()
    conn.close()
    return rows


def read_worklist():
    """既存 worklist.tsv の手入力列を song_id -> {col: value} で読む。"""
    if not os.path.exists(WORKLIST):
        return {}
    kept = {}
    with open(WORKLIST, encoding="utf-8") as f:
        header = f.readline().rstrip("\n").split("\t")
        idx = {c: i for i, c in enumerate(header)}
        if "song_id" not in idx:
            return {}
        for line in f:
            if not line.strip():
                continue
            v = line.rstrip("\n").split("\t")
            v += [""] * (len(header) - len(v))
            kept[v[idx["song_id"]]] = {
                c: v[idx[c]] for c in MANUAL_COLS if c in idx
            }
    return kept


def body_path(song_id):
    return os.path.join(BODY_DIR, song_id + ".txt")


def has_body(song_id):
    p = body_path(song_id)
    return os.path.exists(p) and os.path.getsize(p) > 0


def build_rows(songs, existing, include_unreportable):
    out = []
    for s in songs:
        reportable = bool((s["lyricist"] or "").strip() or (s["composer"] or "").strip())
        if not reportable and not include_unreportable:
            continue
        manual = existing.get(s["id"], {})
        status = manual.get("status") or ("drafted" if has_body(s["id"]) else "todo")
        out.append({
            "song_id": s["id"],
            "title": s["title"],
            "artist": s["artist"],
            "lyricist": s["lyricist"] or "",
            "composer": s["composer"] or "",
            "brand_id": s["brand_id"] or "",
            "setlist_count": str(s["setlist_count"]),
            "reportable": "1" if reportable else "",
            "status": status,
            "source": manual.get("source", ""),
            "note": manual.get("note", ""),
        })
    return out


def write_worklist(rows):
    import re
    with open(WORKLIST, "w", encoding="utf-8", newline="\n") as f:
        f.write("\t".join(COLUMNS) + "\n")
        for r in rows:
            f.write("\t".join(re.sub(r"[\t\r\n]+", " ", r[c]) for c in COLUMNS) + "\n")


def create_bodies(rows):
    """空の本文ファイルを作る。既存ファイルは絶対に触らない。"""
    created = 0
    for r in rows:
        p = body_path(r["song_id"])
        if os.path.exists(p):
            continue
        with open(p, "w", encoding="utf-8", newline="\n") as f:
            pass  # 空ファイル。本文は人が書く
        created += 1
    return created


def print_summary(rows, applied):
    total = len(rows)
    drafted = sum(1 for r in rows if r["status"] != "todo")
    print("対象曲          : %d" % total)
    print("本文あり        : %d" % drafted)
    print("未着手          : %d" % (total - drafted))
    if not applied:
        print("\n(--apply なしなので何も書き込んでいない)")

    print("\nセトリ登場回数の上位20曲:")
    print("  %-5s %-34s %-8s %s" % ("回数", "曲名", "状態", "出典"))
    for r in rows[:20]:
        title = r["title"]
        if len(title) > 32:
            title = title[:31] + "…"
        print("  %-5s %-34s %-8s %s"
              % (r["setlist_count"], title, r["status"], r["source"] or "-"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=DEFAULT_DB)
    ap.add_argument("--apply", action="store_true", help="lyrics_local/ に書き込む")
    ap.add_argument("--limit", type=int, help="上位 N 曲だけ対象にする")
    ap.add_argument("--brand", help="ブランドで絞る (cg / ml / 765as ...)")
    ap.add_argument("--include-unreportable", action="store_true",
                    help="作詞・作曲がどちらも空の曲も含める (報告できないので既定は除外)")
    args = ap.parse_args()

    if not os.path.exists(args.db):
        sys.exit("DB が見つからない: %s" % args.db)

    ensure_gitignored()

    songs = fetch_songs(args.db, args.brand)
    existing = read_worklist()
    rows = build_rows(songs, existing, args.include_unreportable)
    if args.limit:
        rows = rows[:args.limit]

    if args.apply:
        os.makedirs(BODY_DIR, exist_ok=True)
        created = create_bodies(rows)
        write_worklist(rows)
        print("wrote %s (%d曲)" % (WORKLIST, len(rows)))
        print("created %d 件の空ファイル in %s\n" % (created, BODY_DIR))

    print_summary(rows, args.apply)

    if args.apply:
        print("\n次にやること:")
        print("  1. lyrics_local/body/<song_id>.txt に歌詞を書く")
        print("  2. worklist.tsv の source 列に出典を書く (空のままでは投入しない)")
        print("  3. python3 tools/lyrics/verify.py で機械的な事故を洗い出す")


if __name__ == "__main__":
    main()
