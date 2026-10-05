#!/usr/bin/env python3
"""P名刺の「名前の書体」を作る (iOS / Android / Web で同じ書体にする)。

書体の一覧 (キー・PostScript 名・ファイル名) の正はコア
(`imas-core/src/domain/producer_card.rs` の `card_name_font_info`)。ここの表はそれと揃える
(`imas-core/tests/card_name_fonts.rs` がファイルの有無と PostScript 名を確かめる)。

作るもの:
  1. 端末 (iOS / Android) に同梱する TTF  → fonts/card-name/card_name_<key>.ttf
     Google Fonts の配布リポジトリ (github.com/google/fonts、コミット固定) の TTF を、
     JIS X 0208 (第 1・第 2 水準・かな・記号) + ASCII + 半角カナ + 名前に使われがちな記号
     に絞る (そのままだと 1 書体 2〜15MB)。使用許諾 (SIL OFL 1.1) の全文も同じ場所に置く。
  2. Web の名刺ページ (/p/) が読む書体 → web/public/fonts/card/<key>/*.woff2 と
     web/src/styles/card-fonts.css
     Google Fonts の unicode-range 分割をそのまま自前で配る (CSP が font-src 'self' のため。
     ブラウザは名前に出る字を含む断片だけを取りに行く)。既定のゴシック (Zen Kaku Gothic New 900)
     はサイト全体の見出し書体 (web/src/styles/fonts.css) にあるので取りに行かない。

使い方 (fonttools と brotli が要る: pip install fonttools brotli):
  python3 tools/build_card_name_fonts.py            # 両方
  python3 tools/build_card_name_fonts.py --app-only
  python3 tools/build_card_name_fonts.py --web-only
"""
from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import sys
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_OUT = ROOT / "fonts" / "card-name"
WEB_FONT_OUT = ROOT / "web" / "public" / "fonts" / "card"
WEB_CSS_OUT = ROOT / "web" / "src" / "styles" / "card-fonts.css"

# github.com/google/fonts のコミット (固定して、作り直しても同じ書体になるようにする)。
GOOGLE_FONTS_COMMIT = "7085eb89a950e85db5b166b7a58d414544b4140c"
RAW = f"https://raw.githubusercontent.com/google/fonts/{GOOGLE_FONTS_COMMIT}/ofl"

# key, リポジトリのフォルダ, TTF, PostScript 名, 書体名, 太さ (Web)
FONTS = [
    ("gothic", "zenkakugothicnew", "ZenKakuGothicNew-Black.ttf", "ZenKakuGothicNew-Black", "Zen Kaku Gothic New", 900),
    ("mincho", "zenoldmincho", "ZenOldMincho-Black.ttf", "ZenOldMincho-Black", "Zen Old Mincho", 900),
    ("maru", "zenmarugothic", "ZenMaruGothic-Black.ttf", "ZenMaruGothic-Black", "Zen Maru Gothic", 900),
    ("pop", "mochiypopone", "MochiyPopOne-Regular.ttf", "MochiyPopOne-Regular", "Mochiy Pop One", 400),
    ("hand", "yomogi", "Yomogi-Regular.ttf", "Yomogi-Regular", "Yomogi", 400),
]

# 名前に使われがちで JIS X 0208 に無い字 (ハート・音符・波ダッシュの全角など)。
EXTRA_CHARS = "♡♥☆★♪♫♬♩✿❀❤✧✦〜～・ー々〆ヶヵゞゝヾヽ①②③④⑤⑥⑦⑧⑨⑩"

# Web 用の CSS を取るときの UA (woff2 と unicode-range を返させる)。
UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0 Safari/537.36"
)


def fetch(url: str, ua: str | None = None) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": ua or "build_card_name_fonts"})
    with urllib.request.urlopen(req, timeout=120) as res:
        return res.read()


