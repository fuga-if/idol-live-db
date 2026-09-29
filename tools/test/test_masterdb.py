"""lib/masterdb.py (正本の書き出しの形・書く前の検査・指紋) のテスト。

    python3 -m unittest discover -s tools/test -p 'test_*.py'
"""

import contextlib
import io
import sqlite3
import tempfile
import unittest
from pathlib import Path

import support
from lib import masterdb


class MasterDbTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def fixture(self):
        path = self.root / "db.sqlite"
        support.schema_only(path)
        conn = sqlite3.connect(str(path))
        conn.executescript("""
            INSERT INTO meta (key, value) VALUES ('data_version', '3');
            INSERT INTO events (id, brand_id, name, event_type) VALUES ('ev_t', 'ml', 'ライブ\n改行入り', 'live');
            INSERT INTO shows (id, event_id, name, date, sort_order) VALUES ('sh_t', 'ev_t', 'DAY1', '2026-01-01', 0);
        """)
        conn.commit()
        return conn

    def write(self, conn, path):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            masterdb.write_master_sql(conn, path)

    def test_dump_of_the_canonical_file_is_stable(self):
        # 同じ関数で 2 回書き出して、バイト単位で同じになること。
        with masterdb.restored(support.MASTER_SQL) as conn:
            first = masterdb.dump_text(conn)
        again = self.root / "again.sql"
        again.write_text(first, encoding="utf-8")
        with masterdb.restored(again) as conn:
            self.assertEqual(masterdb.dump_text(conn), first)

    def test_newlines_are_written_as_plain_literals(self):
        # unistr() は古い sqlite3 で読めないので、正本に出さない。
        text = masterdb.dump_text(self.fixture())
        self.assertNotIn("unistr(", text)
        self.assertIn("ライブ\n改行入り", text)

    def test_refuses_to_write_a_broken_reference(self):
        conn = self.fixture()
        path = self.root / "master.sql"
        self.write(conn, path)
        before = support.sha256(path)
        conn.execute("INSERT INTO show_tickets (id, show_id, name, price) VALUES ('t1', 'sh_missing', '券', 1000)")
        with self.assertRaises(SystemExit):
            self.write(conn, path)
        self.assertEqual(support.sha256(path), before)

    def test_a_refused_write_rolls_the_connection_back(self):
        # 検査に落ちたら、正本も手元の DB も変えない (commit してから検査しない)。
        conn = self.fixture()
        path = self.root / "master.sql"
        self.write(conn, path)
        conn.execute("INSERT INTO show_tickets (id, show_id, name, price) VALUES ('t1', 'sh_missing', '券', 1000)")
        with self.assertRaises(SystemExit):
            self.write(conn, path)
        self.assertEqual(conn.execute("SELECT count(*) FROM show_tickets").fetchone()[0], 0)
        other = sqlite3.connect(str(self.root / "db.sqlite"))
        self.assertEqual(other.execute("SELECT count(*) FROM show_tickets").fetchone()[0], 0)
        other.close()

    def test_the_content_hash_row_is_carried_over_from_the_canonical_file(self):
        # 手元の DB の content_hash は build_db.sh が毎回入れ直す値なので、正本に書くと
        # 書き出すたびに差分になる。正本の行をそのまま引き継ぐ (export と同じ)。
        conn = self.fixture()
        path = self.root / "master.sql"
        path.write_text(masterdb.dump_text(conn).replace(
            "COMMIT;", "INSERT INTO \"meta\" VALUES('content_hash','canon');\nCOMMIT;"), encoding="utf-8")
        for local in ("local-1", "local-2"):
            conn.execute("INSERT OR REPLACE INTO meta (key, value) VALUES ('content_hash', ?)", (local,))
            self.write(conn, path)
            text = path.read_text(encoding="utf-8")
            self.assertIn("VALUES('content_hash','canon')", text)
            self.assertNotIn(local, text)

    def test_the_row_is_kept_even_if_the_local_db_has_none(self):
        conn = self.fixture()
        path = self.root / "master.sql"
        path.write_text(masterdb.dump_text(conn).replace(
            "COMMIT;", "INSERT INTO \"meta\" VALUES('content_hash','canon');\nCOMMIT;"), encoding="utf-8")
        self.write(conn, path)
        self.assertEqual(path.read_text(encoding="utf-8").count("VALUES('content_hash','canon')"), 1)

    def test_no_content_hash_row_when_the_canonical_file_has_none(self):
        conn = self.fixture()
        conn.execute("INSERT INTO meta (key, value) VALUES ('content_hash', 'local')")
        path = self.root / "master.sql"
        self.write(conn, path)
        self.assertNotIn("content_hash", path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
