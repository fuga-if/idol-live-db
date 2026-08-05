#!/usr/bin/env python3
"""extract_works.py — master.sqlite から JASRAC 申請用の作品リストを棚卸しする。

Usage:
    python3 tools/jasrac/extract_works.py --apply     # works.tsv を生成/更新
    python3 tools/jasrac/extract_works.py             # 集計のみ (書き込まない)
    python3 tools/jasrac/extract_works.py --db path.sqlite --out path.tsv

出力: tools/jasrac/works.tsv (UTF-8 / TAB 区切り)

このファイルは「照合台帳」であって申請書ではない。
works_tsv.MANUAL_COLS の手入力列は再実行しても保持される (song_id をキーにマージ)。

なぜ songs テーブルに列を足さないか:
  JASRAC 作品コードはアプリが表示しない純粋な管理データ。songs に足すと
  CloudKit スキーマと iOS/Android のモデルまで波及するので、独立台帳で持つ。

注意:
  - J-WID に公開 API はなく、了承画面で自動検索が明示的に否定されている。
    jasrac_code は人が J-WID を引いて埋める。詳細は docs/JASRAC.md。
  - 作詞/作曲の正規化は候補生成であって断定ではない。raw 列を必ず残す。
"""

import argparse
import hashlib
import os
import re
import sqlite3
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import works_tsv as W  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
DEFAULT_DB = os.path.join(REPO, "ImasLiveDB", "Resources", "master.sqlite")
MASTER_SQL = os.path.join(REPO, "db", "master.sql")
OUT_TSV = os.path.join(HERE, "works.tsv")

# BNSI(神前暁) / BNEI（中川浩二・小林啓樹） 形式のレーベル包み。
LABEL_WRAPPER_RE = re.compile(
    r"^(?:BNSI|BNEI|BANDAI NAMCO(?: Studios| Entertainment)?)\s*[（(]([^）)]*)[）)]\s*$",
    re.IGNORECASE,
)

# トップレベル区切り文字 (括弧の外にあるものだけ分割対象)
SPLIT_CHARS = set("・、，,／&＆")

# タイトル末尾の付加部分を剥がすパターン。括弧型 / ダッシュ型 / 波型。
# ダッシュ型は開きダッシュの直前に空白を要求する。そうしないと Do-Dai のような
# ハイフン入りタイトルや -LindaAI-CUE Remix- の内部ダッシュで誤爆する。
SUFFIX_PATTERNS = [
    re.compile(r"^(.*?)\s*[（(]([^（()）]*)[）)]\s*$"),
    re.compile(r"^(.*?)\s+[-‐−–—](.+)[-‐−–—]\s*$"),
    re.compile(r"^(.*?)\s*[~～](.+)[~～]\s*$"),
]


def ensure_db(db_path):
    """binary master.sqlite が無ければ db/master.sql から生成する。

    master.sqlite は .gitignore 対象 (db/master.sql が正) なので、
    クローン直後には存在しない。tools/apply_data.py と同じ作法。
    """
    if os.path.exists(db_path) or not os.path.exists(MASTER_SQL):
        return
    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    conn = sqlite3.connect(db_path)
    with open(MASTER_SQL, encoding="utf-8") as f:
        conn.executescript(f.read())
    conn.close()
    print("(db/master.sql から %s を生成しました)" % os.path.basename(db_path))


def split_top_level(s):
    """括弧の中を保護しつつトップレベルの区切り文字で分割する。

    'Dirty Orange (Digz, Inc. Group)、MOMONADY' →
        ['Dirty Orange (Digz, Inc. Group)', 'MOMONADY']
    "DJ'TEKINA//SOMETHING" は '/' を区切りに含めないので割れない。
    """
    parts = []
    buf = []
    depth = 0
    for ch in s:
        if ch in "（(［[｛{":
            depth += 1
            buf.append(ch)
        elif ch in "）)］]｝}":
            depth = max(0, depth - 1)
            buf.append(ch)
        elif depth == 0 and ch in SPLIT_CHARS:
            parts.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
    parts.append("".join(buf))
    return [p.strip() for p in parts if p.strip()]


