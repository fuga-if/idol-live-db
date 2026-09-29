"""export_cloudkit.py のテスト (CloudKit の読み取りは偽物に差し替える)。

    python3 -m unittest discover -s tools/test -p 'test_*.py'
"""

import contextlib
import hashlib
import io
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

import support
import export_cloudkit
import seed_cloudkit
from lib import masterdb


def brand_record(i, name=True):
    fields = {"shortName": {"value": "B%d" % i}, "sortOrder": {"value": i}}
    if name:
        fields["name"] = {"value": "ブランド%d" % i}
    return {"recordName": "b%02d" % i, "recordType": "Brand", "fields": fields}


class RefreshTableTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        path = Path(self.tmp.name) / "m.sqlite"
        support.schema_only(path)
        self.conn = sqlite3.connect(str(path))
        self.cloudkit = {}
        saved = export_cloudkit.query_all
        self.addCleanup(setattr, export_cloudkit, "query_all", saved)
        export_cloudkit.query_all = lambda record_type: self.cloudkit.get(record_type, [])

    def tearDown(self):
        self.conn.close()
        self.tmp.cleanup()

    def given_local_brands(self, n):
        self.conn.executemany(
            "INSERT INTO brands (id, name, short_name, sort_order) VALUES (?, ?, ?, ?)",
            [("b%02d" % i, "ブランド%d" % i, "B%d" % i, i) for i in range(n)])

    def refresh(self):
        with contextlib.redirect_stdout(io.StringIO()) as out, \
                contextlib.redirect_stderr(io.StringIO()) as err:
            inserted = export_cloudkit.refresh_table(self.conn, "brands")
        return inserted, out.getvalue() + err.getvalue()

    def test_every_dropped_row_is_listed(self):
        # name が無いレコードは NOT NULL で入らない。先頭 5 件だけでなく全部を出す。
        self.cloudkit["Brand"] = [brand_record(i, name=(i >= 7)) for i in range(9)]
        inserted, log = self.refresh()
        self.assertEqual(inserted, 2)
        for i in range(7):
            self.assertIn("b%02d" % i, log)

    def test_warns_when_a_table_empties(self):
        self.given_local_brands(3)
        inserted, log = self.refresh()
        self.assertEqual(inserted, 0)
        self.assertIn("brands: 3 行 → 0 行", log)

    def test_exactly_ten_percent_is_warned(self):
        # 「10% 以上減ったら」なので、ちょうど 10% 減も警告する (70 → 63 は浮動小数の
        # 比較だと 70 * 0.9 = 63.000…01 になって漏れる)。
        for before, after in ((20, 18), (100, 90), (70, 63)):
            with self.subTest(before=before, after=after):
                self.conn.execute("DELETE FROM brands")
                self.given_local_brands(before)
                self.cloudkit["Brand"] = [brand_record(i) for i in range(after)]
                _, log = self.refresh()
                self.assertIn(f"brands: {before} 行 → {after} 行", log)

    def test_just_under_ten_percent_is_not_warned(self):
        self.given_local_brands(100)
        self.cloudkit["Brand"] = [brand_record(i) for i in range(91)]
        _, log = self.refresh()
        self.assertNotIn("行 → ", log)


class ExportMainTest(unittest.TestCase):
    """main を通しで回す。CloudKit の中身は、正本の行を seed と同じ規則でレコードにしたもの。"""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        support.schema_only(root / "fixture.sqlite")
        conn = sqlite3.connect(str(root / "fixture.sqlite"))
        conn.executescript("""
            INSERT INTO meta (key, value) VALUES ('data_version', '5');
            INSERT INTO meta (key, value) VALUES ('content_hash', 'stale');
            INSERT INTO brands (id, name, short_name, sort_order) VALUES ('ml', 'ML', 'ML', 3);
            INSERT INTO events (id, brand_id, name, event_type, kind) VALUES ('ev_t', 'ml', 'ライブ', 'live', 'live');
            INSERT INTO shows (id, event_id, name, date, sort_order, performer_type)
                VALUES ('sh_t', 'ev_t', 'DAY1', '2026-01-01', 0, 'cast');
        """)
        conn.commit()
        self.cloudkit = {}
        for table in seed_cloudkit.TABLE_ORDER:
            cols, select = seed_cloudkit.push_columns(conn, table)
            cur = conn.execute(f"SELECT {select} FROM {table}")
            names = [d[0] for d in cur.description]
            rows = [dict(zip(names, r)) for r in cur.fetchall()]
            ops = seed_cloudkit.rows_to_operations(
                table, rows, cols, seed_cloudkit.get_primary_keys(conn, table))
            self.cloudkit[seed_cloudkit.RECORD_TYPE_MAP[table]] = [op["record"] for op in ops]
        self.dump = root / "master.sql"
        self.dump.write_text(masterdb.dump_text(conn), encoding="utf-8")
        conn.close()
        self.db = root / "master.sqlite"
        for obj, name, value in ((export_cloudkit, "DUMP_PATH", self.dump),
                                 (export_cloudkit, "DB_PATH", self.db),
                                 (export_cloudkit, "query_all", lambda rt: self.cloudkit.get(rt, [])),
                                 (seed_cloudkit, "init_session", lambda key_id, key_file: None)):
            self.addCleanup(setattr, obj, name, getattr(obj, name))
            setattr(obj, name, value)
        self.addCleanup(seed_cloudkit._build_paths, "development")

    def tearDown(self):
        self.tmp.cleanup()

    def run_main(self):
        saved = sys.argv
        sys.argv = ["export_cloudkit.py", "--production", "--key-id", "dummy"]
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                export_cloudkit.main()
        finally:
            sys.argv = saved

    def meta(self, key):
        conn = sqlite3.connect(str(self.db))
        try:
            row = conn.execute("SELECT value FROM meta WHERE key = ?", (key,)).fetchone()
            return row and row[0]
        finally:
            conn.close()

    def test_no_change_keeps_the_dump_and_the_version(self):
        before = self.dump.read_bytes()
        self.run_main()
        self.assertEqual(self.dump.read_bytes(), before)
        self.assertEqual(self.meta("data_version"), "5")

    def test_a_change_bumps_the_version(self):
        self.cloudkit["Event"][0]["fields"]["name"]["value"] = "ライブ (改名)"
        self.run_main()
        self.assertIn("ライブ (改名)", self.dump.read_text(encoding="utf-8"))
        self.assertEqual(self.meta("data_version"), "6")

    def test_the_built_master_sqlite_carries_the_new_fingerprint(self):
        # master.sqlite を作る経路では指紋を入れ直す (tools/build_db.sh と同じ値)。
        self.run_main()
        self.assertEqual(self.meta("content_hash"),
                         hashlib.sha256(self.dump.read_bytes()).hexdigest())


if __name__ == "__main__":
    unittest.main()
