#!/usr/bin/env python3
"""lyrics_json.py — 歌詞を JSON で持ち、検証する。

Usage:
    # テキストで書いた歌詞を JSON に変換する (推奨の入力経路)
    python3 tools/lyrics/lyrics_json.py from-text cg_お願いシンデレラ \
        --source "CD歌詞カード (COCC-17064)"

    # 全部まとめて変換 (lyrics_local/body/*.txt のうち中身があるもの)
    python3 tools/lyrics/lyrics_json.py from-text --all --source "CD歌詞カード"

    # 空の雛形を作る
    python3 tools/lyrics/lyrics_json.py init cg_お願いシンデレラ

    # 検証
    python3 tools/lyrics/lyrics_json.py validate

    # 出典の既定値を一度だけ設定しておく (毎回 --source を打たなくてよくなる)
    python3 tools/lyrics/lyrics_json.py set-source "CD歌詞カード"

    # 進捗
    python3 tools/lyrics/lyrics_json.py stats

置き場所:
    lyrics_local/body/<song_id>.txt     手で書くテキスト (普通の改行でよい)
    lyrics_local/lyrics/<song_id>.json  変換後の JSON

**data/fixes/ には絶対に置かない。** あそこは公開 git リポジトリで、
JASRAC の許諾条件 (ユーザが一括ダウンロードできない形での配信) を破る。
lyrics_local/ は .gitignore 済みで、起動時に確認する。

なぜ JSON に改行を埋めないか:
    歌詞は行の並びであって1個の長い文字列ではない。1行を配列の1要素にすれば
    エスケープ (\\n) が要らず、手で読み書きでき、行単位の差分が取れる。
    さらにコールガイドは「行に安定 ID を振ってコールを紐づける」設計なので、
    行が最初から分かれている形が素直に対応する。

行の種類 (kind):
    lyric   歌詞本文
    marker  イントロ / 間奏 / アウトロ 等の構造マーカー (歌詞ではない)。
            コールを置く受け皿になるので、これが無いとイントロコールが置けない
    blank   意図的な余白
"""

import argparse
import glob
import json
import os
import re
import subprocess
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
STAGE_DIR = os.path.join(REPO, "lyrics_local")
BODY_DIR = os.path.join(STAGE_DIR, "body")
JSON_DIR = os.path.join(STAGE_DIR, "lyrics")
CONFIG_PATH = os.path.join(STAGE_DIR, "config.json")
DEFAULT_DB = os.path.join(REPO, "ImasLiveDB", "Resources", "master.sqlite")

KINDS = {"lyric", "marker", "blank"}
SECTIONS = {"intro", "verse", "pre", "chorus", "bridge", "interlude", "outro", ""}

MAX_LINE_CHARS = 200
MAX_LINES = 400

# 空行が2つ以上続いたら間奏とみなす閾値
INTERLUDE_BLANKS = 2

# HTML の改行タグ。Web からコピーした歌詞に混ざるので改行に潰す。
# <br> <br/> <br /> <BR> いずれも。
BR_RE = re.compile(r"<\s*br\s*/?\s*>", re.IGNORECASE)
# 素の HTML タグが残っていたら検出して警告する (取りこぼしの発見用)
TAG_RE = re.compile(r"<[^>]{1,40}>")


def default_source():
    """lyrics_local/config.json の default_source。毎回 --source を打たずに済む。"""
    if not os.path.exists(CONFIG_PATH):
        return ""
    try:
        with open(CONFIG_PATH, encoding="utf-8") as f:
            return (json.load(f).get("default_source") or "").strip()
    except Exception:
        return ""


def ensure_gitignored():
    rc = subprocess.run(
        ["git", "-C", REPO, "check-ignore", "-q", "lyrics_local"],
        capture_output=True,
    ).returncode
    if rc != 0:
        sys.exit(
            "✗ lyrics_local/ が gitignore されていない。中断する。\n"
            "  歌詞が公開リポジトリに入ると JASRAC の許諾条件を破る。"
        )


def song_title(song_id):
    import sqlite3
    if not os.path.exists(DEFAULT_DB):
        return ""
    conn = sqlite3.connect("file:%s?mode=ro" % DEFAULT_DB, uri=True)
    row = conn.execute("SELECT title FROM songs WHERE id = ?", (song_id,)).fetchone()
    conn.close()
    return row[0] if row else ""


def json_path(song_id):
    return os.path.join(JSON_DIR, song_id + ".json")


