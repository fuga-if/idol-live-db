"""lib/cloudkit.py (署名・送信・再試行・一括送信・読み取り) のテスト。通信は偽物。

    python3 -m unittest discover -s tools/test -p 'test_*.py'
"""

import contextlib
import io
import unittest

import support
from lib import cloudkit

URL = cloudkit.BASE_URL + cloudkit.records_path("development", "modify")


class CountingSigner:
    def __init__(self):
        self.signed = 0

    def headers(self, body, subpath):
        self.signed += 1
        return {"X-Signed": str(self.signed)}


def ops(n):
    return [{"operationType": "forceUpdate",
             "record": {"recordType": "Song", "recordName": "s%03d" % i, "fields": {}}}
            for i in range(n)]


def quiet(fn, *args, **kwargs):
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        return fn(*args, **kwargs)


class PostJsonTest(unittest.TestCase):
    def setUp(self):
        self.ck = support.FakeCloudKit(self, lambda url, payload: {"ok": True})

    def test_rate_limited_request_is_signed_again_and_resent(self):
        self.ck.statuses = [429, 200]
        signer = CountingSigner()
        self.assertEqual(quiet(cloudkit.post_json, URL, {"a": 1}, signer), {"ok": True})
        self.assertEqual(len(self.ck.calls), 2)
        self.assertEqual(signer.signed, 2)

    def test_gives_up_after_max_retries(self):
        self.ck.statuses = [429] * cloudkit.MAX_RETRIES
        with self.assertRaises(RuntimeError):
            quiet(cloudkit.post_json, URL, {"a": 1})
        self.assertEqual(len(self.ck.calls), cloudkit.MAX_RETRIES)

    def test_http_error_is_raised(self):
        self.ck.statuses = [500]
        with self.assertRaises(RuntimeError):
            quiet(cloudkit.post_json, URL, {"a": 1})

    def test_body_is_raw_utf8(self):
        # recordName の仮名を \\uXXXX にしない (CloudKit は UTF-8 のまま受け取る)。
        quiet(cloudkit.post_json, URL, {"recordName": "765as_私はアイドル"})
        self.assertIn("私はアイドル".encode("utf-8"), self.ck.bodies[0])


class UploadOperationsTest(unittest.TestCase):
    def setUp(self):
        self.failing = set()
        self.ck = support.FakeCloudKit(self, self.respond)
        self.post = lambda url, payload: cloudkit.post_json(url, payload)

    def respond(self, url, payload):
        response = support.accept_all(url, payload)
        for record in response["records"]:
            if record["recordName"] in self.failing:
                record["serverErrorCode"] = "SERVER_REJECTED_REQUEST"
        return response

    def test_sends_in_batches_and_counts_record_errors(self):
        self.failing = {"s005", "s300"}
        result = quiet(cloudkit.upload_operations, ops(450), URL, False, "Song", self.post)
        self.assertEqual(result, (448, 2))
        self.assertEqual([len(p["operations"]) for _, p in self.ck.calls], [200, 200, 50])

    def test_dry_run_sends_nothing(self):
        result = quiet(cloudkit.upload_operations, ops(3), URL, True, "Song", self.post)
        self.assertEqual(result, (3, 0))
        self.assertEqual(self.ck.calls, [])

    def test_failed_batch_is_retried_once(self):
        attempts = []

        def flaky(url, payload):
            attempts.append(1)
            if len(attempts) == 1:
                raise ConnectionError("temporarily unavailable")
            return support.accept_all(url, payload)

        result = quiet(cloudkit.upload_operations, ops(2), URL, False, "Song", flaky)
        self.assertEqual(result, (2, 0))
        self.assertEqual(len(attempts), 2)

    def test_batch_failing_twice_raises(self):
        def broken(url, payload):
            raise ConnectionError("down")

        with self.assertRaises(ConnectionError):
            quiet(cloudkit.upload_operations, ops(2), URL, False, "Song", broken)


class ReadTest(unittest.TestCase):
    """query_all / count_live / lookup は読み取りだけ (modify を送らない)。"""

    def setUp(self):
        self.ck = support.FakeCloudKit(self, self.respond)
        self.pages = [
            {"records": [{"recordName": "a"}, {"recordName": "b",
                          "fields": {"deletedAt": {"value": 1}}}], "continuationMarker": "m1"},
            {"records": [{"recordName": "c"}], "continuationMarker": "m2"},
            {"records": [{"recordName": "d"}]},
        ]

    def respond(self, url, payload):
        if url.endswith("/records/query"):
            return self.pages[len(self.ck.calls) - 1]
        return {"records": [{"recordName": "x1", "fields": {}},
                            {"serverErrorCode": "NOT_FOUND"}]}

    def post(self, url, payload):
        return cloudkit.post_json(url, payload)

    def test_query_all_follows_continuation_markers(self):
        url = cloudkit.BASE_URL + cloudkit.records_path("production", "query")
        records = cloudkit.query_all(url, "Song", self.post)
        self.assertEqual([r["recordName"] for r in records], ["a", "b", "c", "d"])
        sent = [payload for _, payload in self.ck.calls]
        self.assertEqual([p.get("continuationMarker") for p in sent], [None, "m1", "m2"])
        self.assertEqual(sent[0]["query"]["filterBy"][0]["fieldName"], "modifiedAt")
        self.assertNotIn("desiredKeys", sent[0])

    def test_lookup_maps_missing_records_by_position(self):
        url = cloudkit.BASE_URL + cloudkit.records_path("production", "lookup")
        found = cloudkit.lookup(url, ["x1", "x2"], self.post, desired_keys=["deletedAt"])
        self.assertEqual(found["x1"]["fields"], {})
        self.assertEqual(found["x2"]["serverErrorCode"], "NOT_FOUND")
        self.assertEqual(self.ck.calls[0][1], {"records": [{"recordName": "x1"}, {"recordName": "x2"}],
                                               "desiredKeys": ["deletedAt"]})


if __name__ == "__main__":
    unittest.main()
