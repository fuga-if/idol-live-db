#!/usr/bin/env python3
"""check_apple_music_links.py — songs.apple_music_id が別の曲を指していないか点検する。

同名の別曲を掴む事故が実際に起きた (cg_everlasting が アサルトリリィ の
「Everlasting」を指し、アプリのクイズにそのジャケットと試聴音源が出ていた)。
曲名だけで一致を取ると、この形の誤りは黙って通る。

そこで **Apple 側のアーティスト名・アルバム名に、こちらの曲と繋がる手がかりが
一つも無いもの**を落とす。手がかりは次のいずれか。

  - ブランド語 (シンデレラ / MILLION / 初星学園 など)
  - その曲の singer_label に載っているアイドル名
  - units / idols / idol_voice_actors に載っている名前

アルバム id の食い違いは**見ない**。ベスト盤や GAME VERSION 収録で
track と album が別になっている曲が 267 件あり、そちらは誤りではないため。

    python3 tools/check_apple_music_links.py            # 全曲
    python3 tools/check_apple_music_links.py --brand cg

終了コードは、疑わしいものが 1 件でもあれば 1。
"""

import argparse
import json
import re
import sqlite3
import sys
import time
import urllib.request
from pathlib import Path

DB = Path(__file__).resolve().parent.parent / "ImasLiveDB/Resources/master.sqlite"
LOOKUP = "https://itunes.apple.com/lookup?country=jp&entity=song&limit=200&id="
CHUNK = 150

# units / idols だけでは拾えない、レーベル名義や表記ゆれの補い。
EXTRA_SIGNALS = [
    "IDOLM@STER", "アイドルマスター", "CINDERELLA", "シンデレラ", "デレマス",
    "MILLION", "ミリオン", "SideM", "SHINY COLORS", "シャイニーカラーズ",
    "初星学園", "学園アイドルマスター", "GAKUEN", "765", "876", "346", "315", "283",
    "M@STER", "THE@TER", "ぷちます", "Project Fairy", "DEARLY STARS",
]


def normalize(text):
    return re.sub(r"[\s　]", "", (text or "")).lower()


def load_signals(conn, brand_id=None):
    """名前の手がかり集合。短すぎる名前は誤って通すので落とす。"""
    names = set(EXTRA_SIGNALS)
    for table in ("units", "idols"):
        names.update(r[0] for r in conn.execute("SELECT name FROM %s" % table) if r[0])
    names.update(r[0] for r in conn.execute("SELECT name FROM idol_voice_actors") if r[0])
    return {normalize(n) for n in names if len(normalize(n)) >= 3}


def fetch_tracks(track_ids):
    found = {}
    ids = sorted(track_ids)
    for i in range(0, len(ids), CHUNK):
        url = LOOKUP + ",".join(ids[i:i + CHUNK])
        req = urllib.request.Request(url, headers={"User-Agent": "ImasLiveDB/1.0"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        for res in data.get("results", []):
            if res.get("wrapperType") == "track":
                found[str(res["trackId"])] = res
        sys.stderr.write("  %d/%d 照会\n" % (min(i + CHUNK, len(ids)), len(ids)))
        time.sleep(1.5)
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(DB))
    ap.add_argument("--brand", help="ブランドを絞る (cg / ml / sc など)")
    args = ap.parse_args()

    conn = sqlite3.connect("file:%s?mode=ro" % args.db, uri=True)
    sql = ("SELECT id, title, apple_music_id, singer_label, brand_id FROM songs "
           "WHERE apple_music_id IS NOT NULL AND apple_music_id <> ''")
    params = ()
    if args.brand:
        sql += " AND brand_id = ?"
        params = (args.brand,)
    rows = list(conn.execute(sql, params))
    signals = load_signals(conn)
    conn.close()

    sys.stderr.write("照合対象 %d曲\n" % len(rows))
    found = fetch_tracks({str(r[2]) for r in rows})

    suspect, gone = [], []
    for sid, title, tid, singer, brand in rows:
        res = found.get(str(tid))
        if res is None:
            gone.append((sid, title, tid))
            continue
        blob = normalize((res.get("artistName") or "") + (res.get("collectionName") or ""))
        if any(s in blob for s in signals):
            continue
        # その曲自身の歌唱者名で最後にもう一度見る。
        parts = [normalize(p) for p in re.split(r"[、,／/&]", singer or "")]
        if any(p and len(p) >= 2 and p in blob for p in parts):
            continue
        suspect.append((sid, title, tid, res.get("trackName", ""),
                        res.get("artistName", ""), res.get("collectionName", "")))

    print("=== アイマス側との手がかりが無いトラック: %d件 ===" % len(suspect))
    for s in sorted(suspect):
        print("%s  %s" % (s[0], s[1]))
        print("    track %s → 「%s」/ %s / アルバム「%s」" % (s[2], s[3], s[4], s[5]))
    print("\n=== Apple から引けなかったトラック: %d件 ===" % len(gone))
    for g in sorted(gone):
        print("  %-34s %-28s track %s" % (g[0], g[1][:26], g[2]))
    return 1 if suspect else 0


if __name__ == "__main__":
    sys.exit(main())