def text_to_lines(text, auto_marker=True):
    """プレーンテキストを行の配列にする。

    - 行頭行末の空白は落とす (歌詞の意味を変えないため)
    - 全角空白は残す (詞の間合いとして意味を持つことがある)
    - 空行が2つ以上続いたら間奏マーカーを挿入する
    - <br> は改行として扱う (Web からコピーした歌詞に混ざるため)
    """
    text = BR_RE.sub("\n", text)
    raw = [ln.rstrip() for ln in text.replace("\r\n", "\n").replace("\r", "\n").split("\n")]

    lines = []
    blank_run = 0
    for ln in raw:
        stripped = ln.strip()
        if not stripped:
            blank_run += 1
            continue
        if blank_run:
            if auto_marker and blank_run >= INTERLUDE_BLANKS:
                lines.append({"kind": "marker", "text": "間奏"})
            elif lines:
                lines.append({"kind": "blank", "text": ""})
            blank_run = 0
        lines.append({"kind": "lyric", "text": stripped})

    # 前後にイントロ/アウトロのマーカーを置く。コールの受け皿になる。
    if auto_marker and lines:
        lines.insert(0, {"kind": "marker", "text": "イントロ"})
        lines.append({"kind": "marker", "text": "アウトロ"})
    return lines


def build_doc(song_id, lines, source, note=""):
    return {
        "song_id": song_id,
        "title": song_title(song_id),
        "source": source,
        "note": note,
        "lines": lines,
    }


def write_doc(song_id, doc):
    os.makedirs(JSON_DIR, exist_ok=True)
    with open(json_path(song_id), "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")


def validate_doc(doc, path):
    """(errors, warnings) を返す。"""
    errors, warnings = [], []

    if not doc.get("song_id"):
        errors.append("song_id が空")
    if not (doc.get("source") or "").strip():
        # 表示には使わないが、権利者からの申し入れやコミュニティ投稿の承認時に
        # 「そのテキストがどこから来たか」を示す唯一の記録になる。
        # 自分で転記する分には省略してよいので警告に留める。
        warnings.append("source (出典) が空")

    lines = doc.get("lines")
    if not isinstance(lines, list) or not lines:
        errors.append("lines が空または配列でない")
        return errors, warnings
    if len(lines) > MAX_LINES:
        errors.append("行数が多すぎる (%d > %d)" % (len(lines), MAX_LINES))

    lyric_count = 0
    for i, ln in enumerate(lines):
        where = "lines[%d]" % i
        if not isinstance(ln, dict):
            errors.append("%s がオブジェクトでない" % where)
            continue
        kind = ln.get("kind", "lyric")
        if kind not in KINDS:
            errors.append("%s kind が不正: %r" % (where, kind))
        text = ln.get("text", "")
        if not isinstance(text, str):
            errors.append("%s text が文字列でない" % where)
            continue
        if "\n" in text or "\r" in text:
            errors.append("%s text に改行が含まれる。1行1要素にすること" % where)
        if len(text) > MAX_LINE_CHARS:
            errors.append("%s text が長すぎる (%d文字)。行を分けること" % (where, len(text)))
        tag = TAG_RE.search(text)
        if tag:
            errors.append("%s に HTML タグが残っている: %r" % (where, tag.group(0)))
        sec = ln.get("section", "")
        if sec not in SECTIONS:
            warnings.append("%s section が未知: %r" % (where, sec))
        if kind == "lyric":
            if not text.strip():
                errors.append("%s kind=lyric なのに text が空" % where)
            lyric_count += 1

    if lyric_count == 0:
        errors.append("歌詞行 (kind=lyric) が1つもない")

    # 全行が同一 = コピペ事故の疑い
    texts = [ln.get("text", "") for ln in lines if isinstance(ln, dict) and ln.get("kind") == "lyric"]
    if len(texts) > 3 and len(set(texts)) == 1:
        warnings.append("歌詞行が全て同一。貼り付け事故の疑い")

    return errors, warnings


def cmd_init(args):
    for song_id in args.song_ids:
        if os.path.exists(json_path(song_id)) and not args.force:
            print("skip (既にある): %s" % song_id)
            continue
        write_doc(song_id, build_doc(song_id, [
            {"kind": "marker", "text": "イントロ"},
            {"kind": "lyric", "text": "", "section": "verse"},
        ], args.source or default_source()))
        print("wrote %s" % json_path(song_id))


