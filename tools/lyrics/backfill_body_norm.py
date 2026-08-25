#!/usr/bin/env python3
"""backfill_body_norm.py — song_lyrics.body_norm を埋め直す。

Usage:
    python3 tools/lyrics/backfill_body_norm.py            # SQL を書き出すだけ
    python3 tools/lyrics/backfill_body_norm.py --apply    # D1 に適用

body_norm は表記ゆれを吸収した検索用のコピー (migrations 0031)。
以降は PUT /admin/lyrics/:song_id が body と同時に書くので、これは初回の埋め直し用。

⚠️ 正規化は **1文字 → 1文字** の変換だけ。検索は body_norm 上で一致位置を求め、
   その位置で body から窓を切るので、長さの変わる変換を入れるとスニペットが壊れる。
   routes/lyrics.ts の normalizeForSearch と**同じ規則**にすること。
   片方だけ変えると、検索で当たるのに窓が作れない曲が出る。
"""

import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
API_DIR = os.path.join(REPO, "imas-live-api")
OUT_PATH = os.path.join(REPO, "lyrics_local", "body_norm.sql")
D1_NAME = "imas-live-db"

# 1文あたりのバイト上限。D1 は 100KB 程度で SQLITE_TOOBIG になる。
MAX_STATEMENT_BYTES = 60_000


def normalize(text: str) -> str:
    """routes/lyrics.ts の normalizeForSearch と同じ規則。"""
    out = []
    for ch in text:
        code = ord(ch)
        if 0x3041 <= code <= 0x3096:          # ひらがな → カタカナ
            out.append(chr(code + 0x60))
        elif 0xFF01 <= code <= 0xFF5E:        # 全角英数記号 → 半角
            out.append(chr(code - 0xFEE0).lower())
        else:
            out.append(ch.lower())
    return "".join(out)


def sql_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    proc = subprocess.run(
        ["npx", "wrangler", "d1", "execute", D1_NAME, "--remote", "--json",
         "--command", "SELECT song_id, body FROM song_lyrics WHERE body != ''"],
        cwd=API_DIR, capture_output=True, text=True)
    if proc.returncode != 0:
        print(proc.stderr[-1500:], file=sys.stderr)
        raise SystemExit("D1 の読み取りに失敗した")
    rows = json.loads(proc.stdout[proc.stdout.find("["):])[0]["results"]
    print(f"[read] {len(rows)} 曲", file=sys.stderr)

    parts, batch, size = [], [], 0
    for row in rows:
        stmt = (f"UPDATE song_lyrics SET body_norm = {sql_quote(normalize(row['body'] or ''))}"
                f" WHERE song_id = {sql_quote(row['song_id'])};")
        if size and size + len(stmt.encode()) > MAX_STATEMENT_BYTES:
            parts.append("\n".join(batch))
            batch, size = [], 0
        batch.append(stmt)
        size += len(stmt.encode())
    if batch:
        parts.append("\n".join(batch))

    sql = "\n".join(parts) + "\n"
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        f.write(sql)
    print(f"[build] {OUT_PATH} ({len(sql) / 1_000_000:.1f} MB / {len(rows)} 行)", file=sys.stderr)

    if not args.apply:
        print("\n(--apply で D1 に適用する)", file=sys.stderr)
        return

    proc = subprocess.run(
        ["npx", "wrangler", "d1", "execute", D1_NAME, "--remote", "--file", OUT_PATH],
        cwd=API_DIR, text=True)
    if proc.returncode != 0:
        raise SystemExit("適用に失敗した")
    print("[apply] 完了", file=sys.stderr)


if __name__ == "__main__":
    main()
