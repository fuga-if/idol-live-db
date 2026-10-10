#!/usr/bin/env python3
"""apply_data.py — コミュニティから PR で集めたデータを一括反映する口。

data/ 配下を読み、検証 → master.sqlite に反映 → CloudKit へ一括 push する。
  - data/<種類>/*.json (songs/setlists/events/idols/units) … 新規追加 (INSERT)
  - data/fixes/*.json                                       … 既存レコードの修正 (UPDATE)
                                                               曲の原唱者の追加 (add_original_singers) もここ

    # 貢献者 (鍵不要・自己検証):
    python3 tools/apply_data.py --check

    # オーナー (レビュー後):
    python3 tools/apply_data.py --apply
    CLOUDKIT_KEY_ID=... python3 tools/apply_data.py --apply --push --production

形式は data/<種類>/_template.json / data/fixes/_template.json と data/README.md 参照。
"""
from __future__ import annotations

import argparse
import hashlib
import tempfile
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
from collections import defaultdict
from datetime import datetime
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "ImasLiveDB" / "Resources" / "master.sqlite"
DATA_DIR = ROOT / "data"
SEED_SCRIPT = Path(__file__).resolve().parent / "seed_cloudkit.py"

# 絞り込みの知識は lib/ck_tables.py が持つ (seed_cloudkit.py と共有)。**写さずに読む**
# (片方だけ古くならないように)。標準ライブラリだけのモジュールなので、--check は
# requests などが無くても動く。
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib import masterdb  # noqa: E402
from lib.ck_tables import SCOPED_ID_SPACE, TABLE_ORDER as TABLE_PUSH_ORDER, scope_id  # noqa: E402
DUMP_PATH = ROOT / "db" / "master.sql"


def ensure_db(db_path):
    """binary master.sqlite が無ければ db/master.sql から生成 (クローン直後でも --check 可)。

    指紋 (meta.content_hash) は tools/build_db.sh と同じ値を入れ直す。正本に残っている
    meta の行のままだと、中身と合わない古い指紋が付く。
    """
    p = Path(db_path)
    if not p.exists() and DUMP_PATH.exists():
        p.parent.mkdir(parents=True, exist_ok=True)
        masterdb.restore(DUMP_PATH, p)
        masterdb.stamp_content_hash(p, DUMP_PATH)
        print(f"(db/master.sql から {p.name} を生成しました)")

VALID_BRANDS = {"765as", "cg", "ml", "sidem", "sc", "gakuen", "876", "961", "other"}
# 種類 → (主テーブル, 子テーブル群)。push 時の対象テーブル算出にも使う。
KIND_TABLES = {
    "songs": ["songs", "song_artists"],
    "setlists": ["setlist_items", "setlist_performers"],
    "events": ["events", "shows"],
    # 既存ライブに公演だけを足す入口。event は親の id で参照するだけで触らない
    # (ツアーの追加公演は後から発表される)。data/setlists/ が show_id で子を足すのと同じ形。
    "shows": ["shows"],
    "idols": ["idols", "idol_brands"],
    "units": ["units", "unit_members"],
    "unit_versions": ["unit_versions"],
    "creators": ["creators"],
    "costumes": ["costumes", "costume_wears"],
    # チケット受付 (旧 events.ticket_open_date/ticket_deadline/ticket_lottery_date の後継)。
    # id は事前に振らず、event_id + name から決定的に作る (wear_id と同じ考え方)。
    "ticket_sales": ["ticket_sales"],
}
# data/fixes/ で既存レコードを UPDATE 可能なテーブル (id 列を持つ事実情報のみ)
ALLOWED_FIX_TABLES = {
    "idols", "songs", "events", "shows", "units", "brands", "venues", "venue_names", "creators",
    "setlist_items", "ticket_sales", "show_tickets",
}
# 表ごとに fixes で書き換えてよい列を絞るもの (載っていない表は全列可)。
# show_tickets は価格・券種名を fixes で直させない (価格は import_show_tickets.py の TSV で
# 出典つきに入れる)。ここから触れるのは配信アーカイブの視聴期間だけ。
FIX_FIELD_WHITELIST = {
    "show_tickets": {"archive_starts_at", "archive_ends_at"},
}

TICKET_SALE_KINDS = {"lottery", "first_come", "resale", "same_day"}
TICKET_MOMENT_RE = re.compile(r"^\d{4}-\d{2}-\d{2}(?: \d{2}:\d{2})?$")
# 読みの表は fixes ではなく専用の投入口 (data/creators/) から入れる。

# 出典。投稿はファイルの先頭か各項目に source (URL か一次ソースの名前。複数なら並び) を
# 持つこと。衣装は各着の source_url も出典に数える。_sources は古い投稿の書き方。
# source は DB に入らない (source_url は衣装の列として入る)。
FILE_SOURCE_KEYS = ("source", "_sources")
ITEM_SOURCE_KEYS = ("source", "source_url")
# 各項目に付けてよい、表の列ではないキー (DB には入らない)。
ANNOTATION_KEYS = ("source", "note")

# アイドルの公式タグに運営の 1 票を入れる (data/fixes/ の add_official_tags)。
# タグと票はマスタ (master.sqlite / CloudKit) ではなく D1 (imas-live-api) にあるので、
# --apply はマスタに何も書かず、D1 に流す SQL を --d1-sql に書き出すだけ。
# 公式タグの語は D1 の migration (official_ で始まる id の行) が正本。
D1_MIGRATIONS_DIR = ROOT / "imas-live-api" / "migrations"
# 運営の票の端末 ID の接頭辞 (imas-live-api の OFFICIAL_DEVICE_PREFIX と同じ)。端末の記録に
# この形で入れることで、利用者の票と分かれる (利用者はこの接頭辞を名乗れない)。
OFFICIAL_DEVICE_PREFIX = "official:"


def official_idol_tags():
    """D1 の migration が入れるアイドルの公式タグ: 名前 → id。"""
    out = {}
    for path in sorted(D1_MIGRATIONS_DIR.glob("*.sql")):
        text = path.read_text(encoding="utf-8")
        if "idol_tag_master" not in text:
            continue
        for tag_id, name in re.findall(r"\('(official_[a-z0-9_]+)', '([^']+)'", text):
            out[name] = tag_id
    return out


def official_vote_device(path):
    """運営の票の端末 ID。投稿ファイルごとに分ける (どのファイルで入れた票か辿れ、消すときも絞れる)。"""
    return OFFICIAL_DEVICE_PREFIX + Path(path).stem


def _sql_text(v):
    return "'" + str(v).replace("'", "''") + "'"