def normalize_credit(normalized):
    """作詞者/作曲者名を J-WID 照会用の候補リストに正規化する。

    トップレベル区切りで複数人に分割し、各要素の BNSI(…) 包みを剥がす。
    戻り値は ';' 連結。引数は正規化済み文字列であること。
    """
    if not normalized:
        return ""

    names = []
    for part in split_top_level(normalized):
        m = LABEL_WRAPPER_RE.match(part)
        names.extend(split_top_level(m.group(1)) if m else [part])

    seen = set()
    uniq = []
    for n in names:
        if n and n not in seen:
            seen.add(n)
            uniq.append(n)
    return ";".join(uniq)


def match_key(title):
    """版違い判定でタイトルを突き合わせるためのキー。"""
    return W.normalize_text(title).lower().replace(" ", "")


def split_title(normalized_title, has_parent, known_titles):
    """タイトルを「作品名」と「副題」に割り、版違いかどうかを返す。

    版違いキーワードを列挙するのではなく、構造に問う:
      1. 末尾を剥がした結果が他の曲のタイトルと一致すれば版違い
      2. parent_song_id があれば版違い (apply_post_build.py が張った関係)
      3. どちらでもなければ分割しない

    FO(U)R / 千夜一夜(Alf Layla wa Layla) / S(mile)ING! / ♪(おんぷ) は
    剥がした結果が既存曲を指さないので分割されない。

    接尾辞は入れ子になりうるので (蒼い鳥(M@STER VERSION) ~TV ARRANGE~)、
    既存曲に当たるまで繰り返し剥がす。

    戻り値: (work_title, subtitle, is_version)
    """
    base = normalized_title
    stripped = []
    while True:
        for pat in SUFFIX_PATTERNS:
            m = pat.search(base)
            if m and m.group(1).strip():
                break
        else:
            break
        base, inside = m.group(1).strip(), m.group(2).strip()
        stripped.append(inside)
        if match_key(base) in known_titles:
            return base, " ".join(reversed(stripped)), True

    # 原作品が DB に無い版違い。parent_song_id が張られていれば拾える。
    if has_parent and stripped:
        return base, " ".join(reversed(stripped)), True
    return normalized_title, "", False


def new_interface_key(song_id):
    """報告項目1「インターフェイスキーコード」を新規発行する。

    仕様 (手引き P.19): 1コンテンツ単位にユニーク、一度付与したコードは変更不可、
    使用可能文字は 0-9 a-z A-Z @ - . _ 半角スペース、30桁以内。

    song_id は過半数が日本語を含むのでそのままでは使えない。song_id の SHA-1 を
    発行アルゴリズムに使うが、**不変性は台帳への永続化で担保する**
    (song_id は改名されうるので、決定性だけに頼ると既報告のキーが変わる)。
    """
    return "imasdb-" + hashlib.sha1(song_id.encode("utf-8")).hexdigest()[:12]


def load_existing(path):
    """既存 works.tsv の手入力列を song_id -> {col: value} で読む。"""
    if not os.path.exists(path):
        return {}
    return {r["song_id"]: {c: r[c] for c in W.MANUAL_COLS} for r in W.read_rows(path)}


def fetch_songs(db_path):
    conn = sqlite3.connect("file:%s?mode=ro" % db_path, uri=True)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        """
        SELECT s.id, s.title, s.lyricist, s.composer, s.singer_label,
               s.unit_name, s.song_type, s.brand_id, s.parent_song_id,
               (SELECT group_concat(i.name, '、')
                  FROM song_artists sa JOIN idols i ON i.id = sa.idol_id
                 WHERE sa.song_id = s.id AND sa.role = 'original') AS performers
          FROM songs s
         ORDER BY s.brand_id, s.id
        """
    ).fetchall()
    conn.close()
    return rows


