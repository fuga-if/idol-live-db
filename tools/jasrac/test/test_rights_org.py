#!/usr/bin/env python3
"""JASRAC と NexTone への振り分け (works.tsv の rights_org) のテスト。

    python3 -m unittest discover -s tools/jasrac/test -p 'test_*.py'

同じ曲を両方に報告しない・どちらにも報告しない、をここで固定する。
"""

import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import build_reports as B  # noqa: E402
import works_tsv as W  # noqa: E402


def row(song_id, rights_org="", **kw):
    r = {c: "" for c in W.COLUMNS}
    r.update(song_id=song_id, title=song_id, work_title=song_id, lyricist_raw="作詞者",
             composer_raw="作曲者", artist="歌手", interface_key="k-" + song_id,
             match_status="unmatched", rights_org=rights_org)
    r.update(kw)
    return r


class Args(object):
    ivt = "T"
    lyric_kind = "1"
    info_fee = "0"
    request_count = "0"


def run_quiet(fn, args):
    with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
        fn(args)


class TestRightsOrgSplit(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        d = self.tmp.name
        self.works = os.path.join(d, "works.tsv")
        W.write_rows(self.works, [
            row("cg_a"),                          # 未確認 → JASRAC
            row("cg_b", "jasrac"),
            row("gakuen_c", "nextone"),
            row("gakuen_d", "nextone"),           # 掲載していない
            row("other_e", match_status="excluded"),
        ])
        self.published = os.path.join(d, "published.txt")
        with open(self.published, "w") as f:
            f.write("cg_a\ncg_b\ngakuen_c\n")
        self.req = os.path.join(d, "req")
        os.mkdir(self.req)
        with open(os.path.join(self.req, "2026-09-01.tsv"), "w") as f:
            f.write("song_id\tcount\ncg_a\t3\ngakuen_c\t5\n")
        self.out = os.path.join(d, "out")
        self._orig_out = B.OUT_DIR
        B.OUT_DIR = self.out

    def tearDown(self):
        B.OUT_DIR = self._orig_out
        self.tmp.cleanup()

    def _args(self, **kw):
        a = Args()
        a.works = self.works
        a.published = self.published
        a.requests_dir = self.req
        a.period = "202609-202609"
        a.__dict__.update(kw)
        return a

    def test_nextone_gets_only_published_nextone_songs(self):
        run_quiet(B.cmd_nextone, self._args(license_no="ID000012667"))
        path = os.path.join(self.out, "nextone_ID000012667_202609-202609.tsv")
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
        self.assertEqual(lines[0].split("\t")[0], "song_id")
        self.assertEqual([ln.split("\t")[0] for ln in lines[1:]], ["gakuen_c"])
        self.assertEqual(lines[1].split("\t")[-1], "5")

    def test_annual_leaves_out_nextone_songs(self):
        run_quiet(B.cmd_annual, self._args(license_no="J260943703", month="202609",
                                           suffix="", force=False))
        path = os.path.join(self.out, "J260943703202609.txt")
        with open(path, encoding="cp932") as f:
            keys = [ln.split("\t")[0] for ln in f.read().splitlines()]
        self.assertEqual(sorted(keys), ["k-cg_a", "k-cg_b"])

    def test_vocabulary(self):
        self.assertTrue(W.reports_to_nextone({"rights_org": "nextone"}))
        self.assertFalse(W.reports_to_nextone({"rights_org": ""}))
        self.assertFalse(W.reports_to_nextone({"rights_org": "jasrac"}))


if __name__ == "__main__":
    unittest.main()
