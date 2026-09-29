"""discord_notify.py — apply_data.py で本番に入れたデータを Discord に知らせる。

アプリからの編集は Worker が #更新通知 に出す (imas-live-api/src/discord_digest.ts)。
運営が apply_data.py で CloudKit に直接入れた分は編集履歴を通らないので、ここで
「何が増えたか」を 1 通にまとめて、運営追加用のチャンネルに投稿する。

- Production への push が成功したときだけ呼ぶ (apply_data.py の main)。
- Bot トークンは環境変数 DISCORD_BOT_TOKEN、無ければ macOS のキーチェーン
  (サービス名 discord-idollivedb-bot) から読む。どちらも無ければ何もしない。
- 投稿に失敗しても apply_data.py 自体は成功のまま (データはもう入っている)。
- 標準ライブラリだけで動かす (--check の環境を増やさない)。
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import urllib.request

WEB_BASE = "https://idollivedb.fugaapp.site"
DISCORD_API = "https://discord.com/api/v10"
# 運営追加のチャンネル。環境変数 DISCORD_DATA_CHANNEL_ID で上書きできる。
DATA_CHANNEL_ID = "1552847460559364176"  # #新着データ
KEYCHAIN_SERVICE = "discord-idollivedb-bot"
LIST_LIMIT = 8


def _md(text: str) -> str:
    return re.sub(r"([\\*_~`|\[\]()<>#@:])", r"\\\1", str(text))


def _link(label: str, path: str, rec_id: str) -> str:
    from urllib.parse import quote

    return f"[{_md(label)}](<{WEB_BASE}/{path}/{quote(rec_id, safe='')}/>)"


def _names(items: list[str]) -> str:
    more = f" ほか{len(items) - LIST_LIMIT}件" if len(items) > LIST_LIMIT else ""
    return "、".join(items[:LIST_LIMIT]) + more


def build_report(conn, load) -> list[str]:
    """反映した data/<種類>/*.json から「何が増えたか」の行を作る (名前は master.sqlite から引く)。"""
    lines: list[str] = []

    songs = [s for _, d in load("songs") for s in d.get("songs", [])]
    if songs:
        lines.append("🎵 **曲** " + _names([_link(s.get("title") or s["id"], "songs", s["id"]) for s in songs]))

    setlists = []
    for _, d in load("setlists"):
        show_id = d["show_id"]
        row = conn.execute("SELECT name FROM shows WHERE id = ?", (show_id,)).fetchone()
        name = row[0] if row and row[0] else show_id
        setlists.append(f"{_link(name, 'shows', show_id)}（{len(d.get('songs', []))}曲）")
    if setlists:
        lines.append("📋 **セトリ** " + _names(setlists))

    events = [e for _, d in load("events") for e in d.get("events", [])]
    if events:
        lines.append("🎪 **イベント** " + _names([
            f"{_link(e.get('name') or e['id'], 'events', e['id'])}（公演{len(e.get('shows', []))}）" for e in events
        ]))

    shows = [s for _, d in load("shows") for s in d.get("shows", [])]
    if shows:
        lines.append("🏟️ **公演** " + _names([_link(s.get("name") or s["id"], "shows", s["id"]) for s in shows]))

    idols = [i for _, d in load("idols") for i in d.get("idols", [])]
    if idols:
        lines.append("👤 **アイドル** " + _names([_link(i.get("name") or i["id"], "idols", i["id"]) for i in idols]))

    units = [u for _, d in load("units") for u in d.get("units", [])]
    if units:
        lines.append("👥 **ユニット** " + _names([_link(u.get("name") or u["id"], "units", u["id"]) for u in units]))

    costumes = sum(len(d.get("costumes", [])) for _, d in load("costumes"))
    if costumes:
        lines.append(f"👗 **衣装** {costumes}着")

    fixes = [f for _, d in load("fixes") for f in d.get("fixes", [])]
    if fixes:
        songs_fixed = [f for f in fixes if f.get("table") == "songs"]
        detail = ""
        if songs_fixed:
            titles = []
            for f in songs_fixed:
                row = conn.execute("SELECT title FROM songs WHERE id = ?", (f["id"],)).fetchone()
                titles.append(_link(row[0] if row and row[0] else f["id"], "songs", f["id"]))
            detail = "（" + _names(titles) + "）"
        lines.append(f"🔧 **修正** {len(fixes)}件{detail}")

    return lines


def _token() -> str | None:
    tok = os.environ.get("DISCORD_BOT_TOKEN")
    if tok:
        return tok
    try:
        out = subprocess.run(
            ["security", "find-generic-password", "-a", os.environ.get("USER", ""), "-s", KEYCHAIN_SERVICE, "-w"],
            capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout.strip() or None if out.returncode == 0 else None


def post_report(lines: list[str]) -> bool:
    """運営追加のチャンネルに投稿する。設定が無い・失敗したら False (例外は投げない)。"""
    channel = os.environ.get("DISCORD_DATA_CHANNEL_ID") or DATA_CHANNEL_ID
    if not lines or not channel:
        return False
    token = _token()
    if not token:
        return False
    content = ("🆕 **データを追加しました**\n" + "\n".join(lines))[:2000]
    body = json.dumps({"content": content, "allowed_mentions": {"parse": []}}).encode()
    req = urllib.request.Request(
        f"{DISCORD_API}/channels/{channel}/messages",
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bot {token}",
            "Content-Type": "application/json",
            "User-Agent": "imas-live-db apply_data (https://github.com/fuga-if/idol-live-db, 1)",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as res:
            return 200 <= res.status < 300
    except OSError:
        return False
