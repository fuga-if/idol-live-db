#!/usr/bin/env python3
"""export_links_json.py — 確定した歌詞リンクを data/fixes の JSON に書き出す。

Usage:
    python3 tools/lyrics/export_links_json.py            # 標準出力に出す (確認用)
    python3 tools/lyrics/export_links_json.py --apply    # data/fixes/ に書く
    python3 tools/lyrics/export_links_json.py --min-confidence high

DB を直接書き換えず JSON を経由するのは、このリポジトリの既存の作法に合わせるため。
data/fixes/*.json → tools/apply_data.py --check → --apply → --push という経路を通ると、
PR の履歴がそのまま監査ログになる。

出力後の手順:
    python3 tools/apply_data.py --check     # 検証だけ
    python3 tools/apply_data.py --apply     # ローカル master.sqlite に反映
    python3 tools/apply_data.py --apply --push --production   # CloudKit へ
"""

import argparse
import json
import os
import re
import sys

URL_RE = re.compile(r"^https?://", re.IGNORECASE)

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
LINKS_TSV = os.path.join(HERE, "links.tsv")
FIXES_DIR = os.path.join(REPO, "data", "fixes")


def read_tsv(path):
    if not os.path.exists(path):
        sys.exit("links.tsv がない: %s" % path)
    with open(path, encoding="utf-8") as f:
        header = f.readline().rstrip("\n").split("\t")
        rows = []
        for line in f:
            if not line.strip():
                continue
            v = line.rstrip("\n").split("\t")
            v += [""] * (len(header) - len(v))
            rows.append(dict(zip(header, v)))
    return rows


def build(rows, min_confidence):
    # cover はカバー曲で「原曲アーティストのページと思われる」もの。
    # 候補としては妥当だが、公有曲 (ジングルベル等) は同名の別アレンジが
    # 大量にあるため自動では出さない。--min-confidence cover で明示的に含められる。
    order = {"high": 3, "cover": 2, "low": 2, "ambiguous": 1, "not_found": 0, "": 0}
    threshold = order.get(min_confidence, 3)

    fixes = []
    for r in rows:
        url = r.get("candidate_url", "").strip()
        if not URL_RE.match(url):
            continue
        if order.get(r.get("confidence", ""), 0) < threshold:
            continue
        # 既に同じ URL が入っているなら出さない (冪等)
        if r.get("lyrics_url", "").strip() == url:
            continue
        fixes.append({
            "table": "songs",
            "id": r["song_id"],
            "fields": {"lyrics_url": url},
            "source": url,
            "note": "歌詞サイトの該当ページ。%s / 判定=%s (%s)"
                    % (r.get("candidate_title", "")[:80],
                       r.get("confidence", ""), r.get("note", "")),
        })
    return fixes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--links", default=LINKS_TSV)
    ap.add_argument("--apply", action="store_true", help="data/fixes/ に書き出す")
    ap.add_argument("--min-confidence", default="high",
                    choices=["high", "cover", "low", "ambiguous"],
                    help="この確度以上だけ出す (既定: high)")
    ap.add_argument("--out-name", default="lyrics_url_links.json")
    args = ap.parse_args()

    rows = read_tsv(args.links)
    fixes = build(rows, args.min_confidence)

    doc = {
        "title": "楽曲の歌詞ページへのリンクを登録する",
        "author": "",
        "_note": "リンクは掲載ではないので JASRAC 許諾は不要。"
                 "候補の発見は検索エンジンの結果からのみ行い、"
                 "歌詞サイトのサーバには直接アクセスしていない。",
        "fixes": fixes,
    }

    text = json.dumps(doc, ensure_ascii=False, indent=2) + "\n"

    if args.apply:
        os.makedirs(FIXES_DIR, exist_ok=True)
        path = os.path.join(FIXES_DIR, args.out_name)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("wrote %s (%d件)" % (path, len(fixes)), file=sys.stderr)
        print("\n次の手順:", file=sys.stderr)
        print("  python3 tools/apply_data.py --check", file=sys.stderr)
        print("  python3 tools/apply_data.py --apply", file=sys.stderr)
    else:
        sys.stdout.write(text)
        print("\n(%d件。--apply で data/fixes/ に書き出す)" % len(fixes), file=sys.stderr)


if __name__ == "__main__":
    main()
