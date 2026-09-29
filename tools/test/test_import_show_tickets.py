"""import_show_tickets.py のテスト (一時の正本と一時の同梱 DB だけを使う)。

    python3 -m unittest discover -s tools/test -p 'test_*.py'
"""

import contextlib
import io
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

import support
import import_show_tickets as ist
from lib import masterdb


def fixture(path, shows):
    """公演 shows を持つ DB を path に作る。"""
    support.schema_only(path)
    conn = sqlite3.connect(str(path))
    conn.execute("INSERT INTO meta (key, value) VALUES ('data_version', '1')")
    conn.execute("INSERT INTO events (id, brand_id, name, event_type) VALUES ('ev_t', 'ml', 'ライブ', 'live')")
    for sid in shows:
        conn.execute("INSERT INTO shows (id, event_id, name, date, sort_order)"
                     " VALUES (?, 'ev_t', ?, '2026-01-01', 0)", (sid, sid))
    conn.commit()
    return conn


def ticket_line(show_id, price="8800", name="全席指定"):
    return "\t".join([show_id, "live", name, price, "0", "", "https://example.com/tickets"])


class ImportShowTicketsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.master_sql = root / "master.sql"
        conn = fixture(root / "canonical.sqlite", ["sh_a", "sh_c"])
        self.master_sql.write_text(masterdb.dump_text(conn), encoding="utf-8")
        conn.close()
        # 手元の同梱 DB は正本と食い違っている (sh_b は手元にだけ、sh_c は正本にだけある)。
        self.bundle = root / "bundle.sqlite"
        fixture(self.bundle, ["sh_a", "sh_b"]).close()
        self.tsv = root / "prices.tsv"
        # 旧版は既定のパスを直に使っていたので、そちらも向け直す。
        for name, value in (("BUNDLE_DB", self.bundle), ("MASTER_SQL", self.master_sql)):
            self.addCleanup(setattr, ist, name, getattr(ist, name))
            setattr(ist, name, value)

    def tearDown(self):
        self.tmp.cleanup()

    def run_main(self, *lines, apply=True):
        """終了コードを返す。出力 (stdout と stderr) は self.output に残す。"""
        self.tsv.write_text("\n".join(lines) + "\n", encoding="utf-8")
        argv = ["import_show_tickets.py", str(self.tsv), "--db", str(self.bundle),
                "--master-sql", str(self.master_sql)] + (["--apply"] if apply else [])
        saved = sys.argv
        sys.argv = argv
        out, err = io.StringIO(), io.StringIO()
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                return ist.main()
        except SystemExit as e:
            return e.code
        finally:
            sys.argv = saved
            self.output = out.getvalue() + err.getvalue()

    def canonical(self, sql):
        with masterdb.restored(self.master_sql) as conn:
            return conn.execute(sql).fetchall()

    def bundle_rows(self):
        conn = sqlite3.connect(str(self.bundle))
        try:
            return conn.execute("SELECT show_id, price FROM show_tickets ORDER BY show_id").fetchall()
        finally:
            conn.close()

    def test_a_show_missing_from_the_canonical_dump_is_rejected(self):
        before = support.sha256(self.master_sql)
        # 0 以外なら何でもよいのではなく、検査で弾いた (1) ことと、その理由を見る。
        # 例外で落ちても 0 以外になるので、それと区別する。
        self.assertEqual(self.run_main(ticket_line("sh_b")), 1)
        self.assertIn("知らない公演 id: sh_b", self.output)
        self.assertEqual(support.sha256(self.master_sql), before)

    def test_apply_writes_the_canonical_dump_and_the_bundle(self):
        self.assertEqual(self.run_main(ticket_line("sh_a")), 0)
        self.assertEqual(self.canonical("SELECT show_id, price FROM show_tickets"), [("sh_a", 8800)])
        self.assertEqual(self.bundle_rows(), [("sh_a", 8800)])

    def test_reimport_replaces_the_row_instead_of_duplicating_it(self):
        self.assertEqual(self.run_main(ticket_line("sh_a")), 0)
        # 間に日次の export が正本を書き直す (今の db/master.sql と同じ形になる)。
        with masterdb.restored(self.master_sql) as conn:
            self.master_sql.write_text(masterdb.dump_text(conn), encoding="utf-8")
        self.assertEqual(self.run_main(ticket_line("sh_a", price="9900")), 0)
        self.assertEqual(self.canonical("SELECT show_id, price FROM show_tickets"), [("sh_a", 9900)])

    def test_the_bundle_gets_no_row_when_any_show_is_missing(self):
        # 同梱 DB へは 1 つのトランザクションで入れる。1 公演でも無ければ全部巻き戻る。
        self.assertEqual(self.run_main(ticket_line("sh_a"), ticket_line("sh_c")), 0)
        self.assertEqual(self.canonical("SELECT show_id FROM show_tickets ORDER BY show_id"),
                         [("sh_a",), ("sh_c",)])
        self.assertEqual(self.bundle_rows(), [])
        # 作り直しで揃えられることを言うなら、手元にしか無い行が消えることも言う。
        self.assertIn("作り直すと消える", self.output)

    def test_check_only_writes_nothing(self):
        before = support.sha256(self.master_sql), support.sha256(self.bundle)
        self.assertEqual(self.run_main(ticket_line("sh_a"), apply=False), 0)
        self.assertEqual((support.sha256(self.master_sql), support.sha256(self.bundle)), before)


if __name__ == "__main__":
    unittest.main()
