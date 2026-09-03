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
    ~/.config/imas/lyrics_push_token に運用者トークンを1行で置く。
    Worker 側は `npx wrangler secret put LYRICS_PUSH_TOKEN` で同じ値を設定する。
    (admin のセッション JWT を ~/.config/imas/admin_token に置く旧方式も使える)
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
# 運用者トークン。Worker の LYRICS_PUSH_TOKEN と同じ値を置く。
# アプリからは歌詞を直接投入できない (提案のみ) ので、ユーザーのセッション JWT を
# 端末から持ち出す必要がないようにこちらを既定にしている。
TOKEN_PATH = os.path.expanduser("~/.config/imas/lyrics_push_token")
# 後方互換: admin のセッション JWT でも投入できる。
LEGACY_TOKEN_PATH = os.path.expanduser("~/.config/imas/admin_token")
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
    if not os.path.exists(path) and path == TOKEN_PATH and os.path.exists(LEGACY_TOKEN_PATH):
        path = LEGACY_TOKEN_PATH          # admin JWT の旧方式にも対応する
    if not os.path.exists(path):
        sys.exit(
            "✗ 投入トークンが無い: %s\n\n"
            "  運用者トークンを作って両側に設定する:\n"
            "    TOKEN=$(python3 -c \"import secrets;print(secrets.token_urlsafe(32))\")\n"
            "    mkdir -p ~/.config/imas && chmod 700 ~/.config/imas\n"
            "    printf '%%s' \"$TOKEN\" > %s && chmod 600 %s\n"
            "    cd imas-live-api && printf '%%s' \"$TOKEN\" | npx wrangler secret put LYRICS_PUSH_TOKEN\n"
            % (path, path, path)
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
            # Cloudflare のボット保護が既定の "Python-urllib/x.y" を
            # 403 (error code 1010) で弾くので、素性の分かる UA を明示する。
            "User-Agent": "imas-lyrics-push/1.0",
            "Content-Type": "application/json; charset=utf-8",
            # 運用者トークンは X-Push-Token、セッション JWT は Authorization で送る。
            # JWT は "eyJ" (base64 の '{"') で始まるので、それで見分ける。
            **({"Authorization": "Bearer " + token} if token.startswith("eyJ")
               else {"X-Push-Token": token}),
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


def fetch_quota(base_url, token):
    """GET /admin/lyrics/quota。取れなければ None (枠の確認は必須ではない)。"""
    req = urllib.request.Request(
        base_url.rstrip("/") + "/admin/lyrics/quota",
        headers={"X-Push-Token": token} if token else {},
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as res:
            return json.loads(res.read().decode("utf-8"))
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser(description="歌詞 JSON を D1 に投入する")
    ap.add_argument("song_ids", nargs="*", help="投入する song_id")
    ap.add_argument("--all", action="store_true", help="lyrics_local/lyrics/*.json 全部")
    ap.add_argument("--base-url", default=DEFAULT_BASE_URL,
                    help="API のベース URL (ローカル検証は http://127.0.0.1:8787)")
    # 既定は draft。published は掲載枠 (許諾 J260943703 / 100曲) を消費するので、
    # 事故で配信状態にならないよう明示指定を要求する。
    ap.add_argument("--status", default="draft", choices=["draft", "published"],
                    help="JSON 側に status が無いときの既定 (既定: draft)")
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

    # published を含む実行では、始める前に残り枠を見せる。サーバも 101 曲目を 409 で
    # 弾くが、そちらは「途中まで公開されて残りが失敗する」形になる。何曲入るのかを
    # 先に出しておけば、流す前に選び直せる。
    wants_published = args.status == "published" or any(
        (load_doc(sid)[0] or {}).get("status") == "published" for sid in song_ids
    )
    if wants_published:
        quota = fetch_quota(args.base_url, token) if args.apply else None
        if quota:
            print("  掲載枠: %d/%d 使用中 (残り %d)"
                  % (quota["published"], quota["limit"], quota["remaining"]))
            if len(song_ids) > quota["remaining"]:
                print("  ⚠️ 残り枠より多い。%d 曲目以降は 409 で弾かれる。"
                      % (quota["remaining"] + 1))
        else:
            print("  掲載枠: JASRAC 許諾 J260943703 / 100曲まで")

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
