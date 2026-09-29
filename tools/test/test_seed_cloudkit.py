"""seed_cloudkit.py のテスト (互換の名前・レコードの組み立て・終了コード)。通信は偽物。

    python3 -m unittest discover -s tools/test -p 'test_*.py'
"""

import contextlib
import io
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

import support
import seed_cloudkit as sk

# 手元のスクリプトが seed_cloudkit から import している名前。消したり変えたりしない。
COMPAT_NAMES = [
    "BASE_URL", "CONTAINER", "DB_PATH", "DEFAULT_KEY_FILE", "ENVIRONMENT", "MODIFY_PATH",
    "QUERY_PATH", "RECORD_TYPE_MAP", "TABLE_ORDER", "ID_FILTER_COLUMN", "SCOPED_ID_SPACE",
    "_build_paths", "init_session", "post_json", "get_json", "upload_operations",
    "get_column_info", "get_primary_keys", "make_record_name", "next_modified_ms",
    "rows_to_operations", "build_fields", "snake_to_camel", "scope_id", "push_columns",
    "seed_table", "delete_records", "parse_delete_file", "verify", "cloudkit_count",
]


def fixture_db(path):
    support.schema_only(path)
    conn = sqlite3.connect(str(path))
    conn.executescript("""
        INSERT INTO brands (id, name, short_name, color, sort_order) VALUES ('ml', 'ML', 'ML', NULL, 3);
        INSERT INTO song_artists (song_id, idol_id, role) VALUES ('song_t', 'ml_t', 'original');
        INSERT INTO idols (id, brand_id, name, sort_order, height) VALUES ('ml_t', 'ml', 'テスト', 3001, 158.5);
        INSERT INTO idol_voice_actors (id, idol_id, name, valid_to) VALUES ('va1', 'ml_t', '今の声', NULL);
        INSERT INTO idol_voice_actors (id, idol_id, name, valid_to) VALUES ('va0', 'ml_t', '前の声', '2020-01-01');
    """)
    conn.commit()
    conn.close()


def operations(conn, table, **kwargs):
    """seed_table と同じ経路で組み、modifiedAt を除いて返す。"""
    col_info, select = sk.push_columns(conn, table)
    cur = conn.execute(f"SELECT {select} FROM {table}")
    cols = [d[0] for d in cur.description]
    rows = [dict(zip(cols, r)) for r in cur.fetchall()]
    ops = sk.rows_to_operations(table, rows, col_info, sk.get_primary_keys(conn, table), **kwargs)
    for op in ops:
        assert op["record"]["fields"].pop("modifiedAt")["type"] == "TIMESTAMP"
    return ops


class CompatNamesTest(unittest.TestCase):
    def test_names_used_by_local_scripts_are_still_there(self):
        missing = [name for name in COMPAT_NAMES if not hasattr(sk, name)]
        self.assertEqual(missing, [])


class RowsToOperationsTest(unittest.TestCase):
    """行 → レコードの規則 (recordName・NULL を送らない・型・派生列) を固定する。"""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        path = Path(self.tmp.name) / "m.sqlite"
        fixture_db(path)
        self.conn = sqlite3.connect(str(path))
        self.conn.row_factory = sqlite3.Row

    def tearDown(self):
        self.conn.close()
        self.tmp.cleanup()

    def test_single_primary_key_is_the_record_name_and_nulls_are_not_sent(self):
        self.assertEqual(operations(self.conn, "brands"), [{
            "operationType": "forceUpdate",
            "record": {"recordType": "Brand", "recordName": "ml", "fields": {
                "name": {"value": "ML", "type": "STRING"},
                "shortName": {"value": "ML", "type": "STRING"},
                "sortOrder": {"value": 3, "type": "INT64"},
            }},
        }])

    def test_composite_primary_key_is_prefixed_with_the_table(self):
        [op] = operations(self.conn, "song_artists")
        self.assertEqual(op["record"]["recordName"], "song_artists-song_t-ml_t-original")
        self.assertEqual(op["record"]["fields"], {
            "songId": {"value": "song_t", "type": "STRING"},
            "idolId": {"value": "ml_t", "type": "STRING"},
            "role": {"value": "original", "type": "STRING"},
        })

    def test_idols_carry_the_current_voice_actor(self):
        [op] = operations(self.conn, "idols")
        fields = op["record"]["fields"]
        self.assertEqual(fields["voiceActors"], {"value": "今の声", "type": "STRING"})
        self.assertEqual(fields["height"], {"value": 158.5, "type": "DOUBLE"})
        self.assertNotIn("id", fields)

    def test_replace_include_and_exclude(self):
        [op] = operations(self.conn, "brands", replace=True, include_fields={"name", "sortOrder"},
                          exclude_fields={"sortOrder"})
        self.assertEqual(op["operationType"], "forceReplace")
        self.assertEqual(op["record"]["fields"], {"name": {"value": "ML", "type": "STRING"}})


