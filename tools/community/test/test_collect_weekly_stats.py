#!/usr/bin/env python3
"""collect_weekly_stats.py のユニットテスト。ネットワークには出ない。

    python3 -m unittest discover -s tools/community/test -p 'test_*.py'
"""
import datetime as dt
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import collect_weekly_stats as C  # noqa: E402

JST = dt.timezone(dt.timedelta(hours=9))


def at(y, m, d, hh=12):
    return int(dt.datetime(y, m, d, hh, tzinfo=JST).timestamp())


def song(song_id, week=None, wp=0, wf=0, pp=0, pf=0, fav=0):
    s = {"song_id": song_id, "favorites": fav, "preview": 99, "full": 99}
    if week:
        s.update(week=week, week_preview=wp, week_full=wf, prev_week_preview=pp, prev_week_full=pf)
    return s


class TestWeek(unittest.TestCase):
    def test_monday_start_in_jst(self):
        # 2026-11-23 は月曜。JST の月曜 0 時台は UTC ではまだ日曜。
        self.assertEqual(C.jst_week_of(at(2026, 11, 23, 0)), dt.date(2026, 11, 23))
        self.assertEqual(C.jst_week_of(at(2026, 11, 22, 23)), dt.date(2026, 11, 16))
        self.assertEqual(C.jst_week_of(at(2026, 11, 29)), dt.date(2026, 11, 23))


class TestFinishedWeek(unittest.TestCase):
    def rows(self, songs):
        return C.finished_week_rows({"generated_at": at(2026, 11, 24), "songs": songs})

    def test_reads_finished_week_by_row_week(self):
        week, rows = self.rows([
            song("a", "2026-11-23", wp=7, wf=7, pp=3, pf=2, fav=1),  # 今週も再生あり → prev_week
            song("b", "2026-11-16", wp=4, wf=1, pp=9, pf=9),         # 今週まだ無し → week
            song("c", "2026-11-09", wp=5, wf=5, fav=6),              # 先週は再生無し
            song("d", fav=2),                                        # お気に入りだけ
            song("e", "2026-11-02", wp=5),                           # 何も無い → 出さない
        ])
        self.assertEqual(week, dt.date(2026, 11, 16))
        self.assertEqual(rows, {"a": (3, 2, 1), "b": (4, 1, 0), "c": (0, 0, 6), "d": (0, 0, 2)})

    def test_rejects_empty_response(self):
        with self.assertRaises(ValueError):
            C.finished_week_rows({"generated_at": at(2026, 11, 24), "songs": []})
        with self.assertRaises(ValueError):
            C.finished_week_rows({"error": "rate limited"})


class TestCollect(unittest.TestCase):
    def test_rerun_refreshes_plays_and_keeps_favorites(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            first = {"generated_at": at(2026, 11, 23, 1), "songs": [
                song("a", "2026-11-16", wp=3, wf=2, fav=5), song("b", fav=1)]}
            path = C.collect(out, first)
            self.assertEqual(path.name, "2026-11-16.tsv")
            self.assertEqual(path.read_text(), "song_id\tpreview\tfull\tfavorites\na\t3\t2\t5\nb\t0\t0\t1\n")
            # 3 日後: 遅れて届いた再生が足され、お気に入りは増えている。新しい曲も出る。
            later = {"generated_at": at(2026, 11, 26), "songs": [
                song("a", "2026-11-23", wp=1, pp=4, pf=2, fav=8), song("b", fav=1),
                song("n", "2026-11-23", wp=1, pp=1, fav=3)]}
            C.collect(out, later)
            self.assertEqual(C.read_tsv(path), {"a": (4, 2, 5), "b": (0, 0, 1), "n": (1, 0, 0)})

    def test_next_week_gets_its_own_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            C.collect(out, {"generated_at": at(2026, 11, 24), "songs": [song("a", "2026-11-16", wp=1)]})
            C.collect(out, {"generated_at": at(2026, 12, 1), "songs": [song("a", "2026-11-23", wp=2)]})
            self.assertEqual(sorted(p.name for p in out.glob("*.tsv")), ["2026-11-16.tsv", "2026-11-23.tsv"])


if __name__ == "__main__":
    unittest.main()