def official_tag_vote_sql(votes):
    """(端末 ID, idol_id, タグ名) の並びを、D1 に流す SQL にする。何度流しても 1 票のまま。

    API の付与 (routes/tags.ts の attachTags) と同じく、端末の記録 (device_idol_tag) に行があれば
    数えない。先に票を足してから記録を入れるので、2 回目は NOT EXISTS で票が増えない
    (changes() に頼らない: wrangler の --file でも文の境目で値が変わらない)。
    タグは名前で引く (同名の利用者タグを公式にした場合、id は migration の id と違う)。
    """
    lines = [
        "-- 公式タグの運営の票 (tools/apply_data.py が書き出した)。",
        "-- npx wrangler d1 execute imas-live-db --remote --file <このファイル>",
    ]
    for device, idol_id, name in votes:
        d, i, n = _sql_text(device), _sql_text(idol_id), _sql_text(name)
        lines.append(
            f"INSERT INTO idol_tags (idol_id, tag_id, vote_count) SELECT {i}, t.id, 1 FROM idol_tag_master t"
            f" WHERE t.name = {n} AND t.status != 'removed' AND NOT EXISTS (SELECT 1 FROM device_idol_tag"
            f" WHERE device_id = {d} AND idol_id = {i} AND tag_id = t.id)"
            f" ON CONFLICT(idol_id, tag_id) DO UPDATE SET vote_count = vote_count + 1;"
        )
        lines.append(
            f"INSERT OR IGNORE INTO device_idol_tag (device_id, idol_id, tag_id, created_at)"
            f" SELECT {d}, {i}, t.id, CAST(strftime('%s', 'now') AS INTEGER) FROM idol_tag_master t"
            f" WHERE t.name = {n} AND t.status != 'removed';"
        )
    return "\n".join(lines) + "\n"


def cols(conn, table):
    return {r[1] for r in conn.execute(f"PRAGMA table_info({table})")}


def exists(conn, table, rec_id):
    return conn.execute(f"SELECT 1 FROM {table} WHERE id = ?", (rec_id,)).fetchone() is not None


def table_exists(conn, table):
    """master.sqlite (= db/master.sql) にその表があるか。

    ticket_sales は imas-core 側の DDL 反映を待たずにこのファイルをマージできるようにする
    (罠: 表が無い間も --check は中身の検証をしたい。--apply は表が無ければ諦める)。
    """
    return conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", (table,)
    ).fetchone() is not None


def pending_events_and_shows():
    """同じバッチで data/events, data/shows から新規に足される event/show の id。

    ticket_sales はまだ master.sqlite に無いイベント・公演も参照できる
    (受付の告知がイベント本体と同じ PR で来ることもある。resolve_song の pending と同じ考え方)。
    戻り値: (event_id の集合, {show_id: event_id})
    """
    events = set()
    shows = {}
    for _, data in load("events"):
        for ev in data.get("events", []):
            if ev.get("id"):
                events.add(ev["id"])
            for sh in ev.get("shows", []):
                if sh.get("id"):
                    shows[sh["id"]] = ev.get("id")
    for _, data in load("shows"):
        for sh in data.get("shows", []):
            if sh.get("id"):
                shows[sh["id"]] = sh.get("event_id")
    return events, shows


def ticket_sale_id(event_id, name):
    """ticket_sales.id。**中身 (event_id + name) から決定的に決める。**

    衣装の wear_id と同じ考え方: 同じ投稿を 2 度流しても同じ id になるので、
    二重登録にならない。ユーザーは id を書かなくてよい。
    """
    key = f"{event_id}\t{name}"
    return "ts_" + hashlib.sha1(key.encode("utf-8")).hexdigest()[:12]


def _ticket_moment_bound(value, pad):
    """日付だけの値を比較用に境界時刻へ正規化する (時刻つきならそのまま)。"""
    return value if len(value) > 10 else f"{value} {pad}"


def _valid_ticket_moment(value):
    """TICKET_MOMENT_RE の形式に加え、実在する日時か検査する。

    正規表現は桁数しか見ないので、2026-02-30 や 24:00 のような架空の日時も通ってしまい、
    imas-core 側では「解釈できない値」として扱われる (H1 と同じく締切が壊れて受付中のまま
    終わらなくなる)。ここで datetime.strptime に投げて実在性を確かめる。
    呼び出し側は先に TICKET_MOMENT_RE.match で形式を確認しておくこと。
    """
    fmt = "%Y-%m-%d %H:%M" if len(value) > 10 else "%Y-%m-%d"
    try:
        datetime.strptime(value, fmt)
        return True
    except ValueError:
        return False


def find_ticket_sale_id(conn, event_id, name):
    """同じ (event_id, name) の既存 ticket_sales 行の id。無ければ None。

    id は apply_data では sha1(event_id + name) から決定的に作るが、アプリ側 (Worker) が
    作った受付は ts_<uuid> を振るので、id の作り方が食い違う。id の値ではなく中身
    (event_id, name) で引かないと、アプリで作った受付と同じ名前を後から JSON で入れたときに
    「既存判定」をすり抜けて二重登録になる (L4)。
    """
    row = conn.execute(
        "SELECT id FROM ticket_sales WHERE event_id = ? AND name = ?", (event_id, name)
    ).fetchone()
    return row[0] if row else None


_TICKET_SALE_COLS = (
    "event_id", "kind", "name", "starts_at", "ends_at", "result_at", "source_url", "url", "show_ids",
)


def _merged_ticket_sale_row(conn, rid, fields):
    """既存の ticket_sales 行に data/fixes/ の fields をかぶせた値。行が無ければ None。

    show_ids は表では CSV 文字列で持つが、投稿・検査では配列で扱う (他のフィールドと
    形を揃える。fixes の fields で show_ids を渡すときも配列で書く)。ここで CSV → list に開く。
    """
    cur = conn.execute(
        f"SELECT {', '.join(_TICKET_SALE_COLS)} FROM ticket_sales WHERE id = ?", (rid,)
    ).fetchone()
    if cur is None:
        return None
    row = dict(zip(_TICKET_SALE_COLS, cur))
    row["show_ids"] = row["show_ids"].split(",") if row["show_ids"] else []
    for k, v in fields.items():
        if k in _TICKET_SALE_COLS:
            row[k] = v
    return row


