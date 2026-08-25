#!/usr/bin/env python3
"""build_gram_index.py — 歌詞検索の転置インデックス (lyrics_gram_index) を作り直す。

Usage:
    # D1 の歌詞から SQL を組み立てて適用する
    python3 tools/lyrics/build_gram_index.py --apply

    # SQL を書き出すだけ (中身を見たいとき)
    python3 tools/lyrics/build_gram_index.py --out /tmp/gram.sql

    # 手元の lyrics_local から作る (D1 を読まない。push 前の確認用)
    python3 tools/lyrics/build_gram_index.py --from-local --out /tmp/gram.sql

入力は既定で **D1 の song_lyrics.body_norm** (表記ゆれを吸収した検索用のコピー)。
検索側も正規化した語で引くので、索引も正規化後の本文から作らないと候補が合わない。
lyrics_local ではなく D1 を正とするのは、アプリからの編集などローカルに無い更新が
入りうるため。

⚠️ 全消し全入れで作り直す。差分更新にしないのは、歌詞1曲で 2-gram が 900 種類
   ほどあり、投入のたびに 900 行の read-modify-write が走って D1 無料枠の
   書き込み (10万行/日) をすぐ食い潰すため。再構築1回で約 67,000 行使う。
   **1日に2回は流せない。**

⚠️ このインデックスは近似で、routes/lyrics.ts が候補を body LIKE で必ず検証する。
   古いままでも誤ヒットは出ず、「出るはずの曲が出ない」側にだけズレる。
"""

import argparse
import json
import os
import subprocess
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
API_DIR = os.path.join(REPO, "imas-live-api")
LOCAL_DIR = os.path.join(REPO, "lyrics_local", "lyrics")
D1_NAME = "imas-live-db"

# 1文 INSERT の上限バイト数。D1 の 1 SQL 文の上限は 100KB 程度で、これを超えると
# SQLITE_TOOBIG になる。行数で区切ると壊れる (posting の長さが gram によって桁違い)
# ので、必ずバイト数で区切る。
MAX_STATEMENT_BYTES = 60_000

# 1行 (= 1 part) に入れる posting の上限バイト数。
# 「い」だけで 60KB あり、1行に押し込むと 1 文がそれだけで上限に当たる。
# part に分割して、1文に複数行を詰められる大きさに保つ。
MAX_POSTING_BYTES = 20_000


def sql_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def read_from_d1() -> list[tuple[str, str]]:
    """D1 から (song_id, body) を読む。"""
    print("[read] D1 から歌詞を取得中...", file=sys.stderr)
    proc = subprocess.run(
        ["npx", "wrangler", "d1", "execute", D1_NAME, "--remote", "--json",
         "--command", "SELECT song_id, body_norm AS body FROM song_lyrics WHERE body_norm != ''"],
        cwd=API_DIR, capture_output=True, text=True,
    )
    if proc.returncode != 0:
        print(proc.stderr[-2000:], file=sys.stderr)
        raise SystemExit("D1 の読み取りに失敗した")
    # wrangler は JSON の前に警告を出すことがあるので、最初の '[' から読む。
    start = proc.stdout.find("[")
    payload = json.loads(proc.stdout[start:])
    rows = payload[0]["results"]
    return [(r["song_id"], r["body"] or "") for r in rows]


def read_from_local() -> list[tuple[str, str]]:
    import glob
    out = []
    for path in sorted(glob.glob(os.path.join(LOCAL_DIR, "*.json"))):
        with open(path, encoding="utf-8") as f:
            doc = json.load(f)
        body = "\n".join(l["text"] for l in doc["lines"] if l.get("kind") == "lyric")
        if body:
            out.append((doc["song_id"], body))
    return out


def build_index(rows: list[tuple[str, str]]) -> dict[str, list[str]]:
    """song_id ごとに 1-gram / 2-gram を集めて gram -> [song_id] に反転する。"""
    index: dict[str, set[str]] = defaultdict(set)
    for song_id, body in rows:
        # 改行をまたぐ gram は作らない。行をまたいだ並びは歌詞として連続していない。
        for line in body.split("\n"):
            for ch in set(line):
                index[ch].add(song_id)
            for i in range(len(line) - 1):
                index[line[i:i + 2]].add(song_id)
    # song_id を並べておくと差分が読める (投入順は結果に影響しない)。
    return {gram: sorted(ids) for gram, ids in index.items()}


