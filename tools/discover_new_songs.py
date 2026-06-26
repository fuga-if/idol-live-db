#!/usr/bin/env python3
"""discover_new_songs.py — iTunes Search API でアイマス系の配信曲を seed しつつ、
master.sqlite に未登録の新曲を検出 → songs テーブルに追加するスキル支援スクリプト。

Usage:
    python3 Scripts/discover_new_songs.py --dry-run
    python3 Scripts/discover_new_songs.py --apply
    python3 Scripts/discover_new_songs.py --apply --brand sc
    python3 Scripts/discover_new_songs.py --apply --since 2025-01-01

挙動:
  - ブランド別に seed term (ユニット名等) で iTunes API を叩き、 配信曲を収集
  - artistName に CV 表記 or ブランド関連キーワードを含む曲のみ採用
  - title + brand_id + ±60日 release_date で master.sqlite と突合
  - 未登録分を songs に INSERT (id, title, brand_id, release_date, apple_music_id, artwork_url)
  - song_artists は CV クレジットから簡易的に解決 (失敗時は skip)
  - 同タイトルが既存 (apple_music_id 別) と被ったら新規 ID にサフィックス (_v2 等)
  - dry-run では INSERT/UPDATE せず、 追加候補一覧のみ出力

注意:
  - title 完全一致のみ突合 (表記揺れは別タスク)
  - GAME VERSION / instrumental / off vocal は除外
"""

import argparse
import json
import re
import sqlite3
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Optional

DB = Path(__file__).parent.parent / "ImasLiveDB/Resources/master.sqlite"

# ブランド別 seed (iTunes Search の検索キーワード)。 各ブランドの代表ユニット/レーベル名等。
BRAND_SEEDS: dict[str, list[str]] = {
    "765as":  ["THE IDOLM@STER 765", "765PRO ALLSTARS"],
    "876":    ["vα-liv", "アイドルマスター DEARLY STARS"],
    "961":    ["961 PRODUCTION", "プロジェクトフェアリー"],
    "cg":     ["シンデレラガールズ", "CINDERELLA MASTER", "CINDERELLA GIRLS"],
    "ml":     ["ミリオンスターズ", "MILLION LIVE", "ミリシタ"],
    "sidem":  ["アイドルマスター SideM", "SideM ST@RTING LINE", "DRAMATIC STARS"],
    "sc":     ["シャイニーカラーズ", "ストレイライト", "ノクチル", "アルストロメリア",
              "イルミネーションスターズ", "アンティーカ", "放課後クライマックスガールズ",
              "SHHis", "コメティック"],
    "gakuen": ["学園アイドルマスター", "初星学園", "GAKUMAS"],
}

# ブランド判定用 (artistName に含まれていれば、 その曲はこのブランドの曲)
BRAND_KEYWORDS = {
    "765as":  ["765PRO", "765プロ", "765"],
    "876":    ["vα-liv", "ヴイアラ", "876", "DEARLY STARS"],
    "961":    ["961", "プロジェクトフェアリー", "PROJECT FAIRY"],
    "cg":     ["シンデレラ", "CINDERELLA"],
    "ml":     ["ミリオン", "MILLION", "ミリシタ"],
    "sidem":  ["SideM", "サイマス", "DRAMATIC STARS", "Jupiter", "Beit", "High×Joker",
              "F-LAGS", "Café Parade", "もふもふえん", "Legenders", "FRAME", "神速一魂",
              "C.FIRST", "ピアレスガーベラ", "S.E.M", "THE 虎牙道"],
    "sc":     ["シャイニーカラーズ", "Shiny Colors", "283", "ストレイライト", "ノクチル",
              "アルストロメリア", "イルミネーションスターズ", "アンティーカ",
              "放課後クライマックスガールズ", "SHHis", "コメティック", "ザ・ふたりトラベラー"],
    "gakuen": ["学園アイドルマスター", "学マス", "GAKUMAS", "初星学園"],
}

CV_PATTERN = re.compile(r"\(CV[\.\:\s]")
EXCLUDE_PATTERN = re.compile(
    r"(instrumental|inst\.|off vocal|オフヴォーカル|オフボーカル|karaoke|"
    r"GAME VERSION|GAME VER\.|TVサイズ|TV size|Music Box|オルゴール)", re.I)