def ticket_sale_row_problems(tag, row, conn, pending_events, pending_shows):
    """1 件の ticket_sales 行 (event_id/show_ids/kind/name/starts_at/ends_at/result_at/
    source_url/url) を検査する。data/ticket_sales/ の新規と data/fixes/ (table: ticket_sales)
    の両方から呼ぶ (M5: 検査を 1 箇所にまとめ、fixes 側にも同じ検査を効かせる)。

    show_ids はここでは list 前提 (呼び出し側で CSV ⇄ list を変換すること)。
    """
    problems = []
    event_id = row.get("event_id")
    if not event_id or not (exists(conn, "events", event_id) or event_id in pending_events):
        problems.append(f"{tag}: event_id '{event_id}' が存在しない")
    kind = row.get("kind")
    if kind not in TICKET_SALE_KINDS:
        problems.append(f"{tag}: kind 不正 ({kind})。許可: {sorted(TICKET_SALE_KINDS)}")
    if not row.get("name"):
        problems.append(f"{tag}: name が空")

    show_ids = row.get("show_ids")
    if show_ids is None:
        show_ids = []
    elif not isinstance(show_ids, list):
        problems.append(f"{tag}: show_ids は配列 (省略/空 = 全公演)")
        show_ids = []
    for sid in show_ids:
        r = conn.execute("SELECT event_id FROM shows WHERE id = ?", (sid,)).fetchone()
        owner = r[0] if r else pending_shows.get(sid)
        if owner is None:
            problems.append(f"{tag}: show_id '{sid}' が存在しない")
        elif event_id and owner != event_id:
            problems.append(f"{tag}: show_id '{sid}' は別のイベント ({owner}) の公演")

    moments = {}
    for field in ("starts_at", "ends_at", "result_at"):
        v = row.get(field)
        if v is None:
            continue
        if not isinstance(v, str) or not TICKET_MOMENT_RE.match(v) or not _valid_ticket_moment(v):
            problems.append(f"{tag}: {field} の形式が不正 ({v!r})。'YYYY-MM-DD' か 'YYYY-MM-DD HH:MM'")
        else:
            moments[field] = v
    if not moments:
        problems.append(f"{tag}: starts_at / ends_at / result_at のいずれかが必要")
    if "starts_at" in moments and "ends_at" in moments:
        if _ticket_moment_bound(moments["starts_at"], "00:00") > _ticket_moment_bound(moments["ends_at"], "23:59"):
            problems.append(f"{tag}: starts_at が ends_at より後になっている")
    if "ends_at" in moments and "result_at" in moments:
        if _ticket_moment_bound(moments["ends_at"], "23:59") > _ticket_moment_bound(moments["result_at"], "23:59"):
            problems.append(f"{tag}: ends_at が result_at より後になっている")

    source_url = row.get("source_url")
    if not source_url or not re.match(r"^https?://", source_url):
        problems.append(f"{tag}: source_url は http(s) URL 必須")
    url = row.get("url")
    if url and not re.match(r"^https?://", url):
        problems.append(f"{tag}: url は http(s) URL")
    return problems


# 処理対象を 1 ファイルに絞るときのファイル名 (--only)。
#
# data/ 全体を一度に流すと、無関係な保留中の投稿が 1 件でも失敗した時点で
# トランザクションごと巻き戻り、レビュー済みの投稿まで入らなくなる
# (実際、保留中のセトリの UNIQUE 違反で読み仮名 316 件が入らなかった)。
# レビューが済んだものから順に入れられるようにする。
ONLY_FILE = None


def load(kind):
    """data/<kind>/*.json を読む。反映済みを移した data/_applied/ は読まない。"""
    out = []
    d = DATA_DIR / kind
    if not d.exists():
        return out
    for p in sorted(d.glob("*.json")):
        if p.name.startswith("_"):
            continue
        if ONLY_FILE and p.name != ONLY_FILE:
            continue
        out.append((p, json.loads(p.read_text(encoding="utf-8"))))
    return out


def resolve_song(conn, brand_id, song_id, title, pending=()):
    """song_id 優先。無ければ brand 内でタイトル完全一致を試みる。

    pending は同じバッチで data/songs/ に追加される新曲。新曲を登録して同じ PR で
    その初披露のセトリも入れる、という普通の流れを --check で弾かないために見る
    (apply_all は songs → setlists の順に入れるので、反映時点では実在する)。
    """
    if song_id:
        if any(p.get("id") == song_id for p in pending):
            return song_id
        return song_id if exists(conn, "songs", song_id) else None
    hits = {p["id"] for p in pending
            if p.get("id") and p.get("brand_id") == brand_id and p.get("title") == title}
    hits |= {r[0] for r in conn.execute(
        "SELECT id FROM songs WHERE brand_id = ? AND title = ?", (brand_id, title)
    )}
    return next(iter(hits)) if len(hits) == 1 else None


# ---- 検証 -----------------------------------------------------------------

def has_source(value) -> bool:
    """出典として使える値か (空でない文字列か、空でない文字列だけの並び)。"""
    if isinstance(value, str):
        return bool(value.strip())
    if isinstance(value, list):
        return bool(value) and all(isinstance(v, str) and v.strip() for v in value)
    return False


def source_problems(kind, path, data):
    """出典の無い投稿を問題にする。ファイルの先頭か、全項目に出典があればよい。"""
    if any(has_source(data.get(k)) for k in FILE_SOURCE_KEYS):
        return []
    # セットリストは 1 公演 1 ファイルなので、出典はファイルの先頭に書く。
    items = [] if kind == "setlists" else data.get(kind, [])
    missing = [i for i, item in enumerate(items)
               if not any(has_source(item.get(k)) for k in ITEM_SOURCE_KEYS)]
    if items and not missing:
        return []
    where = f" (項目 {missing[:5]}{' ほか' if len(missing) > 5 else ''})" if items else ""
    return [f"{kind}/{path.name}: 出典が無い{where}。ファイルの先頭か各項目に source "
            f"(URL か一次ソースの名前) を書く"]


