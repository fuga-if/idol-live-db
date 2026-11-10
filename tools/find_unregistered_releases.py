#!/usr/bin/env python3
"""find_unregistered_releases.py — 登録済みの曲の歌い手 (Apple Music のアーティスト) の
新しい配信から、まだ songs に無い曲を探す。

ミリシタのイベント曲の配信シングル (例: 「ハピピス♡」「BLACK LIPS」) は、公式ニュースに
記事が出ず、Apple Music の名義もアイドル名 (CV) だけで「ミリオン」などの語を含まない。
そのため公式ニュースを読む日次収集にも、ブランド名で検索する discover_new_songs.py にも
かからなかった。ここではブランド名ではなく「アーティスト」から引く:

  1. songs.apple_music_id (since 以降の曲) を lookup して、歌い手の artistId を集める
     (複数名義の曲は先頭のアイドルの artistId が付く)
  2. その artistId ごとに最近の曲 (sort=recent) を lookup
  3. 配信日が --days 以内で、trackId も曲名も songs に無いものを出す

Off Vocal・Instrumental・GAME VERSION・ソロ Ver.・リミックス・Live 版は除く。
書き込みはしない (見つけた曲は data/songs/ に JSON を書いて足す)。

Usage:
    python3 tools/find_unregistered_releases.py            # 直近 30 日
    python3 tools/find_unregistered_releases.py --days 120
    python3 tools/find_unregistered_releases.py --json     # 機械向け
"""

import argparse
import datetime as dt
import json
import re
import sqlite3
import sys
import time
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from lib import itunes  # noqa: E402

ROOT = Path(__file__).parent.parent
MASTER_SQL = ROOT / "db/master.sql"
UA = "ImasLiveDB-unregistered/1.0"

EXCLUDE = re.compile(
    r"(off vocal|instrumental|inst\.|game version|game ver\.|カラオケ|karaoke|"
    r"ソロ\s*ver|ソロ・リミックス|remix|リミックス|-live|\(live|ver\.\)\s*\[|tv\s*size|tvサイズ)",
    re.I,
)


def norm(s: str) -> str:
    s = unicodedata.normalize("NFKC", s or "").lower()
    return re.sub(r"[\s・!！?？♡☆★〜～~\-‐]", "", s)


def lookup(ids: list, **extra) -> list:
    params = {"id": ",".join(map(str, ids)), "country": "jp", **extra}
    for i in range(3):
        try:
            return itunes.results("lookup", params, user_agent=UA, timeout=30)
        except Exception as e:  # noqa: BLE001
            print(f"  retry lookup ({e})", file=sys.stderr)
            time.sleep(2 * (i + 1))
    return []


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=30, help="配信日がこの日数以内の曲だけ")
    ap.add_argument("--since", default="2022-01-01", help="歌い手を集める曲の release_date 下限")
    ap.add_argument("--master-sql", default=str(MASTER_SQL))
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    conn = sqlite3.connect(":memory:")
    conn.executescript(Path(args.master_sql).read_text())
    known_ids = {r[0] for r in conn.execute(
        "SELECT apple_music_id FROM songs WHERE apple_music_id IS NOT NULL AND apple_music_id != ''")}
    known_titles = {norm(r[0]) for r in conn.execute("SELECT title FROM songs")}
    unit_names = {norm(r[0]) for r in conn.execute("SELECT name FROM units")}
    unit_names |= {"シャイニーカラーズ", "765millionallstars", "765proallstars"}
    seed = [r[0] for r in conn.execute(
        "SELECT apple_music_id FROM songs WHERE apple_music_id IS NOT NULL AND apple_music_id != '' "
        "AND release_date >= ?", (args.since,))]

    artists = set()
    for i in range(0, len(seed), 150):
        for r in lookup(seed[i:i + 150]):
            if r.get("artistId"):
                artists.add(r["artistId"])
        time.sleep(0.5)

    cutoff = (dt.date.today() - dt.timedelta(days=args.days)).isoformat()
    found = {}
    al = sorted(artists)
    for i in range(0, len(al), 50):
        for r in lookup(al[i:i + 50], entity="song", sort="recent", limit=10):
            if r.get("wrapperType") != "track":
                continue
            rel = (r.get("releaseDate") or "")[:10]
            name = r.get("trackName") or ""
            if rel < cutoff or EXCLUDE.search(name):
                continue
            # アイマス名義 (CV 表記・既知のユニット名義・アイマスのアルバム) 以外のコラボ等は除く
            artist = r.get("artistName") or ""
            album = r.get("collectionName") or ""
            if not ("CV" in artist or norm(artist) in unit_names or "IDOLM@STER" in album.upper()
                    or "アイドルマスター" in album or "初星学園" in artist):
                continue
            if str(r.get("trackId")) in known_ids or norm(name) in known_titles:
                continue
            found[r["trackId"]] = {
                "track_id": str(r["trackId"]),
                "album_id": str(r.get("collectionId") or ""),
                "release": rel,
                "title": name,
                "artist": artist,
                "album": r.get("collectionName") or "",
            }
        time.sleep(0.5)

    rows = sorted(found.values(), key=lambda x: (x["release"], x["title"]))
    if args.json:
        print(json.dumps(rows, ensure_ascii=False, indent=1))
    else:
        print(f"歌い手 {len(artists)} 組 / 配信日 {cutoff} 以降で未登録: {len(rows)} 曲")
        for x in rows:
            print(f"  {x['release']}  {x['title']}  — {x['artist'][:60]}  (id={x['track_id']})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
