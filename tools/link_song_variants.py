#!/usr/bin/env python3
"""link_song_variants.py — 別バージョン曲を親曲へ紐付ける (songs.parent_song_id)。

Usage:
    python3 tools/link_song_variants.py                 # 提案を出すだけ
    python3 tools/link_song_variants.py --write         # data/fixes/ に書き出す

`parent_song_id` は既に「派生曲」を表す列で、一覧・カレンダー・統計・クイズが
`parent_song_id IS NULL` で除外している (AppDatabase+SongQueries.swift ほか)。
ただし埋まっているのは Remix / REM@STER 系だけで、ソロの「〜 Ver.」が抜けていた。
「Crossing!」だけで 15 バージョンが一覧に並ぶのはこのため。

判定は2系統。どちらかに当たれば候補にする。

  (1) 曲名規則
      曲名の末尾から修飾 (括弧書き / ダッシュ囲み) を剥がしたものが、
      **同じブランドに曲として実在する**なら、その曲の派生とみなす。

      「実在する」を条件にしているのが肝で、これが無いと `Do-Dai` や
      `恋だもん〜初級編〜` のような「括弧やダッシュを含むだけの独立した曲名」を
      巻き込む。素の曲名が別に存在することを、派生であることの根拠にしている。

  (2) 歌詞一致 (lyrics_local がある場合のみ)
      歌詞本文が完全一致する曲どうしは同じ作品の別バージョン。曲名規則が
      拾えない表記ゆれ (`隣に…` と `隣に・・・`、`チョー↑` と `チョー⬆`) を
      こちらが拾う。親は「曲名が最短」かつ「相手の曲名がその前方一致」のときだけ
      確定させ、それ以外は保留として報告する (別曲どうしが同じ歌詞になっている
      = 歌詞リンクの誤り、という別の不具合も混ざるため)。

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
#
# 囲みに `ー` (U+30FC 長音符) を入れてあるのは、実データが実際にそれを使っているため
# (`こいかぜ ー花葉ー` `ー序章ー` `ー紺碧ー`)。ダッシュ類だけを並べていた頃は
# この 3 曲が親なしのまま残り、同じ「こいかぜ」でも `-Night Wind Remix-` は
# 紐付いているのに、という割れ方をしていた。
#
# 長音符を囲みとして扱っても、素の曲名が実在することを別途条件にしているので
# 「ソーダ」のような語中の長音符を巻き込むことはない。
SUFFIX = re.compile(
    r"^(?P<base>.+?)\s*(?:[(（\[].*?[)）\]]|[-–—~〜―ー]\s*[^-–—~〜―ー]+\s*[-–—~〜―ー]?)\s*$"
)


# 機械判定では拾えず、1件ずつ調べて確定させた紐付け。
#
# いずれも歌詞本文が親と完全一致し、歌詞サイトの同じページを指していることを確認済み。
# 曲名規則が外したのは表記のゆれが原因で、内訳はコメントのとおり。
MANUAL_LINKS = {
    # 矢印が ⬆ と ↑ で違う
    "ml_チョー元気showアイドルchng_giga_remix": "ml_チョー元気showアイドルchng",
    # 括弧が全角と半角で違う
    "ml_プライヴェイトロードショウplayback_weekdayy0c1e_remix":
        "ml_プライヴェイトロードショウ_playback_weekday",
    # 三点リーダが … と ・・・ で違う
    "765as_隣に_-jazz_rearrange_mix-": "765as_隣に",
    # 親の曲名だけ末尾に 。が付く
    "ml_微笑んだから気づいたんだkan_takahiko_remix": "ml_微笑んだから気づいたんだ",
    # 親は「ポジティブ！」。REM@STER-A は ！! と重なり、B は ！ が抜けている
    "765as_ポジティブremster-a": "765as_ポジティブ",
    "765as_ポジティブremster-b": "765as_ポジティブ",
}


def normalize(title: str) -> str:
    """比較用。空白と大小文字の揺れだけ吸収する (それ以上は同一視しない)。"""
    return re.sub(r"\s+", "", title).lower()


def lyrics_based_pairs(rows, already_linked):
    """歌詞本文が完全一致する曲どうしから (子, 親) を作る。

    戻り値の2つ目は保留分。歌詞が同じなのに曲名が別系統のもので、
    「表記ゆれの別バージョン」か「歌詞リンクの誤り」かを人が見ないと決められない。
    """
    import glob
    import hashlib

    lyrics_dir = os.path.join(REPO, "lyrics_local", "lyrics")
    if not os.path.isdir(lyrics_dir):
        return [], []

    meta = {r[0]: r for r in rows}
    groups: dict[str, list[str]] = defaultdict(list)
    for path in glob.glob(os.path.join(lyrics_dir, "*.json")):
        with open(path, encoding="utf-8") as f:
            doc = json.load(f)
        lines = [l["text"] for l in doc["lines"] if l.get("kind") == "lyric"]
        # 極端に短い歌詞は偶然一致しうるので同一判定に使わない。
        if len(lines) < 5 or doc["song_id"] not in meta:
            continue
        groups[hashlib.md5("\n".join(lines).encode()).hexdigest()].append(doc["song_id"])

    pairs, ambiguous = [], []
    for ids in groups.values():
        # 既に親が居る / 既に (1) で拾った曲は対象外。
        free = [i for i in ids if not meta[i][4] and i not in already_linked]
        if len(free) < 2:
            continue
        # 曲名が最短 (= 修飾が付いていない) ものを親候補にする。
        free.sort(key=lambda i: (len(meta[i][1]), meta[i][3] or "9999"))
        parent, children = free[0], free[1:]
        for child in children:
            if meta[child][1].startswith(meta[parent][1]):
                pairs.append((child, parent))
            else:
                ambiguous.append((parent, child))
    return pairs, ambiguous


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help=f"{OUT_PATH} に書き出す")
    args = ap.parse_args()

    db = sqlite3.connect(DB_PATH)
    rows = db.execute(
        "SELECT id, title, brand_id, release_date, parent_song_id FROM songs"
    ).fetchall()
    # 出典URL用。派生であることの根拠は「その版が実在して配信されている」ことなので、
    # その曲の Apple Music ページを指す。無い曲は親の配信ページで代用する。
    music_id = {r[0]: (r[1] or "") for r in db.execute(
        "SELECT id, apple_music_id FROM songs")}

    def source_url(song_id: str, parent_id: str) -> str:
        for target in (song_id, parent_id):
            if music_id.get(target):
                return f"https://music.apple.com/jp/song/{music_id[target]}"
        return "https://music.apple.com/jp/"

    by_title: dict[tuple, list[str]] = defaultdict(list)
    for song_id, title, brand_id, _date, _parent in rows:
        by_title[(brand_id, normalize(title))].append(song_id)

    proposals: list[dict] = []
    skipped_no_base: list[str] = []
    for song_id, title, brand_id, _date, parent in rows:
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
            "source": source_url(song_id, candidates[0]),
            "note": f"「{title}」は「{base}」の別バージョン (曲名の派生規則)。一覧では親にまとめる。",
        })

    # --- (0) 手で確定させた分 ------------------------------------------
    titles_by_id = {r[0]: r[1] for r in rows}
    existing_parent = {r[0]: r[4] for r in rows}
    for child, parent in MANUAL_LINKS.items():
        if child not in titles_by_id or parent not in titles_by_id:
            raise SystemExit(f"MANUAL_LINKS の id が songs に無い: {child} / {parent}")
        if existing_parent.get(child):
            continue
        proposals.append({
            "table": "songs",
            "id": child,
            "fields": {"parent_song_id": parent},
            "source": source_url(child, parent),
            "note": f"「{titles_by_id[child]}」は「{titles_by_id[parent]}」の別バージョン。"
                    "曲名の表記ゆれで機械判定から漏れたため、歌詞一致を確認して手で紐付けた。",
        })

    # --- (2) 歌詞一致 --------------------------------------------------
    linked = {p["id"] for p in proposals}
    lyric_hits, ambiguous = lyrics_based_pairs(rows, linked)
    for child, parent in lyric_hits:
        proposals.append({
            "table": "songs",
            "id": child,
            "fields": {"parent_song_id": parent},
            "source": source_url(child, parent),
            "note": f"「{titles_by_id[child]}」は「{titles_by_id[parent]}」と歌詞が完全に同じ。"
                    "別バージョンとして親にまとめる。",
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
    print(f"  内訳: 曲名規則 {len(proposals) - len(lyric_hits)} 件 / 歌詞一致 {len(lyric_hits)} 件")
    print(f"新たに紐付ける: {len(proposals)} 曲 ({len(by_parent)} 親)")
    print(f"括弧付きだが素の曲名が無く、独立扱いにした: {len(skipped_no_base)} 曲")
    print()
    if ambiguous:
        print(f"⚠️ 歌詞は同じだが曲名が別系統 = 要判断: {len(ambiguous)} 件")
        print("   (表記ゆれの別バージョン / 曲の二重登録 / 歌詞リンクの誤り のどれか)")
        for parent, child in ambiguous:
            print(f"   - {titles_by_id[child]}  ←→  {titles_by_id[parent]}")
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
        "source": "https://music.apple.com/jp/",
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