def validate(conn):
    problems = []

    for kind in list(KIND_TABLES) + ["fixes"]:
        for path, data in load(kind):
            problems += source_problems(kind, path, data)

    for path, data in load("songs"):
        scol = cols(conn, "songs")
        for i, s in enumerate(data.get("songs", [])):
            tag = f"songs/{path.name}[{i}]"
            if s.get("brand_id") not in VALID_BRANDS:
                problems.append(f"{tag}: brand_id 不正 ({s.get('brand_id')})")
            if not s.get("id"):
                problems.append(f"{tag}: id が空")
            elif exists(conn, "songs", s["id"]):
                problems.append(f"{tag}: id '{s['id']}' は既に存在 (新規追加のみ)")
            elif not s["id"].startswith(f"{s.get('brand_id')}_"):
                # 他ブランドの接頭辞を借りると、そのブランドの同名曲と id がぶつかる
                # (KR の曲を 765as_ で入れていて、KR「Dream」が 765as_dream に混ざった)。
                problems.append(f"{tag}: id '{s['id']}' は brand_id ({s.get('brand_id')}) + '_' で始める")
            for k in s:
                if k not in scol and k not in ("original_singers", *ANNOTATION_KEYS):
                    problems.append(f"{tag}: 未知の列 '{k}'")
            for idol in s.get("original_singers", []):
                if not exists(conn, "idols", idol):
                    problems.append(f"{tag}: original_singers の idol '{idol}' が存在しない")
            if s.get("unit_id") and not exists(conn, "units", s["unit_id"]):
                problems.append(f"{tag}: unit_id '{s['unit_id']}' が存在しない")
            # 読みが空だと五十音順・かな検索から漏れる。既存行は全部ひらがな。
            kana = s.get("title_kana") or ""
            if not kana:
                problems.append(f"{tag}: title_kana が空")
            elif re.search(r"[ァ-ヶ]", kana):
                problems.append(f"{tag}: title_kana はひらがなで書く ({kana})")

    # 同じバッチで追加される新曲。セトリ側はこれも「存在する」として解決する。
    new_songs = [s for _, d in load("songs") for s in d.get("songs", [])]

    for path, data in load("setlists"):
        show_id = data.get("show_id")
        if not show_id or not exists(conn, "shows", show_id):
            problems.append(f"setlists/{path.name}: show_id '{show_id}' が存在しない")
            continue
        brand = conn.execute(
            "SELECT e.brand_id FROM shows s JOIN events e ON e.id=s.event_id WHERE s.id=?",
            (show_id,),
        ).fetchone()
        brand_id = brand[0] if brand else None
        # 既にこの公演のセトリが入っているなら、投入すると position の UNIQUE で落ちる。
        # --check が通ったのに --apply が落ちる状態を作らないため、ここで止める
        # (実際、CloudKit へ push 済みのセトリ 6 本が data/ に残っていて --apply が全滅した)。
        already = conn.execute(
            "SELECT count(*) FROM setlist_items WHERE show_id = ?", (show_id,)
        ).fetchone()[0]
        if already:
            problems.append(
                f"setlists/{path.name}: この公演のセトリは既に {already} 曲入っている "
                f"(push 済みなら data/ から消す。直すなら data/fixes/ で)")
            continue
        for i, sg in enumerate(data.get("songs", [])):
            tag = f"setlists/{path.name}[pos {sg.get('position')}]"
            sid = resolve_song(conn, brand_id, sg.get("song_id"), sg.get("title"), new_songs)
            if not sid:
                problems.append(f"{tag}: 曲を特定できない (song_id か brand内一意なtitleが必要): {sg.get('title')}")
            perf = sg.get("performers")
            if isinstance(perf, list):
                for idol in perf:
                    if not exists(conn, "idols", idol):
                        problems.append(f"{tag}: performer '{idol}' が存在しない")
            elif perf != "all":
                problems.append(f"{tag}: performers は \"all\" か idol_id 配列")
        for idol in data.get("all_performers", []):
            if not exists(conn, "idols", idol):
                problems.append(f"setlists/{path.name}: all_performers の '{idol}' が存在しない")

    for path, data in load("events"):
        ecol, scol = cols(conn, "events"), cols(conn, "shows")
        for i, ev in enumerate(data.get("events", [])):
            tag = f"events/{path.name}[{i}]"
            if ev.get("brand_id") not in VALID_BRANDS:
                problems.append(f"{tag}: brand_id 不正")
            if not ev.get("id") or exists(conn, "events", ev.get("id", "")):
                problems.append(f"{tag}: event id が空 or 既存")
            for k in ev:
                if k not in ecol and k not in ("shows", *ANNOTATION_KEYS):
                    problems.append(f"{tag}: events に未知の列 '{k}'")
            for sh in ev.get("shows", []):
                if not sh.get("id") or exists(conn, "shows", sh.get("id", "")):
                    problems.append(f"{tag}: show id が空 or 既存 ({sh.get('id')})")
                for k in sh:
                    if k not in scol and k not in ANNOTATION_KEYS:
                        problems.append(f"{tag}: shows に未知の列 '{k}'")

    for path, data in load("shows"):
        scol = cols(conn, "shows")
        for i, sh in enumerate(data.get("shows", [])):
            tag = f"shows/{path.name}[{i}]"
            if not sh.get("event_id") or not exists(conn, "events", sh.get("event_id", "")):
                problems.append(f"{tag}: event_id '{sh.get('event_id')}' が存在しない")
            if not sh.get("id") or exists(conn, "shows", sh.get("id", "")):
                problems.append(f"{tag}: show id が空 or 既存 ({sh.get('id')})")
            if not sh.get("date"):
                problems.append(f"{tag}: date は必須")
            for k in sh:
                if k not in scol and k not in ANNOTATION_KEYS:
                    problems.append(f"{tag}: shows に未知の列 '{k}'")

    for path, data in load("idols"):
        icol = cols(conn, "idols")
        for i, idol in enumerate(data.get("idols", [])):
            tag = f"idols/{path.name}[{i}]"
            if idol.get("brand_id") not in VALID_BRANDS:
                problems.append(f"{tag}: brand_id 不正")
            if not idol.get("id") or exists(conn, "idols", idol.get("id", "")):
                problems.append(f"{tag}: idol id が空 or 既存")
            for k in idol:
                if k not in icol and k not in ("brands", *ANNOTATION_KEYS):
                    problems.append(f"{tag}: idols に未知の列 '{k}'")

    for path, data in load("creators"):
        ccol = cols(conn, "creators")
        for i, c in enumerate(data.get("creators", [])):
            tag = f"creators/{path.name}[{i}]"
            if not c.get("id") or exists(conn, "creators", c.get("id", "")):
                problems.append(f"{tag}: creator id が空 or 既存")
            if not c.get("name") or not c.get("name_kana"):
                problems.append(f"{tag}: name / name_kana は必須")
            for k in c:
                if k not in ccol and k not in ANNOTATION_KEYS:
                    problems.append(f"{tag}: creators に未知の列 '{k}'")

    for path, data in load("unit_versions"):
        vcol = cols(conn, "unit_versions")
        for i, v in enumerate(data.get("unit_versions", [])):
            tag = f"unit_versions/{path.name}[{i}]"
            if not v.get("id") or exists(conn, "unit_versions", v.get("id", "")):
                problems.append(f"{tag}: unit_version id が空 or 既存")
            if not exists(conn, "units", v.get("unit_id", "")):
                problems.append(f"{tag}: unit_id '{v.get('unit_id')}' が存在しない")
            if not v.get("name"):
                problems.append(f"{tag}: name が空")
            for k in v:
                if k not in vcol and k not in ANNOTATION_KEYS:
                    problems.append(f"{tag}: unit_versions に未知の列 '{k}'")

    for path, data in load("costumes"):
        kcol = cols(conn, "costumes")
        for i, c in enumerate(data.get("costumes", [])):
            tag = f"costumes/{path.name}[{i}]"
            if not c.get("id") or exists(conn, "costumes", c.get("id", "")):
                problems.append(f"{tag}: costume id が空 or 既存")
            if not c.get("name"):
                problems.append(f"{tag}: name が空")
            if c.get("brand_id") is not None and c["brand_id"] not in VALID_BRANDS:
                problems.append(f"{tag}: brand_id 不正")
            for ref, table in (("unit_id", "units"), ("idol_id", "idols")):
                if c.get(ref) and not exists(conn, table, c[ref]):
                    problems.append(f"{tag}: {ref} '{c[ref]}' が存在しない")
            for k in c:
                if k not in kcol and k not in ("wears", *ANNOTATION_KEYS):
                    problems.append(f"{tag}: costumes に未知の列 '{k}'")
            if not c.get("wears"):
                problems.append(f"{tag}: wears が空 (着た公演が 1 つも無い衣装は入れない)")
            for j, w in enumerate(c.get("wears", [])):
                wtag = f"{tag}.wears[{j}]"
                if not exists(conn, "shows", w.get("show_id", "")):
                    problems.append(f"{wtag}: show_id '{w.get('show_id')}' が存在しない")
                # 曲と人は省略してよい (「公演のどこかで全員」が正規の記録)。
                item_id = w.get("setlist_item_id")
                if item_id:
                    row = conn.execute(
                        "SELECT show_id FROM setlist_items WHERE id = ?", (item_id,)
                    ).fetchone()
                    if row is None:
                        problems.append(f"{wtag}: setlist_item_id '{item_id}' が存在しない")
                    elif row[0] != w.get("show_id"):
                        problems.append(
                            f"{wtag}: setlist_item_id '{item_id}' は別の公演 ({row[0]}) の曲"
                        )
                if w.get("idol_id") and not exists(conn, "idols", w["idol_id"]):
                    problems.append(f"{wtag}: idol_id '{w['idol_id']}' が存在しない")
                for k in w:
                    if k not in ("id", "show_id", "setlist_item_id", "idol_id", "note"):
                        problems.append(f"{wtag}: 未知のキー '{k}'")

    pending_events, pending_shows = pending_events_and_shows()
    # ファイルをまたいで重複を見る (L3): 別ファイルに同じ event_id + name があると
    # --check は通るのに --apply で PK 衝突して途中で落ちていた。
    ticket_sales_seen = set()
    for path, data in load("ticket_sales"):
        tcol = cols(conn, "ticket_sales") if table_exists(conn, "ticket_sales") else None
        for i, t in enumerate(data.get("ticket_sales", [])):
            tag = f"ticket_sales/{path.name}[{i}]"
            event_id = t.get("event_id")
            problems += ticket_sale_row_problems(tag, t, conn, pending_events, pending_shows)

            key = (event_id, t.get("name"))
            if key in ticket_sales_seen:
                problems.append(f"{tag}: 同じ event_id + name の受付が重複している (name を変えるか 1 件にまとめる)")
            ticket_sales_seen.add(key)
            if tcol is not None:
                # id ではなく中身 (event_id, name) で既存を引く (L4): apply_data は id を
                # sha1(event_id + name) から決めるが、アプリ (Worker) が作った受付は
                # ts_<uuid> を振るので、id の作り方が食い違う。id で照合すると、アプリで
                # 作った受付と同じ名前を後から JSON で入れたときに二重登録を見逃す。
                existing_id = find_ticket_sale_id(conn, event_id, t.get("name"))
                if existing_id is not None:
                    problems.append(
                        f"{tag}: 同じ event_id + name の受付が既に存在 ({existing_id})。直すなら data/fixes/ で"
                    )
                for k in t:
                    if k in ("show_ids", *ANNOTATION_KEYS):
                        continue
                    if k not in tcol:
                        problems.append(f"{tag}: ticket_sales に未知の列 '{k}'")

    for path, data in load("units"):
        ucol = cols(conn, "units")
        for i, u in enumerate(data.get("units", [])):
            tag = f"units/{path.name}[{i}]"
            if u.get("brand_id") not in VALID_BRANDS:
                problems.append(f"{tag}: brand_id 不正")
            if not u.get("id") or exists(conn, "units", u.get("id", "")):
                problems.append(f"{tag}: unit id が空 or 既存")
            for k in u:
                if k not in ucol and k not in ("members", *ANNOTATION_KEYS):
                    problems.append(f"{tag}: units に未知の列 '{k}'")
            for idol in u.get("members", []):
                if not exists(conn, "idols", idol):
                    problems.append(f"{tag}: member '{idol}' が存在しない")

    # 修正 (data/fixes/): 既存レコードのフィールド UPDATE
    for path, data in load("fixes"):
        for i, fx in enumerate(data.get("fixes", [])):
            tag = f"fixes/{path.name}[{i}]"
            table, rid, fields = fx.get("table"), fx.get("id"), fx.get("fields")
            if table not in ALLOWED_FIX_TABLES:
                problems.append(f"{tag}: table '{table}' は修正対象外 (許可: {sorted(ALLOWED_FIX_TABLES)})")
                continue
            tcol = cols(conn, table)
            if not rid or not exists(conn, table, rid):
                problems.append(f"{tag}: id '{rid}' が {table} に存在しない")
            singers = fx.get("add_original_singers")
            if singers is not None:
                if table != "songs":
                    problems.append(f"{tag}: add_original_singers は songs の修正にだけ書ける")
                elif not isinstance(singers, list) or not singers:
                    problems.append(f"{tag}: add_original_singers は idol_id の配列 (空は不可)")
                else:
                    for idol in singers:
                        if not exists(conn, "idols", idol):
                            problems.append(f"{tag}: add_original_singers の idol '{idol}' が存在しない")
            official = fx.get("add_official_tags")
            if official is not None:
                known = official_idol_tags()
                if table != "idols":
                    problems.append(f"{tag}: add_official_tags は idols の修正にだけ書ける")
                elif not isinstance(official, list) or not official:
                    problems.append(f"{tag}: add_official_tags は公式タグの名前の配列 (空は不可)")
                else:
                    if len(set(official)) != len(official):
                        problems.append(f"{tag}: add_official_tags に同じタグが重なっている")
                    for name in official:
                        if name not in known:
                            problems.append(f"{tag}: '{name}' はアイドルの公式タグに無い "
                                            "(imas-live-api/migrations の official_ の行)")
            if fields is None and (singers or official):
                pass  # 原唱者を足すだけ / 公式タグに票を入れるだけの修正
            elif not isinstance(fields, dict) or not fields:
                problems.append(f"{tag}: fields が無い/空")
            else:
                for k in fields:
                    if k == "id":
                        problems.append(f"{tag}: id は変更不可")
                    elif k not in tcol:
                        problems.append(f"{tag}: '{table}' に列 '{k}' が無い")
                    elif k not in FIX_FIELD_WHITELIST.get(table, {k}):
                        problems.append(
                            f"{tag}: '{table}' の '{k}' は fixes で直せない "
                            f"(許可: {sorted(FIX_FIELD_WHITELIST[table])})")
                # show_tickets のアーカイブ期間: 形式・実在性・前後関係 (ticket_sales の日時と同じ規則)
                if table == "show_tickets" and rid and exists(conn, table, rid):
                    cur = conn.execute(
                        "SELECT archive_starts_at, archive_ends_at, kind FROM show_tickets WHERE id = ?",
                        (rid,)).fetchone()
                    merged = {"archive_starts_at": cur[0], "archive_ends_at": cur[1], **fields}
                    if cur[2] != "stream" and any(fields.get(k) is not None for k in
                                                  ("archive_starts_at", "archive_ends_at")):
                        problems.append(f"{tag}: アーカイブ期間は kind=stream の券にだけ入れられる (kind={cur[2]})")
                    for k in ("archive_starts_at", "archive_ends_at"):
                        v = merged[k]
                        if v is not None and (not isinstance(v, str) or not TICKET_MOMENT_RE.match(v)
                                              or not _valid_ticket_moment(v)):
                            problems.append(f"{tag}: {k} が不正 ({v!r})。YYYY-MM-DD か YYYY-MM-DD HH:MM")
                    a, b = merged["archive_starts_at"], merged["archive_ends_at"]
                    if (isinstance(a, str) and isinstance(b, str) and TICKET_MOMENT_RE.match(a)
                            and TICKET_MOMENT_RE.match(b)
                            and _ticket_moment_bound(a, "00:00") > _ticket_moment_bound(b, "23:59")):
                        problems.append(f"{tag}: archive_starts_at が archive_ends_at より後 ({a} > {b})")
                # M5: data/fixes/ で ticket_sales を直すときも、新規投稿と同じ 1 行検査
                # (kind の値・日時の形式と実在性・前後関係・source_url の http・show_ids の
                # 配列) を効かせる。今まではここが表・id・列の存在しか見ておらず、
                # 壊れた値がそのまま UPDATE され CloudKit まで出ていた。
                if table == "ticket_sales" and rid and exists(conn, table, rid):
                    merged = _merged_ticket_sale_row(conn, rid, fields)
                    if merged is not None:
                        problems += ticket_sale_row_problems(tag, merged, conn, pending_events, pending_shows)

    return problems


