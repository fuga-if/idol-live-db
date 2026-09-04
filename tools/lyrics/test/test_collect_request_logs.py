#!/usr/bin/env python3
"""collect_request_logs.py のユニットテスト (API 応答のフィクスチャで集計を固定する)。

    python3 -m unittest discover -s tools/lyrics/test -p 'test_*.py'

ネットワークには一切出ない。post_query に渡す opener を差し替えて、
Cloudflare Telemetry Query API の応答形を模したフィクスチャを返す。
"""

import datetime as dt
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import collect_request_logs as C  # noqa: E402


_next_id = iter(range(1, 10**6))


def event(message, event_id=None):
    """Workers Logs の 1 イベント (必要なキーだけ)。

    id は本番と同じく 1 件ごとに違う値にする。同じ id を並べると重複除去に
    落とされ、テストが「重複除去のテスト」に化けてしまう。
    """
    if event_id is None:
        event_id = "auto%d" % next(_next_id)
    return {"$metadata": {"id": event_id, "message": message}, "dataset": "cloudflare-workers"}


def lyrics_event(song_id, event_id=None):
    return event(json.dumps({"event": "lyrics_read", "song_id": song_id}), event_id)


def response(events):
    return {"success": True, "result": {"events": {"events": events}}}


class FakeApi:
    """opener 差し替え用。呼ばれた body を記録し、用意した応答を順に返す。"""

    def __init__(self, pages):
        self.pages = list(pages)
        self.bodies = []

    def __call__(self, url, payload, token):
        self.bodies.append(json.loads(payload.decode("utf-8")))
        self.url = url
        return self.pages.pop(0) if self.pages else response([])


DAY = dt.date(2026, 9, 1)


class TestParseEvent(unittest.TestCase):
    def test_lyrics_read_event(self):
        self.assertEqual(C.parse_event(lyrics_event("cg_お願いシンデレラ")), "cg_お願いシンデレラ")

    def test_other_json_log_is_ignored(self):
        # 別の構造化ログが includes フィルタに引っかかっても数えない。
        self.assertIsNone(C.parse_event(event('{"event":"song_detail_lyrics_rate_limited"}')))

    def test_plain_string_log_is_ignored(self):
        self.assertIsNone(C.parse_event(event("lyrics_read っぽい素の文字列")))

    def test_missing_song_id_is_ignored(self):
        self.assertIsNone(C.parse_event(event('{"event":"lyrics_read"}')))
        self.assertIsNone(C.parse_event(event('{"event":"lyrics_read","song_id":""}')))

    def test_broken_event_does_not_raise(self):
        self.assertIsNone(C.parse_event({}))
        self.assertIsNone(C.parse_event({"$metadata": {"message": None}}))


class TestCollectDay(unittest.TestCase):
    def test_counts_per_song(self):
        api = FakeApi([response([
            lyrics_event("a"), lyrics_event("b"), lyrics_event("a"),
            event("何か別のログ"),
        ])])
        counts, seen = C.collect_day("tok", DAY, opener=api)
        self.assertEqual(counts, {"a": 2, "b": 1})
        self.assertEqual(seen, 4)

    def test_query_shape(self):
        api = FakeApi([response([])])
        C.collect_day("tok", DAY, opener=api)
        body = api.bodies[0]
        self.assertEqual(body["view"], "events")
        self.assertEqual(body["parameters"]["datasets"], ["cloudflare-workers"])
        # UTC のその日 [00:00, 翌00:00) で切る。
        self.assertEqual(body["timeframe"]["from"], 1788220800000)
        self.assertEqual(body["timeframe"]["to"], 1788220800000 + 86400000)
        keys = {f["key"]: f for f in body["parameters"]["filters"]}
        self.assertEqual(keys["$metadata.service"]["value"], "imas-live-api")
        self.assertEqual(keys["$metadata.message"]["operation"], "includes")
        self.assertEqual(keys["$metadata.message"]["value"], "lyrics_read")
        self.assertNotIn("offset", body)   # 1 ページ目にカーソルは付けない

    def test_pagination_follows_cursor(self):
        full = [lyrics_event("a", "id%d" % i) for i in range(C.PAGE_SIZE)]
        api = FakeApi([response(full), response([lyrics_event("b", "last")])])
        counts, seen = C.collect_day("tok", DAY, opener=api)
        self.assertEqual(counts, {"a": C.PAGE_SIZE, "b": 1})
        self.assertEqual(seen, C.PAGE_SIZE + 1)
        # 2 ページ目は 1 ページ目の最後のイベント ID をカーソルにする。
        self.assertEqual(api.bodies[1]["offset"], "id%d" % (C.PAGE_SIZE - 1))
        self.assertEqual(api.bodies[1]["offsetDirection"], "next")

    def test_stops_when_cursor_does_not_advance(self):
        # 同じページを返し続ける API でも無限ループせず、二重計上もしない。
        same = [lyrics_event("a", "id%d" % i) for i in range(C.PAGE_SIZE)]
        api = FakeApi([response(same)] * 5)
        counts, _ = C.collect_day("tok", DAY, opener=api)
        self.assertEqual(counts, {"a": C.PAGE_SIZE})
        # 2 回目でカーソルが進んでいないと分かって止まる。
        self.assertEqual(len(api.bodies), 2)

    def test_overlapping_pages_are_not_double_counted(self):
        # カーソル行を含む向きにページが動くと境目が 1 件重なる。重複は落とす。
        page1 = [lyrics_event("a", "id%d" % i) for i in range(C.PAGE_SIZE)]
        page2 = [page1[-1], lyrics_event("b", "id-new")]
        api = FakeApi([response(page1), response(page2)])
        counts, seen = C.collect_day("tok", DAY, opener=api)
        self.assertEqual(counts, {"a": C.PAGE_SIZE, "b": 1})
        self.assertEqual(seen, C.PAGE_SIZE + 1)

    def test_api_error_response_raises(self):
        api = FakeApi([{"success": False, "errors": [{"message": "bad token"}]}])
        with self.assertRaises(C.ApiError):
            C.collect_day("tok", DAY, opener=api)


class TestWriteTsv(unittest.TestCase):
    def test_sorted_and_idempotent(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "2026-09-01.tsv")
            C.write_tsv(path, {"b": 1, "a": 5, "c": 1})
            first = open(path, encoding="utf-8").read()
            self.assertEqual(first, "song_id\tcount\na\t5\nb\t1\nc\t1\n")
            # 同じ日を引き直しても同じ中身 = 冪等 (差分が出ない)。
            C.write_tsv(path, {"c": 1, "a": 5, "b": 1})
            self.assertEqual(open(path, encoding="utf-8").read(), first)

    def test_empty_day_writes_header_only(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "2026-09-02.tsv")
            C.write_tsv(path, {})
            # 「その日は 0 回だった」と「まだ集めていない」を区別できるようにする。
            self.assertEqual(open(path, encoding="utf-8").read(), "song_id\tcount\n")


class TestTargetDays(unittest.TestCase):
    def test_explicit_date(self):
        args = type("A", (), {"date": "2026-09-01", "days": 3})()
        self.assertEqual(C.target_days(args), [DAY])

    def test_defaults_to_three_days_back_from_yesterday(self):
        args = type("A", (), {"date": None, "days": 3})()
        days = C.target_days(args)
        today = dt.datetime.now(dt.timezone.utc).date()
        self.assertEqual(days, [today - dt.timedelta(days=i) for i in (1, 2, 3)])


if __name__ == "__main__":
    unittest.main()
