#!/usr/bin/env python3
"""fill_apple_music_ids.py — iTunes Search API で apple_music_id 未設定の曲を自動マッチ。

Usage:
    python3 tools/fill_apple_music_ids.py --dry-run                  # 2025+ のみ
    python3 tools/fill_apple_music_ids.py --since 2025-01-01         # 同上
    python3 tools/fill_apple_music_ids.py --apply                    # master.sqlite を実更新
    python3 tools/fill_apple_music_ids.py --apply --brand sc         # ブランド絞り

マッチ戦略:
  1. 完全一致 (trackName == title) を優先
  2. ヒット曲の artistName が ブランド関連キーワードを含むものを優先
  3. 上位 5 件から最良候補を選び、 不一致なら skip (ログだけ出して触らない)
"""

import argparse
import json
import sqlite3
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

DB = Path(__file__).parent.parent / "ImasLiveDB/Resources/master.sqlite"

# ブランド別の artistName キーワード (含まれていれば候補スコア +)
BRAND_KEYWORDS = {
    "765as":  ["アイドルマスター", "THE IDOLM@STER", "765"],
    "876":    ["アイドルマスター", "DEARLY STARS", "876", "vα-liv", "レトラ"],
    "961":    ["アイドルマスター", "961", "プロジェクトフェアリー", "PROJECT FAIRY"],
    "cg":     ["シンデレラ", "CINDERELLA", "アイドルマスター", "デレマス"],
    "ml":     ["ミリオン", "MILLION", "アイドルマスター", "ミリシタ"],
    "sidem":  ["SideM", "サイマス", "アイドルマスター", "DRAMATIC STARS", "Jupiter", "S.E.M",
              "Beit", "High×Joker", "F-LAGS", "Café Parade", "もふもふえん", "Legenders",
              "FRAME", "神速一魂", "C.FIRST", "ピアレスガーベラ"],
    "sc":     ["シャイニーカラーズ", "シャニマス", "Shiny Colors", "アイドルマスター", "283",
              "ストレイライト", "ノクチル", "アルストロメリア", "イルミネーションスターズ",
              "アンティーカ", "放課後クライマックスガールズ", "SHHis", "コメティック", "Σ Desire"],
    "gakuen": ["学園アイドルマスター", "学マス", "GAKUMAS", "アイドルマスター", "初星学園", "初星"],
}

# 全ブランド共通: アイマス曲は CV 表記でクレジットされるので artist に "(CV." 等あれば +
CV_MARKERS = ["(CV.", "(CV:", "(CV ", "CV.", "CV:"]


def itunes_search(term: str) -> list:
    url = "https://itunes.apple.com/search?" + urllib.parse.urlencode({
        "term": term,
        "entity": "song",
        "country": "jp",
        "limit": 10,
    })
    req = urllib.request.Request(url, headers={"User-Agent": "ImasLiveDB/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.load(resp)
            return data.get("results", [])
    except Exception as e:
        print(f"  ERROR: itunes lookup failed: {e}", file=sys.stderr)
        return []


def score(result: dict, title: str, brand_id: str) -> int:
    s = 0
    track = (result.get("trackName") or "").strip()
    artist = (result.get("artistName") or "").strip()
    if track == title:
        s += 100
    elif title in track or track in title:
        s += 30
    kw = BRAND_KEYWORDS.get(brand_id, [])
    for k in kw:
        if k.lower() in artist.lower():
            s += 20
            break
    # 短いタイトル (例: "Glass") は誤マッチしやすいので、 アイマス無関連の artist は減点
    if len(title) <= 5 and not any(k.lower() in artist.lower() for k in kw):
        s -= 50
    return s


def pick(title: str, brand_id: str, results: list) -> dict:
    if not results:
        return None
    scored = [(score(r, title, brand_id), r) for r in results]
    scored.sort(key=lambda x: -x[0])
    best_score, best = scored[0]
    return best if best_score >= 60 else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", default="2025-01-01")
    ap.add_argument("--brand", default=None)
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--limit", type=int, default=None)
    args = ap.parse_args()

    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row

    sql = """
        SELECT id, title, brand_id, release_date
        FROM songs
        WHERE (apple_music_id IS NULL OR apple_music_id = '')
          AND release_date >= ?
    """
    params = [args.since]
    if args.brand:
        sql += " AND brand_id = ?"
        params.append(args.brand)
    sql += " ORDER BY brand_id, release_date DESC"
    if args.limit:
        sql += f" LIMIT {args.limit}"

    rows = conn.execute(sql, params).fetchall()
    print(f"Found {len(rows)} songs without apple_music_id")

    matched = 0
    updated = 0
    cur = conn.cursor()
    for row in rows:
        title, brand, release = row["title"], row["brand_id"], row["release_date"]
        # クエリ: title + ブランドキーワード 1 個 (artist hint)
        kw = BRAND_KEYWORDS.get(brand, [""])[0]
        term = f"{title} {kw}".strip()
        results = itunes_search(term)
        chosen = pick(title, brand, results)
        if not chosen:
            # フォールバック: title 単独で再検索
            time.sleep(0.5)
            results = itunes_search(title)
            chosen = pick(title, brand, results)
        if chosen:
            track_id = chosen.get("trackId")
            artwork = (chosen.get("artworkUrl100") or "").replace("100x100bb", "600x600bb")
            album_id = chosen.get("collectionId")
            album_name = chosen.get("collectionName")
            print(f"  ✓ {brand}/{row['id']}: '{title}' -> {track_id} ({chosen.get('trackName')} / {chosen.get('artistName')})")
            matched += 1
            if args.apply and track_id:
                # apple_music_id と一緒に artwork_url / apple_music_album_id / cd_series も上書き。
                # cd_series が古いアルバム名のまま残るとUIで「別ブランドのアルバム」に見える事故が起きる。
                cur.execute(
                    """UPDATE songs SET apple_music_id=?,
                       artwork_url = ?,
                       apple_music_album_id = ?,
                       cd_series = ?
                       WHERE id=?""",
                    (str(track_id), artwork or None, str(album_id) if album_id else None, album_name, row["id"]),
                )
                updated += 1
        else:
            top = results[0] if results else None
            print(f"  ✗ {brand}/{row['id']}: '{title}' -> no good match (top: {top.get('trackName') if top else '-'} / {top.get('artistName') if top else '-'})")
        time.sleep(0.4)  # rate limit

    if args.apply:
        conn.commit()
        print(f"\nMatched: {matched}, Updated: {updated}")
    else:
        print(f"\nMatched: {matched} (DRY-RUN, no changes)")


if __name__ == "__main__":
    main()