# ---- 反映 -----------------------------------------------------------------

def wear_id(costume_id, show_id, setlist_item_id, idol_id):
    """着用記録の id。**中身から決定的に決める。**

    同じ投稿を 2 度流しても同じ id になるので、二重登録にならない
    (曲を別 id で起こし直して二重になった事故の再発を防ぐ)。
    """
    key = "|".join([costume_id, show_id, setlist_item_id or "", idol_id or ""])
    return "cw_" + hashlib.sha1(key.encode("utf-8")).hexdigest()[:16]


def wear_rows(conn, costume):
    """1 着ぶんの `wears` を costume_wears の行に開く。

    sort_order は曲のセトリ位置。曲が特定できていない記録は末尾に置く
    (公演の一覧を進行順に並べるための並び)。
    """
    rows = []
    for w in costume.get("wears", []):
        show_id = w.get("show_id")
        item_id = w.get("setlist_item_id")
        idol_id = w.get("idol_id")
        position = None
        if item_id:
            r = conn.execute(
                "SELECT position FROM setlist_items WHERE id = ?", (item_id,)
            ).fetchone()
            position = r[0] if r else None
        rows.append({
            "id": w.get("id") or wear_id(costume["id"], show_id or "", item_id, idol_id),
            "costume_id": costume["id"],
            "show_id": show_id,
            "setlist_item_id": item_id,
            "idol_id": idol_id,
            # 曲が分からない記録は末尾へ。
            "sort_order": position if position is not None else 9999,
        })
    return rows


