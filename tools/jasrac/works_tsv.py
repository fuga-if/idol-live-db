#!/usr/bin/env python3
"""works_tsv.py — JASRAC 照合台帳 works.tsv のスキーマと入出力。

extract_works.py (master.sqlite → 台帳) と build_reports.py (台帳 → 提出物) の
境界にある唯一の契約。列名を両側が文字列リテラルで触ると、片方の改名が
もう片方で黙って空文字になるので、定義はここに1つだけ置く。

TSV は csv モジュールを使わず手書きで読み書きする。書き出し時に値から
TAB/CR/LF を潰しているため値にデリミタが入りえず、かつ csv のデフォルト
dialect は `"` を含む値をクォートで包んでしまう (年次報告 .txt は
「タブ区切り19項目」がそのまま仕様なのでクォート混入は許されない)。
tools/seed_cloudkit.py も手書き split("\\t") で、リポジトリの流儀でもある。
"""

import re
import unicodedata

# 人が埋める列。extract_works.py を再実行しても保持される。
MANUAL_COLS = [
    "interface_key",
    "jasrac_code",
    "jasrac_title",
    "match_status",
    "note",
]

# master.sqlite から毎回作り直す列。
DERIVED_COLS = [
    "song_id",
    "title",
    "work_title",
    "subtitle",
    "lyricist_raw",
    "lyricist_norm",
    "composer_raw",
    "composer_norm",
    "artist",
    "song_type",
    "brand_id",
    "parent_song_id",
    "is_version",
]

COLUMNS = DERIVED_COLS + MANUAL_COLS

# match_status の語彙。誤記を黙って通さないよう読み込み時に検証する。
MATCH_STATUSES = {
    "unmatched",   # 未照合
    "matched",     # J-WID で作品コードを確定
    "ambiguous",   # 同名異曲が複数あり確定できない
    "not_found",   # J-WID に見つからない
    "excluded",    # JASRAC 管理外と確認済み。報告母集団から外す
}

# JASRAC 作品コード: 1桁目=数字 / 2桁目=数字か英大文字 / 3-8桁目=数字 の8文字。
# 出典: https://j-opus.jasrac.or.jp/opus/popup/sakuhincode_help.html
CODE_RE = re.compile(r"^[0-9][0-9A-Z][0-9]{6}$")

_SCRUB_RE = re.compile(r"[\t\r\n]+")


def normalize_text(s):
    """NFKC 正規化 + 前後空白除去。None は空文字に。"""
    if s is None:
        return ""
    return unicodedata.normalize("NFKC", str(s)).strip()


def normalize_code(raw):
    """作品コードを報告形式に整える。ハイフンを除き、前ゼロは保つ。

    手引き P.20:「コード内のハイフンは不要」「前"0"の場合の桁落ちにご注意」。
    桁や体系の検査はここではせず validate 側で行う (整形と判定を混ぜない)。
    """
    return (raw or "").strip().replace("-", "").replace("−", "").replace("‐", "").upper()


def is_foreign_code(raw):
    """作品コードが外国作品を示すか。左から2桁目がアルファベットなら外国。

    出典: 手引き P.7 §2-1-(13)。ただし手引き自身が「内外区分は途中で変更される
    こともある」と注記しているので、これは推定であって確定ではない。
    コード未入力・体系外なら None を返す。
    """
    c = normalize_code(raw)
    if not CODE_RE.match(c):
        return None
    return c[1].isalpha()


def read_rows(path):
    """works.tsv を list[dict] で読む。未知の列は保持し、欠けた列は空文字で埋める。"""
    with open(path, encoding="utf-8") as f:
        header = f.readline().rstrip("\n").split("\t")
        rows = []
        for line in f:
            if not line.strip():
                continue
            vals = line.rstrip("\n").split("\t")
            vals += [""] * (len(header) - len(vals))
            row = dict(zip(header, vals))
            for col in COLUMNS:
                row.setdefault(col, "")
            rows.append(row)
    return rows


def write_rows(path, rows, columns=COLUMNS):
    """works.tsv を書く。値に紛れた TAB/CR/LF は列ずれになるので空白に潰す。"""
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\t".join(columns) + "\n")
        for r in rows:
            vals = []
            for c in columns:
                v = r.get(c, "")
                # 実データでは1件も該当しないが、混入すると静かに列がずれる
                if "\t" in v or "\r" in v or "\n" in v:
                    v = _SCRUB_RE.sub(" ", v)
                vals.append(v)
            f.write("\t".join(vals) + "\n")
