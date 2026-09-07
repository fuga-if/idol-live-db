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
"""
from __future__ import annotations

import argparse
import tempfile
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
from collections import defaultdict
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "ImasLiveDB" / "Resources" / "master.sqlite"
DATA_DIR = ROOT / "data"
SEED_SCRIPT = Path(__file__).resolve().parent / "seed_cloudkit.py"

# 絞り込みの知識は seed_cloudkit.py が持つ。**写さずに読む** (片方だけ古くならないように)。
sys.path.insert(0, str(Path(__file__).resolve().parent))
from seed_cloudkit import SCOPED_ID_SPACE, TABLE_ORDER as TABLE_PUSH_ORDER  # noqa: E402
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
    "unit_versions": ["unit_versions"],
    "creators": ["creators"],
}
# data/fixes/ で既存レコードを UPDATE 可能なテーブル (id 列を持つ事実情報のみ)
ALLOWED_FIX_TABLES = {
    "idols", "songs", "events", "shows", "units", "brands", "venues", "venue_names", "creators",
    "setlist_items",
}
# 読みの表は fixes ではなく専用の投入口 (data/creators/) から入れる。


def cols(conn, table):
    return {r[1] for r in conn.execute(f"PRAGMA table_info({table})")}


def exists(conn, table, rec_id):
    return conn.execute(f"SELECT 1 FROM {table} WHERE id = ?", (rec_id,)).fetchone() is not None


# 処理対象を 1 ファイルに絞るときのファイル名 (--only)。
#
# data/ 全体を一度に流すと、無関係な保留中の投稿が 1 件でも失敗した時点で
# トランザクションごと巻き戻り、レビュー済みの投稿まで入らなくなる
# (実際、保留中のセトリの UNIQUE 違反で読み仮名 316 件が入らなかった)。
# レビューが済んだものから順に入れられるようにする。
ONLY_FILE = None


def load(kind):
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

def validate(conn):
    problems = []

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
            for k in s:
                if k not in scol and k not in ("original_singers", "source", "note"):
                    problems.append(f"{tag}: 未知の列 '{k}'")
            for idol in s.get("original_singers", []):
                if not exists(conn, "idols", idol):
                    problems.append(f"{tag}: original_singers の idol '{idol}' が存在しない")
            if s.get("unit_id") and not exists(conn, "units", s["unit_id"]):
                problems.append(f"{tag}: unit_id '{s['unit_id']}' が存在しない")

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
                if k not in ecol and k not in ("shows",):
                    problems.append(f"{tag}: events に未知の列 '{k}'")
            for sh in ev.get("shows", []):
                if not sh.get("id") or exists(conn, "shows", sh.get("id", "")):
                    problems.append(f"{tag}: show id が空 or 既存 ({sh.get('id')})")
                for k in sh:
                    if k not in scol:
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
                if k not in icol and k not in ("brands",):
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
                if k not in ccol and k != "note":
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
                if k not in vcol and k != "note":
                    problems.append(f"{tag}: unit_versions に未知の列 '{k}'")

    for path, data in load("units"):
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

    return problems


# ---- 反映 -----------------------------------------------------------------

def insert_row(conn, table, row):
    keys = list(row.keys())
    conn.execute(
        f"INSERT INTO {table} ({', '.join(keys)}) VALUES ({', '.join('?' for _ in keys)})",
        [row[k] for k in keys],
    )


def apply_all(conn):
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

    for path, data in load("fixes"):
        for fx in data["fixes"]:
            table, rid, fields = fx["table"], fx["id"], fx["fields"]
            sets = ", ".join(f"{k} = ?" for k in fields)
            conn.execute(f"UPDATE {table} SET {sets} WHERE id = ?", list(fields.values()) + [rid])
            # fixes は id 列で 1 行を直すので、その表が id で絞れるならその id だけ押す。
            if SCOPED_ID_SPACE.get(table):
                affected[table].add(rid)
            else:
                affected[table]
        print(f"  ✓ fixes/{path.name}: {len(data['fixes'])} 件修正")

    conn.commit()
    return affected


def push_cloudkit(affected, production):
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


def main():
    ap = argparse.ArgumentParser(description="コミュニティ提出の新規データを一括投入する")
    ap.add_argument("--check", action="store_true", help="検証のみ (既定・鍵不要)")
    ap.add_argument("--apply", action="store_true", help="master.sqlite に INSERT")
    ap.add_argument("--push", action="store_true", help="反映後 CloudKit へ push (要 --apply)")
    ap.add_argument("--production", action="store_true", help="push 先を Production に")
    ap.add_argument("--db", default=str(DB_PATH))
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
