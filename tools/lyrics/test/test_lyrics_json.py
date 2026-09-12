#!/usr/bin/env python3
"""lyrics_json.py の検証ロジックのユニットテスト。

    python3 -m unittest discover -s tools/lyrics/test -p 'test_*.py'
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import lyrics_json as L  # noqa: E402


def doc(texts):
    return {"song_id": "x", "source": "test",
            "lines": [{"kind": "lyric", "text": t} for t in texts]}


# 判定の下限 (MIN_DOUBLED_BODY_CHARS) を確実に超える長さの本文。
VERSE = ["高らかに空を飛んで　叡智の海渡って%d" % i for i in range(12)]


class DoubledBodyTest(unittest.TestCase):
    def test_same_body_twice_is_flagged(self):
        self.assertTrue(L.is_doubled_body(VERSE + VERSE))

    def test_second_copy_split_differently_is_flagged(self):
        # 2 回目が文節ごとに分割されていても本文は同じ
        split = [piece for t in VERSE for piece in t.split("　")]
        self.assertTrue(L.is_doubled_body(VERSE + split))

    def test_normal_body_is_not_flagged(self):
        self.assertFalse(L.is_doubled_body(VERSE))

    def test_short_body_is_ignored(self):
        self.assertFalse(L.is_doubled_body(["ラララ"] * 4))

    def test_validate_doc_warns(self):
        errors, warnings = L.validate_doc(doc(VERSE + VERSE), "x.json")
        self.assertEqual(errors, [])
        self.assertTrue(any("繰り返し" in w for w in warnings))

    def test_validate_doc_is_quiet_for_normal_body(self):
        errors, warnings = L.validate_doc(doc(VERSE), "x.json")
        self.assertEqual(errors, [])
        self.assertFalse(any("繰り返し" in w for w in warnings))


if __name__ == "__main__":
    unittest.main()
