#!/usr/bin/env python3
"""build_reports.py — works.tsv から JASRAC 提出物を組み立てる。

Usage:
    # J-WID 照会用のワークシート (100件ずつ)
    python3 tools/jasrac/build_reports.py form --unmatched-only

    # 年次利用曲目報告 (19項目 / SJIS / CRLF / タブ区切り)
    python3 tools/jasrac/build_reports.py annual --license-no J123456789 --month 202608

    # 不足項目の洗い出し
    python3 tools/jasrac/build_reports.py gaps

出力先: tools/jasrac/out/

準拠: 「インターネットや携帯電話等 音楽利用の手引き」ver.26.2
      P.19-20 報告データ項目表 / P.24-25 非商用配信のファイル仕様
      https://www.jasrac.or.jp/users/internet/pdf/internet-manual.pdf
      要点は docs/JASRAC.md にまとめてある。

このスクリプトは提出物を組み立てるだけで、許諾区分の判断はしない。
非商用配信に該当するかは docs/JASRAC.md「商用/非商用の判定」を読むこと。
"""

import argparse
import os
import re
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import works_tsv as W  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_WORKS = os.path.join(HERE, "works.tsv")
OUT_DIR = os.path.join(HERE, "out")

# J-WID は人が引く (了承画面が自動検索を明示的に否定している)。
# 100件はフォームの上限であって J-WID の仕様ではなく、人の作業単位。
FORM_CHUNK = 100

ERROR_PREVIEW = 30

# 複数人の作家名は全角スラッシュ区切り (手引き P.20)。
NAME_SEP = "／"

_RE_KEY = re.compile(r"^[0-9a-zA-Z@._ -]+$")
_RE_NUM = re.compile(r"^[0-9]+$")
_RE_BRANCH = re.compile(r"^[0-9]{3}$")


def _opt(pattern):
    """空文字を許す条件付き必須項目用のパターン。"""
    return re.compile(r"^$|" + pattern)


# 報告データ項目表 (手引き P.19-20)。この表が仕様の唯一の表現。
# タブの数が18未満だとエラー (P.26) = 19項目ちょうどで固定。
#
# required: M=必須 / M*=グループ内いずれか必須 / C=条件付き必須 / O=任意
# (key, 項目名, required, 最大バイト, 書式パターン)
ANNUAL_SPEC = [
    ("interface_key",   "インターフェイスキーコード", "M",   30, _RE_KEY),
    ("content_kind",    "コンテンツ区分",             "C",    1, _opt("^Q$")),
    ("content_branch",  "コンテンツ枝番",             "M",    3, _RE_BRANCH),
    ("medley_kind",     "メドレー区分",               "C",    1, _opt("^M$")),
    ("medley_branch",   "メドレー枝番",               "M",    3, _RE_BRANCH),
    ("collect_code",    "コレクトコード",             "C",    1, _opt("^[1XY]$")),
    ("jasrac_code",     "ＪＡＳＲＡＣ作品コード",     "C",    8, _opt(W.CODE_RE.pattern)),
    ("report_title",    "原題名",                     "M",  200, None),
    ("subtitle",        "副題・邦題",                 "O",   60, None),
    ("lyricist_report", "作詞者名",                   "M*",  250, None),
    ("sub_lyricist",    "補作詞・訳詞者名",           "O",   60, None),
    ("composer_report", "作曲者名",                   "M*",  250, None),
    ("arranger_report", "編曲者名",                   "O",   60, None),
    ("artist",          "アーティスト名",             "O",  100, None),
    ("info_fee",        "情報料（税抜）",             "M",   13, _RE_NUM),
    ("ivt",             "ＩＶＴ区分",                 "M",    1, re.compile("^[IVT]$")),
    ("lyric_kind",      "原詞訳詞区分",               "C",    1, _opt("^[123]$")),
    ("il_kind",         "ＩＬ区分",                   "C",    1, _opt("^[IL]$")),
    ("request_count",   "リクエスト回数",             "C",    9, _RE_NUM),
]

ANNUAL_LIMITS = {key: limit for key, _l, _r, limit, _p in ANNUAL_SPEC}

