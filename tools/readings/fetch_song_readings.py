#!/usr/bin/env python3
"""アイマスDB (imas-db.jp) から曲の読み仮名を集める。

許諾を得たうえでの参照 (アプリ内「データ参照元」に掲載済み)。
相手は個人運営なので、**1 件ごとに間を空けて静かに引く**。一気に叩かない。

出力は data/fixes/song_readings_<日付>.json の候補ファイル。
**そのまま master へは入れない**。曲名の一致は完全一致のみを自動採用とし、
派生 (Remix / M@STER VERSION 等) や曖昧なものは要確認として分けて出す。

使い方:
    python3 tools/readings/fetch_song_readings.py --limit 20          # 試し引き
    python3 tools/readings/fetch_song_readings.py --start 1 --end 500 # 範囲指定
    python3 tools/readings/fetch_song_readings.py --resume            # 続きから
"""
from __future__ import annotations

import argparse
import html
import json
import os
import re
import sqlite3
import unicodedata
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DB = os.path.join(ROOT, "ImasLiveDB", "Resources", "master.sqlite")
STATE = os.path.join(ROOT, "tools", "readings", "state.json")
OUT_DIR = os.path.join(ROOT, "data", "fixes")
UA = "ImasLiveDB-reading-collector/1.0 (permission granted; contact: fuga.else@gmail.com)"
# 個人運営サイトなので 1 件ごとにこれだけ空ける。短くしない。
DELAY_SEC = 1.5

TITLE_RE = re.compile(r"<h1[^>]*>\s*楽曲:\s*([^<]+)", re.S)
YOMI_RE = re.compile(r"よみ[^<]*</[^>]+>\s*<[^>]+>([^<]+)")


def fetch(song_id: int) -> tuple[str, str] | None:
    """1 曲ぶんの (曲名, よみ) を返す。無ければ None。"""
    url = f"https://imas-db.jp/song/detail/{song_id}.html"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=20) as res:
            if res.status != 200:
                return None
            body = res.read().decode("utf-8", errors="replace")
    except Exception as e:
        print(f"  id={song_id} 取得失敗: {e}", file=sys.stderr)
        return None
    t = TITLE_RE.search(body)
    y = YOMI_RE.search(body)
    if not t or not y:
        return None
    return html.unescape(t.group(1)).strip(), html.unescape(y.group(1)).strip()


def match_key(title: str) -> str:
    """突き合わせ用の鍵。

    半角/全角の記号ゆれ (`おはよう!!朝ご飯` と `おはよう！！朝ご飯`) だけで
    別物と判定されるのを防ぐ。記号と空白は落とし、英字は小文字へ寄せる。
    曲そのものの弁別は残したいので、かな/漢字はいじらない。
    """
    normalized = unicodedata.normalize("NFKC", title)
    kept = [c for c in normalized if c.isalnum()]
    return "".join(kept).lower()


def load_our_songs() -> dict[str, list[str]]:
    """突き合わせ鍵 → 自分の DB の song_id 群 (同名の派生があるので複数)。"""
    conn = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    rows = conn.execute("SELECT id, title FROM songs").fetchall()
    conn.close()
    by_title: dict[str, list[str]] = {}
    for sid, title in rows:
        by_title.setdefault(match_key(title), []).append(sid)
    return by_title


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--start", type=int, default=1)
    ap.add_argument("--end", type=int, default=None)
    ap.add_argument("--limit", type=int, default=None, help="この件数だけ引いて止める")
    ap.add_argument("--resume", action="store_true", help="前回の続きから")
    args = ap.parse_args()

    state = {"next_id": args.start, "found": {}, "missing": []}
    if args.resume and os.path.exists(STATE):
        state = json.load(open(STATE, encoding="utf-8"))
        print(f"続きから: id={state['next_id']} / 取得済み {len(state['found'])} 件")

    ours = load_our_songs()
    sid = state["next_id"]
    fetched = 0
    try:
        while True:
            if args.end and sid > args.end:
                break
            if args.limit and fetched >= args.limit:
                break
            got = fetch(sid)
            if got:
                title, yomi = got
                state["found"][str(sid)] = {"title": title, "yomi": yomi}
                mark = "○" if match_key(title) in ours else "－"
                print(f"  {mark} id={sid} {title} → {yomi}")
            else:
                state["missing"].append(sid)
            fetched += 1
            sid += 1
            state["next_id"] = sid
            time.sleep(DELAY_SEC)
    except KeyboardInterrupt:
        print("\n中断しました。--resume で続きから引けます。")

    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    json.dump(state, open(STATE, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    # 突き合わせ: 完全一致だけ自動採用、それ以外は要確認へ回す
    auto, review = [], []
    for rec in state["found"].values():
        ids = ours.get(match_key(rec["title"]))
        if ids and len(ids) == 1:
            auto.append({"song_id": ids[0], "title": rec["title"], "title_kana": rec["yomi"]})
        elif ids:
            review.append({**rec, "candidates": ids, "reason": "同名の曲が複数"})
        else:
            review.append({**rec, "candidates": [], "reason": "自分の DB に同名が無い"})

    os.makedirs(OUT_DIR, exist_ok=True)
    stamp = time.strftime("%Y%m%d")
    out = os.path.join(OUT_DIR, f"song_readings_{stamp}.json")
    json.dump(
        {"source": "https://imas-db.jp/ (許諾取得済み・アプリ内に参照元として掲載)",
         "auto": auto, "review": review},
        open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"\n引いた {fetched} 件 / 自動採用 {len(auto)} 件 / 要確認 {len(review)} 件")
    print(f"→ {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