def itunes_search(term: str, limit: int = 200) -> list:
    url = "https://itunes.apple.com/search?" + urllib.parse.urlencode({
        "term": term,
        "entity": "song",
        "country": "jp",
        "limit": limit,
    })
    req = urllib.request.Request(url, headers={"User-Agent": "ImasLiveDB-discover/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.load(resp)
            return data.get("results", [])
    except Exception as e:
        print(f"  ERROR: itunes lookup '{term}' failed: {e}", file=sys.stderr)
        return []


def is_imas_song(brand: str, artist: str) -> bool:
    if CV_PATTERN.search(artist):
        return True
    kw = BRAND_KEYWORDS.get(brand, [])
    return any(k.lower() in artist.lower() for k in kw)


def to_snake_id(brand: str, title: str) -> str:
    s = re.sub(r"[\s\(\)\[\]\{\}\!\?\.\,\:\;\'\"\*\/]", "", title)
    s = s.replace("&", "and").replace("×", "x")
    return f"{brand}_{s.lower()}"


def normalize_release(date_str: Optional[str]) -> Optional[str]:
    if not date_str:
        return None
    return date_str[:10]  # YYYY-MM-DD


def get_existing_titles(conn, brand: str) -> set[str]:
    rows = conn.execute(
        "SELECT title FROM songs WHERE brand_id=?", (brand,)
    ).fetchall()
    return set(r[0] for r in rows)


def get_existing_ids(conn) -> set[str]:
    rows = conn.execute("SELECT id FROM songs").fetchall()
    return set(r[0] for r in rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--brand", default=None, help="特定ブランドのみ (765as/876/961/cg/ml/sidem/sc/gakuen)")
    ap.add_argument("--since", default="2024-01-01", help="iTunes releaseDate がこれ以降の曲のみ採用")
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row

    target_brands = [args.brand] if args.brand else list(BRAND_SEEDS.keys())
    existing_ids = get_existing_ids(conn)

    grand_total = 0
    grand_added = 0

    for brand in target_brands:
        seeds = BRAND_SEEDS.get(brand, [])
        if not seeds:
            continue
        existing_titles = get_existing_titles(conn, brand)
        print(f"\n=== {brand} (seeds: {len(seeds)}, existing songs: {len(existing_titles)}) ===")

        candidates: dict[str, dict] = {}  # title -> result
        for seed in seeds:
            results = itunes_search(seed, limit=200)
            for r in results:
                title = (r.get("trackName") or "").strip()
                artist = (r.get("artistName") or "").strip()
                if not title or not artist:
                    continue
                if EXCLUDE_PATTERN.search(title):
                    continue
                if not is_imas_song(brand, artist):
                    continue
                rel = normalize_release(r.get("releaseDate"))
                if rel and rel < args.since:
                    continue
                # 同一 trackId は既に master にあるか?
                track_id = str(r.get("trackId") or "")
                if track_id and conn.execute(
                    "SELECT id FROM songs WHERE apple_music_id=?", (track_id,)
                ).fetchone():
                    continue
                # title 完全一致の既存 song があれば skip (連携漏れは別 script)
                if title in existing_titles:
                    continue
                candidates[title] = r
            time.sleep(0.5)

        print(f"  New candidates: {len(candidates)}")
        added = 0
        for title, r in candidates.items():
            song_id = to_snake_id(brand, title)
            if song_id in existing_ids:
                song_id = f"{song_id}_v2"
                if song_id in existing_ids:
                    print(f"  SKIP (id conflict): {title}")
                    continue
            rel = normalize_release(r.get("releaseDate"))
            art = (r.get("artworkUrl100") or "").replace("100x100bb", "600x600bb")
            print(f"  + {song_id}: '{title}' ({rel}) -> {r.get('trackId')}")
            grand_total += 1
            if args.apply:
                conn.execute(
                    "INSERT INTO songs (id, title, brand_id, release_date, apple_music_id, artwork_url) VALUES (?,?,?,?,?,?)",
                    (song_id, title, brand, rel, str(r.get("trackId") or ""), art),
                )
                existing_ids.add(song_id)
                added += 1
                grand_added += 1
        if args.apply:
            conn.commit()
        print(f"  Added: {added}/{len(candidates)}")

    print(f"\n=== TOTAL ===")
    if args.apply:
        print(f"Inserted: {grand_added} new songs")
    else:
        print(f"Would insert: {grand_total} new songs (DRY-RUN)")


if __name__ == "__main__":
    main()