# 「非商用配信 × 歌詞掲載」という運用プロファイル。
# 商用配信に切り替わったらプロファイルを足す (docs/JASRAC.md §1)。
PROFILE = {
    "content_kind": "",       # 1コンテンツ1楽曲なのでブランク
    "content_branch": "000",
    "medley_kind": "",
    "medley_branch": "000",
    "collect_code": "",       # 非商用配信は常に空欄。欄ごと消すとエラー (P.25)
    "sub_lyricist": "",
    "arranger_report": "",
    "il_kind": "",            # CD音源配信ではないのでブランク
}

# 条件付き必須 (C) のうち、条件が成立したら非空を要求するもの。
CONDITIONAL_REQUIRED = {
    # IVT区分が V(詞曲とも) か T(詞のみ) のときは原詞訳詞区分が必須
    "lyric_kind": lambda r: r.get("ivt") in ("V", "T"),
}


def read_works(path):
    if not os.path.exists(path):
        sys.exit("works.tsv がない。先に extract_works.py --apply を実行する: %s" % path)
    return W.read_rows(path)


def report_title(row):
    """原題名。J-WID で確認した表記があればそれを優先する。

    手引き P.20「できるだけ J-WID 上の記述にそろえる」。
    J-WID の表記は SJIS に収まるので、ここを埋めることが文字化け対策にもなる。
    """
    return row.get("jasrac_title") or row.get("work_title") or ""


def report_name(row, field):
    """報告用の作家名。複数人は全角スラッシュ区切り。"""
    v = row.get(field + "_norm") or row.get(field + "_raw") or ""
    return NAME_SEP.join(p for p in v.split(";") if p)


def sjis_len(s):
    """SJIS でのバイト長。桁数制限はバイト数指定 (日本語2バイト)。

    変換できない文字を含む場合は -1。長さより先に文字種の問題として報告する。
    """
    if s.isascii():
        return len(s)
    try:
        return len(s.encode("cp932"))
    except UnicodeEncodeError:
        return -1


def fit_optional(s, limit):
    """任意項目を SJIS・指定バイト長に収める。

    変換できない文字は落とし、なお超える分は末尾を切る (2バイト文字の途中では
    切らない)。必須項目には使わない — 黙って値を変えてよいのは任意項目だけ。
    戻り値: (収めた文字列, 変更したか)
    """
    if 0 <= sjis_len(s) <= limit:
        return s, False
    out, used = [], 0
    for ch in s:
        n = sjis_len(ch)
        if n < 0:
            continue          # SJIS にない文字は落とす
        if used + n > limit:
            break             # 残りは長さ超過で切る
        out.append(ch)
        used += n
    return "".join(out), True


def build_record(row, opts):
    """1曲を19項目のレコードに展開する。"""
    r = dict(row)
    r.update(PROFILE)
    r["report_title"] = report_title(row)
    r["lyricist_report"] = report_name(row, "lyricist")
    r["composer_report"] = report_name(row, "composer")
    r["jasrac_code"] = W.normalize_code(row.get("jasrac_code"))
    r["info_fee"] = opts.info_fee
    r["ivt"] = opts.ivt
    r["lyric_kind"] = opts.lyric_kind if opts.ivt in ("V", "T") else ""
    r["request_count"] = opts.request_count

    # アーティスト名は任意項目 (O)。全員曲だと出演者連結で 300 バイトを超え、
    # ユニット名に SJIS 外の記号 (♡ 等) が入ることもある。提出可否に影響しない
    # ので収まる形に均すが、変えた件数は annual が報告する。
    r["artist"], r["_artist_adjusted"] = fit_optional(
        r.get("artist", ""), ANNUAL_LIMITS["artist"])
    return r


# M* は「グループ内いずれか必須」。現状のグループは作詞者名/作曲者名の1つだけ。
EITHER_REQUIRED = [(key, label) for key, label, req, _n, _p in ANNUAL_SPEC if req == "M*"]


def record_errors(r):
    """1レコード分の検査を項目表から回す。"""
    if not any(r.get(k) for k, _label in EITHER_REQUIRED):
        yield "%s がどちらも空 (いずれか必須)" % "・".join(
            label for _k, label in EITHER_REQUIRED)

    for key, label, required, limit, pattern in ANNUAL_SPEC:
        v = r.get(key, "")

        if required == "M" and not v:
            yield "%s が空 (必須)" % label
        elif required == "C" and not v and CONDITIONAL_REQUIRED.get(key, lambda _: False)(r):
            yield "%s が空 (条件付き必須)" % label

        n = sjis_len(v)
        if n < 0:
            bad = sorted({c for c in v if sjis_len(c) < 0})
            yield "%s に SJIS 変換できない文字: %s" % (
                label, " ".join("%r(U+%04X)" % (c, ord(c)) for c in bad))
            continue
        if n > limit:
            yield "%s が %dバイト超過 (%d/%d)" % (label, n - limit, n, limit)
        if pattern and v and not pattern.match(v):
            if key == "jasrac_code" and len(v) == 7 and v.isdigit():
                yield "作品コードが7桁。前ゼロが落ちた疑い: %r" % v
            else:
                yield "%s が書式に合わない: %r" % (label, v)