def insert_row(conn, table, row):
    keys = list(row.keys())
    conn.execute(
        f"INSERT INTO {table} ({', '.join(keys)}) VALUES ({', '.join('?' for _ in keys)})",
        [row[k] for k in keys],
    )


def apply_all(conn, official_votes=None):
    """data/ を master.sqlite に入れる。公式タグの票 (D1 行き) は official_votes に溜める。"""
    if official_votes is None:
        official_votes = []
    # 表 → その表に渡す id 集合。空集合の表は「全件 push」を意味する
    # (絞り込む列が無い表・fixes で行を直した表)。
    affected = defaultdict(set)
    scol = cols(conn, "songs")

    ccol = cols(conn, "creators")
    for path, data in load("creators"):
        for c in data["creators"]:
            c.pop("note", None)
            insert_row(conn, "creators", {k: v for k, v in c.items() if k in ccol})
            affected["creators"]  # 絞る列が無いので全件
        print(f"  ✓ creators/{path.name}: {len(data['creators'])} 件")

    # 版は songs より先に入れる。songs.unit_version_id の参照先になるため。
    vcol = cols(conn, "unit_versions")
    for path, data in load("unit_versions"):
        for v in data["unit_versions"]:
            v.pop("note", None)
            insert_row(conn, "unit_versions", {k: val for k, val in v.items() if k in vcol})
            affected["unit_versions"]  # 絞る列が無いので全件
        print(f"  ✓ unit_versions/{path.name}: {len(data['unit_versions'])} 件")

    for path, data in load("songs"):
        for s in data["songs"]:
            singers = s.pop("original_singers", [])
            s.pop("source", None); s.pop("note", None)
            insert_row(conn, "songs", {k: v for k, v in s.items() if k in scol})
            for idol in singers:
                conn.execute(
                    "INSERT OR IGNORE INTO song_artists (song_id, idol_id, role) VALUES (?,?,'original')",
                    (s["id"], idol),
                )
            affected["songs"].add(s["id"])
            affected["song_artists"].add(s["id"])
        print(f"  ✓ songs/{path.name}: {len(data['songs'])} 曲")

    for path, data in load("setlists"):
        show_id = data["show_id"]
        brand = conn.execute(
            "SELECT e.brand_id FROM shows s JOIN events e ON e.id=s.event_id WHERE s.id=?", (show_id,)
        ).fetchone()
        brand_id = brand[0] if brand else None
        for sg in data["songs"]:
            sid = resolve_song(conn, brand_id, sg.get("song_id"), sg.get("title"))
            item_id = f"{show_id}_{int(sg['position']):04d}"
            affected["setlist_items"].add(item_id)
            affected["setlist_performers"].add(item_id)
            insert_row(conn, "setlist_items", {
                "id": item_id, "show_id": show_id, "song_id": sid,
                "position": sg["position"], "section": sg.get("section"),
                "notes": sg.get("notes"), "unit_name": sg.get("unit_name"),
            })
            perf = sg.get("performers")
            idols = data.get("all_performers", []) if perf == "all" else (perf or [])
            for idol in idols:
                conn.execute(
                    "INSERT OR IGNORE INTO setlist_performers (setlist_item_id, idol_id) VALUES (?,?)",
                    (item_id, idol),
                )
        print(f"  ✓ setlists/{path.name}: {len(data['songs'])} 曲")

    # 衣装は setlists より後。着用記録がセトリ行を指すため。
    kcol = cols(conn, "costumes")
    for path, data in load("costumes"):
        wear_count = 0
        for c in data["costumes"]:
            c.pop("note", None)
            rows = wear_rows(conn, c)
            c.pop("wears", None)
            insert_row(conn, "costumes", {k: v for k, v in c.items() if k in kcol})
            for w in rows:
                # 同じ内容を 2 度流しても増えない (id が中身から決まっている)。
                conn.execute(
                    "INSERT OR IGNORE INTO costume_wears"
                    " (id, costume_id, show_id, setlist_item_id, idol_id, sort_order)"
                    " VALUES (:id, :costume_id, :show_id, :setlist_item_id, :idol_id, :sort_order)",
                    w,
                )
            wear_count += len(rows)
            # 投稿した衣装だけを押す (着用記録は costume_id で絞る)。表を丸ごと送ると、
            # 手元の古い値で CloudKit の新しい値を上書きしうる。
            affected["costumes"].add(c["id"])
            affected["costume_wears"].add(c["id"])
        print(f"  ✓ costumes/{path.name}: {len(data['costumes'])} 着 / 着用 {wear_count} 件")

    ecol, shcol = cols(conn, "events"), cols(conn, "shows")
    for path, data in load("events"):
        for ev in data["events"]:
            shows = ev.pop("shows", [])
            insert_row(conn, "events", {k: v for k, v in ev.items() if k in ecol})
            for sh in shows:
                insert_row(conn, "shows", {**{k: v for k, v in sh.items() if k in shcol}, "event_id": ev["id"]})
            affected["events"].add(ev["id"])
            affected["shows"].add(ev["id"])
        print(f"  ✓ events/{path.name}: {len(data['events'])} 件")

    for path, data in load("shows"):
        for sh in data["shows"]:
            sh.pop("note", None)
            insert_row(conn, "shows", {k: v for k, v in sh.items() if k in shcol})
            # shows は event_id で絞って push する (ID_FILTER_COLUMN)。
            affected["shows"].add(sh["event_id"])
        print(f"  ✓ shows/{path.name}: {len(data['shows'])} 公演")

    icol = cols(conn, "idols")
    for path, data in load("idols"):
        for idol in data["idols"]:
            brands = idol.pop("brands", [])
            idol.pop("source", None)
            insert_row(conn, "idols", {k: v for k, v in idol.items() if k in icol})
            for b in brands:
                conn.execute(
                    "INSERT OR IGNORE INTO idol_brands (idol_id, brand_id, is_primary) VALUES (?,?,?)",
                    (idol["id"], b["brand_id"], b.get("is_primary", 0)),
                )
            affected["idols"].add(idol["id"])
            affected["idol_brands"]  # 絞る列が無いので全件
        print(f"  ✓ idols/{path.name}: {len(data['idols'])} 名")

    ucol = cols(conn, "units")
    for path, data in load("units"):
        for u in data["units"]:
            members = u.pop("members", [])
            insert_row(conn, "units", {k: v for k, v in u.items() if k in ucol})
            for idol in members:
                conn.execute(
                    "INSERT OR IGNORE INTO unit_members (unit_id, idol_id) VALUES (?,?)", (u["id"], idol)
                )
            affected["units"].add(u["id"])
            affected["unit_members"]  # 絞る列が無いので全件
        print(f"  ✓ units/{path.name}: {len(data['units'])} 件")

    tscol = cols(conn, "ticket_sales")  # 呼び出し側 (main) が事前に表の存在を確かめている
    for path, data in load("ticket_sales"):
        for t in data["ticket_sales"]:
            t.pop("source", None)
            show_ids = t.pop("show_ids", None) or []
            event_id, name = t["event_id"], t["name"]
            row = {k: v for k, v in t.items() if k in tscol}
            row["id"] = ticket_sale_id(event_id, name)
            row["show_ids"] = ",".join(show_ids) if show_ids else None
            row.setdefault("sort_order", 0)
            insert_row(conn, "ticket_sales", row)
            # 対象イベントの範囲で絞って push する (events/shows と同じ id 空間)。
            affected["ticket_sales"].add(event_id)
        print(f"  ✓ ticket_sales/{path.name}: {len(data['ticket_sales'])} 件")

    for path, data in load("fixes"):
        for fx in data["fixes"]:
            table, rid, fields = fx["table"], fx["id"], fx.get("fields") or {}
            if fields:
                # ticket_sales.show_ids は表では CSV 文字列。fixes は他の新規投稿と同じく
                # 配列で書けるようにしているので、束縛する直前に CSV へ直す
                # (M5: list のまま bind すると sqlite3 が束縛エラーで apply が途中で落ちる)。
                if table == "ticket_sales" and isinstance(fields.get("show_ids"), list):
                    fields = dict(fields, show_ids=",".join(fields["show_ids"]) or None)
                sets = ", ".join(f"{k} = ?" for k in fields)
                conn.execute(f"UPDATE {table} SET {sets} WHERE id = ?", list(fields.values()) + [rid])
            # 原唱者は足すだけ。消すと CloudKit 側に残るので、削除は台帳 (pending_cloudkit_deletions_*) で扱う。
            for idol in fx.get("add_original_singers", []):
                conn.execute(
                    "INSERT OR IGNORE INTO song_artists (song_id, idol_id, role) VALUES (?,?,'original')",
                    (rid, idol),
                )
                affected["song_artists"].add(rid)
            # 公式タグの票は D1 行き。マスタには書かない (official_votes に溜めて main が SQL にする)。
            for name in fx.get("add_official_tags", []):
                official_votes.append((official_vote_device(path), rid, name))
            if not fields and not fx.get("add_original_singers"):
                continue  # マスタの行は変わっていないので CloudKit へ押さない
            # fixes は id 列で 1 行を直す。その表が絞れるなら、その 1 行だけを押す
            # (押すときに見る列は表ごとに違うので scope_id で読み替える)。
            if SCOPED_ID_SPACE.get(table):
                affected[table].add(scope_id(conn, table, rid))
            else:
                affected[table]
        print(f"  ✓ fixes/{path.name}: {len(data['fixes'])} 件修正")

    conn.commit()
    return affected


