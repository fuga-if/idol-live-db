#!/usr/bin/env python3
"""collect_request_logs.py — 歌詞の曲別リクエスト回数を Workers Logs から日次で集める。

JASRAC 年次利用曲目報告の 19 項目目「リクエスト回数」の材料。

なぜ D1 に数えないのか:
    閲覧のたびに D1 へ書くと、固定無料枠のホットパス (曲詳細・歌詞取得) が
    読み取りから読み書きに変わる。ランニングコストを 0 に保つ絶対制約
    (docs/JASRAC.md / CLAUDE.md) に対して、報告のための集計がいちばん重い
    書き込み経路になるのは筋が悪い。Worker は 1 行ログを出すだけにして、
    集計はログ側 (Workers Logs = Worker の実行に含まれる) で行う。

仕組み:
    Worker が歌詞を返したときだけ  {"event":"lyrics_read","song_id":"..."}  を
    console.log する (imas-live-api/src/routes/lyrics.ts の logLyricsRead)。
    このスクリプトが Cloudflare Workers Observability の Telemetry Query API で
    その行を日ごとに引き、song_id で数えて data/lyrics_requests/YYYY-MM-DD.tsv に書く。

    API: POST /accounts/{account_id}/workers/observability/telemetry/query
      docs: https://developers.cloudflare.com/workers/observability/query-builder/
            https://developers.cloudflare.com/api/resources/workers/subresources/observability/subresources/telemetry/methods/query/

⚠️ Workers Logs の保持期間は無料プランで 3 日。**このバッチが 3 日以上止まると、
   その間のリクエスト回数は取り返せない** (再実行しても API がもう返さない)。
   既定で「昨日から 3 日ぶん」を毎回引き直すのは、1〜2 日の失敗なら次回の実行が
   自動的に埋めるようにするため。同じ日の TSV は上書きなので何度流しても同じ結果になる。

⚠️ ログに載るのは event 名と song_id だけ。uid も IP も歌詞本文も出さない
   (出すと Workers Logs が「誰が何を読んだか」の閲覧履歴になる)。

Usage:
    export CLOUDFLARE_OBSERVABILITY_TOKEN=...      # Workers Observability: Read 権限
    python3 tools/lyrics/collect_request_logs.py                    # 昨日から 3 日ぶん
    python3 tools/lyrics/collect_request_logs.py --date 2026-09-01  # 1 日だけ
    python3 tools/lyrics/collect_request_logs.py --days 3 --dry-run # 書かずに件数だけ
"""

import argparse
import datetime as dt
import json
import os
import sys
import time
import urllib.error
import urllib.request

ACCOUNT_ID = "0baf14f22a0bffdbb33931ce7edebb20"
SCRIPT_NAME = "imas-live-api"
API_BASE = "https://api.cloudflare.com/client/v4"

# Workers Logs の dataset。Query Builder が既定で見ているものと同じ。
DATASET = "cloudflare-workers"

# Worker 側 (logLyricsRead) と 1:1 の契約。変えるなら両方同時に変えること。
EVENT_NAME = "lyrics_read"

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
DEFAULT_OUT_DIR = os.path.join(REPO, "data", "lyrics_requests")

# 1 リクエストで取る件数。API の上限より控えめにして、ページングで回す。
PAGE_SIZE = 500
# 1 日あたりの取得上限 (無限ループ防止)。超えたら警告して打ち切る。
MAX_PAGES_PER_DAY = 400
# 429 / 5xx のときの待ち時間 (秒)。指数で伸ばす。
RETRY_WAITS = [2, 5, 15, 45]


class ApiError(RuntimeError):
    pass


def iso_day(d):
    return d.strftime("%Y-%m-%d")