def validate(records):
    return [(r.get("song_id", "?"), msg) for r in records for msg in record_errors(r)]


def write_tsv(path, columns, rows):
    W.write_rows(path, rows, columns)


def cmd_form(args):
    """J-WID を人手で引くためのワークシート。

    J-WID は了承画面で「自動Script等による検索は実行しないでください」と
    明示しているので、照会そのものは自動化しない。
    """
    rows = read_works(args.works)
    if args.unmatched_only:
        rows = [r for r in rows if not r.get("jasrac_code", "").strip()]

    # 見出しと値の対応を1つの定義から作る (並行リストにしない)
    fields = [
        ("song_id", lambda r: r.get("song_id", "")),
        ("作品名", lambda r: r.get("work_title", "")),
        ("副題", lambda r: r.get("subtitle", "")),
        ("作詞者名", lambda r: report_name(r, "lyricist")),
        ("作曲者名", lambda r: report_name(r, "composer")),
        ("アーティスト名", lambda r: r.get("artist", "")),
        ("JASRAC作品コード", lambda r: r.get("jasrac_code", "")),
        ("J-WID作品名", lambda r: r.get("jasrac_title", "")),
        ("照合状態", lambda r: r.get("match_status", "")),
        ("備考", lambda r: r.get("note", "")),
    ]
    labels = [label for label, _get in fields]

    os.makedirs(OUT_DIR, exist_ok=True)
    chunks = [rows[i:i + FORM_CHUNK] for i in range(0, len(rows), FORM_CHUNK)] or [[]]
    for n, chunk in enumerate(chunks, 1):
        path = os.path.join(OUT_DIR, "form_%03d.tsv" % n)
        write_tsv(path, labels,
                  [{label: get(r) for label, get in fields} for r in chunk])
        print("wrote %s (%d件)" % (path, len(chunk)))
    print("\n計 %d件 / %dファイル" % (len(rows), len(chunks)))


def cmd_annual(args):
    # ファイル名は 許諾番号(10桁) + 報告年月(YYYYMM) + 任意の英数字。
    # 手引きの例 J123456789201207.txt のとおり許諾番号には英字が入りうる。
    if not (args.license_no.isalnum() and len(args.license_no) == 10):
        sys.exit("非商用配信の許諾番号は英数字10桁: %r" % args.license_no)
    if not (args.month.isdigit() and len(args.month) == 6):
        sys.exit("報告年月は YYYYMM 形式: %r" % args.month)
    if args.suffix and not args.suffix.isalnum():
        sys.exit("ファイル名末尾の任意文字列は英数字のみ: %r" % args.suffix)

    rows = [r for r in read_works(args.works) if r.get("match_status") != "excluded"]
    records = [build_record(r, args) for r in rows]
    errors = validate(records)

    if errors and not args.force:
        print("提出前チェックで %d件の問題。報告ファイルは書かない。\n" % len(errors),
              file=sys.stderr)
        for sid, msg in errors[:ERROR_PREVIEW]:
            print("  %-38s %s" % (sid, msg), file=sys.stderr)
        if len(errors) > ERROR_PREVIEW:
            print("  ... 他 %d件" % (len(errors) - ERROR_PREVIEW), file=sys.stderr)
        print("\n--force で書き出せるが、J-NOTES 側で弾かれる。"
              "\nSJIS 変換できない文字は --force でも '?' に置換されるので、"
              "\nworks.tsv の jasrac_title に J-WID 上の表記を入れて解消すること。",
              file=sys.stderr)
        sys.exit(1)

    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, "%s%s%s.txt" % (args.license_no, args.month, args.suffix))

    # 文字コード SJIS / 改行 CR+LF / タブ区切り / 各レコード末尾に必ず改行。
    # --force のときは変換不可文字で落とさず '?' に置換する (落ちると
    # --force が何もしないフラグになってしまう)。
    errs = "replace" if args.force else "strict"
    with open(path, "w", encoding="cp932", newline="", errors=errs) as f:
        for r in records:
            f.write("\t".join(r.get(key, "") for key, _l, _r, _n, _p in ANNUAL_SPEC) + "\r\n")

    print("wrote %s" % path)
    print("  %d レコード / %d項目 / SJIS / CRLF / タブ区切り"
          % (len(records), len(ANNUAL_SPEC)))
    print("  IVT区分=%s 原詞訳詞区分=%s 情報料=%s リクエスト回数=%s"
          % (args.ivt, args.lyric_kind, args.info_fee, args.request_count))
    if errors:
        print("  ※ --force で %d件の警告を無視した" % len(errors))
    adjusted = sum(1 for r in records if r.get("_artist_adjusted"))
    if adjusted:
        print("  アーティスト名を %d件、SJIS・100バイトに収まる形へ均した" % adjusted)
    no_code = sum(1 for r in records if not r.get("jasrac_code"))
    if no_code:
        print("\n作品コード未入力 %d件。手引き P.20 では不明ならブランク可。" % no_code)
    print("提出先: J-TAKT https://j-takt.jasrac.or.jp/ → 利用曲目のご報告[J-NOTES]")


