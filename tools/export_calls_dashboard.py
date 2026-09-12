#!/usr/bin/env python3
"""コールガイドの進捗 (Worker の GET /calls/dashboard) を写して db/calls_dashboard.json に置く。

これは何か
    Web の出面 (`/calls/`) はビルド時にこの写しを焼き込む。閲覧のたびに Worker や D1 は
    読まない (ランニングコスト 0 の原則)。写しは Worker の応答そのもの (曲 id・件数・日時・
    マスク済みの表示名だけ。歌詞もコール本文も uid も含まない — 含まないことは Worker 側の
    テストが固定している)。

使い方
    python3 tools/export_calls_dashboard.py            # 本番の公開エンドポイントから取る
    python3 tools/export_calls_dashboard.py --url http://127.0.0.1:8787/calls/dashboard
    出力先: db/calls_dashboard.json (git 管理。community.sql と同じく日次で更新する)
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "db" / "calls_dashboard.json"
DEFAULT_URL = "https://imas-live-api.tokata3011.workers.dev/calls/dashboard"
# Worker が返す鍵。これ以外 (本文や uid) が混ざったら壊れているので書かない。
EXPECTED_KEYS = {"generatedAt", "songsWithCalls", "recentEdits", "taggedWithoutCalls", "callTag"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default=DEFAULT_URL)
    args = ap.parse_args()
    # Python 既定の UA は Cloudflare に 403 で弾かれる (curl は通る)。名乗りを付ける。
    req = urllib.request.Request(
        args.url,
        headers={"Accept": "application/json", "User-Agent": "imas-live-db-export/1.0 (+https://idollivedb.fugalabs.uk)"},
    )
    with urllib.request.urlopen(req, timeout=30) as res:
        body = json.load(res)
    if set(body) != EXPECTED_KEYS:
        print(f"応答の鍵が想定と違う: {sorted(body)}", file=sys.stderr)
        return 1
    OUT.write_text(json.dumps(body, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    print(f"{OUT}: ガイドあり {len(body['songsWithCalls'])} / 編集 {len(body['recentEdits'])} / 募集中 {len(body['taggedWithoutCalls'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