def push_cloudkit(affected, production, db=None):
    """触った行だけを CloudKit へ push する。

    **表ごとに、その表の id で絞って押す。** まとめて `--tables a b` と渡すと
    seed_cloudkit は各表の**全行**を送る。セトリ 17 曲を足すために
    setlist_items + setlist_performers の全 74,240 行を送っていて、
    1 本 85 分かかっていた (2026-09-06 実測。CloudKit が 200 件バッチあたり 12.6 秒)。

    全行送信は遅いだけでなく**先祖帰りの危険**がある。手元の master.sqlite が
    CloudKit より古い行を持っていると、その古い値で上書きしてしまう。
    触っていない行を送らなければ、そもそも起こらない。

    `--ids` が見る列は表ごとに違う (shows は event_id、show_cast は show_id)。
    同じ id 空間の表だけをまとめ、空間が違えば別々に押す。
    絞る列を持たない表 (creators / idol_brands / unit_members 等) は全件のまま。
    """
    order = {t: i for i, t in enumerate(TABLE_PUSH_ORDER)}
    # 「絞れる表」を id 空間ごとにまとめ、「絞れない表」は 1 回にまとめる。
    groups = defaultdict(lambda: (set(), set()))  # 空間 → (表, id)
    unscoped = set()
    for table, ids in affected.items():
        space = SCOPED_ID_SPACE.get(table)
        if space and ids:
            tables, all_ids = groups[space]
            tables.add(table)
            all_ids |= ids
        else:
            unscoped.add(table)

    runs = []
    for space, (tables, ids) in groups.items():
        runs.append((sorted(tables, key=lambda t: order.get(t, 99)), sorted(ids), space))
    if unscoped:
        runs.append((sorted(unscoped, key=lambda t: order.get(t, 99)), None, None))
    runs.sort(key=lambda r: order.get(r[0][0], 99))

    for tables, ids, space in runs:
        cmd = [sys.executable, str(SEED_SCRIPT), "--tables", *tables]
        cmd += ["--production"] if production else ["--environment", "development"]
        if db:
            cmd += ["--db", str(db)]  # --db で入れた DB から押す (既定の同梱 DB からだと別の DB の行が飛ぶ)
        tmp = None
        if ids:
            # id は日本語やコマンドライン長の問題があるので、ファイルで渡す。
            tmp = tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8")
            tmp.write("\n".join(ids))
            tmp.close()
            cmd += ["--ids-file", tmp.name]
            print(f"\n→ CloudKit push ({space}): {' '.join(tables)} / {len(ids)} 件だけ")
        else:
            print(f"\n→ CloudKit push: {' '.join(tables)} / 全件 (絞る列が無い表)")
        try:
            rc = subprocess.call(cmd)
        finally:
            if tmp:
                os.unlink(tmp.name)
        if rc != 0:
            return rc
    return 0


