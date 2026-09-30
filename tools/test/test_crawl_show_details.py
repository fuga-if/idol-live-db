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
