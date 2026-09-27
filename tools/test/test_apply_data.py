"""apply_data.py のテスト (一時 DB と一時の data/ だけを使う)。

    python3 -m unittest discover -s tools/test -p 'test_*.py'
"""

import contextlib
import io
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import support
import apply_data


def fixture_db(path):
    """衣装の投稿が指せる公演・曲・アイドルを 1 つずつ持つ空の DB。"""
    support.schema_only(path)
    conn = sqlite3.connect(str(path))
    conn.executescript("""
        INSERT INTO brands (id, name, short_name, sort_order) VALUES ('ml', 'ML', 'ML', 3);
        INSERT INTO idols (id, brand_id, name, sort_order) VALUES ('ml_t', 'ml', 'テスト', 3001);
        INSERT INTO songs (id, title, brand_id, song_type) VALUES ('song_t', '曲', 'ml', 'unit');
        INSERT INTO events (id, brand_id, name, event_type) VALUES ('ev_t', 'ml', '公演', 'live');
        INSERT INTO shows (id, event_id, name, date, sort_order) VALUES ('sh_t', 'ev_t', 'DAY1', '2026-01-01', 0);
        INSERT INTO setlist_items (id, show_id, song_id, position) VALUES ('sh_t_0007', 'sh_t', 'song_t', 7);
    """)
    conn.commit()
    conn.close()


COSTUME_POST = {"costumes": [{
    "id": "cos_t", "name": "テスト衣装", "brand_id": "ml",
    "source_url": "https://example.com/costume",
    "wears": [
        {"show_id": "sh_t", "setlist_item_id": "sh_t_0007", "idol_id": "ml_t"},
        {"show_id": "sh_t"},
    ],
}]}


class ApplyCostumesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.db = root / "m.sqlite"
        fixture_db(self.db)
        self.data = root / "data"
        support.write_json(self.data / "costumes" / "t.json", COSTUME_POST)
        self._saved = (apply_data.DATA_DIR, apply_data.ONLY_FILE)
        apply_data.DATA_DIR, apply_data.ONLY_FILE = self.data, None

    def tearDown(self):
        apply_data.DATA_DIR, apply_data.ONLY_FILE = self._saved
        self.tmp.cleanup()

    def connect(self):
        conn = sqlite3.connect(str(self.db))
        conn.execute("PRAGMA foreign_keys = ON")
        return conn

    def test_costumes_are_applied(self):
        conn = self.connect()
        with contextlib.redirect_stdout(io.StringIO()):
            affected = apply_data.apply_all(conn)
        wears = conn.execute(
            "SELECT setlist_item_id, idol_id, sort_order FROM costume_wears"
            " WHERE costume_id = 'cos_t' ORDER BY sort_order").fetchall()
        conn.close()
        # 曲の分かる記録はセトリの位置、分からない記録は末尾 (9999)。
        self.assertEqual(wears, [("sh_t_0007", "ml_t", 7), (None, None, 9999)])
        # 投稿した衣装の id だけを押す (着用記録は costume_id で絞る)。
        self.assertEqual(affected["costumes"], {"cos_t"})
        self.assertEqual(affected["costume_wears"], {"cos_t"})

    def test_costumes_are_pushed_by_their_ids_only(self):
        # 表を丸ごと送ると、手元の古い値で CloudKit の新しい値を上書きしうる。
        conn = self.connect()
        with contextlib.redirect_stdout(io.StringIO()):
            affected = apply_data.apply_all(conn)
        conn.close()
        runs = []

        def fake_call(cmd):
            ids = None
            if "--ids-file" in cmd:
                with open(cmd[cmd.index("--ids-file") + 1], encoding="utf-8") as f:
                    ids = f.read().split()
            tables = cmd[cmd.index("--tables") + 1:cmd.index("--environment")]
            runs.append((tables, ids))
            return 0

        saved = apply_data.subprocess.call
        apply_data.subprocess.call = fake_call
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(apply_data.push_cloudkit(affected, production=False), 0)
        finally:
            apply_data.subprocess.call = saved
        self.assertEqual(runs, [(["costumes", "costume_wears"], ["cos_t"])])


