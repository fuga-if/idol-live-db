#!/usr/bin/env python3
"""file_missing_song_issues.py — find_unregistered_releases.py の候補を GitHub issue にする。

1 曲 1 issue (ラベル edit-request + missing-song)。毎日の収集 (daily-data-crawl) は
edit-request の issue を読んで取り込むので、ここで issue にしておけば、収集の手順を
変えなくても次の収集で自動で足される (確認待ちにしない。間違いはあとで消す)。

同じ曲名の issue (開いていても閉じていても) が既にあれば作らない。対象外の曲は
issue を not planned で閉じれば、二度と出てこない。

Usage:
    python3 tools/find_unregistered_releases.py --json > candidates.json
    python3 tools/file_missing_song_issues.py candidates.json            # 作る
    python3 tools/file_missing_song_issues.py candidates.json --dry-run  # 出すだけ
"""

import argparse
import json
import subprocess
import sys

LABELS = ["edit-request", "missing-song"]
# 毎日の収集は「[修正リクエスト]」をタイトルに含む issue だけを triage-fix-requests で処理する
# (2026-11-11 に「[未登録の曲] 」で立てた #415 が拾われなかった)。
TITLE_PREFIX = "[修正リクエスト] 未登録の曲: "
OLD_PREFIXES = ["[未登録の曲] "]


def gh(*args: str) -> str:
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def existing_titles() -> set:
    out = gh("issue", "list", "--label", "missing-song", "--state", "all",
             "--limit", "1000", "--json", "title")
    titles = set()
    for i in json.loads(out):
        t = i["title"]
        for p in OLD_PREFIXES:
            if t.startswith(p):
                t = TITLE_PREFIX + t[len(p):]
        titles.add(t)
    return titles


def issue_title(c: dict) -> str:
    return f"{TITLE_PREFIX}{c['title']}"


def issue_body(c: dict) -> str:
    lines = [
        "> 新曲の漏れチェック (tools/find_unregistered_releases.py) が見つけた、DB に無い曲です。",
        "> **確認を待たずにそのまま追加してください** (fuga の方針: 基本は自動で入れ、間違っていたらあとで消す)。"
        "ほかの新曲と同じく data/songs/ に JSON を書いて本番まで反映し、この issue を閉じる。",
        "> 歌唱者・初出日・初出は公式 (公式サイト・公式 X・ゲーム内のお知らせ)・Apple Music・下の一覧の表記から埋め、"
        "分からない項目 (作詞・作曲など) は空欄でよい。",
        "> 追加しないのは、アイマスの曲でない・版違い・既に別名で登録済みのときだけ。その場合は理由を書いて not planned で閉じる"
        " (閉じた曲は二度と issue になりません)。",
        "",
        f"**曲名**: {c['title']}",
    ]
    if c.get("source") == "apple_music":
        lines += [
            f"**名義 (Apple Music)**: {c.get('artist', '')}",
            f"**配信日**: {c.get('release', '')}",
            f"**アルバム**: {c.get('album', '')}",
            f"**Apple Music**: https://music.apple.com/jp/song/{c['track_id']} "
            f"(track {c['track_id']} / album {c.get('album_id', '')})",
            "**見つけた経路**: 登録済みの曲の歌い手の新しい配信",
        ]
    else:
        lines += [
            f"**区分**: {' '.join(c.get('classes', []))}",
            f"**歌唱 (一覧の表記)**: {c.get('singer', '')}",
            f"**日付 (一覧の表記)**: {c.get('date', '')}",
            f"**初出 (一覧の表記)**: {c.get('note', '')}",
            f"**見つけた経路**: ファンの曲一覧 ({c.get('source_url', '')})。値は公式で確かめること",
        ]
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("candidates", help="find_unregistered_releases.py --json の出力")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(args.candidates, encoding="utf-8") as f:
        cands = json.load(f)
    seen = set() if args.dry_run else existing_titles()
    made = 0
    for c in cands:
        t = issue_title(c)
        if t in seen:
            continue
        seen.add(t)
        if args.dry_run:
            print(f"--- {t}\n{issue_body(c)}")
            continue
        cmd = ["issue", "create", "--title", t, "--body", issue_body(c)]
        for label in LABELS:
            cmd += ["--label", label]
        print(gh(*cmd).strip())
        made += 1
    print(f"候補 {len(cands)} 曲 / issue を作った {made} 件", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
