#!/usr/bin/env python3
"""collect_solo_records.py — SPECIAL SOLO RECORDS のソロ Ver. を全件集める。

Usage:
    python3 tools/collect_solo_records.py            # 提案を出すだけ
    python3 tools/collect_solo_records.py --write    # data/songs/ に書き出す

企画の実体:
    「THE IDOLM@STER MILLION LIVE! SPECIAL SOLO RECORDS <アイドル名>」が
    アイドル1人につき1枚、9曲入りで週次配信された。2025-07-23 (春日未来) 〜
    2026-07-15 (秋月律子) の 52枚 × 9曲 = 468曲で完結している。

なぜアルバム起点か:
    曲名で検索すると取りこぼす。iTunes Search は関連度順で、limit 200 でも
    全部返る保証がない (実際「Crossing!」は 52人中 50人ぶんしか返らず、
    中谷育と野々原茜が欠けた。どちらも配信は存在した)。
    アルバムを列挙して収録曲を全部取れば、件数が 9 の倍数で検算できる。

⚠️ 曲名の括弧内をアイドル名として解決する。idols に無い名前 (ユニット名等) は
   候補にせず未解決として報告する。
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
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB_PATH = os.path.join(ROOT, "ImasLiveDB", "Resources", "master.sqlite")
OUT_PATH = os.path.join(ROOT, "data", "songs", "solo_versions.json")

ALBUM_TERM = "SPECIAL SOLO RECORDS"
ALBUM_MARK = "SOLO RECORDS"
VERSION_RE = re.compile(r"^(?P<base>.+?)\s*[(（](?P<who>.+?)\s*Ver\.?[)）]\s*$", re.IGNORECASE)


def squash(text: str) -> str:
    """比較用に空白を潰す。「所 恵美」と「所恵美」を同じ人として扱うため。"""
    return re.sub(r"\s+", "", text)


def itunes(path: str, **params) -> list[dict]:
    params.setdefault("country", "jp")
    url = f"https://itunes.apple.com/{path}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": "imas-live-db/1.0"})
    with urllib.request.urlopen(req, timeout=30) as res:
        return json.load(res).get("results", [])


def artwork_url(result: dict) -> str:
    """一覧で使える大きさに差し替える (既定の 100x100 は粗い)。"""
    return (result.get("artworkUrl100") or result.get("artworkUrl60") or "") \
        .replace("100x100bb", "600x600bb")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help=f"{OUT_PATH} に書き出す")
    args = ap.parse_args()

    db = sqlite3.connect(DB_PATH)
    songs = db.execute("SELECT id, title, brand_id, apple_music_id FROM songs").fetchall()
    by_squashed_title = {(b, squash(t)): i for i, t, b, _ in songs}
    known_music_ids = {a for _, _, _, a in songs if a}
    known_titles = {(b, squash(t)) for _, t, b, _ in songs}

    idol_by_name = defaultdict(list)
    for idol_id, name in db.execute("SELECT id, name FROM idols"):
        idol_by_name[squash(name)].append(idol_id)

    albums = [a for a in itunes("search", term=ALBUM_TERM, entity="album", limit=200)
              if ALBUM_MARK in (a.get("collectionName") or "")]
    expected = sum(a.get("trackCount", 0) for a in albums)
    print(f"アルバム {len(albums)} 枚 / 収録曲 {expected} 曲", file=sys.stderr)

    proposals: list[dict] = []
    unresolved: list[str] = []
    no_parent: set[str] = set()
    seen_tracks = 0

    for album in sorted(albums, key=lambda a: a.get("releaseDate", "")):
        tracks = [t for t in itunes("lookup", id=album["collectionId"], entity="song", limit=60)
                  if t.get("wrapperType") == "track"]
        seen_tracks += len(tracks)
        time.sleep(0.4)  # iTunes に連打しない

        for track in tracks:
            name = (track.get("trackName") or "").strip()
            m = VERSION_RE.match(name)
            if not m:
                unresolved.append(f"{name} (「〜 Ver.」の形ではない)")
                continue

            base = m.group("base").strip()
            who = squash(m.group("who"))
            # 親曲は ml と 765as に散っているので、ブランドを固定せず曲名で探す。
            parent = next((by_squashed_title[(b, squash(base))]
                           for b in ("ml", "765as", "cg", "sidem", "sc", "gakuen")
                           if (b, squash(base)) in by_squashed_title), None)
            if not parent:
                no_parent.add(base)
                continue
            if str(track.get("trackId")) in known_music_ids:
                continue

            brand = next(b for i, t, b, _ in songs if i == parent)
            if (brand, squash(name)) in known_titles:
                continue
            idols = idol_by_name.get(who)
            if not idols:
                unresolved.append(f"{name} (アイドル '{m.group('who')}' が idols に無い)")
                continue

            proposals.append({
                "id": f"{parent}{who}ver",
                "title": name,
                "brand_id": brand,
                "song_type": "solo",
                "release_date": (track.get("releaseDate") or "")[:10],
                "apple_music_id": str(track.get("trackId") or ""),
                "artwork_url": artwork_url(track),
                "preview_url": track.get("previewUrl") or "",
                "parent_song_id": parent,
                "original_singers": [idols[0]],
                "source": track.get("trackViewUrl") or "https://music.apple.com/jp/",
                "note": f"「{base}」のソロ Ver.。{album['collectionName']} 収録。",
            })

    print(f"取得したトラック: {seen_tracks} / 期待 {expected}", file=sys.stderr)
    print(f"新規追加の候補: {len(proposals)} 曲", file=sys.stderr)
    if no_parent:
        print(f"親曲が songs に無くて見送り: {sorted(no_parent)}", file=sys.stderr)
    if unresolved:
        print(f"解決できず見送り: {len(unresolved)} 件", file=sys.stderr)
        for u in unresolved[:5]:
            print(f"  - {u}", file=sys.stderr)

    if not args.write:
        print("\n(--write で data/songs/ に書き出す)", file=sys.stderr)
        return

    doc = {
        "title": "SPECIAL SOLO RECORDS のソロ Ver. 追加",
        "author": "",
        "source": "https://music.apple.com/jp/",
        "_note": "週次配信のソロ Ver. 企画 (52枚 × 9曲)。親曲は parent_song_id で"
                 "紐付けてあるので一覧には出ず、曲詳細の「別バージョン」から辿れる。",
        "songs": proposals,
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"{OUT_PATH} に {len(proposals)} 件書き出した", file=sys.stderr)


if __name__ == "__main__":
    main()
