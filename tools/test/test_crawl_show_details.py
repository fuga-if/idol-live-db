"""crawl_show_details.py のテスト (ページは行の並びで渡し、一時 DB だけを使う)。

    python3 -m unittest discover -s tools/test -p 'test_*.py'
"""

import sqlite3
import tempfile
import unittest
from pathlib import Path

import support
import crawl_show_details as csd


class ParseTest(unittest.TestCase):
    def test_start_times_in_several_layouts(self):
        lines = ["開催日時", "2027年2月13日(土)", "開場18:00 / 開演19:00",
                 "2027.3.14 Sun", "15:30開場/16:30開演(予定)",
                 "2027年3月22日(月・祝)", "昼公演 12:00開場／13:00開演", "夜公演 17:00開場／18:00開演",
                 "※公演時間等は予告なく変更", "グッズ販売 10:00開演"]
        self.assertEqual(csd.parse_start_times(lines), [
            ("2027-02-13", "19:00"), ("2027-03-14", "16:30"), ("2027-03-22", "13:00"), ("2027-03-22", "18:00")])

    def test_door_open_time_is_not_start_time(self):
        self.assertEqual(csd.parse_start_times(["2027年3月13日(土) 開場16:00 開演17:00"]), [("2027-03-13", "17:00")])
        self.assertEqual(csd.parse_start_times(["2027年3月13日(土) 開場 16:00　開演 17:00"]), [("2027-03-13", "17:00")])
        self.assertEqual(csd.parse_start_times(["2027年3月14日(日)", "15:30開場/16:30開演", "※ライブビューイング 開演17:30"]),
                         [("2027-03-14", "16:30")])

    def test_venue_heading_only(self):
        lines = ["開催場所", "山形県 やまぎん県民ホール", "会場内では会話をお控えください。", "会場",
                 "パシフィコ横浜 国立大ホール MAP", "★会場：幕張イベントホール"]
        self.assertEqual(csd.parse_venues(lines), ["やまぎん県民ホール", "パシフィコ横浜 国立大ホール", "幕張イベントホール"])

    def test_prices(self):
        lines = ["価格", "3,300円(税込)", "チケット概要", "アリーナ前方席", "30,000円(税込)", "一般指定席 15,000円（税込）",
                 "グッズ販売", "価格", "11,000円(税込)"]
        self.assertEqual(csd.parse_prices(lines), [("アリーナ前方席", 30000), ("一般指定席", 15000)])


class ArchivePeriodTest(unittest.TestCase):
    def test_same_line_and_next_line(self):
        self.assertEqual(csd.parse_archive_periods(
            ["アーカイブ視聴期間：2026年9月28日(月)18:00～10月5日(月)23:59（予定）"]),
            [("2026-09-28 18:00", "2026-10-05 23:59", None)])
        self.assertEqual(csd.parse_archive_periods(
            ["✦ アーカイブ視聴期間", "2026年9月28日(月)18:00～10月5日(月)23:59（予定）"]),
            [("2026-09-28 18:00", "2026-10-05 23:59", None)])

    def test_other_headings_and_year_rollover(self):
        self.assertEqual(csd.parse_archive_periods(["見逃し配信期間 2026年12月26日 ～ 1月5日"]),
                         [("2026-12-26", "2027-01-05", None)])
        self.assertEqual(csd.parse_archive_periods(["アーカイブ配信期間 2026年10月1日 12:00 ～ 2026年10月8日 23:59"]),
                         [("2026-10-01 12:00", "2026-10-08 23:59", None)])

    def test_unreadable_periods_are_skipped(self):
        # 終わりしか無い / 始まりに年が無い / 逆順 / 実在しない日付
        for line in ("アーカイブ視聴期間 10月5日(月)23:59まで", "アーカイブ視聴期間 9月28日18:00～10月5日23:59",
                     "アーカイブ視聴期間 2026年10月5日～2026年9月28日", "アーカイブ視聴期間 2026年2月30日～3月5日",
                     "視聴期間 2026年9月28日～10月5日"):
            self.assertEqual(csd.parse_archive_periods([line]), [], line)

    def test_day_label_and_duplicates(self):
        lines = ["✦ DAY1", "アーカイブ視聴期間", "2026年9月28日～10月5日", "✦ DAY2", "アーカイブ視聴期間：2026年9月29日～10月6日",
                 "※視聴コメント付きアーカイブ映像視聴期間：2026年9月29日～10月6日"]
        self.assertEqual(csd.parse_archive_periods(lines),
                         [("2026-09-28", "2026-10-05", "1"), ("2026-09-29", "2026-10-06", "2")])


