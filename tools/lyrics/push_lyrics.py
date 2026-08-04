#!/usr/bin/env python3
"""push_lyrics.py — lyrics_local/lyrics/*.json を D1 (Cloudflare Worker) に投入する。

Usage:
    # 何が送られるか見るだけ (既定。何も書き換えない)
    python3 tools/lyrics/push_lyrics.py cg_お願いシンデレラ

    # 実際に送る
    python3 tools/lyrics/push_lyrics.py cg_お願いシンデレラ --apply

    # ローカルの wrangler dev に向ける
    python3 tools/lyrics/push_lyrics.py --all --base-url http://127.0.0.1:8787 --apply

    # 下書きとして入れておく (GET は published しか返さない)
    python3 tools/lyrics/push_lyrics.py --all --status draft --apply

置き場所と経路:
    lyrics_local/lyrics/<song_id>.json  →  PUT /admin/lyrics/<song_id>  →  D1

**歌詞本文は D1 にしか置かない。** db/master.sql / ImasLiveDB/Resources/master.sqlite /
CloudKit のいずれにも入れない。JASRAC 許諾の条件が「ユーザが一括ダウンロードできない
形式での配信」であり、bundle SQLite も CloudKit 同期も一括ダウンロードそのもの。
そのため lyrics_local/ は .gitignore 済みで、起動時に確認する (tools/backup_d1.sh と同じガード)。

**1リクエスト = 1曲。** 複数曲をまとめて送る経路は作らない (サーバ側にも無い)。
--all でも1曲ずつ PUT を投げる。

トークン:
    ~/.config/imas/admin_token に管理者のセッション JWT を1行で置く。
    コマンドライン引数や環境変数で歌詞・トークンを渡す経路は作らない
    (ps / シェル履歴に残るため)。
"""

import argparse
import glob
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
JSON_DIR = os.path.join(REPO, "lyrics_local", "lyrics")
TOKEN_PATH = os.path.expanduser("~/.config/imas/admin_token")
# ImasLiveDB/Services/APIEndpoints.swift の baseURL と同じ本番 Worker。
DEFAULT_BASE_URL = "https://imas-live-api.tokata3011.workers.dev"

sys.path.insert(0, HERE)
from lyrics_json import validate_doc  # noqa: E402  (同ディレクトリの検証ロジックを共有する)


def ensure_gitignored():
    """lyrics_local/ が git 管理外であることを確認する。

    このリポジトリは public。歌詞が commit されると JASRAC の許諾条件を破り、
    しかも git 履歴からは実質消せない。送信前に必ず止める。
    """
    rc = subprocess.run(
        ["git", "-C", REPO, "check-ignore", "-q", "lyrics_local"],
        capture_output=True,
    ).returncode
    if rc != 0:
        sys.exit(
            "✗ lyrics_local/ が gitignore されていない。中断する。\n"
            "  歌詞が公開リポジトリに入ると JASRAC の許諾条件を破る。"
        )


def read_token(path):
    if not os.path.exists(path):
        sys.exit(
            "✗ 管理者トークンが無い: %s\n"
            "  アプリでログインして得たセッション JWT を1行で置くこと:\n"
            "    mkdir -p ~/.config/imas && chmod 700 ~/.config/imas\n"
            "    printf '%%s' '<JWT>' > %s && chmod 600 %s" % (path, path, path)
        )
    with open(path, encoding="utf-8") as f:
        token = f.read().strip()
    if not token:
        sys.exit("✗ %s が空" % path)
    return token


def load_doc(song_id):
    path = os.path.join(JSON_DIR, song_id + ".json")
    if not os.path.exists(path):
        return None, "JSON が無い: %s" % path
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
    errors, warnings = validate_doc(doc, path)
    for w in warnings:
        print("  ! %s" % w)
    if errors:
        return None, "検証エラー:\n    " + "\n    ".join(errors)
    return doc, None


