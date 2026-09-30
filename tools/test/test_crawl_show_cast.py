"""crawl_show_cast.py のテスト (ページは文字列で渡し、一時 DB だけを使う)。

    python3 -m unittest discover -s tools/test -p 'test_*.py'
"""

import sqlite3
import tempfile
import unittest
from pathlib import Path

import support
import crawl_show_cast as csc

# 特設ページの書き方の揺れ: 見出し (DAY / 日付 / 昼夜)・全角半角の括弧・役の前の空白・
# 出演作品の「…」〇〇役・プロフィールの「5月2日生まれ」・更新日の行。
PAGE_DAYS = """
<h2>公演概要</h2><p>2027年3月13日(土)</p><p>2027年3月14日(日)</p>
<div class="day">DAY1 - 2027.</div><div>3.13. Sat.</div>
<p>2026.08.27 Update</p>
<li>仲村 宗悟（天道 輝 役）</li>
<li>藍原ことみ(一ノ瀬志希 役)</li>
<p>5月2日生まれ 青森県出身</p>
<p>「SHIROBAKO」宮森あおい役、</p>
<div>DAY2 - 2027.</div><div>3.14. Sun.</div>
<li>濱 健人（木村 龍役）</li>
"""

PAGE_MATINEE = """
<p>歌唱</p><p>昼公演</p><p>礒部 花凜（月岡 恋鐘役）</p>
<p>夜公演</p><p>関根 瞳（櫻木 真乃役）</p>
"""


def make_db(path):
    support.schema_only(path)
    conn = sqlite3.connect(str(path))
    conn.execute("INSERT INTO events (id, brand_id, name, event_type) VALUES ('ev_t', 'sidem', 'ライブ', 'live')")
    for i, (sid, date, name) in enumerate([("sh_1", "2027-03-13", "DAY1"), ("sh_2", "2027-03-14", "DAY2")]):
        conn.execute("INSERT INTO shows (id, event_id, name, date, sort_order) VALUES (?, 'ev_t', ?, ?, ?)",
                     (sid, name, date, i))
    for iid, brand, name, va in [
        ("sidem_天道輝", "sidem", "天道輝", "仲村宗悟"),
        ("sidem_木村龍", "sidem", "木村龍", "濱健人"),
        ("cg_一ノ瀬志希", "cg", "一ノ瀬志希", "藍原ことみ"),
    ]:
        conn.execute("INSERT INTO idols (id, brand_id, name, sort_order) VALUES (?, ?, ?, 0)", (iid, brand, name))
        conn.execute("INSERT INTO idol_voice_actors (id, idol_id, name) VALUES (?, ?, ?)", (iid + "_va", iid, va))
    conn.commit()
    return conn


class ParseTest(unittest.TestCase):
    def test_splits_by_day_and_skips_filmography(self):
        segs = csc.parse_cast(PAGE_DAYS)
        self.assertEqual([s.cast for s in segs], [
            [("仲村 宗悟", "天道 輝"), ("藍原ことみ", "一ノ瀬志希")],
            [("濱 健人", "木村 龍")],
        ])
        self.assertEqual(csc.header_hint(segs[0].headers, 2027)[:2], (1, csc.dt.date(2027, 3, 13)))

    def test_birthday_line_is_not_a_header(self):
        self.assertFalse(csc.is_header("5月2日生まれ 青森県出身 趣味は歌唱。"))
        self.assertTrue(csc.is_header("2.27 Sat"))
        self.assertTrue(csc.is_header("2027年2月27日(土)"))
        self.assertFalse(csc.is_header("2026.08.27 Update"))

    def test_matinee_and_evening_on_same_day(self):
        shows = [csc.Show("a", "昼公演", "2027-03-22", False), csc.Show("b", "夜公演", "2027-03-22", False)]
        mapping, why = csc.assign(csc.parse_cast(PAGE_MATINEE), shows)
        self.assertEqual(why, "")
        self.assertEqual(mapping["a"].cast, [("礒部 花凜", "月岡 恋鐘")])
        self.assertEqual(mapping["b"].cast, [("関根 瞳", "櫻木 真乃")])

    def test_one_list_for_two_shows_needs_judgment(self):
        shows = [csc.Show("a", "DAY1", "2027-03-13", False), csc.Show("b", "DAY2", "2027-03-14", False)]
        mapping, why = csc.assign(csc.parse_cast("<p>仲村 宗悟（天道 輝 役）</p>"), shows)
        self.assertEqual(mapping, {})
        self.assertIn("決められない", why)


class CrawlTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / "master.sqlite"
        self.conn = make_db(self.db)

    def tearDown(self):
        self.conn.close()
        self.tmp.cleanup()

    def crawl(self, page):
        return csc.crawl(self.conn, "2026-10-01", {"ev_t": "https://example.com/x"}, fetcher=lambda _: page)

    def test_out_of_brand_idol_is_a_warning(self):
        (result,) = self.crawl(PAGE_DAYS)
        day1, day2 = result.plans
        self.assertEqual(day1.idol_ids, ["sidem_天道輝", "cg_一ノ瀬志希"])
        self.assertEqual(day1.status, "warn")
        self.assertEqual((day2.idol_ids, day2.status), (["sidem_木村龍"], "ok"))

    def test_unknown_name_and_other_voice_actor(self):
        page = "<p>DAY1</p><p>別人（天道 輝 役）</p><p>誰か（いないひと 役）</p><p>DAY2</p><p>濱 健人（木村 龍 役）</p>"
        (result,) = self.crawl(page)
        self.assertEqual(result.plans[0].status, "unresolved")
        self.assertIn("声優", result.plans[0].warnings[0])

    def test_shows_with_cast_are_left_alone(self):
        self.conn.execute("INSERT INTO show_cast VALUES ('sh_1', 'sidem_天道輝', 'member')")
        self.conn.commit()
        (result,) = self.crawl(PAGE_DAYS)
        self.assertEqual([p.show.id for p in result.plans], ["sh_2"])

    def test_no_page_and_no_cast(self):
        self.assertEqual(csc.crawl(self.conn, "2026-10-01", {}, fetcher=lambda _: None)[0].note[:7], "特設ページ不明")
        self.assertEqual(self.crawl("<p>出演者は後日発表</p>")[0].note, "出演者の記載なし")


class MasterSqlTest(unittest.TestCase):
    def test_appends_after_show_cast_rows_and_skips_unknown_show(self):
        with tempfile.TemporaryDirectory() as tmp:
            sql = Path(tmp) / "master.sql"
            sql.write_text(
                'CREATE TABLE "show_cast" (x);\n'
                """INSERT INTO "shows" VALUES('sh_1','ev','DAY1');\n"""
                """INSERT INTO "idols" VALUES('i''1','sidem');\n"""
                """INSERT INTO "show_cast" VALUES('sh_0','i''1','member');\n"""
                "COMMIT;\n", encoding="utf-8")
            skipped = csc.append_master_sql(sql, [("sh_1", "i'1"), ("sh_9", "i'1")])
            self.assertEqual(skipped, ["sh_9 / i'1"])
            lines = sql.read_text(encoding="utf-8").splitlines()
            self.assertEqual(lines[4], """INSERT INTO "show_cast" VALUES('sh_1','i''1','member');""")
            self.assertEqual(csc.append_master_sql(sql, [("sh_1", "i'1")]), [])
            self.assertEqual(sql.read_text(encoding="utf-8").count("'sh_1','i''1'"), 1)


if __name__ == "__main__":
    unittest.main()
