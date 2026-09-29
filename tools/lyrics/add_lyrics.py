#!/usr/bin/env python3
"""add_lyrics.py — 歌詞テキストを貼るだけで登録する。

Usage:
    # クリップボードから (いちばん安全。シェルが一切解釈しない)
    python3 tools/lyrics/add_lyrics.py "お願い！シンデレラ" --clipboard

    # 引数で渡す。**必ず全体をクォートすること**
    python3 tools/lyrics/add_lyrics.py "お願い！シンデレラ" "一行目<br>二行目<br>三行目"

    # 標準入力から。貼り付けて Ctrl-D
    python3 tools/lyrics/add_lyrics.py "お願い！シンデレラ"

    # パイプで
    pbpaste | python3 tools/lyrics/add_lyrics.py "お願い！シンデレラ"

    # song_id で直接
    python3 tools/lyrics/add_lyrics.py --id cg_お願いシンデレラ --clipboard

    # 投入まで一気に (バックエンド実装後)
    python3 tools/lyrics/add_lyrics.py "お願い！シンデレラ" --clipboard --push

曲名から song_id を解決する。同名の曲が複数あるときは候補を出して選ばせる。

改行の形式は問わない:
    通常の改行 / <br> / <br/> / <br /> / <BR> のいずれでも受け付ける。
    引数で渡すときは <br> 区切りにすると1行に収まって扱いやすい。

⚠ 引数で渡すときは必ずクォートすること。
   < と > はシェルのリダイレクト記号なので、クォートしないと
   `<br>夢は…` が「br を読んで 夢は… に書く」と解釈され、
   **意図しないファイルが作られる/上書きされる**。
   クォートを忘れやすいので、迷ったら --clipboard を使うこと。

注意: 引数で渡した歌詞はシェルの履歴 (~/.zsh_history 等) に残る。
      気になる場合は標準入力かクリップボードを使うこと。

出力は lyrics_local/lyrics/<song_id>.json (gitignore 済み)。
**data/fixes/ には置かない** — 公開 git リポジトリなので、歌詞を置くと
JASRAC の許諾条件 (一括ダウンロードできない形での配信) を破る。
"""

import argparse
import json
import os
import subprocess
import sqlite3
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import lyrics_json as LJ  # noqa: E402

DEFAULT_DB = os.path.join(REPO, "ImasLiveDB", "Resources", "master.sqlite")


def norm(s):
    s = unicodedata.normalize("NFKC", s or "").lower()
    return "".join(s.split())


def resolve_song(db_path, title=None, song_id=None):
    """曲名または song_id から (song_id, title) を1件に決める。"""
    conn = sqlite3.connect("file:%s?mode=ro" % db_path, uri=True)
    conn.row_factory = sqlite3.Row

    if song_id:
        row = conn.execute(
            "SELECT id, title, brand_id, "
            "COALESCE(NULLIF(singer_label,''), NULLIF(unit_name,''), '') AS artist "
            "FROM songs WHERE id = ?", (song_id,)).fetchone()
        conn.close()
        if not row:
            sys.exit("song_id が見つからない: %s" % song_id)
        return row["id"], row["title"]

    rows = conn.execute(
        "SELECT id, title, brand_id, "
        "COALESCE(NULLIF(singer_label,''), NULLIF(unit_name,''), '') AS artist, "
        "(SELECT COUNT(*) FROM setlist_items si WHERE si.song_id = songs.id) AS cnt "
        "FROM songs ORDER BY cnt DESC").fetchall()
    conn.close()

    key = norm(title)
    exact = [r for r in rows if norm(r["title"]) == key]
    if not exact:
        partial = [r for r in rows if key and key in norm(r["title"])]
        if not partial:
            sys.exit("曲が見つからない: %r" % title)
        exact = partial

    if len(exact) == 1:
        return exact[0]["id"], exact[0]["title"]

    print("候補が %d件ある。どれか選べ:\n" % len(exact), file=sys.stderr)
    for i, r in enumerate(exact[:20], 1):
        print("  %2d) %-40s %-10s %s (セトリ%d回)"
              % (i, r["title"][:38], r["brand_id"], r["artist"][:24], r["cnt"]),
              file=sys.stderr)
    print("", file=sys.stderr)
    if not sys.stdin.isatty():
        sys.exit("複数候補がある。--id で song_id を直接指定するか、対話で実行すること。")
    try:
        n = int(input("番号: ").strip())
    except (ValueError, EOFError):
        sys.exit("中断")
    if not 1 <= n <= len(exact):
        sys.exit("範囲外")
    return exact[n - 1]["id"], exact[n - 1]["title"]


