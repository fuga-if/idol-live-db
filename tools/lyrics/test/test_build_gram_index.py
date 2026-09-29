#!/usr/bin/env python3
"""build_gram_index.py の --from-local (手元の JSON から索引を作る経路) のテスト。

    python3 -m unittest discover -s tools/lyrics/test -p 'test_*.py'

本文はダミーの仮名と記号だけ。歌詞は使わない。
"""

import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))
import build_gram_index as B  # noqa: E402

LINES = [
    {"kind": "marker", "text": "イントロ"},
    {"kind": "lyric", "text": "あいＡＢ"},
    {"text": "ゕゖ"},  # kind が無い行は歌詞 (push_lyrics と Worker の既定)
    {"kind": "blank", "text": ""},
    {"kind": "lyric", "text": "ｘ！"},
]


class ReadFromLocalTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(setattr, B, "LOCAL_DIR", B.LOCAL_DIR)
        B.LOCAL_DIR = self.tmp.name
        self.write("s1", LINES)
        self.write("s2", [{"kind": "marker", "text": "間奏"}])  # 歌詞行が無い

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, song_id, lines):
        with open(os.path.join(self.tmp.name, song_id + ".json"), "w", encoding="utf-8") as f:
            json.dump({"song_id": song_id, "lines": lines}, f, ensure_ascii=False)

    def test_the_body_is_normalized_like_body_norm(self):
        # Worker は歌詞行だけを改行でつなぎ (searchBody)、normalizeForSearch を通して
        # body_norm にする。D1 から作る全再構築はその body_norm を読むので、手元から
        # 作るときも同じ文字列にならないと、正規化した検索語の候補から漏れる。
        self.assertEqual(B.read_from_local(), [("s1", "アイab\nヵヶ\nx!")])

    def test_grams_are_normalized_and_do_not_cross_lines(self):
        index = B.build_index(B.read_from_local())
        for gram in ("ア", "アイ", "ab", "ヵヶ", "x!"):
            self.assertEqual(index.get(gram), ["s1"], gram)
        for gram in ("あ", "Ａ", "Ｂ", "bヵ", "イント"):
            self.assertNotIn(gram, index)


if __name__ == "__main__":
    unittest.main()