class ArchiveReviewTest(unittest.TestCase):
    def test_h1_every_range_under_one_heading_is_read_with_labels(self):
        lines = ["アーカイブ視聴期間", "DAY1：2026年9月28日～10月5日", "DAY2：2026年9月29日～10月6日"]
        self.assertEqual(csd.parse_archive_periods(lines),
                         [("2026-09-28", "2026-10-05", "1"), ("2026-09-29", "2026-10-06", "2")])

    def test_h1_labelled_periods_never_use_the_same_for_all_branch(self):
        page = ["アーカイブ視聴期間", "DAY1：2026年9月28日～10月5日", "DAY2：2026年9月29日～10月6日"]
        shows = [csd.Show("a", "D1", "2026-09-26", "", "", "", True, [("t1", "", "")]),
                 csd.Show("b", "D2", "2026-09-27", "", "", "", True, [("t2", "", "")])]
        plan = csd.EventPlan("ev", "e", "u")
        csd.plan_archive(plan, shows, {"u": page})
        self.assertEqual([(f["id"], f["fields"]["archive_ends_at"]) for f in plan.fixes],
                         [("t1", "2026-10-05"), ("t2", "2026-10-06")])
        # DAY ラベルが 1 つしかなく公演日が 2 つ: 全公演に入れず注記
        plan = csd.EventPlan("ev", "e", "u")
        csd.plan_archive(plan, shows, {"u": ["アーカイブ視聴期間", "DAY1：2026年9月28日～10月5日"]})
        self.assertEqual(plan.fixes, [])
        self.assertIn("割り当てられない", plan.notes[0])
        # 見出しの下に範囲が 2 つ (ラベル無し)
        plan = csd.EventPlan("ev", "e", "u")
        csd.plan_archive(plan, shows, {"u": ["アーカイブ視聴期間", "2026年9月28日～10月5日", "2026年9月29日～10月6日"]})
        self.assertEqual(plan.fixes, [])

    def test_h2_finished_days_still_count_for_day_numbers(self):
        # 3 日公演で DAY1 (9/26) は終わっている。DAY2 の期間は 9/27 の公演に入る (DAY3 に入れない)。
        page = ["アーカイブ視聴期間", "DAY1：2026年9月28日～10月5日", "DAY2：2026年9月29日～10月6日",
                "DAY3：2026年9月30日～10月7日"]
        shows = [csd.Show("b", "D2", "2026-09-27", "", "", "", True, [("t2", "", "")]),
                 csd.Show("c", "D3", "2026-09-28", "", "", "", True, [("t3", "", "")])]
        plan = csd.EventPlan("ev", "e", "u")
        csd.plan_archive(plan, shows, {"u": page}, ["2026-09-26", "2026-09-27", "2026-09-28"])
        self.assertEqual([(f["id"], f["fields"]["archive_ends_at"]) for f in plan.fixes],
                         [("t2", "2026-10-06"), ("t3", "2026-10-07")])
        # ラベルの集合が {1..n} と合わない (DAY1・DAY2 だけで 3 日) なら注記
        plan = csd.EventPlan("ev", "e", "u")
        csd.plan_archive(plan, shows, {"u": page[:3]}, ["2026-09-26", "2026-09-27", "2026-09-28"])
        self.assertEqual(plan.fixes, [])
        self.assertIn("割り当てられない", plan.notes[0])

    def test_m2_bare_missed_stream_heading_and_sales_lines_are_not_read(self):
        self.assertEqual(csd.parse_archive_periods(["見逃し配信", "受付期間 2026年9月1日～9月20日"]), [])
        self.assertEqual(csd.parse_archive_periods(["アーカイブ視聴期間", "販売期間", "2026年9月1日～9月20日"]), [])
        self.assertEqual(csd.parse_archive_periods(["アーカイブ視聴期間 抽選受付 2026年9月1日～9月20日"]), [])

    def test_m2_period_ending_before_the_show_is_dropped(self):
        shows = [csd.Show("a", "D1", "2026-09-26", "", "", "", True, [("t1", "", "")])]
        plan = csd.EventPlan("ev", "e", "u")
        csd.plan_archive(plan, shows, {"u": ["アーカイブ視聴期間：2026年3月1日～3月8日"]})
        self.assertEqual((plan.fixes, plan.notes), ([], []))

    def test_l1_date_only_start_with_timed_end_on_same_day(self):
        self.assertEqual(csd.parse_archive_periods(["アーカイブ視聴期間 2026年9月28日～9月28日 12:00"]),
                         [("2026-09-28", "2026-09-28 12:00", None)])


