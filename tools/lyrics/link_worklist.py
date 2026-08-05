#!/usr/bin/env python3
"""link_worklist.py — 歌詞サイトへの直リンクを解決するための台帳を作る。

Usage:
    python3 tools/lyrics/link_worklist.py --apply --limit 200
    python3 tools/lyrics/link_worklist.py --unresolved-only   # 未解決だけ表示

出力: tools/lyrics/links.tsv (UTF-8 / TAB)

なぜ台帳方式か:
  歌ネットは robots.txt が 403 を返し、自動アクセスを基盤レベルで拒否している。
  そのため**歌ネットのサーバには一切アクセスしない**。URL の発見は検索エンジンの
  結果から行い、その結果をこの台帳に記録して人が確認する。

  さらに、アイマス曲は同名の版が大量にある (「お願い！シンデレラ」だけでも
  M@STER VERSION のキャスト違い複数・ソロリミックス・しんげき Remix)。
  タイトル一致だけでは正しい版に当たらないので、アーティスト名との突合と
  人の確認を前提にする。

列:
  song_id / title / artist / setlist_count  … DB 由来 (毎回作り直す)
  lyrics_url                                … 確定した URL。songs.lyrics_url に入る値
  candidate_url / candidate_title           … 検索で見つかった候補 (未確定)
  confidence                                … high / low / ambiguous / not_found
  note                                      … 判断メモ

confidence が high のものだけ lyrics_url へ昇格させる。
"""

import argparse
import os
import re
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
DEFAULT_DB = os.path.join(REPO, "ImasLiveDB", "Resources", "master.sqlite")
LINKS_TSV = os.path.join(HERE, "links.tsv")

COLUMNS = [
    "song_id", "title", "artist", "setlist_count",
    "lyrics_url", "candidate_url", "candidate_title", "confidence", "note",
]

MANUAL_COLS = ["lyrics_url", "candidate_url", "candidate_title", "confidence", "note"]

CONFIDENCES = {"", "high", "low", "cover", "ambiguous", "not_found"}


def fetch_songs(db_path):
    conn = sqlite3.connect("file:%s?mode=ro" % db_path, uri=True)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        """
        SELECT s.id, s.title, s.lyrics_url,
               -- singer_label / unit_name が空の曲 (876 の一部など) は
               -- song_artists の出演者名で補う。空のまま「曲名 + アイドルマスター」で
               -- 検索すると弱すぎて見つからない (876 は 9/9 が落ちた)。
               COALESCE(
                 NULLIF(s.singer_label,''), NULLIF(s.unit_name,''),
                 (SELECT group_concat(i.name, '、')
                    FROM song_artists sa JOIN idols i ON i.id = sa.idol_id
                   WHERE sa.song_id = s.id AND sa.role = 'original'),
                 '') AS artist,
               (SELECT COUNT(*) FROM setlist_items si WHERE si.song_id = s.id)
                   AS setlist_count
          FROM songs s
         ORDER BY setlist_count DESC, s.id
        """
    ).fetchall()
    conn.close()
    return rows


def read_links(path):
    if not os.path.exists(path):
        return {}
    kept = {}
    with open(path, encoding="utf-8") as f:
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


def build_rows(songs, existing):
    out = []
    for s in songs:
        manual = existing.get(s["id"], {})
        conf = manual.get("confidence", "")
        if conf not in CONFIDENCES:
            print("警告: %s の confidence が不正: %r" % (s["id"], conf), file=sys.stderr)
            conf = ""
        out.append({
            "song_id": s["id"],
            "title": s["title"],
            "artist": s["artist"],
            "setlist_count": str(s["setlist_count"]),
            # DB に既に URL があればそれを正とする
            "lyrics_url": (s["lyrics_url"] or "") or manual.get("lyrics_url", ""),
            "candidate_url": manual.get("candidate_url", ""),
            "candidate_title": manual.get("candidate_title", ""),
            "confidence": conf,
            "note": manual.get("note", ""),
        })
    return out


def write_tsv(path, rows):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\t".join(COLUMNS) + "\n")
        for r in rows:
            f.write("\t".join(re.sub(r"[\t\r\n]+", " ", r[c]) for c in COLUMNS) + "\n")


