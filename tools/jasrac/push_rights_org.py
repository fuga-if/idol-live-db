#!/usr/bin/env python3
"""works.tsv の rights_org を本番 D1 の song_lyrics.rights_org に写す。

Android 版は当面 NexTone の許諾だけで歌詞を出す (Worker の lyricsAllowedForClient)。
その判定に使う列なので、works.tsv で rights_org を直したらこれを流す。

    python3 tools/jasrac/push_rights_org.py            # 流す SQL を出すだけ
    python3 tools/jasrac/push_rights_org.py --apply    # 本番 D1 に流す

全曲を '' に戻してから NexTone 曲を 'nextone' にする (外した曲が残らないように)。
'jasrac' は JASRAC と同じ扱い (Android では出さない) なので D1 には '' で入れる。
"""
import argparse
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import works_tsv as W  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
WORKS = os.path.join(os.path.dirname(__file__), "works.tsv")
# wrangler の --command は長すぎると落ちるので、id をこの数ずつに分ける。
CHUNK = 80


def statements(rows):
    ids = sorted(r["song_id"] for r in rows if W.reports_to_nextone(r))
    out = ["UPDATE song_lyrics SET rights_org = '' WHERE rights_org != ''"]
    for i in range(0, len(ids), CHUNK):
        quoted = ",".join("'" + s.replace("'", "''") + "'" for s in ids[i:i + CHUNK])
        out.append(f"UPDATE song_lyrics SET rights_org = 'nextone' WHERE song_id IN ({quoted})")
    return ids, out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="本番 D1 に流す")
    args = ap.parse_args()
    ids, sqls = statements(W.read_rows(WORKS))
    print(f"NexTone 管理曲: {len(ids)} 曲 / 文: {len(sqls)}", file=sys.stderr)
    if not args.apply:
        for s in sqls:
            print(s + ";")
        return
    for s in sqls:
        subprocess.run(
            ["npx", "wrangler", "d1", "execute", "imas-live-db", "--remote", "--command", s],
            cwd=os.path.join(ROOT, "imas-live-api"), check=True, stdout=subprocess.DEVNULL,
        )
    print("流しました", file=sys.stderr)


if __name__ == "__main__":
    main()
