#!/usr/bin/env python3
"""verify.py — lyrics-ocr の読み順が壊れていないかを自動検証する。

Usage:
    python3 tools/lyrics/test/verify.py <bin/lyrics-ocr> <テスト画像ディレクトリ>
    (通常は `make verify` から呼ばれる)

GenTestImage.swift が描いた自作ダミー文 (著作物ではない) を OCR し、
期待する読み順と一致するかを見る。OCR は 1 文字単位の誤認識を起こしうるので、
「完全一致」ではなく「行の並び順」を評価する:

  - 行数が期待どおりか
  - 各行が期待行と十分似ているか (文字の一致率)
  - 行の順序が入れ替わっていないか

歌詞は 1 文字違うと意味が変わるので、しきい値は高め (0.8)。
"""

import difflib
import os
import re
import subprocess
import sys

# GenTestImage.swift のダミー文と対応させること。
L = {
    "a": "あかつきのそらへ",
    "b": "ちいさなてをふる",
    "c": "きみのなまえをよぶ",
    "d": "かぜがはこんでゆく",
    "e": "ゆめのつづきをうたう",
    "f": "ひかりのなかで",
}

CASES = [
    # (画像, 追加オプション, 期待する向き, 期待する読み順)
    ("vertical.png", [], "vertical", ["a", "b", "c", "d", "e", "f"]),
    ("vertical_ruby.png", [], "vertical", ["a", "b", "c", "f"]),
    ("vertical_2block.png", [], "vertical", ["a", "b", "c", "d", "e", "f"]),
    ("horizontal_2col.png", [], "horizontal", ["a", "b", "c", "d", "e", "f"]),
    ("horizontal.png", [], "horizontal", ["a", "b", "c", "d", "e", "f"]),
]

MARKER_RE = re.compile(r"^\[\?\][0-9.]+\s*")
SIMILARITY_THRESHOLD = 0.8


def run_ocr(binary, image, extra):
    out = subprocess.run([binary, "--quiet"] + extra + [image],
                         capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError("lyrics-ocr failed: %s" % out.stderr)
    return out.stdout


def parse(raw):
    """# 始まりを捨てて本文行だけ返す。マーカーは剥がす。"""
    lines = []
    meta = {}
    for line in raw.splitlines():
        if line.startswith("#"):
            m = re.match(r"#\s*(orientation|ruby|blocks|low-confidence-lines):\s*(.*)", line)
            if m:
                meta.setdefault(m.group(1), m.group(2))
            continue
        line = MARKER_RE.sub("", line).strip()
        if line:
            lines.append(line)
    return lines, meta


def similar(a, b):
    return difflib.SequenceMatcher(None, a, b).ratio()


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    binary, imgdir = sys.argv[1], sys.argv[2]
    failures = 0

    for name, extra, want_orientation, want_keys in CASES:
        path = os.path.join(imgdir, name)
        if not os.path.exists(path):
            print("  SKIP %s (画像が無い)" % name)
            continue
        raw = run_ocr(binary, path, extra)
        got, meta = parse(raw)
        want = [L[k] for k in want_keys]

        problems = []
        orientation = (meta.get("orientation") or "").split()[0]
        if orientation != want_orientation:
            problems.append("向き判定 %s (期待 %s)" % (orientation or "?", want_orientation))
        if len(got) != len(want):
            problems.append("行数 %d (期待 %d)" % (len(got), len(want)))
        for i, expected in enumerate(want):
            if i >= len(got):
                problems.append("行%d 欠落: %s" % (i + 1, expected))
                continue
            r = similar(got[i], expected)
            if r < SIMILARITY_THRESHOLD:
                # 順序違いなのか誤認識なのかを切り分けて報告する。
                best = max(range(len(want)), key=lambda j: similar(got[i], want[j]))
                if similar(got[i], want[best]) >= SIMILARITY_THRESHOLD:
                    problems.append("行%d が期待の行%d の内容 (読み順の崩れ): %r" % (i + 1, best + 1, got[i]))
                else:
                    problems.append("行%d 不一致 (%.2f): got=%r want=%r" % (i + 1, r, got[i], expected))

        if problems:
            failures += 1
            print("✗ %s" % name)
            for p in problems:
                print("    - %s" % p)
            print("    got: %s" % got)
        else:
            print("✓ %s  (%s, %s, ruby=%s)"
                  % (name, orientation, meta.get("blocks", "?") + " blocks", meta.get("ruby", "?")))

    print("")
    if failures:
        print("%d 件失敗" % failures)
        return 1
    print("全ケース通過")
    return 0


if __name__ == "__main__":
    sys.exit(main())
