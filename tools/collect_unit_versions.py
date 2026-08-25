#!/usr/bin/env python3
"""collect_unit_versions.py — ソロでない「〜 Ver.」(ユニット版・別アレンジ) を集める。

Usage:
    python3 tools/collect_unit_versions.py            # 提案を出すだけ
    python3 tools/collect_unit_versions.py --write    # data/songs/ に書き出す

collect_solo_records.py がソロ版を扱うのに対し、こちらは括弧内がアイドル名では
ないもの。中身は2種類あって、扱いが違う:

  (a) ユニット版   … 括弧内が units に居る (エンジェルスターズ 等)
        song_type=unit / unit_name=<ユニット名> / 原唱者はそのユニットの全メンバー
  (b) アレンジ版   … 括弧内がバージョン名 (Brand New Year, Brand New)
        歌唱者は親と同じなので、親の song_type / unit_name / 原唱者を引き継ぐ

⚠️ unit_id は張らない。既存のユニット版 (Migratory Echoes 系) が unit_name だけを
   持つ流儀で、そちらに合わせる。ユニット名の表記が Apple Music と units で
   ずれている場合に誤った紐付けを作らないためでもある。
"""

import argparse
import json
import os
import re
import sqlite3
import sys
import time
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB_PATH = os.path.join(ROOT, "ImasLiveDB", "Resources", "master.sqlite")
OUT_PATH = os.path.join(ROOT, "data", "songs", "unit_versions.json")

VERSION_RE = re.compile(r"^(?P<base>.+?)\s*[(（](?P<who>.+?)\s*Ver\.?[)）]\s*$", re.IGNORECASE)
# 歌唱者ではなくバージョン名であるもの。括弧内がこれに当たれば (b) 扱い。
ARRANGE_LABELS = {"brandnew", "brandnewyear"}


def squash(text: str) -> str:
    """比較用。空白を潰し、大小文字も畳む。

    畳まないと `765PRO ALLSTARS` (Apple Music) と `765ProAllstars` (units) が
    別物になる。日本語名には影響しない。
    """
    return re.sub(r"\s+", "", text).lower()


def itunes(term: str) -> list[dict]:
    url = "https://itunes.apple.com/search?" + urllib.parse.urlencode(
        {"term": term, "entity": "song", "country": "jp", "limit": 200})
    req = urllib.request.Request(url, headers={"User-Agent": "imas-live-db/1.0"})
    with urllib.request.urlopen(req, timeout=30) as res:
        return json.load(res).get("results", [])


def artwork_url(result: dict) -> str:
    return (result.get("artworkUrl100") or "").replace("100x100bb", "600x600bb")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    db = sqlite3.connect(DB_PATH)
    songs = db.execute("SELECT id, title, brand_id, song_type, unit_name, apple_music_id"
                       " FROM songs").fetchall()
    by_title = {(b, squash(t)): (i, st, un) for i, t, b, st, un, _ in songs}
    known_titles = {(b, squash(t)) for _, t, b, _, _, _ in songs}
    known_am = {a for *_, a in songs if a}
    idol_names = {squash(n) for (n,) in db.execute("SELECT name FROM idols")}
    units = {squash(n): i for i, n in db.execute("SELECT id, name FROM units")}

    # ソロ版を持つ親曲 = 企画対象。その曲名でユニット版も探す。
    parents = {}
    for song_id, title, brand, *_ in songs:
        m = VERSION_RE.match(title)
        if not m:
            continue
        hit = by_title.get((brand, squash(m.group("base"))))
        if hit:
            parents[hit[0]] = (m.group("base").strip(), brand)

    proposals, skipped = [], []
    seen_am = set()
    for parent_id, (base, brand) in sorted(parents.items()):
        try:
            results = itunes(base)
        except Exception as err:
            print(f"  [skip] {base}: {err}", file=sys.stderr)
            continue
        time.sleep(0.5)

        for r in results:
            track = (r.get("trackName") or "").strip()
            m = VERSION_RE.match(track)
            if not m or squash(m.group("base")) != squash(base):
                continue
            who = squash(m.group("who"))
            if who in idol_names:
                continue  # ソロ版は collect_solo_records.py の担当
            am = str(r.get("trackId") or "")
            if am in known_am or (brand, squash(track)) in known_titles:
                continue
            # 同じ音源がシングルとベスト盤の両方で返ることがある。先勝ちで1つに絞る。
            if squash(track) in seen_am:
                continue
            seen_am.add(squash(track))

            _, parent_type, parent_unit = by_title[(brand, squash(base))]
            # 括弧内がそのままユニット名のこともあれば (エンジェルスターズ)、
            # アーティスト名の方が一致することもある
            # (括弧内「フィジカル」/ アーティスト「315 STARS (フィジカル Ver.)」)。
            artist = (r.get("artistName") or "").strip()
            unit_key = who if who in units else (
                squash(artist) if squash(artist) in units else None)
            if unit_key:
                song_type = "unit"
                unit_name = m.group("who").strip() if unit_key == who else artist
                members = [i for (i,) in db.execute(
                    "SELECT idol_id FROM unit_members WHERE unit_id=?", (units[unit_key],))]
                kind = "ユニット版"
            elif who in ARRANGE_LABELS:
                # 歌唱者は親と同じ。原唱者も親から引き継ぐ。
                song_type, unit_name = parent_type, parent_unit
                members = [i for (i,) in db.execute(
                    "SELECT idol_id FROM song_artists WHERE song_id=? AND role='original'",
                    (parent_id,))]
                kind = "アレンジ版"
            else:
                # units にも居ないしバージョン名でもない。勝手に決めない。
                skipped.append(f"{track} (括弧内 '{m.group('who')}' を解決できない)")
                continue

            proposals.append({
                "id": f"{parent_id}_{who}ver",
                "title": track,
                "brand_id": brand,
                "song_type": song_type,
                "unit_name": unit_name or "",
                "release_date": (r.get("releaseDate") or "")[:10],
                "apple_music_id": am,
                "artwork_url": artwork_url(r),
                "preview_url": r.get("previewUrl") or "",
                "parent_song_id": parent_id,
                "original_singers": members,
                "source": r.get("trackViewUrl") or "https://music.apple.com/jp/",
                "note": f"「{base}」の{kind}。{r.get('collectionName')} 収録。",
            })

    print(f"追加候補: {len(proposals)} 曲", file=sys.stderr)
    for p in proposals:
        print(f"  {p['title']}  [{p['song_type']}/{p['unit_name'] or '-'}]"
              f" 原唱者{len(p['original_singers'])}人", file=sys.stderr)
    if skipped:
        print(f"見送り: {len(skipped)} 件", file=sys.stderr)
        for s in skipped:
            print(f"  - {s}", file=sys.stderr)

    if not args.write:
        print("\n(--write で data/songs/ に書き出す)", file=sys.stderr)
        return

    json.dump({
        "title": "ユニット版・アレンジ版の追加",
        "author": "",
        "source": "https://music.apple.com/jp/",
        "_note": "ソロ版と同じく parent_song_id で親に紐付けるので、一覧には出ず"
                 "曲詳細の「別バージョン」から辿れる。",
        "songs": proposals,
    }, open(OUT_PATH, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print(f"{OUT_PATH} に {len(proposals)} 件書き出した", file=sys.stderr)


if __name__ == "__main__":
    main()