class CheckWithoutThirdPartyModulesTest(unittest.TestCase):
    """--check は鍵も外部のライブラリも要らない (貢献者が手元で回す口)。"""

    def test_check_runs_under_python_dash_S(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = Path(tmp) / "m.sqlite"
            fixture_db(db)
            # -S: site-packages を読まない (requests / ecdsa が無い環境と同じ)。
            proc = subprocess.run(
                [sys.executable, "-S", str(support.TOOLS / "apply_data.py"), "--check",
                 "--db", str(db), "--only", "no_such_file.json"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("投入対象なし", proc.stdout)


class EnsureDbTest(unittest.TestCase):
    def test_a_missing_db_is_built_from_the_dump_with_its_fingerprint(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = Path(tmp) / "sub" / "master.sqlite"
            with contextlib.redirect_stdout(io.StringIO()):
                apply_data.ensure_db(db)
            conn = sqlite3.connect(str(db))
            [(value,)] = conn.execute("SELECT value FROM meta WHERE key = 'content_hash'").fetchall()
            shows = conn.execute("SELECT count(*) FROM shows").fetchone()[0]
            conn.close()
        self.assertEqual(value, support.sha256(support.MASTER_SQL))
        self.assertGreater(shows, 0)


class PostFixture(unittest.TestCase):
    """一時の data/ と master に投稿を置いて validate する土台。"""

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

    def song(self, **extra):
        return dict({"id": "ml_new_song", "title": "新曲", "brand_id": "ml", "song_type": "solo"}, **extra)


class SourceRequiredTest(PostFixture):
    """出典 (source) の無い投稿は --check で落とす。"""

    def problems(self, kind, post):
        support.write_json(self.data / kind / "post.json", post)
        conn = sqlite3.connect(str(self.db))
        try:
            return [p for p in apply_data.validate(conn) if "出典" in p]
        finally:
            conn.close()

    def test_blank_sources_do_not_count(self):
        self.assertEqual(len(self.problems("songs", {"source": " ", "songs": [self.song(source=[])]})), 1)

    def test_every_item_may_carry_its_own_source(self):
        post = {"songs": [self.song(source="https://example.com/a"),
                          self.song(id="ml_other", source=["CD のブックレット"])]}
        self.assertEqual(self.problems("songs", post), [])
        post["songs"][1].pop("source")
        [problem] = self.problems("songs", post)
        self.assertIn("[1]", problem)

    def test_costume_source_url_counts_as_a_source(self):
        self.assertEqual(self.problems("costumes", COSTUME_POST), [])

    def test_setlists_and_fixes_need_one_too(self):
        setlist = {"show_id": "sh_t", "songs": [{"position": 1, "song_id": "song_t", "performers": "all"}]}
        self.assertEqual(len(self.problems("setlists", setlist)), 1)
        self.assertEqual(self.problems("setlists", dict(setlist, source="公式のセットリスト画像")), [])
        fix = {"table": "songs", "id": "song_t", "fields": {"title": "曲"}}
        self.assertEqual(len(self.problems("fixes", {"fixes": [fix]})), 1)
        self.assertEqual(self.problems("fixes", {"fixes": [dict(fix, source="https://example.com")]}), [])

    def test_every_template_shows_a_source(self):
        # テンプレートをそのまま写した投稿が、出典の検査に落ちないこと。
        import json
        for path in sorted((support.REPO / "data").glob("*/_template.json")):
            data = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(apply_data.source_problems(path.parent.name, path, data), [], path)

    def test_an_item_level_source_is_not_an_unknown_column(self):
        conn = sqlite3.connect(str(self.db))
        idol = {"id": "ml_new", "brand_id": "ml", "name": "新人", "sort_order": 3002,
                "source": "https://example.com/idol"}
        support.write_json(self.data / "idols" / "post.json", {"idols": [idol]})
        try:
            self.assertEqual(apply_data.validate(conn), [])
        finally:
            conn.close()


class TitleKanaRequiredTest(PostFixture):
    """新曲は読み (ひらがな) が無いと --check で落とす。空だと五十音順・かな検索から漏れる。"""

    def kana_problems(self, **extra):
        post = {"source": "https://example.com/news", "songs": [self.song(**extra)]}
        support.write_json(self.data / "songs" / "post.json", post)
        conn = sqlite3.connect(str(self.db))
        try:
            return [p for p in apply_data.validate(conn) if "title_kana" in p]
        finally:
            conn.close()

    def test_a_song_without_a_reading_is_rejected(self):
        self.assertEqual(len(self.kana_problems()), 1)
        self.assertEqual(len(self.kana_problems(title_kana="")), 1)

    def test_a_katakana_reading_is_rejected(self):
        self.assertEqual(len(self.kana_problems(title_kana="シンキョク")), 1)


class SongIdPrefixTest(PostFixture):
    """新曲の id は brand_id で始める。他ブランドの接頭辞だと同名曲とぶつかる (765as_dream と KR「Dream」)。"""

    def id_problems(self, **extra):
        post = {"source": "https://example.com/news", "songs": [self.song(title_kana="しんきょく", **extra)]}
        support.write_json(self.data / "songs" / "post.json", post)
        conn = sqlite3.connect(str(self.db))
        try:
            return [p for p in apply_data.validate(conn) if "で始める" in p]
        finally:
            conn.close()

    def test_an_id_with_its_own_brand_passes(self):
        self.assertEqual(self.id_problems(), [])
        self.assertEqual(self.id_problems(id="other_kr_dream", brand_id="other"), [])

    def test_an_id_borrowing_another_brand_is_rejected(self):
        self.assertEqual(len(self.id_problems(id="765as_dream", brand_id="other")), 1)


class AddOriginalSingersTest(PostFixture):
    """data/fixes/ の add_original_singers で既存曲に原唱者を足す。"""

    def post(self, *fixes):
        support.write_json(self.data / "fixes" / "post.json",
                           {"source": "https://example.com/cd", "fixes": list(fixes)})

    def validate(self):
        conn = sqlite3.connect(str(self.db))
        try:
            return apply_data.validate(conn)
        finally:
            conn.close()

    def test_singers_are_added_and_pushed_by_song(self):
        self.post({"table": "songs", "id": "song_t", "fields": {"song_type": "solo"},
                   "add_original_singers": ["ml_t"]})
        conn = sqlite3.connect(str(self.db))
        with contextlib.redirect_stdout(io.StringIO()):
            affected = apply_data.apply_all(conn)
            # 2 度流しても二重にならない。
            apply_data.apply_all(conn)
        rows = conn.execute("SELECT song_id, idol_id, role FROM song_artists").fetchall()
        song_type = conn.execute("SELECT song_type FROM songs WHERE id='song_t'").fetchone()[0]
        conn.close()
        self.assertEqual(rows, [("song_t", "ml_t", "original")])
        self.assertEqual(song_type, "solo")
        self.assertEqual(affected["song_artists"], {"song_t"})

    def test_an_unknown_idol_is_rejected(self):
        self.post({"table": "songs", "id": "song_t", "add_original_singers": ["ml_nobody"]})
        [problem] = self.validate()
        self.assertIn("ml_nobody", problem)

    def test_only_songs_take_singers(self):
        self.post({"table": "idols", "id": "ml_t", "add_original_singers": ["ml_t"]})
        self.assertTrue(any("songs の修正にだけ" in p for p in self.validate()))

    def test_an_empty_list_is_rejected(self):
        self.post({"table": "songs", "id": "song_t", "add_original_singers": []})
        self.assertTrue(any("空は不可" in p for p in self.validate()))


TICKET_SALES_DDL = (
    "CREATE TABLE ticket_sales ("
    " id TEXT PRIMARY KEY NOT NULL, event_id TEXT NOT NULL, show_ids TEXT, kind TEXT NOT NULL,"
    " name TEXT NOT NULL, starts_at TEXT, ends_at TEXT, result_at TEXT, url TEXT, note TEXT,"
    " source_url TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0,"
    " FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE);"
    "CREATE INDEX idx_ticket_sales_event ON ticket_sales(event_id);"
)


def add_ticket_sales_table(db_path):
    """ticket_sales 表を足す (db/master.sql に無くてもテストできるように、独立して用意する)。

    db/master.sql に既に表があるときは何もしない (fixture_db が schema_only 経由で既に持っている)。
    """
    conn = sqlite3.connect(str(db_path))
    try:
        if not apply_data.table_exists(conn, "ticket_sales"):
            conn.executescript(TICKET_SALES_DDL)
            conn.commit()
    finally:
        conn.close()


def drop_ticket_sales_table(db_path):
    """『まだ imas-core 側の DDL が db/master.sql に無い』状態を作る (罠固有のテスト用)。"""
    conn = sqlite3.connect(str(db_path))
    try:
        conn.executescript("DROP INDEX IF EXISTS idx_ticket_sales_event; DROP TABLE IF EXISTS ticket_sales;")
        conn.commit()
    finally:
        conn.close()


def ticket_sale_post(**extra):
    return dict({
        "event_id": "ev_t", "show_ids": ["sh_t"], "kind": "lottery", "name": "先行抽選",
        "starts_at": "2026-04-01", "ends_at": "2026-04-10 23:59", "result_at": "2026-04-15",
        "url": "https://example.com/apply", "source_url": "https://example.com/news",
    }, **extra)


class TicketSalesCheckWithoutTableTest(PostFixture):
    """罠: db/master.sql の DDL 反映を待たずにこのファイルをマージできる。

    ticket_sales 表がまだ無い master.sqlite でも --check は中身を検証できる
    (未知列チェックと重複 id チェックだけは表が要るので諦める)。
    """

    def setUp(self):
        super().setUp()
        drop_ticket_sales_table(self.db)

    def problems(self, post):
        support.write_json(self.data / "ticket_sales" / "post.json", post)
        conn = sqlite3.connect(str(self.db))
        try:
            return apply_data.validate(conn)
        finally:
            conn.close()

    def test_a_valid_post_passes_even_without_the_table(self):
        post = {"ticket_sales": [ticket_sale_post()]}
        self.assertEqual(self.problems(post), [])

    def test_unknown_event_is_rejected(self):
        post = {"ticket_sales": [ticket_sale_post(event_id="ev_nope")]}
        self.assertTrue(any("event_id" in p for p in self.problems(post)))

    def test_show_id_belonging_to_a_different_event_is_rejected(self):
        # sh_other は別イベントの公演として登録する。
        conn = sqlite3.connect(str(self.db))
        conn.executescript(
            "INSERT INTO events (id, brand_id, name, event_type) VALUES ('ev_other', 'ml', '別公演', 'live');"
            "INSERT INTO shows (id, event_id, name, date, sort_order)"
            " VALUES ('sh_other', 'ev_other', 'DAY1', '2026-01-01', 0);"
        )
        conn.commit()
        conn.close()
        post = {"ticket_sales": [ticket_sale_post(show_ids=["sh_other"])]}
        self.assertTrue(any("別のイベント" in p for p in self.problems(post)))

    def test_unknown_kind_is_rejected(self):
        post = {"ticket_sales": [ticket_sale_post(kind="premium")]}
        self.assertTrue(any("kind 不正" in p for p in self.problems(post)))

    def test_bad_moment_format_is_rejected(self):
        post = {"ticket_sales": [ticket_sale_post(ends_at="2026/04/10")]}
        self.assertTrue(any("ends_at" in p and "形式" in p for p in self.problems(post)))

    def test_at_least_one_moment_is_required(self):
        post = {"ticket_sales": [ticket_sale_post(starts_at=None, ends_at=None, result_at=None)]}
        self.assertTrue(any("いずれかが必要" in p for p in self.problems(post)))

    def test_order_must_be_starts_ends_result(self):
        # シンデレラガールズミュージカルの実例 (当落 04-15 が締切 04-28 より前) の回帰。
        post = {"ticket_sales": [ticket_sale_post(ends_at="2026-04-28", result_at="2026-04-15")]}
        self.assertTrue(any("result_at より後" in p for p in self.problems(post)))

    def test_source_url_must_be_http(self):
        post = {"ticket_sales": [ticket_sale_post(source_url="not-a-url")]}
        self.assertTrue(any("source_url" in p for p in self.problems(post)))

    def test_a_valid_post_without_show_ids_means_every_show(self):
        post = {"ticket_sales": [ticket_sale_post(show_ids=None)]}
        self.assertEqual(self.problems(post), [])


class TicketSalesWithTableTest(PostFixture):
    """ticket_sales 表がある状態 (imas-core 側の DDL 反映後) の検証と反映。"""

    def setUp(self):
        super().setUp()
        add_ticket_sales_table(self.db)

    def validate(self):
        conn = sqlite3.connect(str(self.db))
        try:
            return apply_data.validate(conn)
        finally:
            conn.close()

    def test_unknown_column_is_rejected_once_the_table_exists(self):
        post = {"ticket_sales": [ticket_sale_post(nope_field="x")]}
        support.write_json(self.data / "ticket_sales" / "post.json", post)
        self.assertTrue(any("未知の列" in p for p in self.validate()))

    def test_duplicate_event_and_name_is_rejected_within_a_batch(self):
        post = {"ticket_sales": [ticket_sale_post(), ticket_sale_post()]}
        support.write_json(self.data / "ticket_sales" / "post.json", post)
        self.assertTrue(any("重複" in p for p in self.validate()))

    def test_apply_inserts_a_deterministic_id_scoped_by_event(self):
        post = {"ticket_sales": [ticket_sale_post()]}
        support.write_json(self.data / "ticket_sales" / "post.json", post)
        conn = sqlite3.connect(str(self.db))
        conn.execute("PRAGMA foreign_keys = ON")
        with contextlib.redirect_stdout(io.StringIO()):
            affected = apply_data.apply_all(conn)
        row = conn.execute(
            "SELECT id, event_id, show_ids, kind, name, source_url, sort_order FROM ticket_sales"
        ).fetchone()
        conn.close()
        self.assertEqual(row[1:], ("ev_t", "sh_t", "lottery", "先行抽選", "https://example.com/news", 0))
        self.assertTrue(row[0].startswith("ts_"))
        self.assertEqual(affected["ticket_sales"], {"ev_t"})

    def test_reposting_the_same_sale_is_rejected_as_already_existing(self):
        # id は event_id + name から決まるので、同じ内容の 2 回目の投稿は「既存」として --check で弾く
        # (曲を別 id で起こし直して二重登録になった事故と同じ再発防止)。
        post = {"ticket_sales": [ticket_sale_post()]}
        support.write_json(self.data / "ticket_sales" / "post.json", post)
        conn = sqlite3.connect(str(self.db))
        conn.execute("PRAGMA foreign_keys = ON")
        with contextlib.redirect_stdout(io.StringIO()):
            apply_data.apply_all(conn)
        problems = apply_data.validate(conn)
        conn.close()
        self.assertTrue(any("既に存在" in p for p in problems))


class TicketSalesApplyRequiresTableTest(PostFixture):
    """--apply は表が無ければ作らずエラーにする (imas-core の DDL 反映待ち)。

    main() は DATA_DIR をモジュール変数で読むので、実リポジトリの data/ を巻き込まないよう
    subprocess ではなく直接呼び (setUp で DATA_DIR を差し替え済み)、argv だけ差し替える。
    """

    def setUp(self):
        super().setUp()
        drop_ticket_sales_table(self.db)

    def run_main(self, *argv):
        saved_argv = sys.argv
        sys.argv = ["apply_data.py", *argv]
        out, err = io.StringIO(), io.StringIO()
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                try:
                    apply_data.main()
                    code = 0
                except SystemExit as e:
                    code = e.code or 0
        finally:
            sys.argv = saved_argv
        return code, out.getvalue(), err.getvalue()

    def test_apply_dash_dash_check_only_passes_without_the_table(self):
        post = {"ticket_sales": [ticket_sale_post()]}
        support.write_json(self.data / "ticket_sales" / "post.json", post)
        code, out, err = self.run_main("--check", "--db", str(self.db))
        self.assertEqual(code, 0, err)
        self.assertIn("全件妥当", out)

    def test_apply_is_refused_without_the_table(self):
        post = {"ticket_sales": [ticket_sale_post()]}
        support.write_json(self.data / "ticket_sales" / "post.json", post)
        code, _out, err = self.run_main("--apply", "--db", str(self.db))
        self.assertNotEqual(code, 0)
        self.assertIn("ticket_sales 表が master.sqlite に無い", err)
        # 諦めるだけで、表を作ったりはしない。
        conn = sqlite3.connect(str(self.db))
        try:
            self.assertFalse(apply_data.table_exists(conn, "ticket_sales"))
        finally:
            conn.close()


class AppliedPostsTest(unittest.TestCase):
    def test_posts_moved_to_applied_are_not_read(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = Path(tmp) / "data"
            support.write_json(data / "_applied" / "songs" / "old.json", {"songs": []})
            support.write_json(data / "songs" / "new.json", {"songs": []})
            saved = apply_data.DATA_DIR
            apply_data.DATA_DIR = data
            try:
                self.assertEqual([p.name for p, _ in apply_data.load("songs")], ["new.json"])
            finally:
                apply_data.DATA_DIR = saved


if __name__ == "__main__":
    unittest.main()
