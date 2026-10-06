"""live_setlist_watch の、ネットに出ない部分 (曲名の照合と下書きの形) のテスト。"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import live_setlist_watch as w  # noqa: E402


class NormTest(unittest.TestCase):
    def test_ignores_width_case_and_marks(self):
        self.assertEqual(w.norm("Ｇｏｉｎｇ my way!"), w.norm("going  my way"))
        self.assertEqual(w.norm("わたしの主人公はわたしだから！"), w.norm("わたしの主人公はわたしだから"))


class SetlistJsonTest(unittest.TestCase):
    def test_orders_by_position_and_keeps_unordered_apart(self):
        show = {"id": "sh_x_1"}
        result = {"songs": [
            {"position": 2, "title": "B", "song_id": "sc_b", "confidence": "high"},
            {"position": 1, "title": "新曲", "song_id": None, "confidence": "low"},
            {"position": None, "title": "C", "song_id": "sc_c", "confidence": "medium"},
        ]}
        out = w.to_setlist_json(show, result, "src")
        self.assertEqual(out["show_id"], "sh_x_1")
        self.assertEqual([s["position"] for s in out["songs"]], [1, 2])
        self.assertEqual(out["songs"][0]["title"], "新曲")  # 一覧に無い曲は title のまま
        self.assertNotIn("title", out["songs"][1])
        self.assertEqual(out["songs"][1]["song_id"], "sc_b")
        self.assertEqual(out["unordered_titles"], ["C"])


if __name__ == "__main__":
    unittest.main()
