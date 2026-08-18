#!/usr/bin/env python3
"""link_song_variants.py — 別バージョン曲を親曲へ紐付ける (songs.parent_song_id)。

Usage:
    python3 tools/link_song_variants.py                 # 提案を出すだけ
    python3 tools/link_song_variants.py --write         # data/fixes/ に書き出す

`parent_song_id` は既に「派生曲」を表す列で、一覧・カレンダー・統計・クイズが
`parent_song_id IS NULL` で除外している (AppDatabase+SongQueries.swift ほか)。
ただし埋まっているのは Remix / REM@STER 系だけで、ソロの「〜 Ver.」が抜けていた。
「Crossing!」だけで 15 バージョンが一覧に並ぶのはこのため。

判定規則:
    曲名の末尾から修飾 (括弧書き / ダッシュ囲み) を剥がしたものが、
    **同じブランドに曲として実在する**なら、その曲の派生とみなす。

    「実在する」を条件にしているのが肝で、これが無いと `Do-Dai` や
    `恋だもん〜初級編〜` のような「括弧やダッシュを含むだけの独立した曲名」を
    巻き込む。素の曲名が別に存在することを、派生であることの根拠にしている。

⚠️ 曲名だけで判断するので、同名異曲 (別ブランドの同名) は対象外にしている。
   ブランドをまたぐ紐付けが要る場合は手で足すこと。
"""

import argparse
import json
import os
import re
import sqlite3
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DB_PATH = os.path.join(REPO, "ImasLiveDB", "Resources", "master.sqlite")
OUT_PATH = os.path.join(REPO, "data", "fixes", "song_variant_parents.json")

# 末尾の修飾を剥がす。括弧書き (全角/半角/角) と、ダッシュ・波ダッシュで囲んだもの。
SUFFIX = re.compile(
    r"^(?P<base>.+?)\s*(?:[(（\[].*?[)）\]]|[-–—~〜―]\s*[^-–—~〜―]+\s*[-–—~〜―]?)\s*$"
)


def normalize(title: str) -> str:
    """比較用。空白と大小文字の揺れだけ吸収する (それ以上は同一視しない)。"""
    return re.sub(r"\s+", "", title).lower()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help=f"{OUT_PATH} に書き出す")
    args = ap.parse_args()

    db = sqlite3.connect(DB_PATH)
    rows = db.execute(
        "SELECT id, title, brand_id, song_type, parent_song_id FROM songs"
    ).fetchall()

    by_title: dict[tuple, list[str]] = defaultdict(list)
    for song_id, title, brand_id, _type, _parent in rows:
        by_title[(brand_id, normalize(title))].append(song_id)

    proposals: list[dict] = []
    skipped_no_base: list[str] = []
    for song_id, title, brand_id, _type, parent in rows:
        if parent:
            continue  # 既に紐付いている
        match = SUFFIX.match(title)
        if not match:
            continue
        base = match.group("base").strip()
        if not base or normalize(base) == normalize(title):
            continue
        candidates = [i for i in by_title.get((brand_id, normalize(base)), []) if i != song_id]
        if not candidates:
            skipped_no_base.append(title)
            continue
        if len(candidates) > 1:
            # 素の曲名が複数ある = どれが親か決められない。手で判断する。
            skipped_no_base.append(f"{title} (親候補が複数: {candidates})")
            continue
        proposals.append({
            "table": "songs",
            "id": song_id,
            "fields": {"parent_song_id": candidates[0]},
            "source": "曲名の派生規則 (tools/link_song_variants.py)",
            "note": f"「{title}」は「{base}」の別バージョン。一覧では親にまとめる。",
        })

    # 親が更に親を持つ場合は根まで辿る (派生の派生を作らない)。
    parent_of = {p["id"]: p["fields"]["parent_song_id"] for p in proposals}
    existing = {r[0]: r[4] for r in rows if r[4]}
    parent_of.update(existing)
    for p in proposals:
        seen = {p["id"]}
        root = p["fields"]["parent_song_id"]
        while root in parent_of and parent_of[root] not in seen:
            seen.add(root)
            root = parent_of[root]
        p["fields"]["parent_song_id"] = root

    by_parent: dict[str, int] = defaultdict(int)
    for p in proposals:
        by_parent[p["fields"]["parent_song_id"]] += 1

    print(f"全 {len(rows)} 曲 / 既に紐付け済み {sum(1 for r in rows if r[4])} 曲")
    print(f"新たに紐付ける: {len(proposals)} 曲 ({len(by_parent)} 親)")
    print(f"括弧付きだが素の曲名が無く、独立扱いにした: {len(skipped_no_base)} 曲")
    print()
    print("=== まとまる数が多い親 上位10 ===")
    titles = {r[0]: r[1] for r in rows}
    for parent_id, count in sorted(by_parent.items(), key=lambda kv: -kv[1])[:10]:
        print(f"  {count:>3} 件 → {titles.get(parent_id, parent_id)}")

    if not args.write:
        print("\n(--write で data/fixes/ に書き出す)")
        return

    doc = {
        "title": "別バージョン曲の親曲紐付け",
        "author": "",
        "_note": "一覧・カレンダー・統計は parent_song_id IS NULL で派生曲を除外する。"
                 "ここを埋めることで「Crossing!」のソロ15種などが親1件にまとまる。",
        "fixes": proposals,
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"\n{OUT_PATH} に {len(proposals)} 件書き出した")


if __name__ == "__main__":
    main()
