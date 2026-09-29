"""master.sqlite と正本 db/master.sql の読み書き。標準ライブラリだけで書く。

- 正本 db/master.sql の書き出しは dump_text の 1 形式だけにする (Python の iterdump。
  cron の export と同じ形)。sqlite3 CLI の .dump と混ぜると、行の順番と引用符が
  変わって差分がレビューできなくなる。
- 正本に書くツールは write_master_sql を通す。書く前に、書く中身を一時 DB に戻して
  外部キーの壊れを調べ、1 件でもあれば書かない (検証先と書き込み先を揃える)。
- master.sqlite を作ったら stamp_content_hash で指紋を入れ直す (tools/build_db.sh と
  同じ値。アプリの reseed はこの値の一致/不一致で決まる)。
"""
from __future__ import annotations

import hashlib
import os
import re
import sqlite3
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
BUNDLE_DB = ROOT / "ImasLiveDB" / "Resources" / "master.sqlite"
MASTER_SQL = ROOT / "db" / "master.sql"

# sqlite3 3.49+ の CLI の .dump は制御文字を含む文字列を unistr('…') で書き、古い sqlite3 は
# それを読めない (tools/normalize_master_sql.py)。iterdump は quote() を使うので今は出ないが、
# 正本に入れないことをここで保証する。
_UNISTR = re.compile(r"unistr\(")

# 正本の meta.content_hash の行。手元の master.sqlite には build_db.sh が「その時の正本の
# 指紋」を入れるので、手元の DB から書き出すと書くたびにこの行が変わる。正本への
# 書き出しでは、今の正本の行をそのまま引き継ぐ (export も正本の meta を引き継ぐので同じ)。
_CONTENT_HASH_ROW = re.compile(r"""^INSERT INTO ["']?meta["']? VALUES\('content_hash',.*\);\n""", re.M)


def _keep_content_hash_row(text: str, sql_path) -> str:
    """text の content_hash の行を、sql_path (今の正本) の行に置き換える (無ければ消す)。"""
    current = Path(sql_path).read_text(encoding="utf-8") if Path(sql_path).exists() else ""
    kept = _CONTENT_HASH_ROW.search(current)
    replacement = kept.group(0) if kept else ""
    text, n = _CONTENT_HASH_ROW.subn(lambda _: replacement, text, count=1)
    if n == 0 and replacement:
        # 手元の DB に行が無ければ、meta の最後の行の後ろに戻す。
        rows = list(re.finditer(r"""^INSERT INTO ["']?meta["']? VALUES.*\n""", text, re.M))
        at = rows[-1].end() if rows else text.rindex("COMMIT;")
        text = text[:at] + replacement + text[at:]
    return text


def restore(sql_path, db_path) -> None:
    """sql_path (db/master.sql の形) を db_path に丸ごと入れる。db_path は空であること。"""
    conn = sqlite3.connect(str(db_path))
    try:
        conn.executescript(Path(sql_path).read_text(encoding="utf-8"))
    finally:
        conn.close()


@contextmanager
def restored(sql_path=MASTER_SQL):
    """sql_path を入れた一時 DB に繋いだ接続を渡す。抜けたら一時 DB ごと消す。"""
    with tempfile.TemporaryDirectory(prefix="masterdb-") as tmp:
        path = Path(tmp) / "master.sqlite"
        restore(sql_path, path)
        conn = sqlite3.connect(str(path))
        try:
            yield conn
        finally:
            conn.close()


def dump_text(conn: sqlite3.Connection) -> str:
    """正本の形の SQL テキスト。同じ中身なら何度出しても同じバイト列になる。"""
    text = "".join(line + "\n" for line in conn.iterdump())
    if _UNISTR.search(text):
        from normalize_master_sql import normalize  # tools/ にある

        text, _ = normalize(text)
    return text


def content_hash(sql_path=MASTER_SQL) -> str:
    """正本の指紋 (tools/build_db.sh の meta.content_hash と同じ作り方)。"""
    return hashlib.sha256(Path(sql_path).read_bytes()).hexdigest()


def stamp_content_hash(db_path, sql_path=MASTER_SQL) -> None:
    """db_path の meta.content_hash を、sql_path の指紋にする。"""
    conn = sqlite3.connect(str(db_path))
    try:
        conn.execute(
            "INSERT INTO meta (key, value) VALUES ('content_hash', ?)"
            " ON CONFLICT(key) DO UPDATE SET value = excluded.value", (content_hash(sql_path),))
        conn.commit()
    finally:
        conn.close()


def integrity_problems(db_path) -> int:
    """外部キーの壊れ (宣言済み + 宣言の無い参照 + 同名ユニット) の件数。内容は表示する。"""
    import check_fk_integrity as fk  # tools/ にある (build_db.sh の FK ゲートと同じ検査)

    return (fk.check_fk_integrity(str(db_path)) + fk.check_undeclared_refs(str(db_path))
            + fk.check_duplicate_units(str(db_path)))


def table_counts(conn: sqlite3.Connection) -> dict:
    tables = [r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")]
    return {t: conn.execute(f'SELECT count(*) FROM "{t}"').fetchone()[0] for t in tables}


def _report_changes(before: dict, after: dict) -> None:
    changed = {t: (before.get(t, 0), after.get(t, 0))
               for t in sorted(set(before) | set(after)) if before.get(t, 0) != after.get(t, 0)}
    if not changed:
        print("  表ごとの行数: 変化なし")
        return
    print("  表ごとの行数の変化 (消えるはずのない行が減っていないか確かめること):")
    for table, (old, new) in changed.items():
        print(f"    {table:<24} {old:>7} → {new:>7} ({new - old:+d})")


def write_master_sql(conn: sqlite3.Connection, sql_path=MASTER_SQL) -> None:
    """conn の中身を正本の形で sql_path に書く。書く前に一時 DB で外部キーを検査する。

    壊れが 1 件でもあれば書かずに、conn の未 commit の変更を rollback して SystemExit(1)。
    通れば正本を書いてから conn を commit する (呼び出し側は先に commit しないこと。
    検査に落ちたときに手元の DB だけ変わった状態を残さないため)。表ごとの行数の
    変化も出す (手元の DB を丸ごと書き出すと、正本にしか無い行が黙って消えるため)。
    """
    text = _keep_content_hash_row(dump_text(conn), sql_path)
    with tempfile.TemporaryDirectory(prefix="masterdb-") as tmp:
        check_path = Path(tmp) / "check.sqlite"
        check = sqlite3.connect(str(check_path))
        try:
            check.executescript(text)
            after = table_counts(check)
        finally:
            check.close()
        problems = integrity_problems(check_path)
    if problems:
        conn.rollback()
        print(f"✗ 書き出す中身に外部キーの壊れが {problems} 件。{sql_path} も手元の DB も"
              "書き換えない。", file=sys.stderr)
        raise SystemExit(1)

    if Path(sql_path).exists():
        with restored(sql_path) as old:
            _report_changes(table_counts(old), after)
    tmp_out = f"{sql_path}.tmp"
    with open(tmp_out, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp_out, str(sql_path))
    conn.commit()
    print(f"✓ {sql_path} を書き出した")