def split_posting(song_ids: list[str]) -> list[list[str]]:
    """posting を 1 行に収まる大きさに割る。読む側が連結し直す。"""
    chunks: list[list[str]] = [[]]
    size = 0
    for song_id in song_ids:
        length = len(song_id.encode()) + 1
        if size and size + length > MAX_POSTING_BYTES:
            chunks.append([])
            size = 0
        chunks[-1].append(song_id)
        size += length
    return chunks


def build_sql(index: dict[str, list[str]]) -> str:
    """全消し全入れの SQL。

    DELETE ではなくテーブルごと作り直すのは、D1 が**削除も行書き込みに数える**ため。
    DELETE + INSERT だと 67,071 × 2 = 134,142 行になり、無料枠の 10万行/日 を超える。
    DDL は行書き込みに計上されないので、作り直せば INSERT 分の 67,071 行で済む。

    さらに別名で作ってから差し替える。途中で失敗しても本番のテーブルが
    半端な状態にならない。索引が欠けた状態は「該当なし」を返してしまい、
    全走査へのフォールバックも効かないので、中途半端が一番まずい。

    ⚠️ CREATE 文は migrations/0029_lyrics_gram_index.sql と同じ定義にすること。
    """
    parts = [
        "DROP TABLE IF EXISTS lyrics_gram_index_new;",
        "CREATE TABLE lyrics_gram_index_new ("
        "  gram TEXT NOT NULL,"
        "  part INTEGER NOT NULL DEFAULT 0,"
        "  song_ids TEXT NOT NULL,"
        "  PRIMARY KEY (gram, part)"
        ") WITHOUT ROWID;",
    ]
    prefix = "INSERT INTO lyrics_gram_index_new (gram, part, song_ids) VALUES "
    batch: list[str] = []
    size = 0

    def flush() -> None:
        nonlocal batch, size
        if batch:
            parts.append(prefix + ",".join(batch) + ";")
            batch, size = [], 0

    for gram in sorted(index):
        for part, chunk in enumerate(split_posting(index[gram])):
            value = f"({sql_quote(gram)},{part},{sql_quote(chr(10).join(chunk))})"
            if size and size + len(value.encode()) > MAX_STATEMENT_BYTES:
                flush()
            batch.append(value)
            size += len(value.encode()) + 1
    flush()
    parts.append("DROP TABLE IF EXISTS lyrics_gram_index;")
    parts.append("ALTER TABLE lyrics_gram_index_new RENAME TO lyrics_gram_index;")
    return "\n".join(parts) + "\n"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--from-local", action="store_true",
                    help="D1 ではなく lyrics_local/lyrics/*.json から作る")
    ap.add_argument("--out", help="SQL の書き出し先")
    ap.add_argument("--apply", action="store_true", help="D1 に適用する")
    args = ap.parse_args()

    rows = read_from_local() if args.from_local else read_from_d1()
    if not rows:
        raise SystemExit("歌詞が1件も取れなかった。中断する。")

    index = build_index(rows)
    postings = sum(len(v) for v in index.values())
    print(f"[build] 曲 {len(rows):,} / gram {len(index):,} 種類 / posting {postings:,}",
          file=sys.stderr)
    # 作り直しなので書き込みは INSERT 分だけ (DDL は行書き込みに計上されない)。
    rows_out = sum(len(split_posting(ids)) for ids in index.values())
    print(f"[build] D1 書き込み見込み: 約 {rows_out:,} 行 (無料枠 10万行/日)",
          file=sys.stderr)

    sql = build_sql(index)
    path = args.out or os.path.join(REPO, "lyrics_local", "gram_index.sql")
    with open(path, "w", encoding="utf-8") as f:
        f.write(sql)
    print(f"[build] {path} に書き出した ({len(sql) / 1_000_000:.1f} MB)", file=sys.stderr)

    if not args.apply:
        print("\n(--apply を付けると D1 に適用する)", file=sys.stderr)
        return

    print("[apply] D1 に適用中...", file=sys.stderr)
    proc = subprocess.run(
        ["npx", "wrangler", "d1", "execute", D1_NAME, "--remote", "--file", path],
        cwd=API_DIR, text=True,
    )
    if proc.returncode != 0:
        raise SystemExit("適用に失敗した")
    print("[apply] 完了", file=sys.stderr)


if __name__ == "__main__":
    main()
