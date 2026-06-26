#!/usr/bin/env python3
"""apply_data.py — コミュニティから PR で集めたデータを一括反映する口。

data/ 配下を読み、検証 → master.sqlite に反映 → CloudKit へ一括 push する。
  - data/<種類>/*.json (songs/setlists/events/idols/units) … 新規追加 (INSERT)
  - data/fixes/*.json                                       … 既存レコードの修正 (UPDATE)

    # 貢献者 (鍵不要・自己検証):
    python3 tools/apply_data.py --check

    # オーナー (レビュー後):
    python3 tools/apply_data.py --apply
    CLOUDKIT_KEY_ID=... python3 tools/apply_data.py --apply --push --production

形式は data/<種類>/_template.json / data/fixes/_template.json と data/README.md 参照。
全ファイルに source (出典URL) 必須。
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "ImasLiveDB" / "Resources" / "master.sqlite"
DATA_DIR = ROOT / "data"
SEED_SCRIPT = Path(__file__).resolve().parent / "seed_cloudkit.py"
DUMP_PATH = ROOT / "db" / "master.sql"


def ensure_db(db_path):
    """binary master.sqlite が無ければ db/master.sql から生成 (クローン直後でも --check 可)。"""
    p = Path(db_path)
    if not p.exists() and DUMP_PATH.exists():
        p.parent.mkdir(parents=True, exist_ok=True)
        c = sqlite3.connect(str(p))
        c.executescript(DUMP_PATH.read_text(encoding="utf-8"))
        c.close()
        print(f"(db/master.sql から {p.name} を生成しました)")

VALID_BRANDS = {"765as", "cg", "ml", "sidem", "sc", "gakuen", "876", "961", "other"}
# 種類 → (主テーブル, 子テーブル群)。push 時の対象テーブル算出にも使う。
KIND_TABLES = {
    "songs": ["songs", "song_artists"],
    "setlists": ["setlist_items", "setlist_performers"],
    "events": ["events", "shows"],
    "idols": ["idols", "idol_brands"],
    "units": ["units", "unit_members"],
}
# data/fixes/ で既存レコードを UPDATE 可能なテーブル (id 列を持つ事実情報のみ)
ALLOWED_FIX_TABLES = {"idols", "songs", "events", "shows", "units", "brands"}


def cols(conn, table):
    return {r[1] for r in conn.execute(f"PRAGMA table_info({table})")}


def exists(conn, table, rec_id):
    return conn.execute(f"SELECT 1 FROM {table} WHERE id = ?", (rec_id,)).fetchone() is not None


def load(kind):
    out = []
    d = DATA_DIR / kind
    if not d.exists():
        return out
    for p in sorted(d.glob("*.json")):
        if p.name.startswith("_"):
            continue
        out.append((p, json.loads(p.read_text(encoding="utf-8"))))
    return out


def resolve_song(conn, brand_id, song_id, title):
    """song_id 優先。無ければ brand 内でタイトル完全一致を試みる。"""
    if song_id:
        return song_id if exists(conn, "songs", song_id) else None
    rows = conn.execute(
        "SELECT id FROM songs WHERE brand_id = ? AND title = ?", (brand_id, title)
    ).fetchall()
    return rows[0][0] if len(rows) == 1 else None


# ---- 検証 -----------------------------------------------------------------

def validate(conn):
    problems = []

    def need_source(path, data):
        if not str(data.get("source", "")).strip().startswith("http"):
            problems.append(f"{path.name}: source (出典URL) が必須")

    for path, data in load("songs"):
        need_source(path, data)
        scol = cols(conn, "songs")
        for i, s in enumerate(data.get("songs", [])):
            tag = f"songs/{path.name}[{i}]"
            if s.get("brand_id") not in VALID_BRANDS:
                problems.append(f"{tag}: brand_id 不正 ({s.get('brand_id')})")
            if not s.get("id"):
                problems.append(f"{tag}: id が空")
            elif exists(conn, "songs", s["id"]):
                problems.append(f"{tag}: id '{s['id']}' は既に存在 (新規追加のみ)")
            for k in s:
                if k not in scol and k not in ("original_singers", "source", "note"):
                    problems.append(f"{tag}: 未知の列 '{k}'")
            for idol in s.get("original_singers", []):
                if not exists(conn, "idols", idol):
                    problems.append(f"{tag}: original_singers の idol '{idol}' が存在しない")
            if s.get("unit_id") and not exists(conn, "units", s["unit_id"]):
                problems.append(f"{tag}: unit_id '{s['unit_id']}' が存在しない")

    for path, data in load("setlists"):
        need_source(path, data)
        show_id = data.get("show_id")
        if not show_id or not exists(conn, "shows", show_id):
            problems.append(f"setlists/{path.name}: show_id '{show_id}' が存在しない")
            continue
        brand = conn.execute(
            "SELECT e.brand_id FROM shows s JOIN events e ON e.id=s.event_id WHERE s.id=?",
            (show_id,),
        ).fetchone()
        brand_id = brand[0] if brand else None
        for i, sg in enumerate(data.get("songs", [])):
            tag = f"setlists/{path.name}[pos {sg.get('position')}]"
            sid = resolve_song(conn, brand_id, sg.get("song_id"), sg.get("title"))
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
        need_source(path, data)
        ecol, scol = cols(conn, "events"), cols(conn, "shows")
        for i, ev in enumerate(data.get("events", [])):
            tag = f"events/{path.name}[{i}]"
            if ev.get("brand_id") not in VALID_BRANDS:
                problems.append(f"{tag}: brand_id 不正")
            if not ev.get("id") or exists(conn, "events", ev.get("id", "")):
                problems.append(f"{tag}: event id が空 or 既存")
            for k in ev:
                if k not in ecol and k not in ("shows",):
                    problems.append(f"{tag}: events に未知の列 '{k}'")
            for sh in ev.get("shows", []):
                if not sh.get("id") or exists(conn, "shows", sh.get("id", "")):
                    problems.append(f"{tag}: show id が空 or 既存 ({sh.get('id')})")
                for k in sh:
                    if k not in scol:
                        problems.append(f"{tag}: shows に未知の列 '{k}'")

    for path, data in load("idols"):
        need_source(path, data)
        icol = cols(conn, "idols")
        for i, idol in enumerate(data.get("idols", [])):
            tag = f"idols/{path.name}[{i}]"
            if idol.get("brand_id") not in VALID_BRANDS:
                problems.append(f"{tag}: brand_id 不正")
            if not idol.get("id") or exists(conn, "idols", idol.get("id", "")):
                problems.append(f"{tag}: idol id が空 or 既存")
            for k in idol:
                if k not in icol and k not in ("brands",):
                    problems.append(f"{tag}: idols に未知の列 '{k}'")

    for path, data in load("units"):
        need_source(path, data)
        ucol = cols(conn, "units")
        for i, u in enumerate(data.get("units", [])):
            tag = f"units/{path.name}[{i}]"
            if u.get("brand_id") not in VALID_BRANDS:
                problems.append(f"{tag}: brand_id 不正")
            if not u.get("id") or exists(conn, "units", u.get("id", "")):
                problems.append(f"{tag}: unit id が空 or 既存")
            for k in u:
                if k not in ucol and k not in ("members",):
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
            if not isinstance(fields, dict) or not fields:
                problems.append(f"{tag}: fields が無い/空")
            else:
                for k in fields:
                    if k == "id":
                        problems.append(f"{tag}: id は変更不可")
                    elif k not in tcol:
                        problems.append(f"{tag}: '{table}' に列 '{k}' が無い")
            if not str(fx.get("source", "")).strip().startswith("http"):
                problems.append(f"{tag}: source (出典URL) が必須")

    return problems


# ---- 反映 -----------------------------------------------------------------

def insert_row(conn, table, row):
    keys = list(row.keys())
    conn.execute(
        f"INSERT INTO {table} ({', '.join(keys)}) VALUES ({', '.join('?' for _ in keys)})",
        [row[k] for k in keys],
    )


def apply_all(conn):
    affected = set()
    scol = cols(conn, "songs")

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
            affected |= {"songs", "song_artists"}
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
        affected |= {"setlist_items", "setlist_performers"}
        print(f"  ✓ setlists/{path.name}: {len(data['songs'])} 曲")

    ecol, shcol = cols(conn, "events"), cols(conn, "shows")
    for path, data in load("events"):
        for ev in data["events"]:
            shows = ev.pop("shows", [])
            insert_row(conn, "events", {k: v for k, v in ev.items() if k in ecol})
            for sh in shows:
                insert_row(conn, "shows", {**{k: v for k, v in sh.items() if k in shcol}, "event_id": ev["id"]})
            affected |= {"events", "shows"}
        print(f"  ✓ events/{path.name}: {len(data['events'])} 件")

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
            affected |= {"idols", "idol_brands"}
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
            affected |= {"units", "unit_members"}
        print(f"  ✓ units/{path.name}: {len(data['units'])} 件")

    for path, data in load("fixes"):
        for fx in data["fixes"]:
            table, rid, fields = fx["table"], fx["id"], fx["fields"]
            sets = ", ".join(f"{k} = ?" for k in fields)
            conn.execute(f"UPDATE {table} SET {sets} WHERE id = ?", list(fields.values()) + [rid])
            affected.add(table)
        print(f"  ✓ fixes/{path.name}: {len(data['fixes'])} 件修正")

    conn.commit()
    return affected


def push_cloudkit(tables, production):
    cmd = [sys.executable, str(SEED_SCRIPT), "--tables", *sorted(tables)]
    cmd += ["--production"] if production else ["--environment", "development"]
    print(f"\n→ CloudKit push: {' '.join(cmd)}")
    return subprocess.call(cmd)


def main():
    ap = argparse.ArgumentParser(description="コミュニティ提出の新規データを一括投入する")
    ap.add_argument("--check", action="store_true", help="検証のみ (既定・鍵不要)")
    ap.add_argument("--apply", action="store_true", help="master.sqlite に INSERT")
    ap.add_argument("--push", action="store_true", help="反映後 CloudKit へ push (要 --apply)")
    ap.add_argument("--production", action="store_true", help="push 先を Production に")
    ap.add_argument("--db", default=str(DB_PATH))
    args = ap.parse_args()

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

    backup = Path(args.db).with_suffix(f".sqlite.bak_{int(time.time())}")
    shutil.copy2(args.db, backup)
    print(f"\nバックアップ: {backup.name}")
    affected = apply_all(conn)
    conn.close()
    print(f"対象テーブル: {sorted(affected)}")

    if args.push:
        rc = push_cloudkit(affected, args.production)
        if rc != 0:
            sys.exit(rc)
        print("✓ CloudKit push 完了")
    else:
        print("\n(master.sqlite のみ反映。CloudKit へ出すには --push --production)")
    print("\n適用済みの data/**/*.json は確認後に削除してOK (PR履歴が監査ログ)。")


if __name__ == "__main__":
    main()
