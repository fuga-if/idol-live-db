#!/usr/bin/env python3
"""公演中に X の実況を集めて、セトリの下書きを育てる (速報セトリの試作)。

情報源は Yahoo!リアルタイム検索 (X の投稿を新着順に返す。ログイン不要・無料)。
X API は読み取りが従量課金なので、ここでは使わない。

    python3 tools/live_setlist_watch.py --show-id sh_xxx_1 \
        --query "#シャニマス セトリ" --query "#シャニマス M1" \
        --start 2026-10-11T18:00+09:00 --out /mnt/project-files/setlist-live/runs/sh_xxx_1

--interval 秒ごとに検索し、新しい投稿があれば --extract-every 秒ごとに Gemini で
曲順を取り出す。開演 10 分前から --duration 分まで回って止まる (--once で 1 回だけ)。

出力 (--out の下):
  posts.jsonl   集めた投稿 (id, 投稿時刻, 取得時刻, 本文, 画像 URL)。遅延の測定に使う
  drafts.jsonl  抽出のたびの下書き (取得時刻と、埋まった曲順)
  draft.json    最新の下書き。data/setlists の形 (show_id / source / songs[])
  timeline.md   何時何分に何曲目まで埋まったか、の人が読む記録

Gemini は generativelanguage.googleapis.com を直接叩く。鍵は GEMINI_API_KEY
(クラウドのセッションではプロキシが付けるので不要)。
"""
import argparse
import base64
import json
import os
import re
import sqlite3
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

JST = timezone(timedelta(hours=9))
ROOT = Path(__file__).resolve().parent.parent
YAHOO = "https://search.yahoo.co.jp/realtime/search"
GEMINI = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
UA = "Mozilla/5.0 (imas-live-db live-setlist-watch)"
# 1 回の抽出に渡す投稿と画像の上限。実況は後の投稿ほど曲が進んでいるので新しい方を残す。
MAX_POSTS = 400
MAX_IMAGES = 6


def now():
    return datetime.now(JST)


def http_get(url, timeout=20):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as res:
                return res.read()
        except (urllib.error.URLError, TimeoutError) as e:
            if attempt == 2:
                raise
            print(f"  取得に失敗 ({e})、再試行", file=sys.stderr)
            time.sleep(3 * (attempt + 1))


def search_yahoo(query):
    """Yahoo!リアルタイム検索の新着順 1 ページ (約 40 件) を返す。"""
    html = http_get(YAHOO + "?" + urllib.parse.urlencode({"p": query, "ei": "UTF-8"})).decode()
    m = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.S)
    if not m:
        raise RuntimeError("検索結果のページの形が変わった (__NEXT_DATA__ が無い)")
    entries = json.loads(m.group(1))["props"]["pageProps"]["pageData"]["timeline"]["entry"]
    posts = []
    for e in entries:
        text = e.get("displayText", "").replace("\tSTART\t", "").replace("\tEND\t", "")
        media = [x.get("item", {}).get("mediaUrl") or x.get("item", {}).get("url")
                 for x in (e.get("media") or []) if isinstance(x, dict)]
        posts.append({
            "id": e["id"],
            "created_at": int(e["createdAt"]),
            "text": text,
            "user": e.get("screenName"),
            "url": (e.get("url") or "").split("?")[0],
            "media": [u for u in media if u],
        })
    return posts


def load_show(show_id):
    """db/master.sql から公演と、そのブランドの曲名一覧を読む。"""
    db = sqlite3.connect(":memory:")
    db.executescript((ROOT / "db/master.sql").read_text())
    row = db.execute(
        "SELECT s.id, s.date, s.start_time, e.name, s.name, e.brand_id, e.joint_brand_ids"
        " FROM shows s JOIN events e ON e.id = s.event_id WHERE s.id = ?", (show_id,)).fetchone()
    if not row:
        sys.exit(f"公演 {show_id} が db/master.sql に無い")
    _, date, start, event_name, show_name, brand, joint = row
    brands = {brand} | set(filter(None, (joint or "").split(",")))
    marks = ",".join("?" * len(brands))
    songs = db.execute(
        f"SELECT id, title FROM songs WHERE brand_id IN ({marks}) AND parent_song_id IS NULL"
        " ORDER BY title", tuple(brands)).fetchall()
    return {"id": show_id, "date": date, "start_time": start,
            "name": event_name + (f" {show_name}" if show_name else ""), "songs": songs}


def norm(s):
    s = unicodedata.normalize("NFKC", s).lower()
    return re.sub(r"[\s・!！?？~〜～\-‐―'’\"“”「」『』()（）]", "", s)


