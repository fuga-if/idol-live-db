"""check_ckdb_schema.py のテスト (git も CloudKit も触らない)。

    python3 -m unittest discover -s tools/test -p 'test_*.py'
"""

import unittest

import support  # noqa: F401  (tools/ を import パスに入れる)
import check_ckdb_schema as ccs

HEAD = "DEFINE SCHEMA\n\n"
BRAND = """
    RECORD TYPE Brand (
        "___createTime" TIMESTAMP,
        deletedAt       TIMESTAMP QUERYABLE SORTABLE,
        ids             LIST<INT64>,
        modifiedAt      TIMESTAMP QUERYABLE SORTABLE,
        name            STRING QUERYABLE SEARCHABLE SORTABLE,
        GRANT READ TO "_world"
    );
"""


def run(new_text, base_text=None):
    """check の結果を (エラー文の並び, 追加項目) で返す。"""
    new, dups = ccs.parse(new_text)
    base = ccs.parse(base_text)[0] if base_text is not None else None
    errors, added = ccs.check(new, dups, base)
    return [e.message for e in errors], added


class ParseTest(unittest.TestCase):
    def test_real_schema_is_clean(self):
        text = (support.REPO / ccs.CKDB_REL).read_text(encoding="utf-8")
        self.assertEqual(run(text), ([], []))
        self.assertEqual(ccs.order_warnings(ccs.parse(text)[0]), [])


class CheckTest(unittest.TestCase):
    def test_duplicate_type_is_an_error(self):
        errors, _ = run(HEAD + BRAND + BRAND)
        self.assertTrue(any("2 回定義" in e for e in errors), errors)

    def test_adding_a_column_is_fine_and_reported(self):
        new = BRAND.replace("        GRANT", "        nameKo          STRING QUERYABLE SEARCHABLE SORTABLE,\n        GRANT")
        errors, added = run(HEAD + new, HEAD + BRAND)
        self.assertEqual(errors, [])
        self.assertEqual(added, ["`Brand.nameKo` STRING QUERYABLE SEARCHABLE SORTABLE"])

    def test_removing_a_column_is_an_error(self):
        new = BRAND.replace("        name            STRING QUERYABLE SEARCHABLE SORTABLE,\n", "")
        errors, _ = run(HEAD + new, HEAD + BRAND)
        self.assertEqual(len(errors), 1)
        self.assertTrue(errors[0].startswith("Brand.name が消えている"), errors)

    def test_changing_a_type_is_an_error(self):
        new = BRAND.replace("name            STRING", "name            INT64")
        new_schema, _ = ccs.parse(HEAD + new)
        problems, _ = ccs.check(new_schema, [], ccs.parse(HEAD + BRAND)[0])
        self.assertIn("型が STRING → INT64", problems[0].message)
        # 注釈が型を変えた行を指す
        self.assertIn("INT64", (HEAD + new).splitlines()[problems[0].line - 1])

    def test_dropping_an_index_is_an_error(self):
        new = BRAND.replace("modifiedAt      TIMESTAMP QUERYABLE SORTABLE", "modifiedAt      TIMESTAMP SORTABLE")
        errors, _ = run(HEAD + new, HEAD + BRAND)
        self.assertTrue(any("QUERYABLE が外れている" in e for e in errors), errors)

    def test_removing_a_type_is_an_error(self):
        errors, _ = run(HEAD, HEAD + BRAND)
        self.assertEqual(len(errors), 1)
        self.assertTrue(errors[0].startswith("RECORD TYPE Brand が消えている"), errors)

    def test_new_type_needs_sync_columns(self):
        new = BRAND.replace("Brand", "Tag").replace(
            "        modifiedAt      TIMESTAMP QUERYABLE SORTABLE,\n", ""
        )
        errors, added = run(HEAD + BRAND + new, HEAD + BRAND)
        self.assertEqual(added, ["RECORD TYPE `Tag` (新規)"])
        self.assertTrue(any("Tag" in e and "modifiedAt" in e for e in errors), errors)

    def test_out_of_order_column_is_only_a_warning(self):
        new = BRAND.replace("        deletedAt", "        zzz             STRING,\n        deletedAt")
        errors, _ = run(HEAD + new, HEAD + BRAND)
        self.assertEqual(errors, [])
        warnings = ccs.order_warnings(ccs.parse(HEAD + new)[0])
        self.assertEqual([w.message for w in warnings], ["Brand.deletedAt は zzz より前 (ASCII 順の位置) に置く"])

    def test_summary_lists_owner_steps_only_when_safely_added(self):
        self.assertIn("やることはありません", ccs.summary_markdown([], []))
        md = ccs.summary_markdown([], ["`Brand.nameKo` STRING"])
        self.assertIn("Deploy Schema Changes", md)
        self.assertIn("作業はここまでで完了", md)
        # エラーがあるうちは「オーナーの手順」を出さない (マージ後の Issue 起票もこれで止まる)
        bad = ccs.summary_markdown([ccs.Problem("x")], ["`Brand.nameKo` STRING"])
        self.assertNotIn("マージ後にオーナーがやること", bad)

    def test_annotation_points_at_the_line(self):
        self.assertEqual(
            ccs.annotate("error", "tools/cloudkit_schema.ckdb", ccs.Problem("a\nb", 12)),
            "::error file=tools/cloudkit_schema.ckdb,line=12,title=cloudkit_schema.ckdb::a%0Ab",
        )


if __name__ == "__main__":
    unittest.main()
