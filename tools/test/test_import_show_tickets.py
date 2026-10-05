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

    def test_archive_period_is_stored_and_seven_columns_stay_null(self):
        stream = "\t".join(["sh_a", "stream", "配信", "3500", "0", "", "https://example.com/t",
                            "2026-09-28 18:00", "2026-10-05"])
        self.assertEqual(self.run_main(ticket_line("sh_a"), stream), 0)
        self.assertEqual(
            self.canonical("SELECT kind, archive_starts_at, archive_ends_at FROM show_tickets ORDER BY kind"),
            [("live", None, None), ("stream", "2026-09-28 18:00", "2026-10-05")])
        conn = sqlite3.connect(str(self.bundle))
        try:
            self.assertEqual(conn.execute("SELECT archive_ends_at FROM show_tickets WHERE kind='stream'").fetchall(),
                             [("2026-10-05",)])
        finally:
            conn.close()

    def test_reimport_without_period_keeps_the_existing_period(self):
        stream7 = "\t".join(["sh_a", "stream", "配信", "3500", "0", "", "https://example.com/t"])
        self.assertEqual(self.run_main(stream7), 0)
        conn = sqlite3.connect(str(self.bundle))
        conn.execute("UPDATE show_tickets SET archive_starts_at='2026-09-28', archive_ends_at='2026-10-05'")
        conn.commit()
        conn.close()
        with masterdb.restored(self.master_sql) as c:
            c.execute("UPDATE show_tickets SET archive_starts_at='2026-09-28', archive_ends_at='2026-10-05'")
            self.master_sql.write_text(masterdb.dump_text(c), encoding="utf-8")
        self.assertEqual(self.run_main(stream7.replace("3500", "3600")), 0)
        want = [(3600, "2026-09-28", "2026-10-05")]
        self.assertEqual(self.canonical("SELECT price, archive_starts_at, archive_ends_at FROM show_tickets"), want)
        conn = sqlite3.connect(str(self.bundle))
        try:
            self.assertEqual(conn.execute(
                "SELECT price, archive_starts_at, archive_ends_at FROM show_tickets").fetchall(), want)
        finally:
            conn.close()

    def test_bad_archive_period_is_rejected(self):
        def row(a, b, kind="stream"):
            return "\t".join(["sh_a", kind, "配信", "3500", "0", "", "https://example.com/t", a, b])
        before = support.sha256(self.master_sql)
        for line, why in (
            (row("2026/09/28", "2026-10-05"), "アーカイブ期間が変"),
            (row("2026-02-30", "2026-03-05"), "アーカイブ期間が変"),
            (row("2026-10-06", "2026-10-05"), "始まりが終わりより後"),
            (row("2026-09-28", "2026-10-05", kind="live"), "kind=stream"),
        ):
            self.assertEqual(self.run_main(line), 1, line)
            self.assertIn(why, self.output)
        self.assertEqual(support.sha256(self.master_sql), before)

    def test_check_only_writes_nothing(self):
        before = support.sha256(self.master_sql), support.sha256(self.bundle)
        self.assertEqual(self.run_main(ticket_line("sh_a"), apply=False), 0)
        self.assertEqual((support.sha256(self.master_sql), support.sha256(self.bundle)), before)


if __name__ == "__main__":
    unittest.main()
