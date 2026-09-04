#!/usr/bin/env python3
"""set_status.py — 投入済みの歌詞の公開状態をまとめて切り替える。

Usage:
    # 何が変わるか見るだけ
    python3 tools/lyrics/set_status.py --verified --status published

    # 実際に切り替える
    python3 tools/lyrics/set_status.py --verified --status published --apply

    # 曲を名指しで
    python3 tools/lyrics/set_status.py cg_star ml_thank_you --status draft --apply

`push_lyrics.py` は歌詞本文の投入用で、1曲ずつ全文を送り直す。既に入っている
歌詞の公開状態だけを変えたいときにそれを使うと、本文と転置インデックスを
無駄に書き直すうえ曲数ぶん HTTP を叩くことになる。ここは
`POST /admin/lyrics/status` を叩いて status だけを更新する。

## --verified が選ぶもの

`links.tsv` の `confidence` が `high` の曲だけ。曲数の制限ではなく**中身**の理由:

- `low`       — 候補ページのタイトルに曲名が無い。同名の別曲を掴んでいる疑いが残る。
- `cover`     — カバー曲。**外国作品が混じりうる**。JASRAC は「外国作品の歌詞・楽譜の
                利用をする場合」「非商用配信の取扱いが出来かねます。」としている。
- `not_found` — 本文が無い。

いずれも1件ずつ確かめれば公開してよいものが混ざっているので、`--all` や
song_id 直指定で個別に出せる。
"""

import argparse
import csv
import glob
import io
import json
import os
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
LINKS = os.path.join(HERE, "links.tsv")
JSON_DIR = os.path.join(REPO, "lyrics_local", "lyrics")
TOKEN_PATH = os.path.expanduser("~/.config/imas/lyrics_push_token")
DEFAULT_BASE_URL = "https://imas-live-api.tokata3011.workers.dev"

# サーバ側 MAX_STATUS_IDS と同値。手元で分割してから送る。
# (D1 のバインド変数上限 100 個から逆算した値)
CHUNK = 90

# ⚠️ UA は必ず送る。urllib の既定 (python-urllib/*) は 403 で弾かれる。
UA = "imas-lyrics-push/1.0"


def read_token(path):
    if not os.path.exists(path):
        sys.exit("トークンが無い: %s" % path)
    with io.open(path, encoding="utf-8") as f:
        return f.read().strip()


def confidence_map():
    out = {}
    with io.open(LINKS, encoding="utf-8") as f:
        r = csv.reader(f, delimiter="\t")
        next(r, None)
        for row in r:
            if len(row) > 7:
                out[row[0]] = row[7]
    return out


def local_song_ids():
    """投入済みの候補 = 手元に歌詞 JSON があるもの。"""
    return sorted(
        os.path.splitext(os.path.basename(p))[0]
        for p in glob.glob(os.path.join(JSON_DIR, "*.json"))
    )


def post(base_url, token, song_ids, status):
    req = urllib.request.Request(
        base_url.rstrip("/") + "/admin/lyrics/status",
        data=json.dumps({"song_ids": song_ids, "status": status}).encode("utf-8"),
        headers={"Content-Type": "application/json", "X-Push-Token": token,
                 "User-Agent": UA},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as res:
            return res.status, json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except urllib.error.URLError as e:
        return 0, str(e)


def counts(base_url, token):
    """GET /admin/lyrics/quota。song_lyrics の全件集計なので 1 回で約 2,800 行読む。

    年次利用曲目報告の母集団を掴むための表示であって、状態変更に必須ではない。
    D1 の読み取り枠を無駄に食わないよう --show-quota のときだけ呼ぶ。
    """
    req = urllib.request.Request(
        base_url.rstrip("/") + "/admin/lyrics/quota",
        headers={"X-Push-Token": token, "User-Agent": UA},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            return json.loads(res.read().decode("utf-8"))
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser(description="歌詞の公開状態をまとめて切り替える")
    ap.add_argument("song_ids", nargs="*", help="対象の song_id")
    ap.add_argument("--verified", action="store_true",
                    help="links.tsv の confidence=high の曲すべて")
    ap.add_argument("--all", action="store_true", help="手元に JSON がある曲すべて")
    ap.add_argument("--status", required=True, choices=["draft", "published"])
    ap.add_argument("--base-url", default=DEFAULT_BASE_URL)
    ap.add_argument("--token-path", default=TOKEN_PATH)
    ap.add_argument("--show-quota", action="store_true",
                    help="前後の掲載曲数を表示する "
                         "(song_lyrics の全件集計なので毎回は叩かない)")
    ap.add_argument("--apply", action="store_true",
                    help="実際に送る。付けない限り dry-run")
    args = ap.parse_args()

    ids = list(args.song_ids)
    if args.verified or args.all:
        conf = confidence_map()
        for sid in local_song_ids():
            if args.all or conf.get(sid) == "high":
                ids.append(sid)
    ids = list(dict.fromkeys(ids))
    if not ids:
        sys.exit("対象が無い。song_id を指定するか --verified / --all を付ける。")

    token = read_token(args.token_path)
    before = counts(args.base_url, token) if args.show_quota else None
    if before:
        print("現在: published %d / draft %d" % (before["published"], before["draft"]))
    print("[%s] %s → %d 曲を %s にする"
          % ("APPLY" if args.apply else "DRY-RUN", args.base_url, len(ids), args.status))

    if not args.apply:
        print("\n(dry-run。実際に送るには --apply)")
        return

    updated = 0
    for i in range(0, len(ids), CHUNK):
        chunk = ids[i:i + CHUNK]
        status, body = post(args.base_url, token, chunk, args.status)
        if status != 200:
            print("  ✗ HTTP %s: %s" % (status, body))
            sys.exit(1)
        updated += body["updated"]
        print("  %d/%d 件送信 (変更 %d)" % (min(i + CHUNK, len(ids)), len(ids), body["updated"]))

    after = counts(args.base_url, token) if args.show_quota else None
    print("\n変更 %d 曲" % updated)
    if after:
        print("現在: published %d / draft %d" % (after["published"], after["draft"]))


if __name__ == "__main__":
    main()
