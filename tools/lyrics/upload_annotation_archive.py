#!/usr/bin/env python3
"""upload_annotation_archive.py — 歌詞を消したときに退避した注釈を D1 の lyric_annotation_archive に入れる。

Usage:
    # 何が入るか見るだけ (既定。何も書き換えない)
    python3 tools/lyrics/upload_annotation_archive.py db_backups_local/lyrics_annotations_20261006.json

    # 実際に入れる (imas-live-api の wrangler で本番 D1 へ)
    python3 tools/lyrics/upload_annotation_archive.py db_backups_local/lyrics_annotations_20261006.json --apply

    # 入れたあと、既に歌詞が入り直している曲に付け直す
    python3 tools/lyrics/upload_annotation_archive.py db_backups_local/lyrics_annotations_20261006.json --restore SONG_ID ...

退避ファイルは歌詞本文と anchorText を持たない (2026-10-06 の全削除の前に作ったもの)。
歌詞が投稿で入り直すと Worker の storeLyrics が付け直す (imas-live-api/src/lyrics_annotation_archive.ts)。
本文由来で text を除いたコールは戻せないので入れない。

何度流してもよい (song_id で上書き。付け直し済みの印 restored_at は触らない)。
"""

import argparse
import json
import os
import subprocess
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
API_DIR = os.path.join(ROOT, "imas-live-api")
BASE_URL = "https://imas-live-api.tokata3011.workers.dev"
TOKEN_PATH = os.path.expanduser("~/.config/imas/lyrics_push_token")

LINE_FIELDS = ("start_ms", "clap", "layer", "singers", "partBreaks")
CALL_FIELDS = ("id", "start", "end", "text", "emphasis", "timing", "startMs", "stale")


def compact_song(song):
    """注釈のある行だけ、値のある項目だけにする。text の無いコールは捨てる。"""
    lines = []
    for line in song.get("lines") or []:
        entry = {"id": line["id"], "ord": line["ord"], "kind": line["kind"]}
        for f in LINE_FIELDS:
            if line.get(f) not in (None, [], ""):
                entry[f] = line[f]
        calls = [{f: c[f] for f in CALL_FIELDS if c.get(f) is not None}
                 for c in line.get("calls") or [] if c.get("text")]
        if calls:
            entry["calls"] = calls
        if len(entry) > 3:
            lines.append(entry)
    likes = {k: v for k, v in (song.get("likes") or {}).items() if isinstance(v, int) and v > 0}
    return lines, likes


def sql_str(value):
    return "'" + value.replace("'", "''") + "'"


def d1(command):
    out = subprocess.run(
        ["npx", "wrangler", "d1", "execute", "imas-live-db", "--remote", "--yes", "--command", command],
        cwd=API_DIR, capture_output=True, text=True, stdin=subprocess.DEVNULL)
    if out.returncode != 0:
        raise SystemExit(out.stdout[-2000:] + out.stderr[-2000:])


def restore(song_id):
    with open(TOKEN_PATH) as f:
        token = f.read().strip()
    req = urllib.request.Request(
        f"{BASE_URL}/admin/lyrics/{urllib.request.quote(song_id, safe='')}/restore-annotations",
        method="POST", headers={"X-Push-Token": token, "User-Agent": "imas-lyrics-push/1.0"})
    with urllib.request.urlopen(req) as res:
        return json.load(res)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("archive")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--restore", nargs="+", metavar="SONG_ID")
    args = ap.parse_args()

    with open(args.archive) as f:
        data = json.load(f)
    archived_at = os.path.basename(args.archive).rsplit("_", 1)[-1].split(".")[0]
    archived_at = f"{archived_at[:4]}-{archived_at[4:6]}-{archived_at[6:8]}"

    if args.restore:
        for song_id in args.restore:
            print(song_id, restore(song_id))
        return

    rows = []
    for song_id, song in sorted(data["songs"].items()):
        lines, likes = compact_song(song)
        if lines or likes:
            rows.append((song_id, lines, likes))
            parts = sum(1 for l in lines if l.get("singers") or l.get("partBreaks"))
            print(f"{song_id}\tlines={len(lines)}\tparts={parts}\tlikes={len(likes)}")
    print(f"{len(rows)} songs", file=sys.stderr)
    if not args.apply:
        return
    for song_id, lines, likes in rows:
        d1("INSERT INTO lyric_annotation_archive (song_id, lines_json, likes_json, archived_at) "
           f"VALUES ({sql_str(song_id)}, {sql_str(json.dumps(lines, ensure_ascii=False))}, "
           f"{sql_str(json.dumps(likes, ensure_ascii=False))}, {sql_str(archived_at)}) "
           "ON CONFLICT(song_id) DO UPDATE SET lines_json = excluded.lines_json, "
           "likes_json = excluded.likes_json, archived_at = excluded.archived_at")
        print("uploaded", song_id, file=sys.stderr)


if __name__ == "__main__":
    main()