def write_slices(rows, size, out_dir):
    """未調査の曲を N 曲ずつのファイルに切り出す。

    WebSearch はセッション全体で 200 回が上限で、エージェント間で共有される。
    1 セッションでは全曲を引けないので、セッションを跨いで再開できるようにする。
    候補が入った曲は links.tsv 側に残るため、再実行すると自動的に対象から外れる。
    """
    # 候補が無く、かつ「検索したが見つからなかった」印も付いていない曲だけ。
    # not_found を除かないと、同じクエリを投げ直して予算を溶かす。
    todo = [r for r in rows
            if not r["candidate_url"].strip() and r["confidence"] != "not_found"]
    if not todo:
        print("未調査の曲は無い。収集は完了している。")
        return

    # 既存のスライスは消す (前回の残りが混ざると二重に引くことになる)
    if os.path.isdir(out_dir):
        for name in os.listdir(out_dir):
            if name.startswith("slice_") and name.endswith(".tsv"):
                os.remove(os.path.join(out_dir, name))
    os.makedirs(out_dir, exist_ok=True)

    cols = ["song_id", "title", "artist", "setlist_count"]
    chunks = [todo[i:i + size] for i in range(0, len(todo), size)]
    for n, chunk in enumerate(chunks, 1):
        path = os.path.join(out_dir, "slice_%02d.tsv" % n)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write("\t".join(cols) + "\n")
            for r in chunk:
                f.write("\t".join([r["song_id"], r["title"],
                                    r["artist"][:60], r["setlist_count"]]) + "\n")
    print("未調査 %d曲 → %dスライス (1件あたり最大 %d曲) を %s に書いた"
          % (len(todo), len(chunks), size, out_dir))
    print("セトリ登場回数の多い順なので、slice_01 から埋めるのが効率的。")


def promote(rows, dry_run):
    """confidence=high の candidate_url を lyrics_url に昇格させる。

    自動でやらない理由: 候補の判定は検索結果のページタイトルを読んだ判断であり、
    アイマス曲は同名でキャスト構成違いの版が大量にある (「お願い！シンデレラ」だけで
    9人版/11人版/3人版/しんげき Remix)。人数のズレは隣の版を掴む形で静かに間違う。
    昇格は人が候補を見てから明示的に実行する。
    """
    targets = [r for r in rows
               if r["confidence"] == "high" and r["candidate_url"] and not r["lyrics_url"]]
    print("昇格対象 (confidence=high かつ URL 未確定): %d件\n" % len(targets))
    for r in targets:
        print("  %-30s %s" % (r["title"][:28], r["candidate_url"]))
        print("    %s" % r["candidate_title"][:100])
    if dry_run:
        print("\n(--promote-apply を付けると lyrics_url に反映する)")
        return 0
    for r in targets:
        r["lyrics_url"] = r["candidate_url"]
    return len(targets)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=DEFAULT_DB)
    ap.add_argument("--out", default=LINKS_TSV)
    ap.add_argument("--apply", action="store_true", help="links.tsv を書き出す")
    ap.add_argument("--promote", action="store_true",
                    help="confidence=high の昇格対象を表示する")
    ap.add_argument("--promote-apply", action="store_true",
                    help="実際に lyrics_url へ昇格させる (--apply と併用)")
    ap.add_argument("--limit", type=int, help="上位 N 曲だけ")
    ap.add_argument("--unresolved-only", action="store_true",
                    help="URL 未確定のものだけ表示")
    ap.add_argument("--slices", type=int, metavar="N",
                    help="未調査の曲を N 曲ずつのスライスに切り出す (収集作業の再開用)")
    ap.add_argument("--slice-dir", default=os.path.join(HERE, "slices"),
                    help="スライスの出力先")
    args = ap.parse_args()

    if not os.path.exists(args.db):
        sys.exit("DB が見つからない: %s" % args.db)

    rows = build_rows(fetch_songs(args.db), read_links(args.out))

    if args.slices:
        write_slices(rows, args.slices, args.slice_dir)
        return

    if args.promote or args.promote_apply:
        n = promote(rows, dry_run=not args.promote_apply)
        if args.promote_apply:
            write_tsv(args.out, rows)
            print("\n%d件を lyrics_url に昇格し %s を更新した" % (n, args.out))
        return

    if args.apply:
        write_tsv(args.out, rows)
        print("wrote %s (%d曲)\n" % (args.out, len(rows)))

    shown = [r for r in rows if not r["lyrics_url"]] if args.unresolved_only else rows
    if args.limit:
        shown = shown[:args.limit]

    resolved = sum(1 for r in rows if r["lyrics_url"])
    print("総曲数      : %d" % len(rows))
    print("URL 確定済み: %d" % resolved)
    print("未確定      : %d" % (len(rows) - resolved))
    by_conf = {}
    for r in rows:
        by_conf[r["confidence"] or "(未調査)"] = by_conf.get(r["confidence"] or "(未調査)", 0) + 1
    for k, v in sorted(by_conf.items(), key=lambda kv: -kv[1]):
        print("  %-12s %d" % (k, v))


if __name__ == "__main__":
    main()
