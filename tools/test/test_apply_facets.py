"""apply_data.py の項目 (idol_facets) と髪型 (idol_hairstyles) の投入・検査のテスト。

    python3 -m unittest discover -s tools/test -p 'test_*.py'
"""

import contextlib
import io
import sqlite3
import tempfile
import unittest
from pathlib import Path

import support
import apply_data
from lib import masterdb


def fixture_db(path):
    support.schema_only(path)
    conn = sqlite3.connect(str(path))
    conn.executescript("""
        INSERT INTO brands (id, name, short_name, sort_order) VALUES ('765as', '765', '765', 1);
        INSERT INTO idols (id, brand_id, name, sort_order) VALUES ('765as_a', '765as', 'A', 1001);
        INSERT INTO idols (id, brand_id, name, sort_order) VALUES ('765as_b', '765as', 'B', 1002);
    """)
    masterdb.ensure_facet_tables(conn)
    conn.commit()
    conn.close()


class FacetsTestBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.db = root / "m.sqlite"
        fixture_db(self.db)
        self.data = root / "data"
        self._saved = (apply_data.DATA_DIR, apply_data.ONLY_FILE)
        apply_data.DATA_DIR, apply_data.ONLY_FILE = self.data, None

    def tearDown(self):
        apply_data.DATA_DIR, apply_data.ONLY_FILE = self._saved
        self.tmp.cleanup()

    def conn(self):
        c = sqlite3.connect(str(self.db))
        c.execute("PRAGMA foreign_keys = ON")
        return c

    def post(self, kind, obj):
        support.write_json(self.data / kind / "t.json", obj)

    def problems(self):
        return apply_data.validate(self.conn())

    def apply(self):
        conn = self.conn()
        with contextlib.redirect_stdout(io.StringIO()):
            affected = apply_data.apply_all(conn)
        conn.close()
        # 反映したファイルは data/_applied/ へ移す運用 (apply_data は "_" 始まりを読まない)。
        for f in list(self.data.glob("*/t.json")):
            f.rename(f.with_name(f"_applied_{f.parent.name}.json"))
        return affected


class FacetsTest(FacetsTestBase):
    def test_valid_facets_apply_with_stable_ids(self):
        self.post("idol_facets", {"source": "x", "idol_facets": [
            {"idol_id": "765as_a", "facet": "dialect", "value": "関西弁"},
            {"idol_id": "765as_a", "facet": "favorite_foods", "values": ["ケーキ", "お茶"]},
            {"idol_id": "765as_a", "facet": "glasses", "value": True},
            {"idol_id": "765as_a", "facet": "eye_color", "value": "青", "origin": "promoted", "source_note": "tag 12票"},
        ]})
        self.assertEqual(self.problems(), [])
        affected = self.apply()
        self.assertEqual(affected["idol_facets"], {"765as_a"})
        rows = self.conn().execute("SELECT facet, value, origin FROM idol_facets ORDER BY facet, sort_order").fetchall()
        self.assertEqual(rows, [("dialect", "関西弁", "official"), ("eye_color", "青", "promoted"),
                                ("favorite_foods", "ケーキ", "official"), ("favorite_foods", "お茶", "official"),
                                ("glasses", "true", "official")])
        # 同じ式の id (Rust の facet_row_key と同じ)。単一値は値を含まない。
        self.assertEqual(apply_data.facet_row_id("i", "dialect", "A", False), apply_data.facet_row_id("i", "dialect", "B", False))
        self.assertNotEqual(apply_data.facet_row_id("i", "favorite_foods", "A", True), apply_data.facet_row_id("i", "favorite_foods", "B", True))

    def test_bad_posts_are_reported(self):
        self.post("idol_facets", {"source": "x", "idol_facets": [
            {"idol_id": "765as_a", "facet": "eye_color", "value": "虹色"},          # 語彙外
            {"idol_id": "765as_a", "facet": "nope", "value": "x"},                 # 定義に無い
            {"idol_id": "765as_a", "facet": "age_band", "value": "10代"},          # 自動
            {"idol_id": "765as_a", "facet": "hair_color", "value": "金"},          # 髪は髪型の表
            {"idol_id": "765as_zzz", "facet": "dialect", "value": "x"},            # アイドル無し
            {"idol_id": "765as_a", "facet": "dialect", "value": "a"},
            {"idol_id": "765as_a", "facet": "dialect", "value": "b"},              # 単一値の重複
            {"idol_id": "765as_a", "facet": "dialect", "values": ["a", "b"]},      # 単一値に values
        ]})
        text = "\n".join(self.problems())
        for needle in ["語彙に無い", "定義に無い", "ここに書けない", "存在しない", "重複", "単一値"]:
            self.assertIn(needle, text)

    def test_existing_single_value_must_be_fixed_not_added(self):
        self.post("idol_facets", {"source": "x", "idol_facets": [{"idol_id": "765as_a", "facet": "dialect", "value": "a"}]})
        self.apply()
        self.post("idol_facets", {"source": "x", "idol_facets": [{"idol_id": "765as_a", "facet": "dialect", "value": "b"}]})
        self.assertTrue(any("既に存在" in p for p in self.problems()))

    def test_fix_changes_value_with_vocabulary_check(self):
        self.post("idol_facets", {"source": "x", "idol_facets": [{"idol_id": "765as_a", "facet": "eye_color", "value": "青"}]})
        self.apply()
        rid = apply_data.facet_row_id("765as_a", "eye_color", "青", False)
        support.write_json(self.data / "fixes" / "f.json", {"source": "x", "fixes": [
            {"table": "idol_facets", "id": rid, "fields": {"value": "虹色"}}]})
        self.assertTrue(any("value が不正" in p for p in self.problems()))
        support.write_json(self.data / "fixes" / "f.json", {"source": "x", "fixes": [
            {"table": "idol_facets", "id": rid, "fields": {"value": "緑"}}]})
        self.assertEqual(self.problems(), [])
        self.assertEqual(self.apply()["idol_facets"], {"765as_a"})
        self.assertEqual(self.conn().execute("SELECT value FROM idol_facets WHERE id = ?", (rid,)).fetchone()[0], "緑")