class ArchivePlanTest(unittest.TestCase):
    PAGE = ["配信チケット", "アーカイブ視聴期間", "2026年9月28日(月)18:00～10月5日(月)23:59（予定）"]

    def plan(self, shows, pages=None):
        plan = csd.EventPlan("ev", "イベント", "u")
        csd.plan_archive(plan, shows, pages or {"u": self.PAGE})
        return plan

    def test_one_period_fills_empty_stream_rows_only(self):
        shows = [csd.Show("a", "DAY1", "2026-09-26", "", "", "", True, [("t1", "", "")]),
                 csd.Show("b", "DAY2", "2026-09-27", "", "", "", True,
                          [("t2", "2026-09-28 18:00", "2026-10-05 23:59")])]
        plan = self.plan(shows)
        self.assertEqual(plan.fixes, [{
            "table": "show_tickets", "id": "t1",
            "fields": {"archive_starts_at": "2026-09-28 18:00", "archive_ends_at": "2026-10-05 23:59"},
            "source": "u", "note": "公式ページのアーカイブ視聴期間"}])
        self.assertEqual(plan.notes, [])

    def test_differing_db_value_is_noted_not_overwritten(self):
        shows = [csd.Show("a", "DAY1", "2026-09-26", "", "", "", True, [("t1", "2026-09-28 18:00", "2026-10-06")])]
        plan = self.plan(shows)
        self.assertEqual(plan.fixes, [])
        self.assertIn("DB は 2026-09-28 18:00～2026-10-06", plan.notes[0])

    def test_no_stream_row_is_noted(self):
        shows = [csd.Show("a", "DAY1", "2026-09-26", "", "", "", True, [])]
        plan = self.plan(shows)
        self.assertEqual(plan.fixes, [])
        self.assertIn("配信の券種が無い", plan.notes[0])

    def test_period_per_day_maps_by_label(self):
        page = ["DAY1", "アーカイブ視聴期間：2026年9月28日～10月5日", "DAY2", "アーカイブ視聴期間：2026年9月29日～10月6日"]
        shows = [csd.Show("a", "DAY1", "2026-09-26", "", "", "", True, [("t1", "", "")]),
                 csd.Show("b", "DAY2", "2026-09-27", "", "", "", True, [("t2", "", "")])]
        plan = self.plan(shows, {"u": page})
        self.assertEqual([(f["id"], f["fields"]["archive_ends_at"]) for f in plan.fixes],
                         [("t1", "2026-10-05"), ("t2", "2026-10-06")])

    def test_ambiguous_periods_are_only_noted(self):
        page = ["アーカイブ視聴期間：2026年9月28日～10月5日", "アーカイブ視聴期間：2026年9月29日～10月6日"]
        shows = [csd.Show("a", "DAY1", "2026-09-26", "", "", "", True, [("t1", "", "")])]
        plan = self.plan(shows, {"u": page})
        self.assertEqual(plan.fixes, [])
        self.assertIn("割り当てられない", plan.notes[0])


class PlanTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        path = Path(self.tmp.name) / "master.sqlite"
        support.schema_only(path)
        self.conn = sqlite3.connect(str(path))
        self.conn.execute("INSERT INTO venues (id, name) VALUES ('venue_p', 'パシフィコ横浜')")
        self.conn.execute("INSERT INTO venue_halls (id, venue_id, name) VALUES ('h', 'venue_p', '国立大ホール')")
        self.conn.execute("INSERT INTO venues (id, name, aliases) VALUES ('venue_k', '京王アリーナTOKYO', '武蔵野の森総合スポーツプラザ')")
        self.index = csd.venue_index(self.conn)

    def tearDown(self):
        self.conn.close()
        self.tmp.cleanup()

    def test_match_venue(self):
        self.assertEqual(csd.match_venue(self.conn, self.index, "パシフィコ横浜 国立大ホール"), ("venue_p", "国立大ホール"))
        self.assertEqual(csd.match_venue(self.conn, self.index, "京王アリーナ TOKYO"), ("venue_k", ""))
        self.assertIsNone(csd.match_venue(self.conn, self.index, "パシフィコ横浜 展示ホール"))
        self.assertIsNone(csd.match_venue(self.conn, self.index, "IGアリーナ"))

    def test_plan_fills_only_empty_columns(self):
        shows = [csd.Show("a", "DAY1", "2027-03-13", "", "", "", False),
                 csd.Show("b", "DAY2", "2027-03-14", "16:00", "", "", True)]
        site = "https://idolmaster-official.jp/live_event/x/"
        pages = {site: ["2027年3月13日(土)", "開演17:00", "2027年3月14日(日)", "開演16:30", "開催場所", "京王アリーナ TOKYO"],
                 site + "ticket/": ["TICKET", "一般指定席 9,900円(税込)"]}
        plan = csd.plan_event(self.conn, "ev", "イベント", "", shows, list(pages), pages, self.index)
        self.assertEqual(plan.fixes, [
            {"table": "events", "id": "ev", "fields": {"ticket_url": site + "ticket/"}},
            {"table": "shows", "id": "a", "fields": {"start_time": "17:00"}},
            {"table": "shows", "id": "a", "fields": {"venue_id": "venue_k", "venue": "京王アリーナ TOKYO"}},
            {"table": "shows", "id": "b", "fields": {"venue_id": "venue_k", "venue": "京王アリーナ TOKYO"}},
        ])
        self.assertIn("DB は 16:00・ページは 16:30", plan.notes[0])
        self.assertEqual(plan.prices, ["a\tlive\t一般指定席\t9900\t0\t\t" + site + "ticket/"])

    def test_filled_time_disagreeing_blocks_the_day(self):
        shows = [csd.Show("a", "昼", "2027-03-22", "13:00", "", "v", True), csd.Show("b", "夜", "2027-03-22", "", "", "v", True)]
        pages = {"u": ["2027年3月22日", "昼 開演12:00", "夜 開演18:00"]}
        plan = csd.plan_event(self.conn, "ev", "イベント", "x", shows, ["u"], pages, self.index)
        self.assertEqual(plan.fixes, [])

    def test_unknown_place_and_tour_are_not_filled(self):
        shows = [csd.Show("a", "D1", "2027-03-13", "", "都内某所", "", True)]
        plan = csd.plan_event(self.conn, "ev", "イベント", "x", shows, ["u"], {"u": ["会場", "都内某所"]}, self.index)
        self.assertEqual(plan.fixes, [])
        shows = [csd.Show("a", "長野", "2027-03-13", "", "ホクト文化ホール", "", True),
                 csd.Show("b", "幕張", "2027-03-20", "", "幕張イベントホール", "", True)]
        plan = csd.plan_event(self.conn, "ev", "イベント", "x", shows, ["u"], {"u": ["会場", "京王アリーナ TOKYO"]}, self.index)
        self.assertEqual(plan.fixes, [])

    def test_time_count_mismatch_is_left_alone(self):
        shows = [csd.Show("a", "昼", "2027-03-22", "", "", "", True), csd.Show("b", "夜", "2027-03-22", "", "", "", True)]
        pages = {"u": ["2027年3月22日", "開演13:00"]}
        plan = csd.plan_event(self.conn, "ev", "イベント", "x", shows, ["u"], pages, self.index)
        self.assertEqual(plan.fixes, [])
        self.assertIn("開演がページに 1 つ・公演は 2 つ", plan.notes[0])


if __name__ == "__main__":
    unittest.main()
