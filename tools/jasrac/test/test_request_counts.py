#!/usr/bin/env python3
"""build_reports.py の「リクエスト回数」(19項目目) のテスト。

    python3 -m unittest discover -s tools/jasrac/test -p 'test_*.py'

報告に出す数なので、合算の仕方と欠測の扱いをここで固定する。
"""

import io
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import build_reports as B  # noqa: E402


def write(dirpath, name, rows, header=True):
    with io.open(os.path.join(dirpath, name), "w", encoding="utf-8", newline="\n") as f:
        if header:
            f.write("song_id\tcount\n")
        for song_id, n in rows:
            f.write("%s\t%d\n" % (song_id, n))


class Args(object):
    """build_record が読むプロファイル引数だけを持つ最小の入れ物。"""

    ivt = "T"
    lyric_kind = "1"
    info_fee = "0"
    request_count = "0"


class TestParsePeriod(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(B.parse_period("202604-202703"), ("202604", "202703"))

    def test_invalid_forms_exit(self):
        for bad in ["202604", "2026-04", "202604-2027-03", "202613-202703", "202704-202603"]:
            with self.assertRaises(SystemExit, msg=bad):
                B.parse_period(bad)


class TestReadRequestCounts(unittest.TestCase):
    def test_sums_days_in_period_only(self):
        with tempfile.TemporaryDirectory() as d:
            write(d, "2026-04-01.tsv", [("a", 3), ("b", 1)])
            write(d, "2026-04-02.tsv", [("a", 2)])
            # 期間外 (2026-03) は合算しない。
            write(d, "2026-03-31.tsv", [("a", 100)])
            # 期間外 (2027-04) も合算しない。
            write(d, "2027-04-01.tsv", [("a", 100)])
            counts = B.read_request_counts(d, "202604-202703")
            self.assertEqual(counts, {"a": 5, "b": 1})

    def test_ignores_non_tsv_files(self):
        with tempfile.TemporaryDirectory() as d:
            write(d, "2026-04-01.tsv", [("a", 1)])
            with io.open(os.path.join(d, "README.md"), "w", encoding="utf-8") as f:
                f.write("メモ\n")
            self.assertEqual(B.read_request_counts(d, "202604-202604"), {"a": 1})

    def test_empty_period_is_zero_not_error(self):
        # 日次ファイルがまだ 1 つも無くても報告は作れる (全曲 0 になる)。
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(B.read_request_counts(d, "202604-202703"), {})

    def test_broken_count_exits(self):
        with tempfile.TemporaryDirectory() as d:
            with io.open(os.path.join(d, "2026-04-01.tsv"), "w", encoding="utf-8") as f:
                f.write("song_id\tcount\na\tたくさん\n")
            with self.assertRaises(SystemExit):
                B.read_request_counts(d, "202604-202604")

    def test_missing_dir_exits(self):
        with self.assertRaises(SystemExit):
            B.read_request_counts("/nonexistent/lyrics_requests", "202604-202604")

    def test_over_nine_digits_exits(self):
        # 項目表の上限は9桁。溢れる値を黙って報告しない。
        with tempfile.TemporaryDirectory() as d:
            write(d, "2026-04-01.tsv", [("a", 10 ** 9)])
            with self.assertRaises(SystemExit):
                B.read_request_counts(d, "202604-202604")


class TestBuildRecordRequestCount(unittest.TestCase):
    row = {"song_id": "cg_A", "title": "A", "lyricist": "詞", "composer": "曲"}

    def test_uses_measured_count(self):
        r = B.build_record(self.row, Args(), {"cg_A": 42})
        self.assertEqual(r["request_count"], "42")

    def test_song_without_hits_is_zero(self):
        # 掲載しているが誰も開かなかった曲。報告は 0 で出す (欄は空にしない)。
        r = B.build_record(self.row, Args(), {"cg_B": 7})
        self.assertEqual(r["request_count"], "0")

    def test_falls_back_to_flat_value(self):
        args = Args()
        args.request_count = "0"
        self.assertEqual(B.build_record(self.row, args)["request_count"], "0")

    def test_measured_count_passes_validation(self):
        r = B.build_record(self.row, Args(), {"cg_A": 999999999})
        msgs = [m for m in B.record_errors(r) if "リクエスト回数" in m]
        self.assertEqual(msgs, [])


if __name__ == "__main__":
    unittest.main()
