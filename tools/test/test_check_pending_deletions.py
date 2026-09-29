"""check_pending_deletions.py と削除 TSV の台帳のテスト (CloudKit は偽物)。

    python3 -m unittest discover -s tools/test -p 'test_*.py'
"""

import contextlib
import io
import os
import tempfile
import unittest
from pathlib import Path

import support
import check_pending_deletions as cpd
from seed_cloudkit import parse_delete_file

LEDGER_HEADER = "file\tcreated\tstatus\tchecked\tremaining\tsummary\n"


class CheckerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.alive, self.soft, self.throttled = {"n1"}, {"n2"}, set()
        self.ck = support.FakeCloudKit(self, self.respond)
        self.key_file = self.root / "dummy.pem"
        self.key_file.write_text("not a key")
        saved = os.environ.get("CLOUDKIT_KEY_ID")
        os.environ["CLOUDKIT_KEY_ID"] = "dummy"
        self.addCleanup(lambda: os.environ.__setitem__("CLOUDKIT_KEY_ID", saved) if saved
                        else os.environ.pop("CLOUDKIT_KEY_ID", None))

    def tearDown(self):
        self.tmp.cleanup()

    def respond(self, url, payload):
        out = []
        for ask in payload["records"]:
            name = ask["recordName"]
            if name in self.alive:
                out.append({"recordName": name, "recordType": "Song", "fields": {}})
            elif name in self.throttled:
                out.append({"recordName": name, "serverErrorCode": "THROTTLED"})
            elif name in self.soft:
                out.append({"recordName": name, "recordType": "Song",
                            "fields": {"deletedAt": {"value": 1, "type": "TIMESTAMP"}}})
            else:
                out.append({"recordName": name, "serverErrorCode": "NOT_FOUND"})
        return {"records": out}

    def tsv(self, name, *record_names):
        path = self.root / name
        path.write_text("# 説明\n" + "".join(f"Song\t{n}\n" for n in record_names), encoding="utf-8")
        return path

    def ledger(self, *rows):
        path = self.root / "ledger.tsv"
        path.write_text("# 台帳\n" + LEDGER_HEADER + "".join("\t".join(r) + "\n" for r in rows),
                        encoding="utf-8")
        return path

    def run_main(self, *argv):
        with contextlib.redirect_stdout(io.StringIO()) as out, \
                contextlib.redirect_stderr(io.StringIO()) as err:
            rc = cpd.main(list(argv))
        return rc, out.getvalue() + err.getvalue()

    def test_counts_and_a_ledger_that_agrees(self):
        a = self.tsv("pending_cloudkit_deletions_a.tsv", "n1", "n2", "n3")
        ledger = self.ledger(("pending_cloudkit_deletions_a.tsv", "2026-09-01", "pending", "", "", ""))
        rc, out = self.run_main(str(a), "--ledger", str(ledger), "--key-file", str(self.key_file))
        self.assertEqual(rc, 0, out)
        [(name, counts, problem)] = cpd.check([a], cpd.read_ledger(ledger),
                                             lambda u, p: self.respond(u, p), "production")
        self.assertEqual(counts, {"total": 3, "alive": 1, "soft_deleted": 1, "gone": 1, "unknown": 0})
        self.assertIsNone(problem)

    def test_disagreements_are_reported(self):
        done_early = self.tsv("pending_cloudkit_deletions_b.tsv", "n1")
        finished = self.tsv("pending_cloudkit_deletions_c.tsv", "n3", "n4")
        unknown = self.tsv("pending_cloudkit_deletions_d.tsv", "n5")
        ledger = self.ledger(
            ("pending_cloudkit_deletions_b.tsv", "2026-09-01", "done", "", "", ""),
            ("pending_cloudkit_deletions_c.tsv", "2026-09-01", "pending", "", "", ""))
        rc, out = self.run_main(str(done_early), str(finished), str(unknown),
                                "--ledger", str(ledger), "--key-file", str(self.key_file))
        self.assertEqual(rc, 1)
        self.assertIn("台帳は done だが 1 件が生きている", out)
        self.assertIn("生きているものは無い。台帳を done にする", out)
        self.assertIn("pending_cloudkit_deletions_d.tsv: 台帳に無い", out)

    def test_errors_other_than_not_found_are_unknown(self):
        # 消えたと言えるのは NOT_FOUND だけ。THROTTLED などは「分からない」で、done を案内しない。
        self.throttled = {"n3"}
        a = self.tsv("pending_cloudkit_deletions_a.tsv", "n3", "n4")
        ledger = self.ledger(("pending_cloudkit_deletions_a.tsv", "2026-09-01", "pending", "", "", ""))
        [(_, counts, problem)] = cpd.check([a], cpd.read_ledger(ledger),
                                           lambda u, p: self.respond(u, p), "production")
        self.assertEqual(counts, {"total": 2, "alive": 0, "soft_deleted": 0, "gone": 1, "unknown": 1})
        self.assertNotIn("done", problem)
        rc, out = self.run_main(str(a), "--ledger", str(ledger), "--key-file", str(self.key_file))
        self.assertEqual(rc, 1)
        self.assertIn("確かめられなかった", out)
        self.assertNotIn("台帳を done にする", out)

    def test_it_only_reads(self):
        a = self.tsv("pending_cloudkit_deletions_a.tsv", *["x%d" % i for i in range(250)])
        ledger = self.ledger(("pending_cloudkit_deletions_a.tsv", "2026-09-01", "done", "", "", ""))
        self.run_main(str(a), "--ledger", str(ledger), "--key-file", str(self.key_file))
        urls = {url for url, _ in self.ck.calls}
        self.assertEqual(len(self.ck.calls), 2)  # 200 件ずつ
        self.assertTrue(all(u.endswith("/production/public/records/lookup") for u in urls), urls)

    def test_no_key_stops_before_any_request(self):
        os.environ.pop("CLOUDKIT_KEY_ID")
        a = self.tsv("pending_cloudkit_deletions_a.tsv", "n1")
        rc, _ = self.run_main(str(a), "--key-file", str(self.key_file))
        self.assertEqual(rc, 2)
        self.assertEqual(self.ck.calls, [])


class LedgerTest(unittest.TestCase):
    """tools/ の実物の台帳と削除 TSV が揃っていること (通信しない)。"""

    def test_every_deletion_tsv_has_a_matching_ledger_row(self):
        ledger = cpd.read_ledger(cpd.LEDGER)
        files = {p.name: p for p in cpd.TOOLS_DIR.glob(cpd.TSV_GLOB)}
        self.assertEqual(sorted(files), sorted(ledger))
        for name, row in ledger.items():
            self.assertIn(row["status"], ("pending", "done"), name)
            alive, total = row["remaining"].split("/")
            self.assertEqual(int(total), len(parse_delete_file(files[name])), name)
            self.assertEqual(row["status"] == "pending", int(alive) > 0, name)


if __name__ == "__main__":
    unittest.main()
