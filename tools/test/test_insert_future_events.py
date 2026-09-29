"""insert_future_events.py のテスト。

    python3 -m unittest discover -s tools/test -p 'test_*.py'

書くのは一時 DB だけ。CloudKit への送信は偽物に差し替えて、送られる操作を見る。
"""

import contextlib
import io
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import support
import insert_future_events as ife

EXISTING = {"name": "既存のライブ", "brand": "ml", "kind": "live",
            "shows": [{"date": "2026-10-01", "venue": "会場A"}]}
NEW = {"name": "新しいライブ", "brand": "ml", "kind": "live",
       "shows": [{"date": "2026-11-01", "venue": "会場B"}, {"date": "2026-11-02", "name": "DAY2"}]}
EVENTS = [EXISTING, NEW]

CLASSIFICATION = {"eventType", "kind", "isStreaming", "isSolo"}


def fixture_db(path):
    """EXISTING だけが入っていて、分類も済んでいる DB。"""
    support.schema_only(path)
    eid = ife.event_id(EXISTING["name"])
    conn = sqlite3.connect(str(path))
    conn.execute("INSERT INTO brands (id, name, short_name, sort_order) VALUES ('ml', 'ML', 'ML', 3)")
    conn.execute(
        "INSERT INTO events (id, brand_id, name, event_type, kind, is_streaming, is_solo)"
        " VALUES (?, 'ml', ?, 'anniversary', 'live', 1, 1)", (eid, EXISTING["name"]))
    conn.execute(
        "INSERT INTO shows (id, event_id, name, date, venue, sort_order)"
        " VALUES (?, ?, ?, '2026-10-01', '会場A', 0)", (ife.show_id(eid, 0), eid, EXISTING["name"]))
    conn.commit()
    conn.close()


class CliTest(unittest.TestCase):
    """引数を何も足さずに起動したとき (既定のパス) の副作用を、写した tools/ で見る。"""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.tools = support.copy_tools(root, "insert_future_events.py")
        support.write_json(self.tools / "future_events.json", EVENTS)
        self.db = root / "ImasLiveDB" / "Resources" / "master.sqlite"
        self.db.parent.mkdir(parents=True)
        fixture_db(self.db)

    def tearDown(self):
        self.tmp.cleanup()

    def run_tool(self, *args):
        env = {k: v for k, v in os.environ.items() if k != "CLOUDKIT_KEY_ID"}
        return subprocess.run(
            [sys.executable, str(self.tools / "insert_future_events.py"), *args],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, env=env)

    def test_help_has_no_side_effects(self):
        before = support.sha256(self.db)
        proc = self.run_tool("--help")
        self.assertEqual(support.sha256(self.db), before, "--help で DB が書き換わった")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("--key-id", proc.stdout)
        # --resend-existing は既存の名前を JSON の値へ戻しうる。ヘルプで警告する
        # (argparse が行を折るので空白を除いて見る)。
        self.assertIn("JSONの値へ戻す操作になりうる", "".join(proc.stdout.split()))

    def test_push_without_key_fails_before_writing(self):
        before = support.sha256(self.db)
        proc = self.run_tool("--production")
        self.assertEqual(support.sha256(self.db), before, "鍵が無いのに DB を書き換えた")
        # 例外で落ちても終了コードは 1 になるので、止めた理由まで見て区別する。
        self.assertEqual(proc.returncode, 1, proc.stderr)
        self.assertIn("鍵の ID が無い", proc.stderr)
        self.assertNotIn("Traceback", proc.stderr)


class PushTest(unittest.TestCase):
    """送る操作を偽物の送信口で受け取って確かめる。"""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.db = root / "m.sqlite"
        fixture_db(self.db)
        self.events_file = root / "future_events.json"
        support.write_json(self.events_file, EVENTS)
        self.key_file = root / "dummy.pem"
        self.key_file.write_text("not a key")
        self.errors_for = set()
        self.cloudkit = support.FakeCloudKit(self, self.respond)

    def tearDown(self):
        self.tmp.cleanup()

    def respond(self, url, payload):
        response = support.accept_all(url, payload)
        for record in response["records"]:
            if record["recordName"] in self.errors_for:
                record["serverErrorCode"] = "SERVER_REJECTED_REQUEST"
        return response

    @property
    def sent(self):
        return self.cloudkit.operations()

    def run_main(self, *args):
        argv = ["insert_future_events.py", *args,
                "--db", str(self.db), "--events-file", str(self.events_file),
                "--key-file", str(self.key_file)]
        saved = sys.argv
        sys.argv = argv
        try:
            with contextlib.redirect_stdout(io.StringIO()) as out, \
                    contextlib.redirect_stderr(io.StringIO()):
                try:
                    rc = ife.main()
                except SystemExit as e:
                    rc = e.code
        finally:
            sys.argv = saved
        return rc, out.getvalue()

    def sent_names(self, record_type):
        return [op["record"]["recordName"] for op in self.sent
                if op["record"]["recordType"] == record_type]

    def event_count(self):
        conn = sqlite3.connect(str(self.db))
        n = conn.execute("SELECT count(*) FROM events").fetchone()[0]
        conn.close()
        return n

    def test_only_inserted_rows_are_pushed(self):
        rc, _ = self.run_main("--key-id=dummy")
        new_id = ife.event_id(NEW["name"])
        self.assertEqual(self.sent_names("Event"), [new_id])
        self.assertEqual(self.sent_names("Show"), [ife.show_id(new_id, 0), ife.show_id(new_id, 1)])
        self.assertEqual(rc, 0)
        self.assertEqual(self.event_count(), 2)

    def test_key_id_separated_by_space_is_accepted(self):
        rc, _ = self.run_main("--key-id", "dummy")
        self.assertEqual(self.sent_names("Event"), [ife.event_id(NEW["name"])])
        self.assertEqual(rc, 0)

    def test_record_errors_exit_nonzero_and_keep_the_db(self):
        self.errors_for = {ife.event_id(NEW["name"])}
        rc, _ = self.run_main("--key-id=dummy")
        self.assertNotIn(rc, (0, None))
        # 送れなかった行を手元にだけ残すと、次の実行で「入った行」にならず二度と送られない。
        self.assertEqual(self.event_count(), 1)

    def test_dry_run_writes_and_sends_nothing(self):
        before = support.sha256(self.db)
        rc, out = self.run_main("--dry-run")
        self.assertEqual(support.sha256(self.db), before)
        self.assertEqual(self.sent, [])
        self.assertEqual(rc, 0)
        self.assertIn(ife.event_id(NEW["name"]), out)
        self.assertNotIn(ife.event_id(EXISTING["name"]), out)

    def test_resend_existing_does_not_send_classification(self):
        rc, _ = self.run_main("--key-id=dummy", "--resend-existing")
        existing_id = ife.event_id(EXISTING["name"])
        ops = {op["record"]["recordName"]: op["record"]["fields"] for op in self.sent}
        self.assertIn(existing_id, ops)
        self.assertEqual(set(ops[existing_id]) & CLASSIFICATION, set())
        self.assertEqual(ops[existing_id]["name"]["value"], EXISTING["name"])
        # 新しく入った行は、入れた値をそのまま全部送る。
        self.assertLessEqual(CLASSIFICATION, set(ops[ife.event_id(NEW["name"])]))
        self.assertEqual(rc, 0)


if __name__ == "__main__":
    unittest.main()
