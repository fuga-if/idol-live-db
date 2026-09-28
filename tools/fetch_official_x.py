#!/usr/bin/env python3
"""各ブランド公式 X の新着投稿を集めて、日次クロールが読む Markdown にする。

X API は読み取りが有料なので使わない。FxTwitter の公開 API
(`api.fxtwitter.com/2/profile/<handle>/statuses`、ログイン不要・無料) を叩く。
1 回 20 件前後を返し、`cursor.bottom` で古い方へ辿れる。

前回どこまで読んだかは --state の JSON に handle ごとの最新投稿 id で持つ。
初回 (state に無い handle) は --days 日前まで遡る。

    python3 tools/fetch_official_x.py --state Scripts/crawl_review/x_state.json \
        --out Scripts/crawl_review/2026-09-27.x.md

画像 (出演者一覧の告知画像など) は URL を並べるだけ。読むのは呼び出し側。
"""
import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

# 公式ポータル・各ブランドサイトのフッタにあるリンクで確認したアカウント。
ACCOUNTS = [
    ("総合", "imas_official"),
    ("765/ミリオン", "imasml_765PRO"),
    ("ミリオン", "imasml_theater"),
    ("シンデレラ", "imas_CGofficial"),
    ("シンデレラ", "imascg_stage"),
    ("SideM", "SideM_official"),
    ("シャニ", "imassc_official"),
    ("シャニ", "imassc_prism"),
    ("シャニ", "shinyc_official"),
    ("学マス", "gkmas_official"),
    ("ヴイアライヴ", "valiv_official"),
]

API = "https://api.fxtwitter.com/2/profile/{handle}/statuses"
MAX_PAGES = 10


def fetch_page(handle, cursor=None):
    url = API.format(handle=handle)
    if cursor:
        url += "?cursor=" + urllib.parse.quote(cursor)
    req = urllib.request.Request(url, headers={"User-Agent": "imas-live-db-crawl"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=30) as res:
                return json.load(res)
        except (urllib.error.URLError, TimeoutError) as e:
            if attempt == 2:
                raise
            print(f"  {handle}: {e}、再試行", file=sys.stderr)
            time.sleep(5 * (attempt + 1))


def posted_at(status):
    return datetime.fromtimestamp(status["created_timestamp"], tz=timezone.utc)


def collect(handle, last_id, since):
    """last_id より新しい (無ければ since 以降の) 投稿を新しい順で返す。"""
    posts, cursor = [], None
    for _ in range(MAX_PAGES):
        data = fetch_page(handle, cursor)
        results = data.get("results") or []
        if not results:
            break
        for s in results:
            # 固定ツイートが先頭に古い日付で来るので、古いものに当たっても即打ち切らない。
            if last_id and int(s["id"]) <= int(last_id):
                continue
            if not last_id and posted_at(s) < since:
                continue
            posts.append(s)
        oldest = results[-1]
        if (last_id and int(oldest["id"]) <= int(last_id)) or (not last_id and posted_at(oldest) < since):
            break
        cursor = (data.get("cursor") or {}).get("bottom")
        if not cursor:
            break
    seen = set()
    uniq = [p for p in posts if not (p["id"] in seen or seen.add(p["id"]))]
    return sorted(uniq, key=lambda s: int(s["id"]), reverse=True)


def render(status):
    jst = posted_at(status).astimezone(timezone(timedelta(hours=9)))
    lines = [f"### {jst:%Y-%m-%d %H:%M} {status['url']}"]
    if status.get("reposted_by"):
        lines.append(f"(リポスト: 元 @{status['author']['screen_name']})")
    lines.append("")
    lines.append(status.get("text", "").strip())
    for m in (status.get("media") or {}).get("all", []):
        lines.append(f"- {m.get('type')}: {m.get('url')}")
    card = status.get("embed_card") or {}
    if isinstance(card, dict) and card.get("url"):
        lines.append(f"- link: {card['url']}")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--state", required=True, help="handle → 最後に読んだ投稿 id の JSON")
    ap.add_argument("--out", required=True, help="書き出す Markdown")
    ap.add_argument("--days", type=int, default=3, help="state に無い handle を何日遡るか")
    ap.add_argument("--dry-run", action="store_true", help="state を更新しない")
    args = ap.parse_args()

    try:
        with open(args.state, encoding="utf-8") as f:
            state = json.load(f)
    except FileNotFoundError:
        state = {}
    since = datetime.now(timezone.utc) - timedelta(days=args.days)

    out, failed = [], []
    for brand, handle in ACCOUNTS:
        try:
            posts = collect(handle, state.get(handle), since)
        except Exception as e:  # 1 アカウントの失敗で全体を止めない
            failed.append(f"@{handle}: {e}")
            continue
        out.append(f"## {brand} @{handle} ({len(posts)} 件)\n")
        out.extend(render(p) + "\n" for p in posts)
        if posts:
            state[handle] = max((p["id"] for p in posts), key=int)
        time.sleep(1)

    head = [f"# 公式 X 新着 ({datetime.now(timezone(timedelta(hours=9))):%Y-%m-%d %H:%M} JST)\n"]
    if failed:
        head.append("取得失敗:\n" + "\n".join(f"- {x}" for x in failed) + "\n")
    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(head + out))
    if not args.dry_run:
        with open(args.state, "w", encoding="utf-8") as f:
            json.dump(state, f, ensure_ascii=False, indent=1)
    print(f"{args.out}: {sum(o.startswith('### ') for o in out)} 件 / 失敗 {len(failed)}")
    return 1 if len(failed) == len(ACCOUNTS) else 0


if __name__ == "__main__":
    sys.exit(main())
