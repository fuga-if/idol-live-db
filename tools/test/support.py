"""tools/test の共通の下ごしらえ。

    python3 -m unittest discover -s tools/test -p 'test_*.py'

テストは一時ディレクトリと一時 DB だけを触る。手元の master.sqlite・db/master.sql・
data/ は読むだけで、書き換えない。外部への通信もしない。
"""

import hashlib
import json
import os
import shutil
import socket
import sqlite3
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent
REPO = TOOLS.parent
MASTER_SQL = REPO / "db" / "master.sql"

if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))


def _no_network(*args, **kwargs):
    raise AssertionError("テストから外へ通信しようとした: %r" % (args,))


# テストのプロセスからは 1 本も外へ出さない。通信を偽物に差し替え損ねたら、
# 本番に届く前にここで落ちる。
socket.socket.connect = _no_network
socket.create_connection = _no_network

_master_text = None


def master_sql_text():
    global _master_text
    if _master_text is None:
        _master_text = MASTER_SQL.read_text(encoding="utf-8")
    return _master_text


def restore_master(path):
    """db/master.sql を丸ごと入れた DB を path に作る。"""
    conn = sqlite3.connect(str(path))
    conn.executescript(master_sql_text())
    conn.close()


def schema_only(path):
    """db/master.sql と同じ表と索引だけを持つ、空の DB を path に作る。"""
    src = sqlite3.connect(":memory:")
    src.executescript(master_sql_text())
    ddl = [sql for (sql,) in src.execute(
        "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL"
        " ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, rowid")]
    src.close()
    conn = sqlite3.connect(str(path))
    for sql in ddl:
        conn.execute(sql)
    conn.commit()
    conn.close()


def write_json(path, obj):
    os.makedirs(os.path.dirname(str(path)), exist_ok=True)
    with open(str(path), "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False)


class FakeResponse:
    def __init__(self, status_code, payload=None, text=""):
        self.status_code = status_code
        self._payload = payload
        self.text = text

    def json(self):
        return self._payload

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError("HTTP %d" % self.status_code)


def accept_all(url, payload):
    """modify を全部成功として返す応答。"""
    return {"records": [{"recordName": op["record"]["recordName"],
                         "recordType": op["record"]["recordType"]}
                        for op in payload.get("operations", [])]}


class FakeCloudKit:
    """lib/cloudkit.py の送信口を偽物に差し替える (テストの間だけ)。

    handler(url, payload) が応答の JSON を返す。送られたものは calls に (url, payload)
    で残る。鍵の読み込みと待ちも差し替えるので、鍵のファイルも時間も要らない。
    """

    def __init__(self, testcase, handler=accept_all):
        from lib import cloudkit

        self.handler = handler
        self.calls = []
        self.bodies = []  # 送られた生のバイト列
        self.statuses = []  # 先頭から順に返す HTTP ステータス (空なら 200)
        for name, fake in (("http_post", self._post),
                           ("load_signer", lambda key_id, key_file: None),
                           ("sleep", lambda seconds: None)):
            testcase.addCleanup(setattr, cloudkit, name, getattr(cloudkit, name))
            setattr(cloudkit, name, fake)

    def _post(self, url, body, headers):
        payload = json.loads(body.decode("utf-8"))
        self.calls.append((url, payload))
        self.bodies.append(body)
        status = self.statuses.pop(0) if self.statuses else 200
        if status != 200:
            return FakeResponse(status, text="fake %d" % status)
        return FakeResponse(200, self.handler(url, payload))

    def operations(self):
        return [op for _, payload in self.calls for op in payload.get("operations", [])]


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def copy_tools(root, *names):
    """tools/ の一部を root/tools/ へ写す (lib/ は常に写す)。

    既定のパス (tools/ の隣の ImasLiveDB/Resources/master.sqlite など) を
    root の下に向けて、スクリプトを本物の手元の DB に触らせずに起動するため。
    """
    dst = Path(root) / "tools"
    dst.mkdir(parents=True, exist_ok=True)
    shutil.copytree(str(TOOLS / "lib"), str(dst / "lib"),
                    ignore=shutil.ignore_patterns("__pycache__"))
    for name in names:
        shutil.copy2(str(TOOLS / name), str(dst / name))
    return dst