def hair(idol, label, main, **kw):
    return {"idol_id": idol, "label": label, "is_main": main, "hair_color": "金", "hair_length": "ロング", **kw}


class HairstylesTest(FacetsTestBase):
    def test_exactly_one_main_per_idol(self):
        self.post("idol_hairstyles", {"source": "x", "idol_hairstyles": [
            hair("765as_a", "基本", True, styles=["ウェーブ", "アホ毛"]),
            hair("765as_a", "覚醒後", False, hair_color="茶", hair_length="ショート"),
        ]})
        self.assertEqual(self.problems(), [])
        affected = self.apply()
        self.assertEqual(affected["idol_hairstyles"], {"765as_a"})
        rows = self.conn().execute("SELECT label, is_main, styles FROM idol_hairstyles ORDER BY label").fetchall()
        self.assertEqual(rows, [("基本", 1, "ウェーブ、アホ毛"), ("覚醒後", 0, None)])

    def test_main_count_label_vocab_and_empty_are_checked(self):
        self.post("idol_hairstyles", {"source": "x", "idol_hairstyles": [
            hair("765as_a", "基本", False),                                   # main なし
            hair("765as_b", "基本", True), hair("765as_b", "別", True),        # main 2 つ
            hair("765as_a", "基本", False),                                   # label 重複
            hair("765as_a", "x", False, hair_color="虹"),                      # 語彙外
            {"idol_id": "765as_a", "label": "空", "is_main": False},           # 中身なし
        ]})
        text = "\n".join(self.problems())
        self.assertIn("765as_a の is_main が 0 個", text)
        self.assertIn("765as_b の is_main が 2 個", text)
        self.assertIn("語彙に無い", text)
        self.assertIn("どれも無い", text)

    def test_database_refuses_a_second_main(self):
        self.post("idol_hairstyles", {"source": "x", "idol_hairstyles": [hair("765as_a", "基本", True)]})
        self.apply()
        with self.assertRaises(sqlite3.IntegrityError):
            self.conn().execute(
                "INSERT INTO idol_hairstyles (id, idol_id, label, is_main) VALUES ('x', '765as_a', '別', 1)")

    def test_set_main_switches_atomically_and_second_post_cannot_add_main(self):
        self.post("idol_hairstyles", {"source": "x", "idol_hairstyles": [
            hair("765as_a", "基本", True), hair("765as_a", "セカンドヘア", False, styles=["ポニーテール"])]})
        self.apply()
        self.post("idol_hairstyles", {"source": "x", "idol_hairstyles": [hair("765as_a", "別", True)]})
        self.assertTrue(any("is_main が 2 個" in p for p in self.problems()))
        self.post("idol_hairstyles", {"source": "x", "set_main": [{"idol_id": "765as_a", "label": "セカンドヘア"}]})
        self.assertEqual(self.problems(), [])
        self.apply()
        rows = dict(self.conn().execute("SELECT label, is_main FROM idol_hairstyles").fetchall())
        self.assertEqual(rows, {"基本": 0, "セカンドヘア": 1})

    def test_fix_edits_a_hairstyle_but_not_main(self):
        self.post("idol_hairstyles", {"source": "x", "idol_hairstyles": [hair("765as_a", "基本", True)]})
        self.apply()
        rid = apply_data.hairstyle_row_id("765as_a", "基本")
        support.write_json(self.data / "fixes" / "f.json", {"source": "x", "fixes": [
            {"table": "idol_hairstyles", "id": rid, "fields": {"hair_color": "茶", "styles": ["ツインテール"]}}]})
        self.assertEqual(self.problems(), [])
        self.apply()
        self.assertEqual(self.conn().execute("SELECT hair_color, styles FROM idol_hairstyles").fetchone(), ("茶", "ツインテール"))
        support.write_json(self.data / "fixes" / "f.json", {"source": "x", "fixes": [
            {"table": "idol_hairstyles", "id": rid, "fields": {"is_main": 0}}]})
        self.assertTrue(any("is_main" in p for p in self.problems()))


class FacetTablesTest(unittest.TestCase):
    def test_ensure_is_idempotent_and_matches_rust_ids(self):
        conn = sqlite3.connect(":memory:")
        self.assertTrue(masterdb.ensure_facet_tables(conn))
        self.assertFalse(masterdb.ensure_facet_tables(conn))
        # 他の人が確かめた式 (Rust の facet_row_key と同じ文字列) の固定。
        import hashlib
        self.assertEqual(apply_data.facet_row_id("a", "f", "v", True),
                         "if_" + hashlib.sha1("a|f|v".encode()).hexdigest()[:20])
        self.assertEqual(apply_data.hairstyle_row_id("a", "基本"),
                         "ih_" + hashlib.sha1("a|基本".encode()).hexdigest()[:20])


if __name__ == "__main__":
    unittest.main()
