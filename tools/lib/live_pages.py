"""live_pages.py — ライブの公式ページ (特設・公式ポータルのスケジュール/ニュース) を探して読む。

crawl_show_cast.py (出演者) と crawl_show_details.py (開演時刻・会場・特設 URL・価格) が使う。
標準ライブラリだけで書く。

- 特設: events.ticket_url の `https://idolmaster-official.jp/live_event/<slug>/` から、トップ・
  information/・cast/・member/・ticket/ を見る。
- ticket_url が無い催しは、公式ポータルの CMS API で探す。SCHEDULE (EVENT) は公演日と名前で、
  NEWS はイベントのブランドの直近の記事から名前で当てる。記事本文は
  `https://idolmaster-official.jp/news/<path>.html` (SSR 済み) を読む。
  CMS API のホストは変わることがある (memory: reference_imas_portal_cms_api)。
"""
from __future__ import annotations

import datetime as dt
import difflib
import html
import http.client
import json
import re
import unicodedata
import urllib.parse
import urllib.request

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) imas-live-db crawl"
PORTAL = "https://idolmaster-official.jp"
CMS = "https://cmsapi-frontend.idolmaster-official.jp/sitern/api"
LIVE_EVENT = re.compile(r"(https?://idolmaster-official\.jp/live_event/[^/?#]+/)")
SUBPAGES = ("", "information/", "cast/", "member/", "ticket/")
JST = dt.timezone(dt.timedelta(hours=9))
# DB の brand_id → CMS の brand コード。
CMS_BRANDS = {
    "765as": "IDOLMASTER", "961": "IDOLMASTER", "876": "OTHER", "cg": "CINDERELLAGIRLS",
    "ml": "MILLIONLIVE", "sidem": "SIDEM", "sc": "SHINYCOLORS", "gakuen": "GAKUEN", "other": "OTHER",
}


def fetch(url: str, depth: int = 0) -> str | None:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=20) as res:
            body = res.read().decode("utf-8", "replace")
    except (OSError, http.client.HTTPException, ValueError):
        return None
    m = re.search(r"""(?i)<meta[^>]+http-equiv=["']?refresh[^>]+url=([^"'>]+)""", body)
    if m and len(body) < 5000:
        return fetch(urllib.parse.urljoin(url, m[1].strip()), depth + 1) if depth < 3 else None
    return body


def html_to_lines(text: str) -> list[str]:
    text = re.sub(r"(?is)<(script|style|noscript)\b.*?</\1>", "", text)
    text = re.sub(r"(?s)<!--.*?-->", "", text)
    text = re.sub(r"(?i)<br[^>]*>", "\n", text)
    text = re.sub(r"(?i)</?(p|div|li|h\d|dt|dd|tr|td|th|ul|ol|dl|section|article|table)\b[^>]*>", "\n", text)
    text = re.sub(r"<[^>]+>", "", text)
    lines = (re.sub(r"\s+", " ", html.unescape(line)).strip() for line in text.split("\n"))
    return [line for line in lines if line]


def fold_title(text: str) -> str:
    """イベント名の照合用。NFKC・小文字にし、英数とかな漢字以外を落とす。"""
    text = unicodedata.normalize("NFKC", text).lower()
    return re.sub(r"[^0-9a-z぀-ヿ㐀-鿿@]", "", text)


# どの記事の題にも出てくる決まり文句。これが一致しただけで同じイベントとみなさないよう、比べる前に落とす。
BOILERPLATE = (
    "theidolm@ster", "idolm@ster", "学園アイドルマスター", "アイドルマスター", "shinycolors", "cinderellagirls",
    "millionlive", "sidem", "songforprism", "発売記念イベント", "production", "presents",
)


def _core(text: str) -> str:
    text = fold_title(text)
    for word in BOILERPLATE:
        text = text.replace(word, "")
    return text


def title_matches(event_name: str, title: str) -> bool:
    """記事の題が、このイベントのものか。決まり文句を除いて、共通の最長の塊がイベント名の 8 割以上。"""
    a, b = _core(event_name), _core(title)
    if not a or not b:
        return False
    # 年や回の数字 (KIMCHIKURA Fes '26 と '25 など) が題に無ければ別の回。
    if any(n not in b for n in re.findall(r"\d+", a)):
        return False
    if a in b or b in a:
        return True
    m = difflib.SequenceMatcher(None, a, b, autojunk=False).find_longest_match(0, len(a), 0, len(b))
    return m.size >= max(8, int(len(a) * 0.8))


class Cms:
    """公式ポータルの CMS API。取れなければ空を返す (日次を止めない)。"""

    def __init__(self, opener=None):
        self._open = opener or self._http
        self._token = None
        self._news: dict[str, list[dict]] = {}

    @staticmethod
    def _http(url: str) -> dict | None:
        body = fetch(url)
        try:
            return json.loads(body) if body else None
        except ValueError:
            return None

    def _list(self, category: str, brands: list[str], start=None, end=None, limit=1000) -> list[dict]:
        if self._token is None:
            got = self._open(f"{CMS}/cmsbase/Token/get") or {}
            self._token = (got.get("data") or {}).get("token") or ""
        if not self._token:
            return []
        data = {"category": [category], "brand": brands, "subcategory": []}
        if start:
            data["target_start_date"] = start
            data["target_end_date"] = end
        q = urllib.parse.urlencode({
            "site": "jp", "ip": "idolmaster", "token": self._token, "sort": "desc", "limit": limit,
            "data": json.dumps(data, ensure_ascii=False),
        })
        got = self._open(f"{CMS}/idolmaster/Article/list?{q}") or {}
        return (got.get("data") or {}).get("article_list") or []

    def schedule(self, dates: list[str]) -> list[dict]:
        """公演日の前後 1 日にかかる SCHEDULE の記事。"""
        lo = dt.date.fromisoformat(min(dates)) - dt.timedelta(days=1)
        hi = dt.date.fromisoformat(max(dates)) + dt.timedelta(days=1)
        return self._list("SCHEDULE", [], f"{lo.isoformat()}T00:00:00Z", f"{hi.isoformat()}T23:59:59Z")

    def news(self, brand_code: str) -> list[dict]:
        if brand_code not in self._news:
            self._news[brand_code] = self._list("NEWS", [brand_code])
        return self._news[brand_code]