def notify_discord(db_path, backup_path=None):
    """本番に入れた分を Discord の運営追加チャンネルに知らせる。失敗しても止めない。

    backup_path (反映前のバックアップ) があれば、修正の変更前の値も出す。
    """
    from lib import discord_notify

    conn = sqlite3.connect(db_path)
    before = sqlite3.connect(backup_path) if backup_path and Path(backup_path).exists() else None
    try:
        lines = discord_notify.build_report(conn, load, before)
    finally:
        conn.close()
        if before is not None:
            before.close()
    if discord_notify.post_report(lines):
        print("✓ Discord に追加のお知らせを投稿")
    elif lines:
        print("(Discord へのお知らせは出していません: チャンネル・トークン未設定か投稿失敗)")


def main():
    ap = argparse.ArgumentParser(description="コミュニティ提出の新規データを一括投入する")
    ap.add_argument("--check", action="store_true", help="検証のみ (既定・鍵不要)")
    ap.add_argument("--apply", action="store_true", help="master.sqlite に INSERT")
    ap.add_argument("--push", action="store_true", help="反映後 CloudKit へ push (要 --apply)")
    ap.add_argument("--production", action="store_true", help="push 先を Production に")
    ap.add_argument("--db", default=str(DB_PATH))
    ap.add_argument("--d1-sql", metavar="OUT.sql",
                    help="公式タグの票 (add_official_tags) を D1 に流す SQL の書き出し先。"
                         "票のある投稿を --apply するときは必須 (票はマスタではなく D1 にある)")
    ap.add_argument("--only", metavar="FILE.json",
                    help="この 1 ファイルだけを対象にする (他の保留中の投稿に巻き込まれない)")
    args = ap.parse_args()
    if args.only:
        global ONLY_FILE
        ONLY_FILE = Path(args.only).name

    ensure_db(args.db)
    conn = sqlite3.connect(args.db)
    conn.execute("PRAGMA foreign_keys = ON")

    has_any = any(load(k) for k in list(KIND_TABLES) + ["fixes"])
    if not has_any:
        print("投入対象なし (data/<種類>/*.json または data/fixes/*.json)。")
        return

    print("検証中...")
    problems = validate(conn)
    if problems:
        print(f"\n✗ {len(problems)} 件の問題:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        sys.exit(1)
    print("✓ 全件妥当")

    if not args.apply:
        print("\n(--check のみ。投入するには --apply)")
        return

    if load("ticket_sales") and not table_exists(conn, "ticket_sales"):
        # imas-core 側の DDL (db/master.sql の ticket_sales 表) がまだこの master.sqlite に
        # 無い。表を作ってしまうと db/master.sql の正本と食い違うので、ここでは作らずに諦める。
        print(
            "\n✗ ticket_sales 表が master.sqlite に無い"
            " (imas-core 側の DDL がこの db/master.sql にまだ反映されていない)。"
            " --apply を中止します。db/master.sql の更新を待つか pull し直してください。",
            file=sys.stderr,
        )
        sys.exit(1)

    has_official_votes = any(fx.get("add_official_tags")
                             for _, data in load("fixes") for fx in data.get("fixes", []))
    if has_official_votes and not args.d1_sql:
        print(
            "\n✗ 公式タグの票 (add_official_tags) は D1 (imas-live-api) に入れるもので、"
            "--apply / --push ではどこにも届かない。--d1-sql <書き出し先.sql> を付けて SQL を作り、"
            "npx wrangler d1 execute imas-live-db --remote --file <その.sql> で流すこと。",
            file=sys.stderr,
        )
        sys.exit(1)

    backup = Path(args.db).with_suffix(f".sqlite.bak_{int(time.time())}")
    shutil.copy2(args.db, backup)
    print(f"\nバックアップ: {backup.name}")
    official_votes = []
    affected = apply_all(conn, official_votes)
    conn.close()
    if official_votes:
        Path(args.d1_sql).write_text(official_tag_vote_sql(official_votes), encoding="utf-8")
        print(f"\n公式タグの票 {len(official_votes)} 件の SQL: {args.d1_sql}"
              f"\n  → cd imas-live-api && npx wrangler d1 execute imas-live-db --remote --file {Path(args.d1_sql).resolve()}")
    print(f"対象テーブル: {sorted(affected)}")

    if args.push:
        rc = push_cloudkit(affected, args.production, args.db)
        if rc != 0:
            sys.exit(rc)
        print("✓ CloudKit push 完了")
        if args.production:
            notify_discord(args.db, backup)
    else:
        print("\n(master.sqlite のみ反映。CloudKit へ出すには --push --production)")
    print("\n反映したファイルは data/_applied/<種類>/ へ移す (git mv。apply_data は読まない)。")


if __name__ == "__main__":
    main()
