#!/usr/bin/env python3
"""tools/ の追跡中の Python を読んで、構文の壊れを一覧する (読むだけで何も書かない)。

    python3 tools/check_python_syntax.py

手元は Python 3.9、CI は 3.12 で動かしている。どちらでも動くことを確かめるため、
次の 2 つを落とす。

- 3.9 の文法で読めないもの (match 文など)。ast.parse の feature_version で見る。
- `str | None` のような注釈を、`from __future__ import annotations` 無しで書いたもの。
  3.12 では動くが、3.9 では関数を定義した時点で TypeError になる。
"""

import ast
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OLDEST = (3, 9)


def tracked_python_files():
    out = subprocess.check_output(["git", "ls-files", "-z", "--", "tools/*.py"], cwd=ROOT)
    return sorted(p for p in out.decode("utf-8").split("\0") if p)


def _has_future_annotations(tree):
    return any(
        isinstance(node, ast.ImportFrom) and node.module == "__future__"
        and any(alias.name == "annotations" for alias in node.names)
        for node in tree.body
    )


def _union_annotations(tree):
    """`X | Y` の形の注釈がある行番号を返す。"""
    annotations = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            args = node.args
            every = args.posonlyargs + args.args + args.kwonlyargs + [args.vararg, args.kwarg]
            annotations += [a.annotation for a in every if a is not None]
            annotations.append(node.returns)
        elif isinstance(node, ast.AnnAssign):
            annotations.append(node.annotation)
    return sorted({
        sub.lineno
        for ann in annotations if ann is not None
        for sub in ast.walk(ann)
        if isinstance(sub, ast.BinOp) and isinstance(sub.op, ast.BitOr)
    })


def problems_in(path, source):
    try:
        tree = ast.parse(source, filename=path, feature_version=OLDEST)
    except SyntaxError as e:
        return ["%s:%s: 構文エラー (Python %d.%d の文法): %s" % (path, e.lineno, *OLDEST, e.msg)]
    if _has_future_annotations(tree):
        return []
    return ["%s:%d: `X | Y` の注釈には from __future__ import annotations が要る (3.9 で落ちる)"
            % (path, line) for line in _union_annotations(tree)]


def main():
    files = tracked_python_files()
    problems = []
    for path in files:
        with open(os.path.join(ROOT, path), encoding="utf-8") as f:
            problems += problems_in(path, f.read())
    for p in problems:
        print("✗ " + p)
    print("%d 本を読んだ。問題 %d 件" % (len(files), len(problems)))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
