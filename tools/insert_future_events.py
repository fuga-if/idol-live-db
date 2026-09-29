#!/usr/bin/env python3
"""公式スケジュールから取得した未来イベントを master.sqlite と CloudKit に入れる。

tools/future_events.json の各イベントを INSERT OR IGNORE で入れ、**入った行だけ**を
CloudKit へ送る。

    python3 tools/insert_future_events.py --dry-run          # 何が入り何を送るか見るだけ
    python3 tools/insert_future_events.py --skip-cloudkit    # 手元の DB にだけ入れる
    python3 tools/insert_future_events.py --production --key-id KEY_ID
    (--key-id=KEY_ID の形と、環境変数 CLOUDKIT_KEY_ID も使える)

既に入っているイベントは送らない。CloudKit 側で直した分類 (event_type / kind /
is_streaming / is_solo) を、発表時点の空の値で上書きしてしまうため。名前や日付を
送り直したいときだけ --resend-existing を付ける (そのときも分類の列は送らない)。
⚠️ --resend-existing が送るのは JSON の値なので、CloudKit 側で直したイベント名・公演名を
JSON の値へ戻す操作になりうる (2026-09-19 に実際に 3 公演の名前が戻った)。
使う前に、JSON の名前が今の正本と同じか確かめる。

送信でエラーが 1 件でも出たら、手元の DB には入れずに exit 1 で終わる。入れてしまうと
次の実行で「入った行」にならず、その行が二度と送られないため。同じコマンドを
もう一度流せばよい。
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import sys
import unicodedata
from pathlib import Path

from lib import cloudkit as ck
from lib.ck_records import next_modified_ms

TOOLS_DIR = Path(__file__).resolve().parent
DB_PATH = TOOLS_DIR.parent / "ImasLiveDB" / "Resources" / "master.sqlite"
EVENTS_FILE = TOOLS_DIR / "future_events.json"
DEFAULT_KEY_FILE = TOOLS_DIR / "eckey.pem"

# 発表の時点では分からないので、新しいイベントには空・0 で入れる列。
# 既存の行を送り直すときは送らない (CloudKit 側で直した値を消さないため)。
CLASSIFICATION_FIELDS = ("eventType", "kind", "isStreaming", "isSolo")


def slugify(name: str) -> str:
    """name → ASCII-safe id 一部 (英数字・日本語維持、空白と記号→_)。"""
    s = unicodedata.normalize("NFKC", name)
    # 既存 ev_ は半角 ASCII + 日本語混在。同じ規則で:
    s = re.sub(r"[\s　・〜～()（）\[\]【】「」『』<>《》:;,.!?\"'/+*]", "_", s)
    s = re.sub(r"_+", "_", s)
    s = s.strip("_").lower()
    return s


def event_id(name: str) -> str:
    return "ev_" + slugify(name)[:120]


def show_id(eid: str, idx: int) -> str:
    return f"sh_{eid[3:]}_{idx + 1}"  # ev_ プレフィックス除去


def has_cast_table(cur) -> bool:
    """旧 cast テーブルの有無。スキーマ移行で消えているので参照前に確認する。"""
    return cur.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='cast'"
    ).fetchone() is not None


def cast_id_lookup(name: str, cur) -> str | None:
    """cast 名 → cast.id 解決。NFKC + 大文字小文字・スペース無視で一致を探す。"""
    norm = unicodedata.normalize("NFKC", name).replace(" ", "").replace("　", "").lower()
    rows = cur.execute("SELECT id, name FROM cast").fetchall()
    for cid, cname in rows:
        cnorm = unicodedata.normalize("NFKC", cname).replace(" ", "").replace("　", "").lower()
        if cnorm == norm:
            return cid
    return None


def _operation(record_type: str, record_name: str, fields: dict) -> dict:
    return {
        "operationType": "forceUpdate",
        "record": {"recordType": record_type, "recordName": record_name, "fields": fields},
    }


def insert_events(conn: sqlite3.Connection, events: list, resend_existing: bool = False) -> dict:
    """events を INSERT OR IGNORE で入れ、送る操作を集める (commit はしない)。

    送るのは入った行だけ。resend_existing のときは既存の行も送るが、分類の列は除く。
    modifiedAt は送る直前に付ける (ここでは付けない)。
    """
    cur = conn.cursor()
    # 旧 cast テーブルはスキーマ移行で削除済み。残っている cast 記載は無視する
    # (出演者はコミュニティのオープン編集に委ねる方針)。
    cast_available = has_cast_table(cur)
    counts = {"events": 0, "shows": 0, "show_cast": 0}
    ops = {"Event": [], "Show": [], "ShowCast": []}
    unknown_casts: set[str] = set()

    for ev in events:
        eid = event_id(ev["name"])
        cur.execute(
            "INSERT OR IGNORE INTO events (id, brand_id, name, event_type, kind, is_streaming, is_solo) VALUES (?, ?, ?, ?, ?, 0, 0)",
            # event_type は催しの性格 (周年 / オケ / 外部イベント …)。発表段階では
            # 分からないので**未分類 (空)** で入れる。"live" を既定にすると周年ライブが
            # 自社の単発公演として数えられ、「周年では」の答えが静かに変わる。
            (eid, ev["brand"], ev["name"], "", ev["kind"]),
        )
        inserted = cur.rowcount > 0
        counts["events"] += inserted
        fields = {
            "name": {"value": ev["name"], "type": "STRING"},
            "brandId": {"value": ev["brand"], "type": "STRING"},
            "eventType": {"value": "", "type": "STRING"},
            "kind": {"value": ev["kind"], "type": "STRING"},
            "isStreaming": {"value": 0, "type": "INT64"},
            "isSolo": {"value": 0, "type": "INT64"},
        }
        if inserted:
            ops["Event"].append(_operation("Event", eid, fields))
        elif resend_existing:
            kept = {k: v for k, v in fields.items() if k not in CLASSIFICATION_FIELDS}
            ops["Event"].append(_operation("Event", eid, kept))

        for idx, sh in enumerate(ev.get("shows", [])):
            sid = show_id(eid, idx)
            sh_name = sh.get("name") or ev["name"]
            cur.execute(
                "INSERT OR IGNORE INTO shows (id, event_id, name, date, venue, sort_order) VALUES (?, ?, ?, ?, ?, ?)",
                (sid, eid, sh_name, sh["date"], sh.get("venue"), idx),
            )
            inserted = cur.rowcount > 0
            counts["shows"] += inserted
            if inserted or resend_existing:
                sh_fields = {
                    "eventId": {"value": eid, "type": "STRING"},
                    "name": {"value": sh_name, "type": "STRING"},
                    "date": {"value": sh["date"], "type": "STRING"},
                    "sortOrder": {"value": idx, "type": "INT64"},
                }
                if sh.get("venue"):
                    sh_fields["venue"] = {"value": sh["venue"], "type": "STRING"}
                ops["Show"].append(_operation("Show", sid, sh_fields))

            for cast_name in (ev.get("cast", []) if cast_available else []):
                cid = cast_id_lookup(cast_name, cur)
                if cid is None:
                    unknown_casts.add(cast_name)
                    continue
                cur.execute(
                    "INSERT OR IGNORE INTO show_cast (show_id, cast_id) VALUES (?, ?)",
                    (sid, cid),
                )
                inserted = cur.rowcount > 0
                counts["show_cast"] += inserted
                if inserted or resend_existing:
                    ops["ShowCast"].append(_operation("ShowCast", f"show_cast-{sid}-{cid}", {
                        "showId": {"value": sid, "type": "STRING"},
                        "castId": {"value": cid, "type": "STRING"},
                    }))

    return {"counts": counts, "ops": ops, "unknown_casts": unknown_casts,
            "cast_available": cast_available}


def push(ops: dict, production: bool, key_id: str, key_file: Path) -> int:
    """ops を CloudKit へ送り、レコード単位のエラーの件数を返す (Event → Show → ShowCast の順)。"""
    signer = ck.load_signer(key_id, key_file)
    url = ck.BASE_URL + ck.records_path("production" if production else "development", "modify")
    errors = 0
    for record_type in ("Event", "Show", "ShowCast"):
        records = ops[record_type]
        for op in records:
            op["record"]["fields"]["modifiedAt"] = {"value": next_modified_ms(), "type": "TIMESTAMP"}
        _, failed = ck.upload_operations(
            records, url, False, record_type, post=lambda u, p: ck.post_json(u, p, signer))
        errors += failed
    return errors


def parse_args(argv=None):
    ap = argparse.ArgumentParser(
        description="未来イベントを master.sqlite に入れ、入った行だけを CloudKit へ送る")
    ap.add_argument("--production", action="store_true",
                    help="送り先を Production にする (既定は development)")
    ap.add_argument("--key-id", default=os.environ.get("CLOUDKIT_KEY_ID", ""),
                    help="CloudKit の S2S 鍵の ID。--key-id=ID の形も可 (既定: 環境変数 CLOUDKIT_KEY_ID)")
    ap.add_argument("--key-file", type=Path, default=DEFAULT_KEY_FILE,
                    help="S2S 鍵の PEM (既定: tools/eckey.pem)")
    ap.add_argument("--db", type=Path, default=DB_PATH, help="入れる先の SQLite (既定: 同梱 master.sqlite)")
    ap.add_argument("--events-file", type=Path, default=EVENTS_FILE,
                    help="イベントの JSON (既定: tools/future_events.json)")
    ap.add_argument("--dry-run", action="store_true",
                    help="DB を書き換えず、入る行と送る操作を表示するだけ")
    ap.add_argument("--skip-cloudkit", action="store_true",
                    help="手元の DB にだけ入れ、CloudKit へは送らない")
    ap.add_argument("--resend-existing", action="store_true",
                    help="既に入っている行も送る (分類の列は送らない)。⚠️ 既存のイベント名・公演名を "
                         "JSON の値へ戻す操作になりうる (2026-09-19 に実際に 3 公演の名前が戻った)。"
                         "使う前に JSON の名前が今の正本と同じか確かめる")
    return ap.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    sending = not (args.dry_run or args.skip_cloudkit)
    # 鍵の不備は DB に触る前に止める。入れてから止まると、次の実行で送られなくなる。
    if sending and not args.key_id:
        print("Error: 鍵の ID が無い (--key-id か環境変数 CLOUDKIT_KEY_ID)。"
              "送らずに入れるだけなら --skip-cloudkit", file=sys.stderr)
        return 1
    if sending and not args.key_file.exists():
        print(f"Error: 鍵のファイルが無い: {args.key_file}", file=sys.stderr)
        return 1

    events = json.loads(args.events_file.read_text(encoding="utf-8"))
    conn = sqlite3.connect(str(args.db))
    try:
        plan = insert_events(conn, events, args.resend_existing)
        if not plan["cast_available"]:
            print("cast テーブルが無いため cast/show_cast の登録はスキップする")
        c = plan["counts"]
        print(f"Local: events={c['events']}, shows={c['shows']}, show_cast={c['show_cast']}")
        if plan["unknown_casts"]:
            print(f"Unknown casts ({len(plan['unknown_casts'])}):")
            for name in sorted(plan["unknown_casts"]):
                print(f"  - {name}")

        if args.dry_run:
            conn.rollback()
            print("(--dry-run: DB は書き換えていない。送る操作は次のとおり)")
            for record_type, ops in plan["ops"].items():
                for op in ops:
                    print(f"  {record_type} {op['record']['recordName']}")
            return 0
        if not sending:
            conn.commit()
            return 0

        errors = push(plan["ops"], args.production, args.key_id, args.key_file)
        if errors:
            conn.rollback()
            print(f"✗ CloudKit でエラーが {errors} 件。手元の DB には入れていない。"
                  "原因を直して同じコマンドをもう一度流す。", file=sys.stderr)
            return 1
        conn.commit()
        print("done")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