def cmd_gaps(args):
    """報告に足りないものを、annual と同じ検査で洗い出す。

    独立した欠落定義を持たない (持つと annual との判定がずれる)。
    """
    rows = read_works(args.works)
    records = [build_record(r, args) for r in rows]

    by_song = {}
    for sid, msg in validate(records):
        by_song.setdefault(sid, []).append(msg)

    print("総レコード      : %d" % len(rows))
    print("要対応レコード  : %d" % len(by_song))
    print("作品コード未入力: %d  (不明ならブランク報告可)"
          % sum(1 for r in rows if not r.get("jasrac_code", "").strip()))

    foreign = sum(1 for r in rows if W.is_foreign_code(r.get("jasrac_code")))
    print("2桁目が英字     : %d  ← 外国作品の可能性。扱いは JASRAC 未確認" % foreign)

    print("\n問題の内訳:")
    kinds = Counter(re.split(r" (?:に|が) ", m)[0]
                    for msgs in by_song.values() for m in msgs)
    for kind, n in kinds.most_common():
        print("  %-44s %d" % (kind, n))

    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, "gaps.tsv")
    title_of = {r["song_id"]: r.get("title", "") for r in rows}
    write_tsv(path, ["song_id", "title", "問題"],
              [{"song_id": sid, "title": title_of.get(sid, ""), "問題": " / ".join(msgs)}
               for sid, msgs in sorted(by_song.items())])
    print("\nwrote %s" % path)


def add_profile_args(p):
    """報告値のプロファイル。既定は非商用配信 × 歌詞掲載。"""
    p.add_argument("--ivt", default="T", choices=["I", "V", "T"],
                   help="I=曲のみ V=詞曲とも T=詞のみ (歌詞掲載は T)")
    p.add_argument("--lyric-kind", default="1", choices=["1", "2", "3"],
                   help="原詞=1 訳詞=2 不明=3")
    p.add_argument("--info-fee", default="0", help="情報料(税抜)。無料なら 0")
    p.add_argument("--request-count", default="0",
                   help="リクエスト回数。集計不可能なら 0")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--works", default=DEFAULT_WORKS, help="照合台帳 works.tsv のパス")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_form = sub.add_parser("form", help="J-WID 照会用ワークシート (100件ずつ)")
    p_form.add_argument("--unmatched-only", action="store_true",
                        help="作品コード未入力のものだけ出す")
    p_form.set_defaults(func=cmd_form)

    p_ann = sub.add_parser("annual", help="年次利用曲目報告 (19項目/SJIS/CRLF/TAB)")
    p_ann.add_argument("--license-no", required=True, help="非商用配信の許諾番号 英数字10桁")
    p_ann.add_argument("--month", required=True, help="報告年月 YYYYMM")
    p_ann.add_argument("--suffix", default="", help="ファイル名末尾の任意文字列 (英数字)")
    p_ann.add_argument("--force", action="store_true", help="検証エラーを無視して書く")
    add_profile_args(p_ann)
    p_ann.set_defaults(func=cmd_annual)

    p_gap = sub.add_parser("gaps", help="不足項目の洗い出し")
    add_profile_args(p_gap)
    p_gap.set_defaults(func=cmd_gaps)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
