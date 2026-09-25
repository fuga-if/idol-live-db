"""iTunes の呼び出しと名前の畳み方 (lib/itunes.py・lib/text.py) のテスト。

    python3 -m unittest discover -s tools/test -p 'test_*.py'

各ツールの関数の入出力を固定する (共有の部品に寄せても変わらないことの確認)。
iTunes の応答は Search API の応答と同じ形のものに差し替え、外へは出ない。
"""

import contextlib
import io
import json
import unittest
import urllib.request

import support
from lib import itunes, text

import apply_official_idol_order
import check_apple_music_links
import collect_solo_records
import collect_song_versions
import collect_unit_versions
import discover_new_songs
import fill_apple_music_ids
import fill_artwork_urls
import link_song_variants

# Search API の応答の形 (使う項目だけ)。
TRACK = {"wrapperType": "track", "kind": "song", "trackId": 1440000001, "trackName": "曲 (Ver.)",
         "artistName": "アイドル (CV: 声優)", "collectionName": "アルバム",
         "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/x/100x100bb.jpg",
         "releaseDate": "2026-01-01T12:00:00Z"}
RESPONSE = {"resultCount": 1, "results": [TRACK]}

INPUTS = ["所 恵美", "765PRO　ALLSTARS", "a\tb\nc", "Ａｂｃ　ｄ", "x y", "ｱｲﾄﾞﾙ ﾏｽﾀｰ"]


class TextRulesTest(unittest.TestCase):
    def check(self, fn, expected):
        self.assertEqual([fn(x) for x in INPUTS], expected)

    def test_squash_spaces(self):
        expected = ["所恵美", "765PROALLSTARS", "abc", "Ａｂｃｄ", "xy", "ｱｲﾄﾞﾙﾏｽﾀｰ"]
        for fn in (text.squash_spaces, collect_solo_records.squash, collect_song_versions.squash):
            self.check(fn, expected)

    def test_squash_spaces_lower(self):
        expected = ["所恵美", "765proallstars", "abc", "ａｂｃｄ", "xy", "ｱｲﾄﾞﾙﾏｽﾀｰ"]
        for fn in (text.squash_spaces_lower, collect_unit_versions.squash,
                   link_song_variants.normalize, check_apple_music_links.normalize):
            self.check(fn, expected)
        self.assertEqual(check_apple_music_links.normalize(None), "")

    def test_drop_spaces_lower_keeps_tabs_and_newlines(self):
        expected = ["所恵美", "765proallstars", "a\tb\nc", "ａｂｃｄ", "x y", "ｱｲﾄﾞﾙﾏｽﾀｰ"]
        for fn in (text.drop_spaces_lower, fill_apple_music_ids.normalize):
            self.check(fn, expected)
        self.assertEqual(fill_apple_music_ids.normalize(None), "")

    def test_nfkc_drop_spaces(self):
        expected = ["所恵美", "765PROALLSTARS", "a\tb\nc", "Abcd", "xy", "アイドルマスター"]
        for fn in (text.nfkc_drop_spaces, apply_official_idol_order.key):
            self.check(fn, expected)


class NormalizeForSearchTest(unittest.TestCase):
    """歌詞検索の正規化。Worker (imas-live-api/src/routes/lyrics.ts の normalizeForSearch) と同じ規則。

    ダミーの仮名と記号だけで確かめる (歌詞は使わない)。
    """

    CASES = [
        ("あいうゔゕゖ", "アイウヴヵヶ"),          # U+3041〜U+3096 はカタカナへ
        ("\u3040\u3097ゝゞーアイ", "\u3040\u3097ゝゞーアイ"),  # 範囲の外と、既にカタカナのものはそのまま
        ("ＡＢＣａｂｃ０１２！～", "abcabc012!~"),  # U+FF01〜U+FF5E は半角へ (英字は小文字)
        ("\uff00｟ｱｲ", "\uff00｟ｱｲ"),             # 範囲の外 (半角カナも広げない)
        ("ABC xyz", "abc xyz"),
    ]

    def test_cases(self):
        for given, expected in self.CASES:
            with self.subTest(given=given):
                self.assertEqual(text.normalize_for_search(given), expected)
                # 1 文字 → 1 文字 (検索は body_norm 上の位置で body から窓を切る)。
                self.assertEqual(len(text.normalize_for_search(given)), len(given))

    def test_the_backfill_tool_uses_the_same_function(self):
        import sys
        sys.path.insert(0, str(support.TOOLS / "lyrics"))
        import backfill_body_norm
        self.assertIs(backfill_body_norm.normalize, text.normalize_for_search)