def gemini(model, parts):
    body = {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {"responseMimeType": "application/json", "temperature": 0},
    }
    headers = {"Content-Type": "application/json"}
    if os.environ.get("GEMINI_API_KEY"):
        headers["x-goog-api-key"] = os.environ["GEMINI_API_KEY"]
    req = urllib.request.Request(GEMINI.format(model=model), json.dumps(body).encode(), headers)
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=180) as res:
                out = json.load(res)
            break
        except urllib.error.HTTPError as e:
            # 混雑 (429/500/502/503) は待てば通る。それ以外 (400 など) は直さないと通らない
            if e.code not in (429, 500, 502, 503, 504) or attempt == 3:
                raise RuntimeError(f"Gemini {e.code}: {e.read()[:300]!r}") from e
            time.sleep(10 * (attempt + 1))
    text = "".join(p.get("text", "") for p in out["candidates"][0]["content"]["parts"])
    return json.loads(text)


PROMPT = """あなたはアイドルマスターのライブのセットリストを、ファンの実況投稿から組み立てる係です。
公演: {name} ({date} 開演 {start})

下の「投稿」は X の投稿で、古い順に並んでいます。「M3 〇〇」「〇〇きた!」「〇〇からの〇〇」のような実況から、
この公演で歌われた曲と順番を組み立ててください。画像があればセトリ画像かどうかも見てください。

守ること:
- 曲名は「曲名一覧」にあるものから選び、その表記どおりに書く。一覧に無い曲 (新曲など) は投稿の表記のまま書き、in_catalog を false にする。
- 別の公演 (前日・他の会場・過去のライブ)、予想、願望、プレイリスト、アーカイブ視聴の投稿は数えない。
- 順番が分からない曲は position を null にする。推測で番号を埋めない。
- confidence は、別々の人の投稿で何件裏が取れたかで決める (high: 3 人以上か公式/セトリ画像、medium: 2 人、low: 1 人)。
- 公演が終わった (「終演」「ありがとうございました」が多い) かどうかを ended に入れる。

出力は次の JSON だけ:
{{"ended": bool, "songs": [{{"position": int|null, "title": str, "in_catalog": bool, "confidence": "high"|"medium"|"low", "evidence": [投稿の番号]}}], "notes": str}}

曲名一覧:
{catalog}

投稿:
{posts}
"""


def extract(show, posts, model, start_ts):
    use = [p for p in posts if p["created_at"] >= start_ts - 3600][-MAX_POSTS:]
    lines = []
    for i, p in enumerate(use):
        t = datetime.fromtimestamp(p["created_at"], JST).strftime("%H:%M")
        img = f" [画像{len(p['media'])}枚]" if p["media"] else ""
        lines.append(f"#{i} {t} @{p['user']}: {p['text']}{img}")
    parts = [{"text": PROMPT.format(
        name=show["name"], date=show["date"], start=show["start_time"] or "不明",
        catalog="\n".join(t for _, t in show["songs"]), posts="\n".join(lines))}]
    images = [u for p in reversed(use) for u in p["media"]][:MAX_IMAGES]
    for u in images:
        try:
            data = http_get(u, timeout=20)
        except Exception as e:  # 画像が取れなくても文字だけで続ける
            print(f"  画像を取れなかった {u}: {e}", file=sys.stderr)
            continue
        parts.append({"inline_data": {"mime_type": "image/jpeg",
                                      "data": base64.b64encode(data).decode()}})
    result = gemini(model, parts)
    by_norm = {norm(t): sid for sid, t in show["songs"]}
    for s in result.get("songs", []):
        s["song_id"] = by_norm.get(norm(s.get("title", "")))
    return result