def jis_charset() -> str:
    """JIS X 0208 の全字 (Shift_JIS の 2 バイト領域を全部デコードして集める) + ASCII ほか。"""
    chars: set[str] = set()
    for lead in list(range(0x81, 0xA0)) + list(range(0xE0, 0xF0)):
        for trail in list(range(0x40, 0x7F)) + list(range(0x80, 0xFD)):
            try:
                chars.add(bytes([lead, trail]).decode("shift_jis"))
            except UnicodeDecodeError:
                pass
    chars.update(chr(c) for c in range(0x20, 0x7F))  # ASCII
    chars.update(chr(c) for c in range(0xA0, 0x100))  # ラテン 1 (é など)
    chars.update(chr(c) for c in range(0xFF61, 0xFFA0))  # 半角カナ
    chars.update(EXTRA_CHARS)
    return "".join(sorted(chars))


def build_app() -> None:
    from fontTools import subset
    from fontTools.ttLib import TTFont

    APP_OUT.mkdir(parents=True, exist_ok=True)
    text = jis_charset()
    with tempfile.TemporaryDirectory() as tmp:
        for key, folder, ttf, ps_name, family, _ in FONTS:
            src = Path(tmp) / ttf
            print(f"==> {family}: {ttf}")
            src.write_bytes(fetch(f"{RAW}/{folder}/{ttf}"))
            (APP_OUT / f"OFL-{folder}.txt").write_bytes(fetch(f"{RAW}/{folder}/OFL.txt"))
            out = APP_OUT / f"card_name_{key}.ttf"
            options = subset.Options()
            options.layout_features = ["*"]  # 縦書き・字幅詰め (palt) などを残す
            options.name_IDs = ["*"]
            options.name_languages = ["*"]
            options.notdef_outline = True
            options.glyph_names = False
            font = TTFont(src)
            subsetter = subset.Subsetter(options)
            subsetter.populate(text=text)
            subsetter.subset(font)
            font.save(out)
            actual = TTFont(out)["name"].getDebugName(6)
            if actual != ps_name:
                sys.exit(f"PostScript 名が違う: {out.name} は {actual} (期待は {ps_name})")
            print(f"    {src.stat().st_size // 1024}KB → {out.stat().st_size // 1024}KB")


def build_web() -> None:
    WEB_FONT_OUT.mkdir(parents=True, exist_ok=True)
    lines = [
        "/* P名刺 (/p/) の名前の書体。tools/build_card_name_fonts.py が作る (手で直さない)。",
        "   Google Fonts の unicode-range 分割を自前で配る (CSP が font-src 'self')。",
        "   使用許諾は SIL OFL 1.1 (fonts/card-name/OFL-*.txt)。既定のゴシックは見出しの",
        "   Zen Kaku Gothic New 900 (fonts.css) をそのまま使う。 */",
        "",
    ]
    for key, folder, _ttf, _ps, family, weight in FONTS:
        if key == "gothic":
            continue
        css_url = (
            "https://fonts.googleapis.com/css2?family="
            + family.replace(" ", "+")
            + (f":wght@{weight}" if weight != 400 else "")
            + "&display=swap"
        )
        print(f"==> {family} (Web)")
        css = fetch(css_url, UA).decode("utf-8")
        out_dir = WEB_FONT_OUT / key
        if out_dir.exists():
            shutil.rmtree(out_dir)
        out_dir.mkdir(parents=True)
        blocks = re.findall(r"@font-face\s*{(.*?)}", css, re.S)
        for block in blocks:
            url = re.search(r"url\((https://[^)]+)\)", block).group(1)
            rng = re.search(r"unicode-range:\s*([^;]+);", block)
            data = fetch(url)
            name = hashlib.sha256(data).hexdigest()[:10] + ".woff2"
            (out_dir / name).write_bytes(data)
            lines += [
                "@font-face {",
                f"  font-family: 'IMAS Card {key}';",
                "  font-style: normal;",
                f"  font-weight: {weight};",
                "  font-display: swap;",
                f'  src: url("/fonts/card/{key}/{name}") format("woff2");',
            ]
            if rng:
                lines.append(f"  unicode-range: {rng.group(1).strip()};")
            lines += ["}", ""]
        print(f"    {len(blocks)} 断片")
    WEB_CSS_OUT.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--app-only", action="store_true")
    group.add_argument("--web-only", action="store_true")
    args = parser.parse_args()
    if not args.web_only:
        build_app()
    if not args.app_only:
        build_web()


if __name__ == "__main__":
    main()