def read_text(args):
    if args.inline_text:
        return args.inline_text
    if args.clipboard:
        try:
            return subprocess.run(["pbpaste"], capture_output=True, check=True,
                                  text=True).stdout
        except Exception as e:
            sys.exit("クリップボードを読めない: %s" % e)
    if args.file:
        with open(args.file, encoding="utf-8") as f:
            return f.read()
    if sys.stdin.isatty():
        print("歌詞を貼り付けて、最後に Ctrl-D を押してください。", file=sys.stderr)
    return sys.stdin.read()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("words", nargs="*",
                    help="曲名 [歌詞]。--id 指定時は歌詞だけ")
    ap.add_argument("--id", dest="song_id", help="song_id を直接指定")
    ap.add_argument("--text", help="歌詞をここに渡してもよい")
    ap.add_argument("--db", default=DEFAULT_DB)
    ap.add_argument("--clipboard", action="store_true", help="クリップボードから読む")
    ap.add_argument("--file", help="ファイルから読む")
    ap.add_argument("--source", help="出典 (省略時は config の既定値)")
    ap.add_argument("--note", default="")
    ap.add_argument("--no-auto-marker", action="store_true",
                    help="イントロ/間奏/アウトロのマーカーを自動挿入しない")
    ap.add_argument("--force", action="store_true", help="既存の歌詞を上書き")
    ap.add_argument("--push", action="store_true", help="登録後に D1 へ投入する")
    ap.add_argument("--base-url", help="--push の送信先 (省略時は本番)")
    args = ap.parse_args()

    # 位置引数の解釈。--id があれば全部が歌詞、無ければ先頭が曲名で残りが歌詞。
    words = list(args.words)
    if args.song_id:
        args.title = None
        inline = " ".join(words)
    else:
        args.title = words.pop(0) if words else None
        inline = " ".join(words)
    args.inline_text = args.text or inline or ""

    if not args.title and not args.song_id:
        ap.error("曲名または --id が要る")

    LJ.ensure_gitignored()

    song_id, title = resolve_song(args.db, args.title, args.song_id)
    text = read_text(args)
    if not text.strip():
        sys.exit("歌詞が空")

    path = LJ.json_path(song_id)
    if os.path.exists(path) and not args.force:
        sys.exit("既に歌詞がある: %s\n  上書きするなら --force" % path)

    # シェルにリダイレクトとして食われた形跡を検出する。
    # クォートし忘れると `<br` 以降が切り落とされ、短い断片だけが届く。
    if args.inline_text:
        stray = [c for c in "<>" if c in LJ.BR_RE.sub("", text)]
        if stray:
            print("⚠ 引数に %s が残っている。クォートし忘れの可能性がある。"
                  % "/".join(stray), file=sys.stderr)
        if "<br" not in text.lower() and "\n" not in text and len(text) < 200:
            print("⚠ 改行も <br> も無い短いテキスト。シェルに切られていないか確認すること。"
                  "\n   安全な方法: --clipboard", file=sys.stderr)

    lines = LJ.text_to_lines(text, auto_marker=not args.no_auto_marker)
    doc = LJ.build_doc(song_id, lines, args.source or LJ.default_source(), args.note)

    errors, warnings = LJ.validate_doc(doc, path)
    for w in warnings:
        print("警告: %s" % w, file=sys.stderr)
    if errors:
        print("\n✗ 登録しない。以下を直すこと:", file=sys.stderr)
        for e in errors:
            print("    %s" % e, file=sys.stderr)
        sys.exit(1)

    LJ.write_doc(song_id, doc)

    kinds = {}
    for l in lines:
        kinds[l["kind"]] = kinds.get(l["kind"], 0) + 1
    print("✓ %s (%s)" % (title, song_id))
    print("  %s" % " / ".join("%s %d" % (k, v) for k, v in sorted(kinds.items())))
    print("  → %s" % path)

    if args.push:
        push = os.path.join(HERE, "push_lyrics.py")
        if not os.path.exists(push):
            sys.exit("\npush_lyrics.py がまだ無い (バックエンド実装待ち)。"
                     "\nJSON は書けているので、後からまとめて投入できる。")
        cmd = [sys.executable, push, "--apply", "--song-id", song_id]
        if args.base_url:
            cmd += ["--base-url", args.base_url]
        print("\n投入中...")
        sys.exit(subprocess.run(cmd).returncode)


if __name__ == "__main__":
    main()