def to_setlist_json(show, result, source):
    songs = []
    for s in sorted((s for s in result.get("songs", []) if s.get("position")),
                    key=lambda s: s["position"]):
        item = {"position": s["position"]}
        if s.get("song_id"):
            item["song_id"] = s["song_id"]
        else:
            item["title"] = s["title"]
        item["performers"] = "all"
        item["notes"] = f"速報 ({s.get('confidence')})"
        songs.append(item)
    # 歌われたのは確かだが順番が分からない曲。apply_data は読まない (人が並べる手がかり)
    unordered = [s["title"] for s in result.get("songs", []) if not s.get("position")]
    return {"show_id": show["id"], "source": source, "author": "live_setlist_watch (速報・未確認)",
            "songs": songs, "unordered_titles": unordered}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--show-id", required=True)
    ap.add_argument("--query", action="append", required=True, help="Yahoo!リアルタイム検索の語 (複数可)")
    ap.add_argument("--start", help="開演 (ISO 8601)。省略時は db の date + start_time")
    ap.add_argument("--duration", type=int, default=240, help="開演から何分まで回すか")
    ap.add_argument("--interval", type=int, default=90, help="検索の間隔 (秒)")
    ap.add_argument("--extract-every", type=int, default=300, help="抽出の間隔 (秒)")
    ap.add_argument("--model", default="gemini-flash-latest")
    ap.add_argument("--out", required=True)
    ap.add_argument("--once", action="store_true", help="1 回だけ集めて抽出して終わる (試験用)")
    args = ap.parse_args()

    show = load_show(args.show_id)
    if args.start:
        start = datetime.fromisoformat(args.start)
    else:
        if not show["start_time"]:
            sys.exit("開演時刻が db に無いので --start を付けてください")
        start = datetime.fromisoformat(f"{show['date']}T{show['start_time']}+09:00")
    show["start_time"] = start.astimezone(JST).strftime("%H:%M")
    end = start + timedelta(minutes=args.duration)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    posts = {}
    posts_path = out / "posts.jsonl"
    if posts_path.exists():  # 途中で止まっても続きから
        for line in posts_path.read_text().splitlines():
            p = json.loads(line)
            posts[p["id"]] = p

    if not args.once and now() < start - timedelta(minutes=10):
        wait = (start - timedelta(minutes=10) - now()).total_seconds()
        print(f"開演 10 分前まで {int(wait)} 秒待つ")
        time.sleep(wait)

    last_extract = 0.0
    new_since_extract = 0
    last_positions = None
    first_round = True
    while True:
        fetched = int(time.time())
        for q in args.query:
            try:
                found = search_yahoo(q)
            except Exception as e:
                print(f"{now():%H:%M:%S} 検索に失敗 [{q}]: {e}", file=sys.stderr)
                continue
            with posts_path.open("a") as f:
                for p in found:
                    if p["id"] in posts or p["created_at"] < start.timestamp() - 3600:
                        continue
                    p["fetched_at"] = fetched
                    # 最初の回は溜まっていた分をまとめて拾うので、遅延の測定には使わない
                    p["backlog"] = first_round
                    p["query"] = q
                    posts[p["id"]] = p
                    new_since_extract += 1
                    f.write(json.dumps(p, ensure_ascii=False) + "\n")
        first_round = False
        print(f"{now():%H:%M:%S} 投稿 {len(posts)} 件 (新規 {new_since_extract})")

        if new_since_extract and (args.once or time.time() - last_extract >= args.extract_every):
            ordered = sorted(posts.values(), key=lambda p: p["created_at"])
            try:
                result = extract(show, ordered, args.model, start.timestamp())
            except Exception as e:
                print(f"{now():%H:%M:%S} 抽出に失敗: {e}", file=sys.stderr)
                result = None
            if result is not None:
                last_extract = time.time()
                new_since_extract = 0
                positions = sorted(s["position"] for s in result.get("songs", []) if s.get("position"))
                record = {"at": now().isoformat(timespec="seconds"), "posts": len(posts), **result}
                with (out / "drafts.jsonl").open("a") as f:
                    f.write(json.dumps(record, ensure_ascii=False) + "\n")
                source = f"X 実況 (Yahoo!リアルタイム検索: {' / '.join(args.query)})"
                (out / "draft.json").write_text(json.dumps(
                    to_setlist_json(show, result, source), ensure_ascii=False, indent=2) + "\n")
                if positions != last_positions:
                    elapsed = int((now() - start).total_seconds() // 60)
                    filled = len(positions)
                    total = len(result.get("songs", []))
                    top = max(positions) if positions else 0
                    with (out / "timeline.md").open("a") as f:
                        f.write(f"- {now():%H:%M} (開演 {elapsed:+d} 分): 曲順つき {filled} 曲 (曲名だけ {total - filled} 曲) / 最大 M{top:02d}"
                                f"{' / 終演判定' if result.get('ended') else ''}\n")
                    last_positions = positions
                print(f"{now():%H:%M:%S} 下書き {len(positions)} 曲, ended={result.get('ended')}")

        if args.once or now() >= end:
            break
        time.sleep(args.interval)

    lags = sorted(p["fetched_at"] - p["created_at"] for p in posts.values()
                  if p["created_at"] >= start.timestamp() and not p.get("backlog", True))
    if lags:
        med = lags[len(lags) // 2]
        print(f"公演中の投稿 {len(lags)} 件、投稿から取得までの遅れ 中央値 {med} 秒")


if __name__ == "__main__":
    main()