class FakeUrlopen:
    def __init__(self, testcase, response=RESPONSE, error=None):
        self.requests = []
        self.response, self.error = response, error
        for obj in (urllib.request, itunes):
            testcase.addCleanup(setattr, obj, "urlopen", obj.urlopen)
            obj.urlopen = self

    def __call__(self, req, timeout=None):
        self.requests.append((req.full_url, req.get_header("User-agent"), timeout))
        if self.error:
            raise self.error
        return io.BytesIO(json.dumps(self.response).encode("utf-8"))


class ITunesClientsTest(unittest.TestCase):
    """ツールごとの URL・User-Agent・待ち時間・失敗の扱いを固定する。"""

    def test_fill_artwork_urls(self):
        http = FakeUrlopen(self)
        self.assertEqual(fill_artwork_urls.itunes_lookup("1440000001"), TRACK)
        self.assertEqual(http.requests, [(
            "https://itunes.apple.com/lookup?id=1440000001&country=jp", "ImasLiveDB-artwork/1.0", 10)])

    def test_check_apple_music_links(self):
        http = FakeUrlopen(self)
        self.addCleanup(setattr, check_apple_music_links.time, "sleep",
                        check_apple_music_links.time.sleep)
        check_apple_music_links.time.sleep = lambda seconds: None
        with contextlib.redirect_stderr(io.StringIO()):
            found = check_apple_music_links.fetch_tracks({"1440000001", "1440000002"})
        self.assertEqual(found, {"1440000001": TRACK})
        self.assertEqual(http.requests, [(
            "https://itunes.apple.com/lookup?country=jp&entity=song&limit=200&id=1440000001,1440000002",
            "ImasLiveDB/1.0", 60)])

    def test_failures_that_continue_with_nothing(self):
        FakeUrlopen(self, error=OSError("offline"))
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(discover_new_songs.itunes_search("曲"), [])
            self.assertEqual(fill_apple_music_ids.itunes_search("曲"), [])
            self.assertIsNone(fill_artwork_urls.itunes_lookup("1"))

    def test_failures_that_stop(self):
        FakeUrlopen(self, error=OSError("offline"))
        for call in (lambda: collect_unit_versions.itunes("曲"),
                     lambda: collect_song_versions.itunes_search("曲"),
                     lambda: collect_solo_records.itunes("search", term="曲")):
            with self.assertRaises(OSError):
                call()


class KrReleaseTest(unittest.TestCase):
    """THE IDOLM@STER.KR の盤は 765AS 等の曲に付けない (765as_dream が KR「Dream」を指していた)。"""

    KR = dict(TRACK, trackName="Dream", artistName="Real Girls Project(R.G.P)",
              collectionName="THE IDOLM@STER.KR MUSIC Episode1 - EP")
    AS = dict(TRACK, trackName="DREAM", artistName="THE IDOLM@STER",
              collectionName="THE IDOLM@STER BEST OF 765+876=!! VOL.02")

    def test_detects_kr_releases(self):
        self.assertTrue(itunes.is_kr_release(self.KR))
        self.assertTrue(itunes.is_kr_release(dict(TRACK, collectionName="THE IDOLM@STER.KR MUSIC Episode4")))
        self.assertFalse(itunes.is_kr_release(self.AS))
        self.assertFalse(itunes.is_kr_release({}))

    def test_fill_does_not_pick_a_kr_track_for_765as(self):
        kr = dict(self.KR, trackName="DREAM", artistName="THE IDOLM@STER.KR")
        self.assertIsNone(fill_apple_music_ids.pick("DREAM", "765as", [kr], []))
        self.assertIs(fill_apple_music_ids.pick("DREAM", "765as", [kr, self.AS], []), self.AS)

    def test_fill_still_picks_it_for_other(self):
        kr = dict(self.KR, trackName="One for all", artistName="Real Girls Project")
        self.assertIs(fill_apple_music_ids.pick("One for all", "other", [kr], ["realgirlsproject"]), kr)


class ArtworkTest(unittest.TestCase):
    URL100 = "https://example.com/a/100x100bb.jpg"
    URL60 = "https://example.com/a/60x60bb.jpg"

    def test_the_100px_url_is_enlarged(self):
        for fn in (itunes.artwork_600, collect_solo_records.artwork_url,
                   collect_song_versions.artwork_url, collect_unit_versions.artwork_url):
            self.assertEqual(fn({"artworkUrl100": self.URL100}), "https://example.com/a/600x600bb.jpg")

    def test_the_60px_fallback_is_used_only_where_it_was(self):
        only60 = {"artworkUrl60": self.URL60}
        self.assertEqual(collect_solo_records.artwork_url(only60), self.URL60)
        self.assertEqual(collect_song_versions.artwork_url(only60), self.URL60)
        self.assertEqual(collect_unit_versions.artwork_url(only60), "")
        self.assertEqual(itunes.artwork_600(only60), "")
        self.assertEqual(itunes.artwork_600(only60, fallback_60=True), self.URL60)


if __name__ == "__main__":
    unittest.main()