class SendingTest(unittest.TestCase):
    def setUp(self):
        self.failing = set()
        self.ck = support.FakeCloudKit(self, self.respond)
        self.addCleanup(sk._build_paths, "development")
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / "m.sqlite"
        fixture_db(self.db)
        self.key_file = Path(self.tmp.name) / "dummy.pem"
        self.key_file.write_text("not a key")

    def tearDown(self):
        self.tmp.cleanup()

    def respond(self, url, payload):
        response = support.accept_all(url, payload)
        for record in response["records"]:
            if record["recordName"] in self.failing:
                record["serverErrorCode"] = "SERVER_REJECTED_REQUEST"
        return response

    def run_main(self, *args):
        saved = sys.argv
        sys.argv = ["seed_cloudkit.py", "--db", str(self.db), "--key-id", "dummy",
                    "--key-file", str(self.key_file), *args]
        out = io.StringIO()
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
                sk.main()
            return 0
        except SystemExit as e:
            return e.code
        finally:
            sys.argv = saved
            self.output = out.getvalue()

    def test_upload_goes_to_the_environment_chosen_last(self):
        sk._build_paths("production")
        with contextlib.redirect_stdout(io.StringIO()):
            sk.upload_operations([{"operationType": "forceUpdate",
                                   "record": {"recordType": "Brand", "recordName": "ml", "fields": {}}}],
                                 False, "Brand")
        self.assertTrue(self.ck.calls[0][0].endswith("/production/public/records/modify"))

    def test_main_exits_one_on_record_errors(self):
        self.failing = {"ml"}
        self.assertEqual(self.run_main("--tables", "brands"), 1)

    def test_ids_limit_the_rows_sent(self):
        self.assertEqual(self.run_main("--tables", "song_artists", "--ids", "other_song"), 0)
        self.assertEqual(self.ck.operations(), [])

    def test_ids_that_match_no_row_are_warned(self):
        # 渡した id が表の列に 1 つも当たらないのは、id の種類の取り違えが多い
        # (shows に公演 id を渡す等)。黙って 0 件で終わらせない。
        # 手元の DB に song_t の曲の行は無いが、song_artists には 1 行ある。
        self.assertEqual(self.run_main("--tables", "songs", "song_artists", "--ids", "song_t"), 0)
        self.assertIn("⚠️ songs: --ids で絞ったら 0 行", self.output)
        self.assertNotIn("⚠️ song_artists:", self.output)

    def test_verify_counts_live_records_with_a_modified_at_query(self):
        def respond(url, payload):
            if url.endswith("/records/query"):
                return {"records": [{"recordName": "a"},
                                    {"recordName": "b", "fields": {"deletedAt": {"value": 1}}}]}
            return support.accept_all(url, payload)

        self.ck.handler = respond
        self.assertEqual(sk.cloudkit_count("Brand"), 1)
        query = self.ck.calls[-1][1]["query"]
        self.assertEqual(query["filterBy"][0]["fieldName"], "modifiedAt")
        self.assertEqual(query["sortBy"][0]["fieldName"], "modifiedAt")


if __name__ == "__main__":
    unittest.main()