def day_bounds_ms(day):
    """その日 (UTC) の [00:00:00, 翌日00:00:00) を epoch ミリ秒で返す。

    UTC で切るのは、Workers Logs のタイムスタンプが UTC だから。JST で切ると
    日境界の 9 時間ぶんが隣の日に混ざり、報告の期間合計は同じでも日次 TSV が
    「その日の利用」を表さなくなる。
    """
    start = dt.datetime.combine(day, dt.time.min, tzinfo=dt.timezone.utc)
    end = start + dt.timedelta(days=1)
    return int(start.timestamp() * 1000), int(end.timestamp() * 1000)


def build_query(from_ms, to_ms, cursor=None):
    """Telemetry Query API のリクエストボディ。

    view="events" で生ログを引き、song_id はこちら側で数える。サーバ側の
    groupBy を使わないのは、`console.log(JSON.stringify(...))` の中身が
    $metadata.message の**文字列**であって、song_id が独立した索引キーとして
    存在する保証がないため。文字列を自分で JSON パースする方が、
    ログの載り方 (構造化されるか否か) に依存しない。
    """
    body = {
        # 保存クエリではなくその場のクエリ。API は queryId を必須で要求する。
        "queryId": "imas-lyrics-read",
        "timeframe": {"from": from_ms, "to": to_ms},
        "parameters": {
            "datasets": [DATASET],
            "filters": [
                {
                    "key": "$metadata.service",
                    "type": "string",
                    "operation": "eq",
                    "value": SCRIPT_NAME,
                },
                {
                    "key": "$metadata.message",
                    "type": "string",
                    "operation": "includes",
                    "value": EVENT_NAME,
                },
            ],
            "limit": PAGE_SIZE,
        },
        "view": "events",
        "limit": PAGE_SIZE,
    }
    if cursor:
        # $metadata.id をカーソルに使う (API リファレンスの offset の説明どおり)。
        body["offset"] = cursor
        body["offsetDirection"] = "next"
    return body


def post_query(token, body, opener=None):
    """API を 1 回叩く。429 / 5xx は待って再試行する。"""
    url = "%s/accounts/%s/workers/observability/telemetry/query" % (API_BASE, ACCOUNT_ID)
    payload = json.dumps(body).encode("utf-8")
    send = opener or _urlopen_json
    last = None
    for wait in RETRY_WAITS + [None]:
        try:
            return send(url, payload, token)
        except ApiError as e:
            last = e
            if wait is None or not getattr(e, "retryable", False):
                raise
            print("  API が %s。%d 秒待って再試行" % (e, wait), file=sys.stderr)
            time.sleep(wait)
    raise last


def _urlopen_json(url, payload, token):
    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Authorization": "Bearer %s" % token,
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            return json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:500]
        err = ApiError("HTTP %d: %s" % (e.code, detail))
        # 429 (レート制限) と 5xx は時間で解決する。4xx は設定の誤りなので即座に落とす。
        err.retryable = e.code == 429 or 500 <= e.code < 600
        raise err
    except urllib.error.URLError as e:
        err = ApiError("接続失敗: %s" % e.reason)
        err.retryable = True
        raise err


def parse_event(event):
    """1 イベントから song_id を取り出す。lyrics_read でなければ None。

    ⚠️ Worker 側 logLyricsRead の出力形式と 1:1。片方だけ変えると集計が 0 になる。
    """
    meta = event.get("$metadata") or {}
    message = meta.get("message")
    if not isinstance(message, str):
        return None
    try:
        payload = json.loads(message)
    except (ValueError, TypeError):
        # 他のログ (単なる文字列) が includes フィルタに引っかかることはある。数えない。
        return None
    if not isinstance(payload, dict) or payload.get("event") != EVENT_NAME:
        return None
    song_id = payload.get("song_id")
    return song_id if isinstance(song_id, str) and song_id else None


def extract_events(response):
    """API 応答から events 配列を取り出す。形が違えば空配列 (落とさない)。"""
    if not isinstance(response, dict):
        return []
    if response.get("success") is False:
        raise ApiError("API errors=%s" % json.dumps(response.get("errors"), ensure_ascii=False))
    result = response.get("result") or {}
    events = (result.get("events") or {}).get("events")
    return events if isinstance(events, list) else []


