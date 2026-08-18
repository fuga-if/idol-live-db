#!/usr/bin/env python3
"""collect_song_versions.py — ソロ「〜 Ver.」の未登録分を iTunes から集める。

Usage:
    python3 tools/collect_song_versions.py                 # 提案を出すだけ
    python3 tools/collect_song_versions.py --write         # data/songs/ に書き出す

背景:
    ML の「Crossing!」等は 2025-07 から**毎週1人ずつ**ソロ Ver. が配信される企画で、
    52人ぶん (765 MILLION ALLSTARS) がほぼ出揃っている。DB には飛び飛びに 15 件
    しか入っておらず、一覧に中途半端に並ぶ一方で探している版は見つからない状態だった。

やること:
    既に 1 件でも「〜 Ver.」を持つ曲を企画対象とみなし、iTunes Search API で
    全 Ver. を引いて、DB に無いものを新規曲の候補として書き出す。

    - apple_music_id を入れるときは artwork_url も必ず入れる (一覧のジャケ写は
      songs.artwork_url を直参照するため、片方だけだと絵が出ない)
    - original_singers に歌唱アイドルを必ず入れる (一覧のアイコン表示の根拠)
    - parent_song_id を親に向ける (一覧・カレンダー・統計は派生曲を隠す)

⚠️ 曲名の括弧内をアイドル名として解決する。idols に無い名前は候補にせず未解決として
   報告する (ユニット名や「Instrumental」等を取り込まないため)。
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
ITUNES = "https://itunes.apple.com/search"

# 「<親曲名> (<名前> Ver.)」。全角括弧・半角括弧の両方を受ける。
VERSION_RE = re.compile(r"^(?P<base>.+?)\s*[(（](?P<who>.+?)\s*Ver\.?[)）]\s*$", re.IGNORECASE)


def squash(text: str) -> str:
    """比較用に空白を潰す。「所 恵美」と「所恵美」を同じ人として扱うため。"""
    return re.sub(r"\s+", "", text)


def itunes_search(term: str) -> list[dict]:
    url = f"{ITUNES}?{urllib.parse.urlencode({'term': term, 'entity': 'song', 'country': 'jp', 'limit': 200})}"
    req = urllib.request.Request(url, headers={"User-Agent": "imas-live-db/1.0"})
    with urllib.request.urlopen(req, timeout=30) as res:
        return json.load(res).get("results", [])


def artwork_url(result: dict) -> str:
    """一覧で使える大きさに差し替える (既定の 100x100 は粗い)。"""
    url = result.get("artworkUrl100") or result.get("artworkUrl60") or ""
    return url.replace("100x100bb", "600x600bb")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help=f"{OUT_PATH} に書き出す")
    ap.add_argument("--only", help="親曲IDを1つだけ指定して試す")
    args = ap.parse_args()

    db = sqlite3.connect(DB_PATH)
    songs = db.execute("SELECT id, title, brand_id, apple_music_id FROM songs").fetchall()
    idols = db.execute("SELECT id, name, brand_id FROM idols").fetchall()

    by_squashed_title = {(b, squash(t)): i for i, t, b, _ in songs}
    known_music_ids = {a for _, _, _, a in songs if a}
    known_titles = {(b, squash(t)) for _, t, b, _ in songs}
    idol_by_name = defaultdict(list)
    for idol_id, name, brand in idols:
        idol_by_name[squash(name)].append((idol_id, brand))

    # 既に 1 件でも Ver. を持つ曲 = 企画対象。親曲IDへ寄せる。
    parents: dict[str, tuple[str, str]] = {}
    for song_id, title, brand, _ in songs:
        m = VERSION_RE.match(title)
        if not m:
            continue
        parent_id = by_squashed_title.get((brand, squash(m.group("base"))))
        if parent_id:
            parents[parent_id] = (m.group("base").strip(), brand)
    if args.only:
        parents = {k: v for k, v in parents.items() if k == args.only}

    print(f"企画対象とみなした親曲: {len(parents)} 件", file=sys.stderr)

    proposals: list[dict] = []
    unresolved: list[str] = []
    for parent_id, (base_title, brand) in sorted(parents.items()):
        try:
            results = itunes_search(base_title)
        except Exception as err:
            print(f"  [skip] {base_title}: {err}", file=sys.stderr)
            continue
        time.sleep(0.5)  # iTunes に連打しない

        found = 0
        for r in results:
            track = (r.get("trackName") or "").strip()
            m = VERSION_RE.match(track)
            if not m or squash(m.group("base")) != squash(base_title):
                continue
            found += 1
            if str(r.get("trackId")) in known_music_ids:
                continue
            if (brand, squash(track)) in known_titles:
                continue

            who = squash(m.group("who"))
            candidates = [i for i, b in idol_by_name.get(who, [])]
            if not candidates:
                unresolved.append(f"{track} (アイドル '{m.group('who')}' が idols に無い)")
                continue

            proposals.append({
                "id": f"{parent_id}{who}ver",
                "title": track,
                "brand_id": brand,
                "song_type": "solo",
                "release_date": (r.get("releaseDate") or "")[:10],
                "apple_music_id": str(r.get("trackId") or ""),
                "artwork_url": artwork_url(r),
                "preview_url": r.get("previewUrl") or "",
                "parent_song_id": parent_id,
                "original_singers": [candidates[0]],
                "source": r.get("trackViewUrl") or "https://music.apple.com/jp/",
                "note": f"「{base_title}」のソロ Ver.。Apple Music の配信情報より。",
            })
        # ---- 2周目: 取りこぼしを原唱者リストから拾い直す ----
        #
        # 曲名1語の検索は関連度順で、limit 200 でも全部返るとは限らない。実際
        # 「Crossing!」は 52人中 50人ぶんしか返らず、中谷育・野々原茜が欠けていた
        # (どちらも配信は存在した)。親曲の原唱者を正として、Ver. が見つからなかった
        # 人だけ名指しで引き直す。
        singers = db.execute(
            "SELECT i.name FROM song_artists sa JOIN idols i ON i.id = sa.idol_id"
            " WHERE sa.song_id = ? AND sa.role = 'original'", (parent_id,)
        ).fetchall()
        covered = {squash(m.group("who"))
                   for r in results
                   if (m := VERSION_RE.match((r.get("trackName") or "").strip()))
                   and squash(m.group("base")) == squash(base_title)}
        for (name,) in singers:
            if squash(name) in covered:
                continue
            try:
                extra = itunes_search(f"{base_title} {name}")
            except Exception:
                continue
            time.sleep(0.5)
            for r in extra:
                track = (r.get("trackName") or "").strip()
                m = VERSION_RE.match(track)
                if not m or squash(m.group("base")) != squash(base_title):
                    continue
                if squash(m.group("who")) != squash(name):
                    continue
                if str(r.get("trackId")) in known_music_ids:
                    continue
                if (brand, squash(track)) in known_titles:
                    continue
                candidates = [i for i, b in idol_by_name.get(squash(name), [])]
                if not candidates:
                    continue
                found += 1
                proposals.append({
                    "id": f"{parent_id}{squash(name)}ver",
                    "title": track,
                    "brand_id": brand,
                    "song_type": "solo",
                    "release_date": (r.get("releaseDate") or "")[:10],
                    "apple_music_id": str(r.get("trackId") or ""),
                    "artwork_url": artwork_url(r),
                    "preview_url": r.get("previewUrl") or "",
                    "parent_song_id": parent_id,
                    "original_singers": [candidates[0]],
                    "source": r.get("trackViewUrl") or "https://music.apple.com/jp/",
                    "note": f"「{base_title}」のソロ Ver.。曲名検索から漏れたため"
                            f"原唱者名で引き直した。Apple Music の配信情報より。",
                })
                break

        print(f"  {base_title}: iTunes {found} 件 / 新規 "
              f"{sum(1 for p in proposals if p['parent_song_id'] == parent_id)} 件", file=sys.stderr)

    print(f"\n新規追加の候補: {len(proposals)} 曲", file=sys.stderr)
    if unresolved:
        print(f"アイドル未解決で見送り: {len(unresolved)} 件", file=sys.stderr)
        for u in unresolved[:10]:
            print(f"  - {u}", file=sys.stderr)

    if not args.write:
        print("\n(--write で data/songs/ に書き出す)", file=sys.stderr)
        return

    doc = {
        "title": "ソロ Ver. の一括追加",
        "author": "",
        # ファイル全体の出典。1曲ごとの source には各トラックの Apple Music URL が入る。
        "source": "https://music.apple.com/jp/",
        "_note": "毎週配信のソロ Ver. 企画ぶん。親曲は parent_song_id で紐付けてあるので、"
                 "一覧には出ず曲詳細の「別バージョン」から辿れる。",
        "songs": proposals,
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"{OUT_PATH} に {len(proposals)} 件書き出した", file=sys.stderr)


if __name__ == "__main__":
    main()
