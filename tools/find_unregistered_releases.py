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

配信されていない曲 (シャニソンの実装曲・CM 曲・特装版 CD のみの曲など) は Apple Music に
無いので、もう 1 つの目として、ファンが保守している曲一覧 (アイドルマスター楽曲メモの
「アイドルマスター オリジナル曲一覧」) の曲名とも突き合わせる (--no-list で切る)。
一覧は候補を見つけるためだけに使い、登録する値は公式・Apple Music で確かめる。
ゼノグラシア・ラジオ曲・ドラマ・BGM (歌唱者なし)・〈… Ver.〉は対象外として除く。

書き込みはしない (見つけた曲は data/songs/ に JSON を書いて足す)。

Usage:
    python3 tools/find_unregistered_releases.py            # 直近 30 日
    python3 tools/find_unregistered_releases.py --days 120
    python3 tools/find_unregistered_releases.py --json     # 機械向け
    python3 tools/find_unregistered_releases.py --no-list  # Apple Music だけ
"""

import argparse
import datetime as dt
import html
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
SONG_LIST_URL = ("https://music765plus.com/%E3%82%A2%E3%82%A4%E3%83%89%E3%83%AB%E3%83%9E%E3%82%B9"
                 "%E3%82%BF%E3%83%BC_%E3%82%AA%E3%83%AA%E3%82%B8%E3%83%8A%E3%83%AB%E6%9B%B2%E4%B8%80%E8%A6%A7")
# 一覧の行の class のうち、このアプリで扱わないもの
LIST_SKIP_CLASSES = {"XENO", "RAD"}

EXCLUDE = re.compile(
    r"(off vocal|instrumental|inst\.|game version|game ver\.|カラオケ|karaoke|"
    r"ソロ\s*ver|ソロ・リミックス|remix|リミックス|-live|\(live|ver\.\)|tv\s*size|tvサイズ|"
    r"game\s*size|m@ster\s*version)",
    re.I,
)


def norm(s: str) -> str:
    """曲名の比べ方: 全角半角・大小・空白・記号 (句読点・括弧・♡☆ など) の違いを無視する。"""
    s = unicodedata.normalize("NFKC", s or "").lower()
    return "".join(ch for ch in s if unicodedata.category(ch)[0] not in "PSZ")


def lookup(ids: list, **extra) -> list:
    params = {"id": ",".join(map(str, ids)), "country": "jp", **extra}
    for i in range(3):
        try:
            return itunes.results("lookup", params, user_agent=UA, timeout=30)
        except Exception as e:  # noqa: BLE001
            print(f"  retry lookup ({e})", file=sys.stderr)
            time.sleep(2 * (i + 1))
    return []


def parse_song_list(page: str) -> list:
    """曲一覧の HTML から (区分, 曲名, 歌唱者, 日付, 初出) を取り出す。"""
    out = []
    for cls, body in re.findall(r'<tr class="filter-row ([^"]+)">(.*?)</tr>', page, re.S):
        cells = [html.unescape(re.sub(r"<[^>]+>", "", c)).strip()
                 for c in re.findall(r"<td>(.*?)</td>", body, re.S)]
        if len(cells) < 5:
            continue
        classes = set(html.unescape(cls).replace("_", "").split())
        _, title, singer, date, note = cells[:5]
        out.append({"classes": sorted(classes), "title": title, "singer": singer,
                    "date": date.replace("/", "-"), "note": " ".join(note.split())})
    return out


def list_candidates(rows: list, known_titles: set) -> list:
    out = []
    for r in rows:
        if LIST_SKIP_CLASSES & set(r["classes"]):
            continue
        if r["singer"] in ("", "-") or r["singer"].startswith("(ドラマ"):
            continue
        if re.search(r"[〈<].*ver\.?[〉>]", r["title"], re.I):
            continue
        t = norm(r["title"])
        # 「修楽旅行」のように、版ごとに分けて登録してある曲は前方一致で済みとする
        if not t or t in known_titles or any(k.startswith(t) for k in known_titles):
            continue
        out.append(r)
    return out


def fetch_song_list() -> list:
    for i in range(3):
        try:
            req = itunes.urllib.request.Request(SONG_LIST_URL, headers={"User-Agent": UA})
            with itunes.urlopen(req, timeout=60) as res:
                return parse_song_list(res.read().decode("utf-8", "replace"))
        except Exception as e:  # noqa: BLE001
            print(f"  retry song list ({e})", file=sys.stderr)
            time.sleep(3 * (i + 1))
    raise RuntimeError("曲一覧を読めなかった")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=30, help="配信日がこの日数以内の曲だけ")
    ap.add_argument("--since", default="2022-01-01", help="歌い手を集める曲の release_date 下限")
    ap.add_argument("--master-sql", default=str(MASTER_SQL))
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--no-list", action="store_true", help="曲一覧との突き合わせをしない")
    args = ap.parse_args()

    conn = sqlite3.connect(":memory:")
    conn.executescript(Path(args.master_sql).read_text())
    known_ids = {r[0] for r in conn.execute(
        "SELECT apple_music_id FROM songs WHERE apple_music_id IS NOT NULL AND apple_music_id != ''")}
    known_titles = {norm(r[0]) for r in conn.execute("SELECT title FROM songs")}
    # まだ db/master.sql に戻っていない (今日足した) 曲も済みとする
    for f in sorted((ROOT / "data").glob("songs/*.json")) + sorted((ROOT / "data").glob("_applied/songs/*.json")):
        try:
            for song in json.loads(f.read_text()).get("songs", []):
                known_titles.add(norm(song.get("title", "")))
                if song.get("apple_music_id"):
                    known_ids.add(str(song["apple_music_id"]))
        except (ValueError, AttributeError):
            continue
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
                "source": "apple_music",
                "track_id": str(r["trackId"]),
                "album_id": str(r.get("collectionId") or ""),
                "release": rel,
                "title": name,
                "artist": artist,
                "album": r.get("collectionName") or "",
            }
        time.sleep(0.5)

    rows = sorted(found.values(), key=lambda x: (x["release"], x["title"]))
    listed = []
    if not args.no_list:
        apple_titles = {norm(x["title"]) for x in rows}
        listed = [dict(r, source="song_list", source_url=SONG_LIST_URL)
                  for r in list_candidates(fetch_song_list(), known_titles)
                  if norm(r["title"]) not in apple_titles]
    if args.json:
        print(json.dumps(rows + listed, ensure_ascii=False, indent=1))
    else:
        print(f"歌い手 {len(artists)} 組 / 配信日 {cutoff} 以降で未登録: {len(rows)} 曲")
        for x in rows:
            print(f"  {x['release']}  {x['title']}  — {x['artist'][:60]}  (id={x['track_id']})")
        if not args.no_list:
            print(f"曲一覧にあって未登録 (配信なし or 上で拾えない): {len(listed)} 曲")
            for x in listed:
                print(f"  {x['date']}  {x['title']}  — {x['singer']}  [{x['note']}]")
    return 0


if __name__ == "__main__":
    sys.exit(main())
