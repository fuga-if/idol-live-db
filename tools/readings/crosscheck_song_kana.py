#!/usr/bin/env python3
"""アイマス楽曲DB (fujiwarahaji.me) のかな表記と、master の title_kana を突き合わせる。

`songs.title_kana` の大半は当方が起こしたもので、当て字や熟語の読み違いが混ざる
(`星宙のVoyage` を「せいちゅう」、`解夏傀儡` を「げげくぐつ」と入れていた)。
1 件ずつ人手で裏取りするより、かな表記を持つ外部 DB と機械的に突き合わせて
**食い違った曲だけ**を人に回す方が、見落としも手数も少ない。

## 出典サイトへの作法

相手は個人運営。**1 曲につき 2 リクエスト (検索 → API)、1 リクエストごとに間を空ける**。
一気に叩かない。`--resume` で途中から続けられるので、分けて回してよい。

## このツールは master を書き換えない

出すのは食い違いの一覧だけ。相手の DB も人が入れたもので、英語題の音写は実際に
外していた (`Majoram Therapie` → 「マジョラムセラピー」)。採否は人が決める。

使い方:
    python3 tools/readings/crosscheck_song_kana.py --limit 20        # 試し引き
    python3 tools/readings/crosscheck_song_kana.py --resume          # 続きから
    python3 tools/readings/crosscheck_song_kana.py --ids-file x.txt  # 曲 id を指定
"""
from __future__ import annotations

import argparse
import html
import json
import os
import re
import sqlite3
import sys
import time
import unicodedata
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DB = os.path.join(ROOT, "ImasLiveDB", "Resources", "master.sqlite")
STATE = os.path.join(ROOT, "tools", "readings", "crosscheck_state.json")
UA = "ImasLiveDB-reading-crosscheck/1.0 (contact: fuga.else@gmail.com)"
# 個人運営サイトなので 1 リクエストごとにこれだけ空ける。短くしない。
DELAY_SEC = 1.5

SEARCH_URL = "https://fujiwarahaji.me/?s={}"
API_URL = "https://api.fujiwarahaji.me/v3/music?id={}"
HIT_RE = re.compile(r'<a href="https://fujiwarahaji\.me/music/([a-z0-9]+)/(\d+)">([^<]*)</a>')


def get(url: str) -> str | None:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=25) as res:
            if res.status != 200:
                return None
            return res.read().decode("utf-8", errors="replace")
    except Exception as e:  # noqa: BLE001 - 落とさず次の曲へ進む
        print(f"  取得失敗 {url}: {e}", file=sys.stderr)
        return None


def fold(text: str) -> str:
    """突き合わせ用に読みを畳む。

    片方が「！」や「～」を含み片方が含まない、といった飾りの差で食い違い扱いに
    なると、本当に読みが違う曲が埋もれる。かな以外は落とし、カタカナは
    ひらがなへ寄せる (音引き `ー` は音の一部なので残す)。
    """
    normalized = unicodedata.normalize("NFKC", text)
    out = []
    for ch in normalized:
        if "ァ" <= ch <= "ヶ":  # カタカナ → ひらがな
            ch = chr(ord(ch) - 0x60)
        if "ぁ" <= ch <= "ゖ" or ch == "ー":
            out.append(ch)
    return "".join(out)


def search_song_id(title: str) -> tuple[str, int, str] | None:
    """曲名で検索し、(ブランド, id, 相手側の曲名) を返す。一意に決まらなければ None。"""
    body = get(SEARCH_URL.format(urllib.parse.quote(title)))
    if not body:
        return None
    hits = [(b, int(i), html.unescape(n).strip()) for b, i, n in HIT_RE.findall(body)]
    if not hits:
        return None
    exact = [h for h in hits if fold_title(h[2]) == fold_title(title)]
    if len(exact) == 1:
        return exact[0]
    # 完全一致が無い/複数あるものは人に回す (別名義・派生の取り違えを避ける)。
    return None


def fold_title(title: str) -> str:
    """曲名の突き合わせ用の鍵。記号と空白の揺れだけで別物にしない。"""
    normalized = unicodedata.normalize("NFKC", title)
    return "".join(c for c in normalized if c.isalnum()).lower()


def fetch_kana(song_id: int) -> str | None:
    body = get(API_URL.format(song_id))
    if not body:
        return None
    try:
        return (json.loads(body).get("kana") or "").strip() or None
    except json.JSONDecodeError:
        return None


def load_targets(ids_file: str | None) -> list[tuple[str, str, str]]:
    conn = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    if ids_file:
        wanted = [l.strip() for l in open(ids_file, encoding="utf-8") if l.strip()]
        marks = ",".join("?" * len(wanted))
        sql = f"SELECT id, title, title_kana FROM songs WHERE id IN ({marks})"
        rows = conn.execute(sql, wanted).fetchall()
    else:
        rows = conn.execute(
            "SELECT id, title, title_kana FROM songs WHERE title_kana IS NOT NULL"
        ).fetchall()
    conn.close()
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids-file", help="対象の曲 id を 1 行 1 件で書いたファイル")
    ap.add_argument("--limit", type=int, help="この件数だけ引いて止める")
    ap.add_argument("--resume", action="store_true", help="前回の続きから")
    ap.add_argument("--out", default=os.path.join(ROOT, "tools", "readings", "crosscheck.tsv"))
    args = ap.parse_args()

    done: dict[str, str] = {}
    if args.resume and os.path.exists(STATE):
        done = json.load(open(STATE, encoding="utf-8"))

    targets = [t for t in load_targets(args.ids_file) if t[0] not in done]
    if args.limit:
        targets = targets[: args.limit]
    print(f"対象 {len(targets)} 曲 (済み {len(done)} 曲)")

    diffs = agreed = missing = 0
    for n, (sid, title, ours) in enumerate(targets, 1):
        hit = search_song_id(title)
        time.sleep(DELAY_SEC)
        if not hit:
            done[sid] = "notfound"
            missing += 1
        else:
            theirs = fetch_kana(hit[1])
            time.sleep(DELAY_SEC)
            if not theirs:
                done[sid] = "nokana"
                missing += 1
            elif fold(theirs) == fold(ours):
                done[sid] = "same"
                agreed += 1
            else:
                done[sid] = f"diff\t{theirs}\t{hit[0]}/{hit[1]}"
                diffs += 1
                print(f"  ★ {title}\n     当方: {ours}\n     先方: {theirs}")
        if n % 25 == 0:
            json.dump(done, open(STATE, "w", encoding="utf-8"), ensure_ascii=False)
            print(f"  … {n}/{len(targets)} (一致 {agreed} / 相違 {diffs} / 不明 {missing})")

    json.dump(done, open(STATE, "w", encoding="utf-8"), ensure_ascii=False)

    conn = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    titles = dict(conn.execute("SELECT id, title FROM songs"))
    kanas = dict(conn.execute("SELECT id, title_kana FROM songs"))
    conn.close()
    with open(args.out, "w", encoding="utf-8") as w:
        for sid, val in sorted(done.items()):
            if not val.startswith("diff\t"):
                continue
            _, theirs, ref = val.split("\t")
            w.write(f"{sid}\t{titles.get(sid, '')}\t{kanas.get(sid, '')}\t{theirs}\t{ref}\n")
    print(f"\n一致 {agreed} / 相違 {diffs} / 引けず {missing}")
    print(f"相違の一覧: {args.out} (このツールは master を書き換えない)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
