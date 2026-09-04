#!/usr/bin/env python3
"""copy_variants.py — 版違いの曲に親の歌詞を流用する。

Usage:
    python3 tools/lyrics/copy_variants.py            # 何が作られるか見るだけ
    python3 tools/lyrics/copy_variants.py --apply    # lyrics_local/lyrics/ に書く
    python3 tools/lyrics/copy_variants.py --only 765as_902pm_rem@ster-a

REM@STER / Remix / rearrange / Game Size のような**版違いは歌詞が同じ**なので、
親 (`songs.parent_song_id`) の歌詞をそのまま使える。プチリリから取り直す必要はない。

対象は次を全部満たす曲:
  - `parent_song_id` を持つ
  - 親に公開歌詞がある (D1 の published)
  - 自分には公開歌詞が無い
  - 手元にまだ JSON が無い (**既存は絶対に上書きしない**)
  - **タイトルの本体部分が親と一致する**

最後の条件が要。`parent_song_id` は人手で入るので、別曲が親になっている取り違えが
ありうる。版名を剥がした本体が親と違うものは採らず、一覧に出して人に見せる。
版名の剥がし方は歌詞リンク収集と同じ `link_verify.base_title` を使う
(括弧・ハイフン・波ダッシュで囲った接尾辞を、変化しなくなるまで剥がす)。
"""

import argparse
import io
import os
import sqlite3
import sys
import time
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import lyrics_json  # noqa: E402
from link_verify import base_title  # noqa: E402
from petitlyrics_check import load_published  # noqa: E402

DEFAULT_DB = os.path.join(REPO, "ImasLiveDB", "Resources", "master.sqlite")
JSON_DIR = os.path.join(REPO, "lyrics_local", "lyrics")


# 約物の字形違い。NFKC は ’ (U+2019) を ' に直さないので、ここで揃える。
# これが無いと「Parade d’amour」と「Parade d'amour (les amis d'enfance ver.)」が
# 別曲と判定されて弾かれる (実測)。
TYPOGRAPHIC = {
    "’": "'", "‘": "'", "ʼ": "'",
    "“": '"', "”": '"',
    "–": "-", "—": "-", "―": "-", "−": "-",
    "～": "~", "〜": "~",
}


def strict_key(text):
    """比較用のキー。NFKC で幅を揃え、約物の字形を揃え、空白を落とし、大小を無視する。"""
    text = unicodedata.normalize("NFKC", text or "")
    text = "".join(TYPOGRAPHIC.get(ch, ch) for ch in text)
    return "".join(ch for ch in text if not ch.isspace()).casefold()


def load_pairs(db_path):
    conn = sqlite3.connect("file:%s?mode=ro" % db_path, uri=True)
    titles = {r[0]: (r[1] or "") for r in conn.execute("SELECT id, title FROM songs")}
    pairs = [(r[0], r[1]) for r in conn.execute(
        "SELECT id, parent_song_id FROM songs "
        "WHERE parent_song_id IS NOT NULL AND parent_song_id <> ''")]
    conn.close()
    return titles, pairs


def parent_lines(parent_id):
    path = os.path.join(JSON_DIR, "%s.json" % parent_id)
    if not os.path.exists(path):
        return None
    import json
    with io.open(path, encoding="utf-8") as f:
        doc = json.load(f)
    lines = doc.get("lines") or []
    return lines if any(x.get("kind") == "lyric" for x in lines) else None


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--db", default=DEFAULT_DB)
    ap.add_argument("--only")
    ap.add_argument("--apply", action="store_true", help="実際に書き込む")
    args = ap.parse_args()

    published = set(load_published())
    titles, pairs = load_pairs(args.db)

    made, rejected, skipped = [], [], []
    for song_id, parent_id in sorted(pairs):
        if args.only and song_id != args.only:
            continue
        if parent_id not in published or song_id in published:
            continue
        if os.path.exists(os.path.join(JSON_DIR, "%s.json" % song_id)):
            skipped.append((song_id, "手元に既に歌詞がある"))
            continue

        child_t, parent_t = titles.get(song_id, ""), titles.get(parent_id, "")
        if strict_key(base_title(child_t)) != strict_key(parent_t):
            rejected.append((song_id, child_t, parent_id, parent_t))
            continue

        lines = parent_lines(parent_id)
        if lines is None:
            skipped.append((song_id, "親の歌詞が手元に無い (%s)" % parent_id))
            continue

        doc = lyrics_json.build_doc(
            song_id, [dict(x) for x in lines],
            "親 %s の歌詞を流用 (版違い)" % parent_id,
            note="版違いのため親の歌詞を流用 (%s)" % time.strftime("%Y-%m-%d"))
        if args.apply:
            lyrics_json.write_doc(song_id, doc)
        made.append((song_id, child_t, parent_id))

    for song_id, child_t, parent_id in made:
        print("%-44s ← %s" % (song_id[:44], parent_id))
    print("\n作成 %d件 / 除外 %d件 / 見送り %d件%s"
          % (len(made), len(rejected), len(skipped),
             "" if args.apply else "  (--apply なしなので書き込んでいない)"))

    if rejected:
        print("\n=== 採用しなかった (タイトル本体が親と一致しない) ===")
        for song_id, child_t, parent_id, parent_t in rejected:
            print("  %-40s %r ↛ 親 %r" % (song_id[:40], child_t[:38], parent_t[:30]))
    reasons = {}
    for _, why in skipped:
        reasons[why.split(" (")[0]] = reasons.get(why.split(" (")[0], 0) + 1
    if reasons:
        print("\n見送りの内訳:")
        for why, n in sorted(reasons.items(), key=lambda kv: -kv[1]):
            print("  %-28s %d件" % (why, n))
    return 0


if __name__ == "__main__":
    sys.exit(main())
