#!/usr/bin/env python3
"""公式スケジュールから取得した未来イベントを Bundle DB + CloudKit Production に投入する。"""
from __future__ import annotations

import json
import re
import sqlite3
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import seed_cloudkit as sk  # type: ignore
from seed_cloudkit import next_modified_ms  # 関数は参照渡しでよい

DB_PATH = Path(__file__).resolve().parent.parent / "ImasLiveDB" / "Resources" / "master.sqlite"

# サブエージェント取得結果
EVENTS = json.loads(Path(__file__).resolve().parent.joinpath("future_events.json").read_text())


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


def cast_id_lookup(name: str, cur) -> str | None:
    """cast 名 → cast.id 解決。NFKC + 大文字小文字・スペース無視で一致を探す。"""
    norm = unicodedata.normalize("NFKC", name).replace(" ", "").replace("　", "").lower()
    rows = cur.execute("SELECT id, name FROM cast").fetchall()
    for cid, cname in rows:
        cnorm = unicodedata.normalize("NFKC", cname).replace(" ", "").replace("　", "").lower()
        if cnorm == norm:
            return cid
    return None


def main() -> None:
    args = sys.argv[1:]
    is_production = "--production" in args
    skip_cloudkit = "--skip-cloudkit" in args
    key_id_arg = next((a.split("=", 1)[1] for a in args if a.startswith("--key-id=")), None)

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    inserted_events, inserted_shows, inserted_show_casts = 0, 0, 0
    unknown_casts: set[str] = set()

    event_records: list[dict] = []
    show_records: list[dict] = []
    show_cast_records: list[dict] = []

    for ev in EVENTS:
        eid = event_id(ev["name"])
        # event INSERT OR IGNORE
        cur.execute(
            "INSERT OR IGNORE INTO events (id, brand_id, name, event_type, kind, is_streaming, is_solo) VALUES (?, ?, ?, ?, ?, 0, 0)",
            (eid, ev["brand"], ev["name"], "live", ev["kind"]),
        )
        if cur.rowcount:
            inserted_events += 1
        event_records.append({
            "operationType": "forceUpdate",
            "record": {
                "recordType": "Event",
                "recordName": eid,
                "fields": {
                    "name": {"value": ev["name"], "type": "STRING"},
                    "brandId": {"value": ev["brand"], "type": "STRING"},
                    "eventType": {"value": "live", "type": "STRING"},
                    "kind": {"value": ev["kind"], "type": "STRING"},
                    "isStreaming": {"value": 0, "type": "INT64"},
                    "isSolo": {"value": 0, "type": "INT64"},
                    "modifiedAt": {"value": next_modified_ms(), "type": "TIMESTAMP"},
                },
            },
        })

        for idx, sh in enumerate(ev.get("shows", [])):
            sid = show_id(eid, idx)
            sh_name = sh.get("name") or ev["name"]
            cur.execute(
                "INSERT OR IGNORE INTO shows (id, event_id, name, date, venue, sort_order) VALUES (?, ?, ?, ?, ?, ?)",
                (sid, eid, sh_name, sh["date"], sh.get("venue"), idx),
            )
            if cur.rowcount:
                inserted_shows += 1
            sh_fields = {
                "eventId": {"value": eid, "type": "STRING"},
                "name": {"value": sh_name, "type": "STRING"},
                "date": {"value": sh["date"], "type": "STRING"},
                "sortOrder": {"value": idx, "type": "INT64"},
                "modifiedAt": {"value": next_modified_ms(), "type": "TIMESTAMP"},
            }
            if sh.get("venue"):
                sh_fields["venue"] = {"value": sh["venue"], "type": "STRING"}
            show_records.append({
                "operationType": "forceUpdate",
                "record": {
                    "recordType": "Show",
                    "recordName": sid,
                    "fields": sh_fields,
                },
            })

            for cast_name in ev.get("cast", []):
                cid = cast_id_lookup(cast_name, cur)
                if cid is None:
                    unknown_casts.add(cast_name)
                    continue
                cur.execute(
                    "INSERT OR IGNORE INTO show_cast (show_id, cast_id) VALUES (?, ?)",
                    (sid, cid),
                )
                if cur.rowcount:
                    inserted_show_casts += 1
                show_cast_records.append({
                    "operationType": "forceUpdate",
                    "record": {
                        "recordType": "ShowCast",
                        "recordName": f"show_cast-{sid}-{cid}",
                        "fields": {
                            "showId": {"value": sid, "type": "STRING"},
                            "castId": {"value": cid, "type": "STRING"},
                            "modifiedAt": {"value": next_modified_ms(), "type": "TIMESTAMP"},
                        },
                    },
                })

    conn.commit()
    print(f"Local: events={inserted_events}, shows={inserted_shows}, show_cast={inserted_show_casts}")
    if unknown_casts:
        print(f"Unknown casts ({len(unknown_casts)}):")
        for c in sorted(unknown_casts):
            print(f"  - {c}")

    if skip_cloudkit:
        return
    if not key_id_arg:
        print("--key-id=... required for CloudKit push")
        return

    env = "production" if is_production else "development"
    sk._build_paths(env)
    sk.init_session(key_id_arg, Path(__file__).resolve().parent / "eckey.pem")
    url = sk.BASE_URL + sk.MODIFY_PATH

    def push(records, label):
        for i in range(0, len(records), 200):
            batch = records[i : i + 200]
            r = sk.post_json(url, {"operations": batch})
            errs = [x for x in r.get("records", []) if "serverErrorCode" in x]
            print(f"  {label}: {min(i + 200, len(records))}/{len(records)} (errors {len(errs)})")
            if errs and i == 0:
                print("  first err:", errs[0])

    push(event_records, "events")
    push(show_records, "shows")
    push(show_cast_records, "show_cast")
    print("done")


if __name__ == "__main__":
    main()
