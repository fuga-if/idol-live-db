#!/usr/bin/env python3
"""D1 のコミュニティデータから、公開しても安全なスナップショットを作る。

これは何か
    タグの語彙・付与数、お気に入り数、ペンライト色、ポールの結果といった
    「集計されたコミュニティの成果物」を、db/master.sql と同じように git で
    diff できるテキストにして残す。リリースごとに撮っておけば、
    「この時点でどんなタグがあり、何が人気だったか」が履歴として追える。

⚠️ 何を落とすか (public repo なので必須)
    D1 には Apple uid (users.id / *_votes.user_id)、device_id、表示名、
    引き継ぎコードが入っている。それらを含むテーブルと列は**一切出力しない**。
    出すのは「誰が」を含まない集計だけ。
    完全バックアップ (PII 込み) が要るなら tools/backup_d1.sh を使うこと。

⚠️ NULL の扱い
    `wrangler d1 execute --json` は SQL の NULL を文字列 "null" として返すため、
    本物の文字列 'null' と区別できない。そこで値の整形は Python でやらず、
    SQLite の quote() に任せて INSERT 文ごと SQL 側で組み立てている。
    quote() は NULL をちゃんと NULL に、文字列をエスケープ済みリテラルにする。

使い方
    python3 tools/export_community_snapshot.py --local     # ローカル D1 で動作確認
    python3 tools/export_community_snapshot.py --remote    # 本番から取得 (オーナーのみ)
    出力先: db/community.sql
"""
from __future__ import annotations  # macOS 同梱の Python 3.9 でも `str | None` 注釈を許す

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
API_DIR = ROOT / "imas-live-api"
OUT = ROOT / "db" / "community.sql"

TAG_COLUMNS = ["id", "name", "description", "category", "color", "is_official", "status"]

# (テーブル, 説明, 出力する列, WHERE 句, ORDER BY 句)
# 列を足すときは「誰が」を含まないか必ず確認すること (FORBIDDEN_COLUMNS で機械チェック)。
EXPORTS = [
    ("tags", "曲タグの語彙 (作成者 created_by/updated_by は出さない)",
     TAG_COLUMNS, "status = 'active'", "id"),
    ("idol_tag_master", "アイドルタグの語彙",
     TAG_COLUMNS, "status = 'active'", "id"),
    ("unit_tag_master", "ユニットタグの語彙",
     TAG_COLUMNS, "status = 'active'", "id"),
    ("song_tags", "曲へのタグ付与数 (集計のみ)",
     ["song_id", "tag_id", "vote_count"], None, "song_id, tag_id"),
    ("idol_tags", "アイドルへのタグ付与数",
     ["idol_id", "tag_id", "vote_count"], None, "idol_id, tag_id"),
    ("unit_tags", "ユニットへのタグ付与数",
     ["unit_id", "tag_id", "vote_count"], None, "unit_id, tag_id"),
    ("song_favorites", "お気に入り数",
     ["song_id", "count"], None, "song_id"),
    ("penlight_color_set_votes", "ペンライト色セットの投票数",
     ["song_id", "color_set_key", "count"], None, "song_id, color_set_key"),
    ("polls", "お題 (作成者 created_by は出さない)",
     ["id", "title", "description", "target_type", "created_at", "ends_at", "status"],
     None, "created_at, id"),
    ("poll_entries", "お題の得票 (first_voted_by は出さない)",
     ["poll_id", "entity_id", "vote_count"], None, "poll_id, vote_count DESC, entity_id"),
]

# 絶対に出力してはいけない列名。指定に紛れ込んでいたら止める。
FORBIDDEN_COLUMNS = {
    "user_id", "device_id", "created_by", "updated_by", "first_voted_by",
    "editor_id", "display_name", "avatar_url", "payload", "public_key", "code",
}


def build_sql(table: str, columns: list[str], where: str | None, order: str) -> str:
    """INSERT 文そのものを SQLite に組み立てさせる (quote() で NULL/エスケープを正しく処理)。"""
    # SQLite の単一引用符リテラル内では " をエスケープしない (二重化すると列名が壊れる)
    col_list = ", ".join(f'"{c}"' for c in columns)
    quoted = " || ', ' || ".join(f"quote({c})" for c in columns)
    sql = (
        f"SELECT 'INSERT INTO \"{table}\" ({col_list}) VALUES (' || {quoted} || ');' AS stmt "
        f"FROM {table}"
    )
    if where:
        sql += f" WHERE {where}"
    return sql + f" ORDER BY {order}"


def run_query(sql: str, target: str) -> list[dict]:
    proc = subprocess.run(
        ["npx", "wrangler", "d1", "execute", "imas-live-db", target, "--json", "--command", sql],
        cwd=API_DIR, capture_output=True, text=True,
    )
    if proc.returncode != 0:
        sys.exit(f"クエリ失敗:\n{sql}\n{proc.stderr}")
    start = proc.stdout.find("[")
    if start < 0:
        sys.exit(f"JSON が返らなかった:\n{proc.stdout[:400]}")
    return json.loads(proc.stdout[start:])[0]["results"]


def main() -> int:
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--local", action="store_true", help="ローカル D1 (動作確認用)")
    g.add_argument("--remote", action="store_true", help="本番 D1 (オーナーのみ)")
    args = ap.parse_args()
    target = "--local" if args.local else "--remote"

    for table, _, columns, where, _ in EXPORTS:
        leaked = FORBIDDEN_COLUMNS.intersection(columns)
        if leaked:
            sys.exit(f"✗ {table}: 個人を識別しうる列 {sorted(leaked)} が指定されている")
        if where and any(c in where for c in FORBIDDEN_COLUMNS):
            sys.exit(f"✗ {table}: WHERE 句に識別子が含まれている: {where}")

    lines = [
        "-- db/community.sql — コミュニティ集計 (D1) の公開用スナップショット",
        "--",
        "-- ⚠️ これは完全バックアップではない。「誰が」を含む列 (user_id / device_id /",
        "--    created_by / 表示名 / 引き継ぎコード) は意図的に一切含めていない。",
        "--    このリポジトリは public なので、生ダンプを載せると個人情報が漏れる。",
        "--    完全バックアップは tools/backup_d1.sh で db_backups_local/ に取ること。",
        "--",
        "-- 生成: python3 tools/export_community_snapshot.py --remote",
        "",
    ]

    total = 0
    for table, note, columns, where, order in EXPORTS:
        rows = run_query(build_sql(table, columns, where, order), target)
        stmts = [r["stmt"] for r in rows]
        total += len(stmts)
        lines.append(f"-- {table}: {note} ({len(stmts)} 行)")
        lines.extend(stmts)
        lines.append("")
        print(f"  {table}: {len(stmts)} 行")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"\n✓ {OUT.relative_to(ROOT)} ({total} 行)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