def cmd_from_text(args):
    if args.all:
        paths = sorted(glob.glob(os.path.join(BODY_DIR, "*.txt")))
    else:
        if not args.song_ids:
            sys.exit("song_id を指定するか --all を付ける")
        paths = [os.path.join(BODY_DIR, sid + ".txt") for sid in args.song_ids]

    made = skipped = 0
    for p in paths:
        song_id = os.path.splitext(os.path.basename(p))[0]
        if not os.path.exists(p):
            print("なし: %s" % p)
            continue
        with open(p, encoding="utf-8") as f:
            text = f.read()
        if not text.strip():
            skipped += 1
            continue
        if os.path.exists(json_path(song_id)) and not args.force:
            print("skip (既にある。上書きは --force): %s" % song_id)
            skipped += 1
            continue

        lines = text_to_lines(text, auto_marker=not args.no_auto_marker)
        doc = build_doc(song_id, lines,
                        args.source or default_source(), args.note or "")
        errors, warnings = validate_doc(doc, json_path(song_id))
        if errors:
            print("✗ %s" % song_id)
            for e in errors:
                print("    %s" % e)
            continue
        write_doc(song_id, doc)
        made += 1
        print("✓ %-40s %d行 (歌詞 %d)"
              % (song_id, len(lines),
                 sum(1 for l in lines if l["kind"] == "lyric")))
        for w in warnings:
            print("    警告: %s" % w)

    print("\n変換 %d件 / スキップ %d件" % (made, skipped))


def cmd_set_source(args):
    os.makedirs(STAGE_DIR, exist_ok=True)
    cfg = {}
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, encoding="utf-8") as f:
                cfg = json.load(f)
        except Exception:
            pass
    cfg["default_source"] = args.source
    with open(CONFIG_PATH, "w", encoding="utf-8", newline="\n") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("既定の出典を設定した: %r" % args.source)


def cmd_validate(args):
    paths = sorted(glob.glob(os.path.join(JSON_DIR, "*.json")))
    if not paths:
        print("lyrics_local/lyrics/ に JSON がない")
        return
    ng = 0
    for p in paths:
        try:
            with open(p, encoding="utf-8") as f:
                doc = json.load(f)
        except Exception as e:
            print("✗ %s: JSON として読めない: %s" % (os.path.basename(p), e))
            ng += 1
            continue
        errors, warnings = validate_doc(doc, p)
        if errors:
            ng += 1
            print("✗ %s" % os.path.basename(p))
            for e in errors:
                print("    %s" % e)
        for w in warnings:
            print("  警告 %s: %s" % (os.path.basename(p), w))

    print("\n検証 %d件 / 問題 %d件" % (len(paths), ng))
    if ng:
        sys.exit(1)


def cmd_stats(args):
    paths = sorted(glob.glob(os.path.join(JSON_DIR, "*.json")))
    total_lines = 0
    no_source = 0
    for p in paths:
        try:
            with open(p, encoding="utf-8") as f:
                doc = json.load(f)
        except Exception:
            continue
        total_lines += sum(1 for l in doc.get("lines", [])
                           if isinstance(l, dict) and l.get("kind") == "lyric")
        if not (doc.get("source") or "").strip():
            no_source += 1
    print("歌詞 JSON      : %d曲" % len(paths))
    print("歌詞行の合計   : %d行" % total_lines)
    print("出典が空       : %d曲  ← 投入前に埋めること" % no_source)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("init", help="空の雛形 JSON を作る")
    p.add_argument("song_ids", nargs="+")
    p.add_argument("--source", help="出典")
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=cmd_init)

    p = sub.add_parser("from-text", help="lyrics_local/body/<id>.txt から変換する")
    p.add_argument("song_ids", nargs="*")
    p.add_argument("--all", action="store_true", help="body/*.txt を全部")
    p.add_argument("--source", help="出典 (例: CD歌詞カード (COCC-17064))")
    p.add_argument("--note", help="メモ")
    p.add_argument("--no-auto-marker", action="store_true",
                   help="イントロ/間奏/アウトロのマーカーを自動挿入しない")
    p.add_argument("--force", action="store_true", help="既存の JSON を上書き")
    p.set_defaults(func=cmd_from_text)

    p = sub.add_parser("set-source", help="出典の既定値を設定する")
    p.add_argument("source")
    p.set_defaults(func=cmd_set_source)

    p = sub.add_parser("validate", help="JSON を検証する")
    p.set_defaults(func=cmd_validate)

    p = sub.add_parser("stats", help="進捗を出す")
    p.set_defaults(func=cmd_stats)

    args = ap.parse_args()
    ensure_gitignored()
    args.func(args)


if __name__ == "__main__":
    main()
