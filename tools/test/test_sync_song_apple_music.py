"""sync_song_apple_music.py のテスト (送信は偽物)。

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
import sync_song_apple_music as sync

SONG_ID = "765as_私はアイドル_2"


class SyncSongAppleMusicTest(unittest.TestCase):
    def setUp(self):
        self.failing = set()
        self.ck = support.FakeCloudKit(self, self.respond)
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / "m.sqlite"
        support.schema_only(self.db)
        conn = sqlite3.connect(str(self.db))
        conn.execute(
            "INSERT INTO songs (id, title, brand_id, song_type, apple_music_id, artwork_url, composer)"
            " VALUES (?, '曲', '765as', 'solo', '123', 'https://example.com/a.jpg', '作曲者')", (SONG_ID,))
        conn.commit()
        conn.close()
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

    def run_main(self):
        saved = sys.argv
        sys.argv = ["sync_song_apple_music.py", "--env", "production", "--key-id", "dummy",
                    "--key-file", str(self.key_file), "--db", str(self.db), "--ids", SONG_ID]
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                return sync.main()
        finally:
            sys.argv = saved

    def test_sends_only_the_apple_music_fields(self):
        self.assertEqual(self.run_main(), 0)
        [op] = self.ck.operations()
        self.assertEqual(op["record"]["recordName"], SONG_ID)
        self.assertEqual(set(op["record"]["fields"]), {"appleMusicId", "artworkUrl", "modifiedAt"})
        self.assertTrue(self.ck.calls[0][0].endswith("/production/public/records/modify"))
        # 仮名の recordName を \\uXXXX にしない (seed_cloudkit.py と同じ送り方)。
        self.assertIn(SONG_ID.encode("utf-8"), self.ck.bodies[0])

    def test_record_errors_exit_one(self):
        self.failing = {SONG_ID}
        self.assertEqual(self.run_main(), 1)


if __name__ == "__main__":
    unittest.main()
