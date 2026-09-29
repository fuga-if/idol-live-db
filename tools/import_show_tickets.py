#!/usr/bin/env python3
"""集めたチケット価格 (TSV) を db/master.sql と同梱 DB に入れる。

`data/tickets/README.md` の形式で書かれた TSV を読み、検査してから流す。
**検査に落ちた行は 1 行も入れない** — 価格表は「どんな券があったか」を答える
マスタなので、桁の打ち間違いが 1 件混ざると価格帯がまるごと嘘になる。

使い方:
    python3 tools/import_show_tickets.py data/tickets/prices_*.tsv          # 検査だけ
    python3 tools/import_show_tickets.py --apply data/tickets/prices_*.tsv  # 反映

公演の実在は、書き込む先の正本 (db/master.sql を戻した一時 DB) で確かめる。手元の
master.sqlite で確かめて正本に書くと、手元にだけある公演を指す行が正本に入り、
外部キーの壊れになる (実際に 23 行入った)。正本は tools/lib/masterdb.py の
write_master_sql で書き出す (書く前に一時 DB で外部キーを検査する)。
同梱 DB (手元の master.sqlite) には全行を 1 つのトランザクションで入れる。同梱 DB に
無い公演を指す行が 1 つでもあれば、同梱 DB には 1 行も入れずに知らせる (正本には入る)。
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sqlite3
import sys
from pathlib import Path

from lib import masterdb

BUNDLE_DB = masterdb.BUNDLE_DB
MASTER_SQL = masterdb.MASTER_SQL

INSERT_TICKETS = (
    "INSERT OR REPLACE INTO show_tickets "
    "(id, show_id, kind, name, price, is_estimate, note, sort_order) "
    "VALUES (?, ?, ?, ?, ?, ?, ?, ?)")

KINDS = {"live", "stream", "live_viewing"}
# 1 枚 100 万円を超える券は無い (コアの validate_ticket と同じ上限)。
MAX_PRICE = 1_000_000


def slug(text: str) -> str:
    """id に使える形へ。日本語の券種名はそのままでは id に向かないので畳む。"""
    table = {
        "全席指定": "seat", "指定席": "seat", "アリーナ": "arena", "スタンド": "stand",
        "立見": "standing", "ステージサイド": "stageside", "見切れ": "restricted",
        "配信": "stream", "アーカイブ": "archive", "ライブビューイング": "lv",
        "一般": "general", "特典": "bonus", "前方": "front", "後方": "back",
    }
    out = text
    for ja, en in table.items():
        out = out.replace(ja, f"_{en}_")
    out = re.sub(r"[^A-Za-z0-9_]+", "_", out).strip("_").lower()
    return re.sub(r"_+", "_", out) or "ticket"


def load(paths: list[Path], known_shows: set[str]) -> tuple[list[tuple], list[str]]:
    rows: list[tuple] = []
    errors: list[str] = []
    seen: set[tuple[str, str, str]] = set()
    order: dict[tuple[str, str], int] = {}

    for path in paths:
        for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 7:
                errors.append(f"{path.name}:{lineno} 列が {len(parts)} 個 (7 個必要)")
                continue
            show_id, kind, name, price_s, estimate_s, note, source = (p.strip() for p in parts)

            if show_id not in known_shows:
                errors.append(f"{path.name}:{lineno} 知らない公演 id: {show_id}")
                continue
            if kind not in KINDS:
                errors.append(f"{path.name}:{lineno} kind が {kind} ({'/'.join(sorted(KINDS))} のどれか)")
                continue
            if not name:
                errors.append(f"{path.name}:{lineno} 券種名が空")
                continue
            if not price_s.isdigit() or not (0 < int(price_s) <= MAX_PRICE):
                errors.append(f"{path.name}:{lineno} 価格が変: {price_s}")
                continue
            if estimate_s not in {"0", "1"}:
                errors.append(f"{path.name}:{lineno} is_estimate は 0 か 1: {estimate_s}")
                continue
            if not source.startswith("http"):
                errors.append(f"{path.name}:{lineno} 出典 URL が無い")
                continue

            key = (show_id, kind, name)
            if key in seen:
                errors.append(f"{path.name}:{lineno} 同じ公演に同じ券種が 2 回: {name}")
                continue
            seen.add(key)

            # 並び順は「公式の表記順 = ファイルに書かれた順」を形態ごとに振る。
            seq = order.get((show_id, kind), 0) + 1
            order[(show_id, kind)] = seq

            note_full = note if not source else (f"{note} / 出典: {source}" if note else f"出典: {source}")
            # id は (公演, 形態, 券種名) で決まる。券種名の畳み方 (slug) だけだと
            # 「全席指定」と「全席指定 一般チケット」が同じ id になって、
            # **片方が黙って消える** (実際に 1112 行が 988 行に減った)。
            # 名前のハッシュを足して一意にする。並べ替えても id が動かないよう、
            # 順番ではなくハッシュを使う。
            digest = hashlib.sha1(name.encode("utf-8")).hexdigest()[:6]
            rows.append((
                f"tkt_{show_id}_{kind}_{slug(name)}"[:110] + f"_{digest}",
                show_id, kind, name, int(price_s), int(estimate_s), note_full, seq,
            ))
    return rows, errors


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+", type=Path)
    ap.add_argument("--apply", action="store_true", help="検査を通ったら実際に入れる")
    ap.add_argument("--db", type=Path, default=BUNDLE_DB, help="同梱 DB (既定: ImasLiveDB/Resources/master.sqlite)")
    ap.add_argument("--master-sql", type=Path, default=MASTER_SQL, help="正本 (既定: db/master.sql)")
    args = ap.parse_args()

    with masterdb.restored(args.master_sql) as canonical:
        known = {r[0] for r in canonical.execute("SELECT id FROM shows")}
        rows, errors = load(args.paths, known)
        for e in errors:
            print(f"NG {e}", file=sys.stderr)
        print(f"読めた行: {len(rows)} / はじいた行: {len(errors)}")
        if errors:
            # 1 行でも変なら入れない。直してから通すこと。
            return 1
        if not args.apply:
            print("(--apply を付けると反映する)")
            return 0
        # 同じ id の行は置き換える (追記だけだと重複が増える)。
        canonical.executemany(INSERT_TICKETS, rows)
        masterdb.write_master_sql(canonical, args.master_sql)
    print(f"{args.master_sql} に {len(rows)} 行")

    if not args.db.exists():
        print(f"(同梱 DB {args.db} が無いので、正本にだけ入れた)")
        return 0
    try:
        with sqlite3.connect(str(args.db)) as db:
            db.execute("PRAGMA foreign_keys = ON")
            db.executemany(INSERT_TICKETS, rows)
        print(f"同梱 DB に {len(rows)} 行")
    except sqlite3.IntegrityError as e:
        # 同梱 DB に無い公演がある (正本より古いか、食い違っている)。with を抜けた時点で
        # この書き込みは全部巻き戻っている。正本から作り直せば揃うが、作り直しは手元の
        # 同梱 DB を正本で置き換えるので、まだ Production に届いていない行が消える。
        print(f"⚠️ 同梱 DB には 1 行も入れなかった (同梱 DB に無い公演を指す行がある: {e})。"
              "正本には入っている。同梱 DB を正本から作り直せば (bash tools/build_db.sh) 揃うが、"
              "手元の同梱 DB にしか無い行 (まだ Production に push していない行) は作り直すと消える。"
              "それが無いと確かめてから作り直すこと", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
