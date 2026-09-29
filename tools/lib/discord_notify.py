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


# 修正 (data/fixes/) の表示。表ごとの呼び名と Web のページ。
FIX_TABLES = {
    "songs": ("曲", "songs"),
    "idols": ("アイドル", "idols"),
    "events": ("イベント", "events"),
    "shows": ("公演", "shows"),
    "units": ("ユニット", "units"),
    "brands": ("ブランド", None),
    "venues": ("会場", None),
    "venue_names": ("会場名", None),
    "creators": ("作家", None),
    "setlist_items": ("セトリ", "shows"),
    "ticket_sales": ("チケット受付", "events"),
}
FIX_FIELDS = {
    "title": "曲名", "title_kana": "よみ", "name": "名前", "name_kana": "よみ", "name_romaji": "ローマ字",
    "composer": "作曲", "lyricist": "作詞", "arranger": "編曲", "release_date": "発売日",
    "cd_title": "収録CD", "cd_series": "CDシリーズ", "song_type": "曲の種類", "unit_name": "ユニット名",
    "singer_label": "歌唱", "parent_song_id": "元曲", "series_group": "シリーズ", "duration_sec": "長さ(秒)",
    "note": "補足", "notes": "メモ", "date": "日付", "start_date": "開始日", "end_date": "終了日",
    "venue_id": "会場", "hall": "ホール", "start_time": "開演", "open_time": "開場",
    "stream_platform": "配信", "performer_type": "出演形態", "venue_mode": "会場の形態",
    "position": "曲順", "section": "セクション", "song_id": "曲", "show_ids": "対象公演",
    "kind": "受付形式", "starts_at": "受付開始", "ends_at": "締切", "result_at": "当落発表",
    "height": "身長", "birthday": "誕生日", "color": "イメージカラー", "brand_id": "ブランド",
    "prefecture": "都道府県", "capacity": "キャパ", "aliases": "別名",
    "url": "案内URL", "ticket_url": "チケット案内URL", "lyrics_url": "歌詞URL", "source_url": "出典URL",
    "apple_music_id": "Apple Music", "apple_music_album_id": "Apple Music (アルバム)",
    "artwork_url": "ジャケ写", "preview_url": "試聴", "isrc": "ISRC", "price": "価格",
}
# 値を並べても読めない項目 (URL・外部 ID)。「〜を更新」とだけ出す。
_OPAQUE_FIELD = re.compile(r"(url|_id|^isrc)$")
# 値が ID の項目。名前に読み替える。
_REF_FIELDS = {"song_id": "songs", "parent_song_id": "songs", "venue_id": "venues"}


def _cols(conn, table: str) -> set[str]:
    try:
        return {r[1] for r in conn.execute(f"PRAGMA table_info({table})")}
    except Exception:
        return set()


def _row(conn, table: str, rec_id: str) -> dict:
    if conn is None or table not in FIX_TABLES:
        return {}
    try:
        cur = conn.execute(f"SELECT * FROM {table} WHERE id = ?", (rec_id,))
        r = cur.fetchone()
    except Exception:
        return {}
    return dict(zip([c[0] for c in cur.description], r)) if r else {}


def _title_of(conn, table: str, rec_id: str) -> str:
    row = _row(conn, table, rec_id)
    return str(row.get("title") or row.get("name") or rec_id)


def _short(text, max_len: int = 30) -> str:
    text = str(text)
    return text if len(text) <= max_len else text[:max_len] + "…"


def _value(conn, field: str, value) -> str:
    if value is None or value == "":
        return "（なし）"
    if field in _REF_FIELDS:
        value = _title_of(conn, _REF_FIELDS[field], str(value))
    return f"「{_md(_short(value))}」"


def _fix_line(conn, before, fx: dict) -> str:
    """修正 1 件を「・曲「X」：CDシリーズ「A」→「B」、ジャケ写を更新」の形にする。"""
    table, rec_id = fx.get("table", ""), str(fx.get("id", ""))
    label, path = FIX_TABLES.get(table, (table, None))
    row = _row(conn, table, rec_id)
    old = _row(before, table, rec_id)
    if table == "setlist_items":
        show = _title_of(conn, "shows", str(row.get("show_id") or ""))
        song = _title_of(conn, "songs", str(row.get("song_id") or ""))
        name, page_id = f"{show} の {row.get('position', '?')}曲目 ♪{song}", row.get("show_id")
    elif table == "ticket_sales":
        event = _title_of(conn, "events", str(row.get("event_id") or ""))
        name, page_id = f"{event} の {row.get('name') or rec_id}", row.get("event_id")
    else:
        name, page_id = str(row.get("title") or row.get("name") or rec_id), rec_id
    head = _link(f"{label}「{name}」", path, str(page_id)) if path and page_id else f"{label}「{_md(name)}」"

    changes, opaque = [], []
    for field, new in (fx.get("fields") or {}).items():
        field_label = FIX_FIELDS.get(field, field)
        if _OPAQUE_FIELD.search(field) and field not in _REF_FIELDS:
            opaque.append((field_label, new))
        elif old:
            if old.get(field) != new:
                changes.append(f"{field_label}{_value(before, field, old.get(field))}→{_value(conn, field, new)}")
        else:
            changes.append(f"{field_label}→{_value(conn, field, new)}")
    if opaque:
        if all(v in (None, "") for _, v in opaque):
            changes.append("・".join(n for n, _ in opaque) + "を消去")
        else:
            changes.append("・".join(n for n, _ in opaque) + "を更新")
    singers = fx.get("add_original_singers") or []
    if singers:
        names = "、".join(_md(_title_of(conn, "idols", i)) for i in singers)
        changes.append(f"原唱者に {names} を追加")
    return f"・{head}：" + ("、".join(changes) if changes else "内容を修正")


def build_report(conn, load, before=None) -> list[str]:
    """反映した data/<種類>/*.json から「何が増えたか」の行を作る (名前は master.sqlite から引く)。

    before は反映前の master.sqlite (apply_data のバックアップ)。あれば修正の変更前の値を出す。
    """
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
        items = [_fix_line(conn, before, f) for f in fixes]
        more = f"\n・ほか{len(items) - LIST_LIMIT}件" if len(items) > LIST_LIMIT else ""
        lines.append(f"🔧 **修正** {len(fixes)}件\n" + "\n".join(items[:LIST_LIMIT]) + more)

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