def build_rows(songs, existing):
    known_titles = {match_key(s["title"]) for s in songs}
    out = []
    for s in songs:
        title = W.normalize_text(s["title"])
        parent = W.normalize_text(s["parent_song_id"])
        work_title, subtitle, is_version = split_title(title, bool(parent), known_titles)

        lyricist = W.normalize_text(s["lyricist"])
        composer = W.normalize_text(s["composer"])

        manual = existing.get(s["id"], {})
        status = manual.get("match_status") or "unmatched"
        if status not in W.MATCH_STATUSES:
            print("警告: %s の match_status が不正: %r (unmatched として扱う)"
                  % (s["id"], status), file=sys.stderr)
            status = "unmatched"

        out.append({
            "song_id": s["id"],
            "title": title,
            "work_title": work_title,
            "subtitle": subtitle,
            "lyricist_raw": lyricist,
            "lyricist_norm": normalize_credit(lyricist),
            "composer_raw": composer,
            "composer_norm": normalize_credit(composer),
            "artist": (W.normalize_text(s["singer_label"])
                       or W.normalize_text(s["unit_name"])
                       or W.normalize_text(s["performers"])),
            "song_type": W.normalize_text(s["song_type"]),
            "brand_id": W.normalize_text(s["brand_id"]),
            "parent_song_id": parent,
            "is_version": "1" if is_version else "",
            # 一度発行したキーは絶対に振り直さない
            "interface_key": manual.get("interface_key") or new_interface_key(s["id"]),
            "jasrac_code": manual.get("jasrac_code", ""),
            "jasrac_title": manual.get("jasrac_title", ""),
            "match_status": status,
            "note": manual.get("note", ""),
        })
    return out


def print_stats(rows):
    print("総曲数            : %d" % len(rows))
    print("作詞者なし        : %d" % sum(1 for r in rows if not r["lyricist_raw"]))
    print("作曲者なし        : %d" % sum(1 for r in rows if not r["composer_raw"]))
    print("アーティスト名なし: %d" % sum(1 for r in rows if not r["artist"]))
    print("版違い候補        : %d" % sum(1 for r in rows if r["is_version"]))
    print("作品コード入力済  : %d" % sum(1 for r in rows if r["jasrac_code"]))

    foreign = sum(1 for r in rows if W.is_foreign_code(r["jasrac_code"]))
    print("うち2桁目が英字   : %d  ← 外国作品の可能性。扱いは JASRAC 未確認" % foreign)

    keys = {(r["parent_song_id"] or r["song_id"]) if r["is_version"] else r["song_id"]
            for r in rows}
    print("\n照会が必要な作品数 (版違いを原作品にまとめた場合): %d" % len(keys))

    blanks = [r for r in rows if not r["lyricist_raw"] and not r["composer_raw"]]
    print("\n作詞作曲が両方空の曲 (J-WID 照合の確度が最も低い層): %d" % len(blanks))
    for song_type, n in Counter(r["song_type"] for r in blanks).most_common():
        print("  %-8s %d" % (song_type, n))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=DEFAULT_DB)
    ap.add_argument("--out", default=OUT_TSV)
    ap.add_argument("--apply", action="store_true",
                    help="works.tsv を書き出す (既定は集計のみ)")
    args = ap.parse_args()

    ensure_db(args.db)
    if not os.path.exists(args.db):
        sys.exit("DB が見つからない: %s" % args.db)

    existing = load_existing(args.out)
    rows = build_rows(fetch_songs(args.db), existing)

    if args.apply:
        W.write_rows(args.out, rows)
        print("wrote %s (%d works, %d 件の手入力を引き継ぎ)\n"
              % (args.out, len(rows), len(existing)))
    else:
        print("(--apply なしなので書き込まない)\n")

    print_stats(rows)


if __name__ == "__main__":
    main()
