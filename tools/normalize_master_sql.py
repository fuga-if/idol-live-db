#!/usr/bin/env python3
"""normalize_master_sql.py — db/master.sql を どの sqlite3 でも読める形に均す。

Usage:
    python3 tools/normalize_master_sql.py db/master.sql          # 確認だけ
    python3 tools/normalize_master_sql.py db/master.sql --apply  # 書き換える

## なぜ要るか

**SQLite 3.49 以降の `.dump` は、制御文字を含む文字列を `unistr('…\\u000a…')` で書く。**
`unistr()` はその版で入った関数なので、**それより古い sqlite3 では読めない**:

    Parse error near line 630: no such function: unistr

`db/master.sql` は正本で、CI (core-guard / Android Guard の generateSeedDb) や
他の環境の sqlite3 が読む。手元の sqlite3 が新しいというだけで正本が読めなくなるのは、
生成物ではなく**正本の可搬性の問題**なので、ダンプした側で均す。

改行を含む文字列は素の SQL リテラルにそのまま改行を書けば表せる。意味は変わらない
(`unistr('a\\u000ab')` と `'a<改行>b'` は同じ値)。実データで出てくるのは改行だけ
(2026-09-03 時点で creators の別名 59 行・133 箇所、すべて `\\u000a`)。

⚠️ 改行以外のエスケープが出てきたら**わざと落とす**。黙って壊れた値を書くより、
   気づいて対処する方が安い。
"""

import argparse
import io
import re
import sys

# unistr('…') の中身だけを取る。SQL リテラルなので、中の ' は '' で書かれている。
UNISTR = re.compile(r"unistr\('((?:[^']|'')*)'\)")
ESCAPE = re.compile(r"\\u([0-9a-fA-F]{4})")


def unescape(body: str) -> str:
    """unistr の中身を素の SQL リテラルの中身に変換する。"""
    unknown = {m.group(0) for m in ESCAPE.finditer(body) if m.group(1).lower() != "000a"}
    if unknown:
        raise SystemExit(
            "改行 (\\u000a) 以外のエスケープが出た: %s\n"
            "素のリテラルで表せるか確かめてから、このツールに足すこと。"
            % ", ".join(sorted(unknown))
        )
    if "\\" in ESCAPE.sub("", body):
        # 素のリテラルではバックスラッシュはただの文字なので、unistr が \\ で
        # 書いていた場合に意味が変わってしまう。実データには無いが、出たら止める。
        raise SystemExit("unistr の中に生のバックスラッシュがある。手で確認すること。")
    return ESCAPE.sub("\n", body)


def normalize(text: str) -> tuple[str, int]:
    count = 0

    def repl(m: re.Match) -> str:
        nonlocal count
        count += 1
        return "'%s'" % unescape(m.group(1))

    return UNISTR.sub(repl, text), count


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", help="正規化する .sql")
    ap.add_argument("--apply", action="store_true", help="実際に書き換える")
    args = ap.parse_args()

    with io.open(args.path, encoding="utf-8") as f:
        text = f.read()
    out, count = normalize(text)

    if count == 0:
        print("unistr() は無い。そのままで良い。")
        return
    print("unistr() を %d 箇所ほどいた" % count)
    if not args.apply:
        print("(--apply で書き換える)")
        return
    with io.open(args.path, "w", encoding="utf-8") as f:
        f.write(out)
    print("%s を書き換えた" % args.path)


if __name__ == "__main__":
    main()