def collect_day(token, day, opener=None):
    """1 日ぶんを song_id → 回数 に畳む。"""
    from_ms, to_ms = day_bounds_ms(day)
    counts = {}
    cursor = None
    total = 0
    # イベント ID で重複を落とす。カーソル (offset) がその行を含む向きに動くと
    # ページの境目が 1 件重なり、その曲だけ回数が水増しされる。報告に出す数なので
    # 「同じログを 2 回数えない」ことを API の挙動に頼らず自分で担保する。
    seen_ids = set()
    for page in range(MAX_PAGES_PER_DAY):
        response = post_query(token, build_query(from_ms, to_ms, cursor), opener)
        events = extract_events(response)
        if not events:
            break
        for event in events:
            event_id = (event.get("$metadata") or {}).get("id")
            if event_id:
                if event_id in seen_ids:
                    continue
                seen_ids.add(event_id)
            total += 1
            song_id = parse_event(event)
            if song_id:
                counts[song_id] = counts.get(song_id, 0) + 1
        if len(events) < PAGE_SIZE:
            break
        next_cursor = ((events[-1].get("$metadata") or {}).get("id"))
        if not next_cursor or next_cursor == cursor:
            # カーソルが進まないなら同じページを引き続けることになる。止める。
            print("  ⚠️ カーソルが進まないのでページングを打ち切る (%d 件)" % total,
                  file=sys.stderr)
            break
        cursor = next_cursor
    else:
        print("  ⚠️ %s: ページ上限 %d に達した。取りこぼしがある可能性がある"
              % (iso_day(day), MAX_PAGES_PER_DAY), file=sys.stderr)
    return counts, total


def write_tsv(path, counts):
    """song_id と回数の TSV。同じ日は上書き = 何度流しても同じ結果 (冪等)。"""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # 多い順、同数は song_id 順。差分が読みやすく、再実行で行が入れ替わらない。
    rows = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("song_id\tcount\n")
        for song_id, n in rows:
            f.write("%s\t%d\n" % (song_id, n))


def target_days(args):
    if args.date:
        try:
            return [dt.date.fromisoformat(args.date)]
        except ValueError:
            sys.exit("--date は YYYY-MM-DD 形式: %r" % args.date)
    today = dt.datetime.now(dt.timezone.utc).date()
    # 昨日を起点に遡る (今日はまだ終わっていないので数えない)。
    return [today - dt.timedelta(days=i) for i in range(1, args.days + 1)]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--date", help="集計する日 (YYYY-MM-DD)。指定すると --days は無視")
    ap.add_argument("--days", type=int, default=3,
                    help="昨日から遡る日数 (既定 3 = Workers Logs の保持期間)")
    ap.add_argument("--out-dir", default=DEFAULT_OUT_DIR, help="TSV の出力先")
    ap.add_argument("--dry-run", action="store_true", help="TSV を書かず件数だけ表示する")
    args = ap.parse_args(argv)

    if args.days < 1:
        sys.exit("--days は 1 以上")

    token = os.environ.get("CLOUDFLARE_OBSERVABILITY_TOKEN")
    if not token:
        sys.exit("CLOUDFLARE_OBSERVABILITY_TOKEN が未設定 "
                 "(Workers Observability: Read 権限の API トークン)")

    grand = 0
    for day in target_days(args):
        counts, seen = collect_day(token, day)
        total = sum(counts.values())
        grand += total
        path = os.path.join(args.out_dir, "%s.tsv" % iso_day(day))
        if args.dry_run:
            print("%s: %d 曲 / %d 回 (ログ %d 件) — dry-run なので書かない"
                  % (iso_day(day), len(counts), total, seen))
            continue
        write_tsv(path, counts)
        print("%s: %d 曲 / %d 回 → %s" % (iso_day(day), len(counts), total, path))

    print("合計 %d 回" % grand)
    return 0


if __name__ == "__main__":
    sys.exit(main())
