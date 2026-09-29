"""merge_duplicate_*.py が、正本を書けなかったときに削除 TSV を書かないことのテスト。

    python3 -m unittest discover -s tools/test -p 'test_*.py'

写した tools/ と一時の同梱 DB・正本だけを使う。
"""

import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import support


class MergeToolsTest(unittest.TestCase):
    def run_broken(self, tool, tsv_name):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            tools = support.copy_tools(root, tool, "check_fk_integrity.py")
            (root / "db").mkdir()
            (root / "db" / "master.sql").write_text(support.master_sql_text(), encoding="utf-8")
            db = root / "ImasLiveDB" / "Resources" / "master.sqlite"
            db.parent.mkdir(parents=True)
            support.restore_master(db)
            conn = sqlite3.connect(str(db))
            # 手元の DB に外部キーの壊れを 1 件混ぜる (正本には書けない状態)。
            conn.execute("INSERT INTO show_tickets (id, show_id, name, price)"
                         " VALUES ('t_broken', 'sh_missing', '券', 1000)")
            conn.commit()
            conn.close()
            before = support.sha256(root / "db" / "master.sql")
            proc = subprocess.run([sys.executable, str(tools / tool), "--apply"],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  universal_newlines=True)
            self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
            self.assertIn("外部キーの壊れ", proc.stderr)
            self.assertEqual(support.sha256(root / "db" / "master.sql"), before)
            self.assertFalse((tools / tsv_name).exists(), "正本を書けなかったのに削除 TSV を書いた")

    def test_merge_duplicate_songs(self):
        self.run_broken("merge_duplicate_songs.py", "pending_cloudkit_deletions_song_merge.tsv")


if __name__ == "__main__":
    unittest.main()