def build_payload(doc, status):
    """サーバが受け取る形 {source, status, lines:[{kind,text,section}]} に絞る。

    行 ID はサーバ採番 (発行後不変) なので、こちらからは一切送らない。
    """
    lines = []
    for line in doc["lines"]:
        item = {"kind": line.get("kind", "lyric"), "text": line.get("text", "")}
        section = line.get("section") or None
        if section:
            item["section"] = section
        lines.append(item)
    # doc に status があればそちらを優先する (曲ごとに公開/下書きを持てるように)。
    return {
        "source": doc.get("source") or None,
        "status": doc.get("status") or status,
        "lines": lines,
    }


def put_lyrics(base_url, token, song_id, payload):
    # song_id は非 ASCII を含む ("765as_蒼い鳥")。safe="" で全部エスケープする。
    url = "%s/admin/lyrics/%s" % (
        base_url.rstrip("/"),
        urllib.parse.quote(song_id, safe=""),
    )
    req = urllib.request.Request(
        url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        method="PUT",
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "Authorization": "Bearer " + token,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            return res.status, json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        return e.code, body
    except urllib.error.URLError as e:
        return 0, str(e)


def main():
    ap = argparse.ArgumentParser(description="歌詞 JSON を D1 に投入する")
    ap.add_argument("song_ids", nargs="*", help="投入する song_id")
    ap.add_argument("--all", action="store_true", help="lyrics_local/lyrics/*.json 全部")
    ap.add_argument("--base-url", default=DEFAULT_BASE_URL,
                    help="API のベース URL (ローカル検証は http://127.0.0.1:8787)")
    ap.add_argument("--status", default="published", choices=["draft", "published"],
                    help="JSON 側に status が無いときの既定 (既定: published)")
    # トークンは常にファイルから読む。値そのものを引数で渡す経路は作らない
    # (ps とシェル履歴に残る)。ここで受けるのは置き場所だけ。
    ap.add_argument("--token-path", default=TOKEN_PATH,
                    help="管理者トークンのファイル (既定: %s)" % TOKEN_PATH)
    ap.add_argument("--apply", action="store_true",
                    help="実際に送る。付けない限り dry-run (何も書き換えない)")
    args = ap.parse_args()

    ensure_gitignored()

    song_ids = list(args.song_ids)
    if args.all:
        song_ids += [
            os.path.splitext(os.path.basename(p))[0]
            for p in sorted(glob.glob(os.path.join(JSON_DIR, "*.json")))
        ]
    # 重複を落としつつ順序は保つ
    song_ids = list(dict.fromkeys(song_ids))
    if not song_ids:
        sys.exit("投入する曲がない。song_id を指定するか --all を付ける。")

    token = read_token(args.token_path) if args.apply else None
    mode = "APPLY" if args.apply else "DRY-RUN"
    print("[%s] %s → %d 曲" % (mode, args.base_url, len(song_ids)))

    ok = failed = 0
    for song_id in song_ids:
        print("- %s" % song_id)
        doc, err = load_doc(song_id)
        if err:
            print("  ✗ %s" % err)
            failed += 1
            continue
        payload = build_payload(doc, args.status)
        n_lyric = sum(1 for l in payload["lines"] if l["kind"] == "lyric")
        print("  %d 行 (歌詞 %d) / status=%s / source=%s"
              % (len(payload["lines"]), n_lyric, payload["status"],
                 payload["source"] or "(なし)"))
        if not args.apply:
            continue
        status, body = put_lyrics(args.base_url, token, song_id, payload)
        if status == 200:
            print("  ✓ 保存: %d 行" % len(body.get("lines", [])))
            ok += 1
        else:
            print("  ✗ HTTP %s: %s" % (status, body))
            failed += 1

    if args.apply:
        print("\n完了: 成功 %d / 失敗 %d" % (ok, failed))
        if failed:
            sys.exit(1)
    else:
        print("\n(dry-run。実際に送るには --apply)")
        if failed:
            sys.exit(1)


if __name__ == "__main__":
    main()
