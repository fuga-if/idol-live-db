"""lib/live_pages.py のテスト (CMS API は偽物を渡す)。

    python3 -m unittest discover -s tools/test -p 'test_*.py'
"""

import unittest

import support  # noqa: F401
from lib import live_pages as lp


class FakeCms(lp.Cms):
    def __init__(self, schedule=(), news=()):
        super().__init__(opener=lambda url: None)
        self._schedule, self._news_rows = list(schedule), list(news)

    def schedule(self, dates):
        return self._schedule

    def news(self, brand_code):
        return self._news_rows


class TitleTest(unittest.TestCase):
    def test_matches_news_title_with_brackets(self):
        name = "THE IDOLM@STER SHINY COLORS Song for Prism 散花-sanka- / 紅花-benibana- 発売記念イベント"
        self.assertTrue(lp.title_matches(name, "【シャニマス】「THE IDOLM@STER SHINY COLORS Song for Prism 散花-sanka- / 紅花-benibana-」発売記念イベント開催決定！"))
        self.assertFalse(lp.title_matches(name, "【シャニマス】「THE IDOLM@STER SHINY COLORS Song for Prism Karma / Naraku」発売記念イベント"))
        self.assertFalse(lp.title_matches("KIMCHIKURA Fes '26", "KIMCHIKURA Fes '25 出演決定"))
        self.assertFalse(lp.title_matches("315 Production presents F＠NTASTIC BATTLE FES ～Wanna step in～",
                                          "315 Production presents F＠NTASTIC BATTLE FES ～Who goes first～ 開催決定"))


class EventPagesTest(unittest.TestCase):
    def test_special_site_expands_and_skips_cms(self):
        urls = lp.event_pages("x", ["sc"], ["2027-01-01"], "https://idolmaster-official.jp/live_event/abc/ticket/", None)
        self.assertEqual(urls[:2], ["https://idolmaster-official.jp/live_event/abc/",
                                    "https://idolmaster-official.jp/live_event/abc/information/"])

    def test_schedule_then_news(self):
        cms = FakeCms(
            schedule=[{"event_startdate": 1798729200, "title": "315 Production presents F＠NTASTIC BATTLE FES ～Wanna step in～",  # 2027-01-01 JST
                       "event_url": "https://idolmaster-official.jp/news/01_1", "url": "https://idolmaster-official.jp/schedule/01_2.html"},
                      {"event_startdate": 1798729200, "title": "別のイベント", "event_url": "https://example.com/"}],
            news=[{"title": "【SideM】315 Production presents F@NTASTIC BATTLE FES ～Wanna step in～ チケット情報", "path": "01_3"}],
        )
        urls = lp.event_pages("315 Production presents F＠NTASTIC BATTLE FES ～Wanna step in～", ["sidem"],
                              ["2027-01-01"], None, cms)
        self.assertEqual(urls, ["https://idolmaster-official.jp/news/01_1", "https://idolmaster-official.jp/schedule/01_2.html",
                                "https://idolmaster-official.jp/news/01_3.html"])
        self.assertIsNone(lp.special_site(urls))


class HeaderTest(unittest.TestCase):
    def test_show_numbers(self):
        self.assertEqual(lp.header_hint(["第三公演「きっと忘れない」"], 2027)[3], 3)
        self.assertEqual(lp.header_hint(["第12回"], 2027)[3], 12)
        self.assertTrue(lp.is_header("第一公演 TO:STARLIT OF PROMISE"))


if __name__ == "__main__":
    unittest.main()
