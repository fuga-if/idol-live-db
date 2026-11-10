#!/usr/bin/env python3
"""find_unregistered_releases.py の曲名の比べ方と曲一覧の読み方のテスト。

    python3 -m unittest discover -s tools/test -p 'test_*.py'
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import find_unregistered_releases as F  # noqa: E402

PAGE = """
<tr class="filter-row MIL">
<td><span class="iconMIL">[MIL]</span></td>
<td><a href="/x" title="ハピピス♡">ハピピス♡</a></td>
<td>(XST)美奈子,エレナ,可憐,瑞希</td>
<td>2026/10/18</td>
<td>ミリシタイベント
</td></tr>
<tr class="filter-row MIL &#95;765AS">
<td><span>[MIL]</span></td><td>BLACK LIPS</td><td>(BOT)朋花</td><td>2026/07/19</td><td>ミリシタイベント</td></tr>
<tr class="filter-row XENO"><td>x</td><td>Searching</td><td>Snow*</td><td>2007/05/16</td><td>(CD発売日)</td></tr>
<tr class="filter-row SYC"><td>x</td><td>あこがれフリルドレスで</td><td>-</td><td>2026/08/18</td><td>OST</td></tr>
<tr class="filter-row _765AS"><td>x</td><td>Kosmos, Cosmos〈MA09 Ver.〉</td><td>萩原雪歩</td><td>2007/10/03</td><td>MA09</td></tr>
<tr class="filter-row GKM"><td>x</td><td>修楽旅行</td><td>初星学園</td><td>2026/08/20</td><td>配信</td></tr>
<tr class="filter-row SDM"><td>x</td><td>True End’s Tapestry</td><td>(T@LES)</td><td>2026/09/02</td><td>T@LES12</td></tr>
"""


class NormTest(unittest.TestCase):
    def test_ignores_width_case_and_symbols(self):
        self.assertEqual(F.norm("ハピピス♡"), F.norm("ハピピス"))
        self.assertEqual(F.norm("True End’s Tapestry"), F.norm("True End's Tapestry"))
        self.assertEqual(F.norm("「ねえ、言っちゃうよ。」"), F.norm("ねえ、言っちゃうよ。"))
        self.assertEqual(F.norm("ＢＬＡＣＫ　LIPS"), F.norm("black lips"))


class SongListTest(unittest.TestCase):
    def test_parse_and_filter(self):
        rows = F.parse_song_list(PAGE)
        self.assertEqual(len(rows), 7)
        self.assertEqual(rows[0]["date"], "2026-10-18")
        self.assertIn("765AS", rows[1]["classes"])
        known = {F.norm("修楽旅行 (花海咲季 ver.)"), F.norm("True End's Tapestry")}
        got = [r["title"] for r in F.list_candidates(rows, known)]
        # ゼノグラシア・歌唱者なし・〈Ver.〉・版ごとに登録済み・記号違いは出さない
        self.assertEqual(got, ["ハピピス♡", "BLACK LIPS"])


class ExcludeTest(unittest.TestCase):
    def test_variants_are_excluded(self):
        for name in ["Stick to my weapon (Off Vocal)", "クローバー (Game Size)",
                     "EVERAFTER (M@STER VERSION)", "Remain Viable (北村想楽 ソロVer.)",
                     "アニマ・フォルトゥナ (テセウスの少年 Ver.)", "nazonazo [Instrumental]"]:
            self.assertTrue(F.EXCLUDE.search(name), name)
        self.assertFalse(F.EXCLUDE.search("ハピピス♡"))


if __name__ == "__main__":
    unittest.main()