def _jst_date(ts) -> str | None:
    try:
        return dt.datetime.fromtimestamp(int(ts), JST).date().isoformat()
    except (TypeError, ValueError, OverflowError, OSError):
        return None


def expand(url: str) -> list[str]:
    """特設のトップなら下のページも並べる。"""
    m = LIVE_EVENT.match(url)
    return [m[1] + p for p in SUBPAGES] if m else [url]


def event_pages(name: str, brands: list[str], dates: list[str], ticket_url: str | None,
                cms: Cms | None) -> list[str]:
    """このイベントの公式ページ候補 (読む順)。特設 → スケジュール → ニュース。"""
    urls: list[str] = []
    if ticket_url:
        urls += expand(ticket_url)
    if cms is not None and not (ticket_url and LIVE_EVENT.match(ticket_url)):
        for a in cms.schedule(dates):
            if _jst_date(a.get("event_startdate")) in dates and title_matches(name, a.get("title") or ""):
                if a.get("event_url"):
                    urls += expand(a["event_url"])
                if a.get("url"):
                    urls.append(a["url"])
        for code in dict.fromkeys(CMS_BRANDS.get(b, "OTHER") for b in brands):
            for a in cms.news(code):
                if a.get("path") and title_matches(name, a.get("title") or ""):
                    urls.append(f"{PORTAL}/news/{a['path']}.html")
    return list(dict.fromkeys(urls))


def special_site(urls: list[str]) -> str | None:
    """候補の中の特設のトップ (ticket_url に入れる値)。無ければ None。"""
    for u in urls:
        if m := LIVE_EVENT.match(u):
            return m[1]
    return None


# ---------------------------------------------------------------------------
# 見出し (日の切れ目) の読み方。出演者・開演時刻の両方で使う。
# ---------------------------------------------------------------------------

KANJI_NUM = {c: i for i, c in enumerate("〇一二三四五六七八九十")}
DAY_NO = re.compile(r"(?i)(?<![0-9A-Z])DAY\s*\.?\s*(\d+)|(?<!\d)(\d+)\s*日目")
# 第一公演・第2公演・第一回 (公演の通し番号。日番号とは別)
SHOW_NO = re.compile(r"第\s*([〇一二三四五六七八九十]+|\d+)\s*(?:公演|回)")
DATE = re.compile(r"(?:(\d{4})\s*[./年]\s*)?(\d{1,2})\s*[./月]\s*(\d{1,2})\s*日?")
WEEKDAY = re.compile(r"(?i)\b(sun|mon|tue|wed|thu|fri|sat)[a-z]*\b|[（(][日月火水木金土祝・･]+[)）]")
TIME_OF_DAY = ("昼", "夜", "マチネ", "ソワレ")


def _num(text: str) -> int:
    if text.isdigit():
        return int(text)
    if text == "十":
        return 10
    if text.startswith("十"):
        return 10 + KANJI_NUM[text[1]]
    if "十" in text:
        tens, _, ones = text.partition("十")
        return KANJI_NUM[tens] * 10 + (KANJI_NUM[ones] if ones else 0)
    return KANJI_NUM.get(text, 0)


def is_header(line: str) -> bool:
    """日の切れ目の見出しか。DAY1 / 2日目 / 第一公演 / 昼公演 / 2.27 Sat / 2027年2月27日(土) など。"""
    if len(line) > 30 or "役" in line or "Update" in line:
        return False
    if DAY_NO.search(line) or SHOW_NO.search(line):
        return True
    if re.fullmatch(r"(昼|夜)(公演|の部)?|マチネ|ソワレ|第\s*\d\s*部", line.replace(" ", "")):
        return True
    if DATE.search(line):
        rest = WEEKDAY.sub("", DATE.sub("", line))
        rest = re.sub(r"[\s.・\-－―~〜～()（）]|ご?出演|公演", "", rest)
        return len(rest) <= 2
    return False


def header_hint(headers: list[str], year_hint: int):
    """見出しから (日番号, 日付, 昼/夜, 公演番号) を取る。同じ種類が 2 つ以上の値を指すなら None (曖昧)。"""
    days, dates, tods, nos = set(), set(), set(), set()
    for h in headers:
        for m in DAY_NO.finditer(h):
            days.add(int(m[1] or m[2]))
        for m in SHOW_NO.finditer(h):
            nos.add(_num(m[1]))
        for m in DATE.finditer(h):
            try:
                dates.add(dt.date(int(m[1]) if m[1] else year_hint, int(m[2]), int(m[3])))
            except ValueError:
                pass
        tods |= {t for t in TIME_OF_DAY if t in h}
    if max(len(days), len(dates), len(tods), len(nos)) > 1:
        return None
    return tuple(next(iter(s), None) for s in (days, dates, tods, nos))
