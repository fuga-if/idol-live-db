#!/usr/bin/env python3
"""petitlyrics_check.py — プチリリの歌詞と手元の歌詞を突き合わせ、差分を報告する。

取り込み元由来の誤り (♡ 等の記号の欠落、中国語行の表記崩れ) を洗い出すための
**照合専用**ツール。本文の自動書き換えはしない。差分を出すところまでで、
直すかどうかは人が判断する。

    python3 tools/lyrics/petitlyrics_check.py search --limit 50
    python3 tools/lyrics/petitlyrics_check.py fetch
    python3 tools/lyrics/petitlyrics_check.py diff

出力 (いずれも gitignore 済み):
    lyrics_local/petitlyrics/candidates.tsv   song_id / petit_id / title / artist / confidence / note
    lyrics_local/petitlyrics/<song_id>.json   取得した本文のキャッシュ
    tools/lyrics/out/petitlyrics_report.tsv   差分レポート

--------------------------------------------------------------------------
プチリリの歌詞取得について (2026-09-04 に実測)
--------------------------------------------------------------------------
本文は `<canvas id="lyrics">` に描かれるので HTML には載っていない。データは

    POST /com/get_lyrics.ajax   (form: lyrics_id=<id>)
    → [{"lyrics": "<base64 UTF-8>"}, ...]   1要素 = 1行、空行は ""

が返す。暗号化はされておらず base64 のみ。ただし **3点の罠**がある:

1. `X-CSRF-Token` が要る。トークンはページ HTML ではなく、セッションごとに
   生成される `/lib/pl-lib.js?<timestamp>` の中に `$(document).ajaxSend(...)` として
   書かれている。ページを GET → そこに書かれた pl-lib.js の URL を GET →
   32桁の hex を取り出す、という順で拾う。

2. **ヘッダ名の大文字小文字が区別される。** `X-CSRF-Token` でなければ 400 が返る。
   `urllib.request` は送信時に必ず `.title()` を掛けて `X-Csrf-Token` にしてしまうので、
   **urllib では原理的に成功しない**。ここで `http.client` を直に使っているのはこのため。
   (curl で通るのに urllib で 400 になる、という形で現れる)

3. Cookie (`PLSESSION`) をページ取得時から引き回す必要がある。

robots.txt は 404 (= 記述なし)。それでも 1リクエスト 1.5秒以上・同時1接続を守る。
"""

import argparse
import base64
import gzip
import html as html_mod
import http.client
import io
import json
import os
import re
import socket
import sqlite3
import subprocess
import sys
import time
import unicodedata
from difflib import SequenceMatcher

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

# 曲名照合・アイマス語彙の判定は link_verify と同じものを使う。
# 「同名の別曲を掴まない」という判定条件はリンク収集とまったく同じ問題なので、
# ここで別の実装を持つと二つの基準がずれる。
from link_verify import base_title, load_vocab, norm  # noqa: E402

DEFAULT_DB = os.path.join(REPO, "ImasLiveDB", "Resources", "master.sqlite")
LOCAL_LYRICS_DIR = os.path.join(REPO, "lyrics_local", "lyrics")
CACHE_DIR = os.path.join(REPO, "lyrics_local", "petitlyrics")
CANDIDATES_TSV = os.path.join(CACHE_DIR, "candidates.tsv")
PAGES_DIR = os.path.join(CACHE_DIR, "pages")
ARTISTS_JSON = os.path.join(CACHE_DIR, "artists.json")
PUBLISHED_JSON = os.path.join(CACHE_DIR, "published.json")
OUT_DIR = os.path.join(HERE, "out")
REPORT_TSV = os.path.join(OUT_DIR, "petitlyrics_report.tsv")

HOST = "petitlyrics.com"
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")

MIN_INTERVAL = 1.5   # 礼儀: 1リクエストあたり最低この秒数を空ける
MAX_TRIES = 5

CANDIDATE_COLS = ["song_id", "petit_id", "title", "artist", "confidence", "note"]
REPORT_COLS = ["song_id", "title", "verdict", "local_lines", "petit_lines",
               "petit_id", "ndiff", "kinds", "examples"]


# --------------------------------------------------------------------------
# HTTP (礼儀つき)
# --------------------------------------------------------------------------

class PetitLyrics(object):
    """プチリリへの直列アクセス。1接続・1.5秒間隔・指数バックオフ。"""

    def __init__(self, verbose=True, min_interval=MIN_INTERVAL):
        self.min_interval = min_interval
        self.last_poster = ""
        self.conn = None
        self.cookie = ""
        self.token = ""
        self.last_request = 0.0
        self.verbose = verbose
        self.robots_note = ""

    # -- 低レベル -----------------------------------------------------------

    def _connect(self):
        if self.conn is None:
            self.conn = http.client.HTTPSConnection(HOST, timeout=30)

    def _close(self):
        if self.conn is not None:
            try:
                self.conn.close()
            finally:
                self.conn = None

    def _throttle(self):
        wait = self.min_interval - (time.time() - self.last_request)
        if wait > 0:
            time.sleep(wait)
        self.last_request = time.time()

    def request(self, method, path, body=None, extra=None, allow=(200,)):
        """1リクエスト。allow に無いステータスと通信エラーは指数バックオフで再試行。

        戻り値は (status, headers, body_bytes)。再試行を使い切ったら最後の結果を返す。
        """
        headers = {
            "User-Agent": UA,
            "Accept": "*/*",
            "Accept-Language": "ja,en;q=0.8",
            "Connection": "keep-alive",
        }
        if self.cookie:
            headers["Cookie"] = self.cookie
        if extra:
            headers.update(extra)

        delay = 2.0
        last = (0, [], b"")
        for attempt in range(1, MAX_TRIES + 1):
            self._throttle()
            try:
                self._connect()
                self.conn.request(method, path, body=body, headers=headers)
                resp = self.conn.getresponse()
                data = resp.read()
                last = (resp.status, resp.getheaders(), data)
                if resp.status in allow:
                    return last
                # 4xx はこちらの組み立てが悪いので、待っても直らない。
                # 429 と 5xx だけ待って試し直す。
                if resp.status != 429 and resp.status < 500:
                    return last
            except (http.client.HTTPException, socket.error, OSError) as exc:
                last = (0, [], str(exc).encode())
                self._close()

            if attempt < MAX_TRIES:
                if self.verbose:
                    sys.stderr.write("  retry %d/%d (%ds待機) %s\n"
                                     % (attempt, MAX_TRIES - 1, int(delay), path))
                time.sleep(delay)
                delay *= 2
        return last

    # -- セッション ---------------------------------------------------------

    def check_robots(self):
        """robots.txt を取得して、こちらが使うパスが禁止されていないか確かめる。

        戻り値は (許可か, 説明文)。404 = 記述なし = 制限なし。
        """
        status, _, data = self.request("GET", "/robots.txt", allow=(200, 404))
        if status == 404:
            self.robots_note = "robots.txt: 404 (記述なし。Disallow は存在しない)"
            return True, self.robots_note
        if status != 200:
            self.robots_note = "robots.txt: HTTP %d (取得できず)" % status
            return False, self.robots_note

        text = data.decode("utf-8", "replace")
        # 素朴に User-agent: * のブロックだけ読む。ここで使うのは
        # /lyrics/, /search_lyrics, /com/get_lyrics.ajax, /lib/ の4種。
        disallow, applies = [], False
        for line in text.splitlines():
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            key, _, value = line.partition(":")
            key, value = key.strip().lower(), value.strip()
            if key == "user-agent":
                applies = value == "*"
            elif key == "disallow" and applies and value:
                disallow.append(value)

        used = ["/lyrics/", "/search_lyrics", "/com/get_lyrics.ajax", "/lib/"]
        hits = [(p, d) for p in used for d in disallow if p.startswith(d)]
        if hits:
            self.robots_note = ("robots.txt: 使用パスが Disallow に該当 → %s"
                                % ", ".join("%s (%s)" % h for h in hits))
            return False, self.robots_note
        self.robots_note = ("robots.txt: 取得できた。Disallow %d件、使用パスは非該当"
                            % len(disallow))
        return True, self.robots_note

    def start_session(self, seed_path="/lyrics/2643638"):
        """Cookie と CSRF トークンを用意する。

        トークンはページ HTML ではなく、ページが読み込む pl-lib.js の中にある。
        """
        status, headers, data = self.request("GET", seed_path)
        if status != 200:
            raise RuntimeError("セッション開始に失敗: %s → HTTP %d" % (seed_path, status))
        self.cookie = "; ".join(v.split(";", 1)[0]
                                for k, v in headers if k.lower() == "set-cookie")
        page = data.decode("utf-8", "replace")
        m = re.search(r'src="(/lib/pl-lib\.js\?[0-9]+)"', page)
        if not m:
            raise RuntimeError("pl-lib.js の参照が見つからない (ページ構成が変わった?)")
        status, _, js = self.request("GET", html_mod.unescape(m.group(1)))
        if status != 200:
            raise RuntimeError("pl-lib.js の取得に失敗: HTTP %d" % status)
        m = re.search(rb"X-CSRF-Token'\s*,\s*'([0-9a-f]{32})'", js)
        if not m:
            raise RuntimeError("pl-lib.js に CSRF トークンが無い (ページ構成が変わった?)")
        self.token = m.group(1).decode()
        return self.token

    # -- 用途別 -------------------------------------------------------------

    def get_page(self, path):
        status, _, data = self.request("GET", path, allow=(200, 404))
        if status != 200:
            return None
        return data.decode("utf-8", "replace")

    def get_lyrics(self, petit_id):
        """本文の行リストを返す。失敗したら None。

        ブラウザと同じく、まず歌詞ページを開いてから ajax を叩く。
        """
        page = self.get_page("/lyrics/%d" % petit_id)
        if page is None:
            return None, None
        title = ""
        m = re.search(r"<title>(.*?)</title>", page, re.S)
        if m:
            title = html_mod.unescape(m.group(1)).strip()
        m = POSTER_RE.search(html_mod.unescape(page))
        self.last_poster = m.group(1).strip() if m else ""

        for attempt in (1, 2):
            if not self.token:
                self.start_session("/lyrics/%d" % petit_id)
            status, _, data = self.request(
                "POST", "/com/get_lyrics.ajax",
                body="lyrics_id=%d" % petit_id,
                allow=(200,),
                extra={
                    "X-Requested-With": "XMLHttpRequest",
                    # 大文字小文字が区別される。urllib では送れない (冒頭の注記)。
                    "X-CSRF-Token": self.token,
                    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                    "Referer": "https://%s/lyrics/%d" % (HOST, petit_id),
                })
            if status == 200:
                break
            # トークンが古い / セッションが切れた場合は一度だけ取り直す。
            if attempt == 1:
                self.token = ""
                continue
            return None, title

        try:
            rows = json.loads(data.decode("utf-8"))
        except ValueError:
            return None, title
        lines = []
        for row in rows:
            raw = row.get("lyrics") or ""
            try:
                lines.append(base64.b64decode(raw).decode("utf-8"))
            except Exception:
                lines.append("")
        return lines, title

    def search(self, title):
        """曲名検索。戻り値は (status, results)。

        status は "ok" / "throttled" / "error"。
        **"throttled" を "見つからなかった" と混同してはいけない** (下の注記)。
        """
        from urllib.parse import quote
        page = self.get_page("/search_lyrics?title=%s" % quote(title))
        if page is None:
            return "error", []
        # プチリリは日本語を数値文字参照で吐く (「件見つかりました」は生 HTML には
        # 現れず &#20214;... になっている)。目印の判定は必ず unescape してから。
        text = html_mod.unescape(page)
        if THROTTLE_RE.search(text):
            return "throttled", []
        # 「N 件見つかりました」が結果ページ、「検索結果がありません」が0件ページ。
        # **0件ページを見落とすと遮断と誤判定して走行が止まる** (実測: Don't U Worry で
        # 4件目に停止し、遮断されていないのに打ち切っていた)。どちらでもなければ
        # 想定外のページなので error。
        if not FOUND_COUNT_RE.search(text) and not NO_RESULT_RE.search(text):
            return "error", []
        return "ok", parse_search_results(page)


# 検索ページのアクセス制限。プチリリは 403 でも空リストでもなく、
# **200 で「一時的に非表示」と書いたページ**を返す。これを 0件と読むと
# 「検索したが見つからなかった」という誤った記録が候補表に残り、その曲は
# 二度と調査されない。必ず区別して止めること。
THROTTLE_RE = re.compile(r"歌詞検索ページへのアクセスが多いため")
FOUND_COUNT_RE = re.compile(r"件見つかりました")
NO_RESULT_RE = re.compile(r"検索結果がありません")

SEARCH_ROW_RE = re.compile(
    r'<a href="/lyrics/(\d+)"><span class="lyrics-list-title">(.*?)</span></a>'
    r'.*?<span class="lyrics-list-artist">(.*?)</span>'
    r'(?:.*?<span class="lyrics-list-album">(.*?)</span>)?',
    re.S)


def parse_search_results(page):
    out = []
    for m in SEARCH_ROW_RE.finditer(page):
        pid = int(m.group(1))
        title = html_mod.unescape(m.group(2) or "").strip()
        artist = html_mod.unescape(m.group(3) or "").strip()
        album = html_mod.unescape(m.group(4) or "").strip()
        out.append((pid, title, artist, album))
    return out


# --------------------------------------------------------------------------
# TSV
# --------------------------------------------------------------------------

def read_tsv(path, cols):
    if not os.path.exists(path):
        return []
    rows = []
    with io.open(path, encoding="utf-8") as f:
        header = f.readline().rstrip("\n").split("\t")
        for line in f:
            if not line.strip():
                continue
            values = line.rstrip("\n").split("\t")
            values += [""] * (len(header) - len(values))
            row = dict(zip(header, values))
            rows.append({c: row.get(c, "") for c in cols})
    return rows


def write_tsv(path, cols, rows):
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with io.open(path, "w", encoding="utf-8") as f:
        f.write("\t".join(cols) + "\n")
        for r in rows:
            f.write("\t".join(clean_cell(r.get(c, "")) for c in cols) + "\n")


def clean_cell(value):
    return str(value).replace("\t", " ").replace("\n", " ").replace("\r", " ")


# --------------------------------------------------------------------------
# 対象曲の並び (公開済み × 披露回数の多い順)
# --------------------------------------------------------------------------

def load_published(refresh=False):
    """D1 の song_lyrics で status='published' の song_id。結果はキャッシュする。"""
    if not refresh and os.path.exists(PUBLISHED_JSON):
        with io.open(PUBLISHED_JSON, encoding="utf-8") as f:
            return json.load(f)

    api_dir = os.path.join(REPO, "imas-live-api")
    cmd = ["npx", "wrangler", "d1", "execute", "imas-live-db", "--remote", "--json",
           "--command", "select song_id from song_lyrics where status='published'"]
    sys.stderr.write("D1 から公開済み曲を取得中 (時間がかかる)...\n")
    proc = subprocess.run(cmd, cwd=api_dir, capture_output=True, text=True, timeout=600)
    if proc.returncode != 0:
        raise RuntimeError("wrangler が失敗した:\n%s" % proc.stderr[-2000:])
    start = proc.stdout.index("[")
    payload = json.loads(proc.stdout[start:])
    ids = [r["song_id"] for r in payload[0]["results"]]
    os.makedirs(CACHE_DIR, exist_ok=True)
    with io.open(PUBLISHED_JSON, "w", encoding="utf-8") as f:
        json.dump(ids, f, ensure_ascii=False)
    return ids


def load_song_meta(db_path, song_ids):
    """song_id -> (title, singer_label, 披露回数)。披露回数の多い順に並べて返す。"""
    conn = sqlite3.connect("file:%s?mode=ro" % db_path, uri=True)
    titles = {r[0]: (r[1] or "", r[2] or "")
              for r in conn.execute("SELECT id, title, singer_label FROM songs")}
    counts = {r[0]: r[1] for r in conn.execute(
        "SELECT song_id, COUNT(*) FROM setlist_items GROUP BY song_id")}
    conn.close()

    rows = []
    for sid in song_ids:
        if sid not in titles:
            continue
        title, singer = titles[sid]
        rows.append({"song_id": sid, "title": title, "singer": singer,
                     "plays": counts.get(sid, 0)})
    rows.sort(key=lambda r: (-r["plays"], r["song_id"]))
    return rows


# --------------------------------------------------------------------------
# 照合用の正規化
# --------------------------------------------------------------------------

def nl(text):
    """行の比較キー。NFKC で幅を揃え、空白をすべて落とす。

    プチリリ側は行内の空け方がこちらと違うことが多いが、それは表記の違いであって
    歌詞の違いではないので、空白は最初から見ない。
    """
    text = unicodedata.normalize("NFKC", text or "")
    return "".join(ch for ch in text if not ch.isspace())


def letters(text):
    """記号を落として文字と数字だけにしたもの (link_verify.norm と同じ規則)。

    `nl` は違うのに `letters` が同じ = **記号だけの差** (♡ の欠落など)。
    今回の調査で拾いたいのはまさにこれ。
    """
    return norm(text)


def local_lines(song_id):
    """手元の歌詞の lyric 行。無ければ None。"""
    path = os.path.join(LOCAL_LYRICS_DIR, "%s.json" % song_id)
    if not os.path.exists(path):
        return None
    with io.open(path, encoding="utf-8") as f:
        data = json.load(f)
    return [ln.get("text", "") for ln in data.get("lines", [])
            if ln.get("kind") == "lyric"]


# --------------------------------------------------------------------------
# search
# --------------------------------------------------------------------------

def judge_candidates(song, results, vocab, leading_vocab):
    """検索結果から最良の候補を選ぶ。戻り値は (petit_id, title, artist, confidence, note)。

    判定は link_verify と同じ2条件 — 曲名が一致し、かつ歌手名にアイマス関連の
    固有名詞が含まれること。片方だけなら low に落として人が見る。
    """
    want = norm(song["title"])
    base = norm(base_title(song["title"]))

    scored = []
    for pid, title, artist, album in results:
        tn = norm(title)
        if not tn:
            continue
        exact = bool(want) and tn == want
        loose = bool(want) and (want in tn or tn in want)
        based = bool(base) and (base in tn or tn in base)
        if not (exact or loose or based):
            continue

        artist_n = norm(artist)
        hits = [v for v in vocab if v and v in artist_n]
        if not hits:
            hits = [v for v in leading_vocab if v and artist_n.startswith(v)]
        # 曲名がぴったり一致 > 版名つき、語彙が当たる > 当たらない、の順で選ぶ。
        scored.append(((1 if hits else 0, 1 if exact else 0, -pid),
                       pid, title, artist, bool(hits)))

    if not scored:
        return None, "", "", "none", "検索結果に曲名の一致が無い (%d件中)" % len(results)

    scored.sort(key=lambda s: s[0], reverse=True)
    _, pid, title, artist, has_vocab = scored[0]
    alts = len(scored) - 1
    if has_vocab:
        note = "曲名一致 + 歌手名にアイマス語彙"
        conf = "high"
    else:
        note = "曲名は一致するが歌手名にアイマス語彙が無い (同名別曲の疑い)"
        conf = "low"
    if alts:
        note += " / 他候補 %d件" % alts
    return pid, title, artist, conf, note


def cmd_search(args):
    client = PetitLyrics()
    ok, note = client.check_robots()
    print(note)
    if not ok:
        print("robots.txt が使用パスを禁じている。中止する。")
        return 1

    existing = read_tsv(CANDIDATES_TSV, CANDIDATE_COLS)
    done = {r["song_id"] for r in existing}

    if args.targets:
        # 対象曲を外から渡す経路。採用条件は list --targets と同じ厳しい方 (match_target)。
        songs = load_targets(args.targets)
        todo = [s for s in songs if s["song_id"] not in done][args.offset:][:args.limit]
        print("対象 %d曲 (指定リスト) / 今回 %d曲\n" % (len(songs), len(todo)))
    else:
        published = load_published(refresh=args.refresh_published)
        songs = load_song_meta(args.db, published)
        print("公開済み %d曲 / master に存在 %d曲" % (len(published), len(songs)))
        window = songs[args.offset:]
        todo = [s for s in window if s["song_id"] not in done][:args.limit]
        if todo:
            print("今回の対象: %d曲 (披露回数 %d〜%d回)\n"
                  % (len(todo), todo[0]["plays"], todo[-1]["plays"]))
    if not todo:
        print("対象なし (この範囲は調査済み)")
        return 0

    vocab, leading_vocab = load_vocab(args.db)
    client.start_session()

    added = []
    stopped = ""
    for i, song in enumerate(todo, 1):
        status, results = client.search(song["title"])
        if status != "ok":
            # 制限に当たったら**そこで止める**。ここで none を記録すると
            # 「調査済みだが見つからなかった」ことになって次回から漏れる。
            stopped = ("検索ページのアクセス制限に当たった (%s)。%d曲で打ち切る。\n"
                       "  プチリリの表示: 「歌詞検索ページへのアクセスが多いため一時的に"
                       "非表示にしています。しばらく経ってからアクセスして下さい。」\n"
                       "  時間を置いてから同じコマンドを再実行すれば続きから進む。"
                       % (status, len(added)))
            break
        if args.targets:
            # 曲名完全一致 + 歌唱名がアーティストに含まれる、の2条件だけ。
            hits = match_target(song, results)
            if not hits:
                print("[%3d/%d] %-9s %-28s → 採用できる候補なし (%d件中)"
                      % (i, len(todo), "none", song["title"][:26], len(results)))
                added.append({"song_id": song["song_id"], "petit_id": "",
                              "title": "", "artist": "", "confidence": "none",
                              "note": "検索したが採用条件に通る候補なし"})
                if args.interval:
                    time.sleep(args.interval)
                continue
            pid, ptitle, partist, _ = hits[0]
            conf, note = "high", "歌ネットに無し・プチリリ由来 (検索)"
            if len(hits) > 1:
                note += " / 他候補 %d件" % (len(hits) - 1)
        else:
            pid, ptitle, partist, conf, note = judge_candidates(
                song, results, vocab, leading_vocab)
        added.append({
            "song_id": song["song_id"],
            "petit_id": str(pid) if pid else "",
            "title": ptitle,
            "artist": partist,
            "confidence": conf,
            "note": note,
        })
        print("[%3d/%d] %-9s %-28s → %s"
              % (i, len(todo), conf, song["title"][:26], ptitle[:34] or note))
        if args.interval:
            time.sleep(args.interval)

    write_tsv(CANDIDATES_TSV, CANDIDATE_COLS, existing + added)
    if stopped:
        print("\n" + stopped)
    counts = {}
    for r in added:
        counts[r["confidence"]] = counts.get(r["confidence"], 0) + 1
    print("\n%s に %d件追記" % (CANDIDATES_TSV, len(added)))
    for k, v in sorted(counts.items(), key=lambda kv: -kv[1]):
        print("  %-6s %d" % (k, v))
    return 0


# --------------------------------------------------------------------------
# fetch
# --------------------------------------------------------------------------

def cache_path(song_id):
    return os.path.join(CACHE_DIR, "%s.json" % song_id)


def cmd_fetch(args):
    rows = [r for r in read_tsv(CANDIDATES_TSV, CANDIDATE_COLS)
            if r["confidence"] == "high" and r["petit_id"]]
    if args.only:
        rows = [r for r in rows if r["song_id"] == args.only]
    todo = [r for r in rows if not os.path.exists(cache_path(r["song_id"]))]
    if args.limit:
        todo = todo[:args.limit]
    print("high %d件 / 未取得 %d件" % (len(rows), len(todo)))
    if not todo:
        return 0

    client = PetitLyrics()
    ok, note = client.check_robots()
    print(note)
    if not ok:
        print("robots.txt が使用パスを禁じている。中止する。")
        return 1
    client.start_session()

    os.makedirs(CACHE_DIR, exist_ok=True)
    failed = 0
    for i, row in enumerate(todo, 1):
        pid = int(row["petit_id"])
        lines, page_title = client.get_lyrics(pid)
        if lines is None:
            failed += 1
            print("[%3d/%d] FAIL %s (petit %d)" % (i, len(todo), row["song_id"], pid))
            continue
        payload = {
            "song_id": row["song_id"],
            "petit_id": pid,
            "petit_title": row["title"],
            "petit_artist": row["artist"],
            "page_title": page_title,
            "poster": client.last_poster,
            "fetched_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "lines": lines,
        }
        with io.open(cache_path(row["song_id"]), "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=1)
        print("[%3d/%d] %4d行 %s" % (i, len(todo), len(lines), row["song_id"]))
    print("\n取得 %d件 / 失敗 %d件 → %s" % (len(todo) - failed, failed, CACHE_DIR))
    return 0


# --------------------------------------------------------------------------
# diff
# --------------------------------------------------------------------------

def shorten(text, width=34):
    text = clean_cell(text)
    return text if len(text) <= width else text[:width] + "…"


# 全体の一致率がこれを下回ったら、書き起こしの誤りではなく
# 別バージョン (尺違い・追加詞) を掴んでいる疑いが強い。
DIFFERENT_VERSION_RATIO = 0.9


def compare(local, petit):
    """本文を突き合わせて (verdict, 差分件数, 例のリスト) を返す。

    **行単位では比較しない。** プチリリはカラオケ同期サイトなので、1行が
    同期の単位で切られている。「ほら見て　ステキな出会いの予感の青い空」が
    こちらでは1行、あちらでは2行、というだけの違いが大量に出て、本当に見たい
    記号や文字の誤りがその中に埋もれる。

    そこで**空白を落として全行を連結した1本の文字列**として比べる。行の切り方の
    違いは最初から消え、残るのは文字と記号の違いだけになる。

      letters が一致  かつ 本文が不一致 → 記号だけの差 (♡ の欠落など。今回の主目的)
      letters も不一致                  → 文字の差
      一致率が低い                      → そもそも別バージョンの疑い
    """
    a = "".join(nl(x) for x in local)
    b = "".join(nl(x) for x in petit)
    if a == b:
        return "一致", 0, [], []

    matcher = SequenceMatcher(None, a, b, autojunk=False)
    if matcher.ratio() < DIFFERENT_VERSION_RATIO:
        verdict = "大差"
    elif letters(a) == letters(b):
        verdict = "記号差のみ"
    else:
        verdict = "文字差"

    ctx = 12
    examples, ndiff, kinds = [], 0, []
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            continue
        ndiff += 1
        mine, theirs = a[i1:i2], b[j1:j2]
        kind = classify(mine, theirs, a, b, i1, j1)
        kinds.append(kind)
        examples.append("[%s] 手元…%s… / プチリリ…%s…"
                        % (kind,
                           shorten(a[max(0, i1 - ctx):i2 + ctx], 60),
                           shorten(b[max(0, j1 - ctx):j2 + ctx], 60)))
    return verdict, ndiff, examples, kinds


# 差分の仕分け。**どちらが正しいかは判定しない** — 人が見るときの当たりを付けるだけ。
# プチリリ側の ♪ (単独・連続とも) はカラオケ同期用の間奏記号であって歌詞ではない。
# 補完の対象にしないので、手元の欠落とは別枠にする (☆ や ! は対象のまま)。
INTERLUDE_MARK = "♪"

RUBY_RE = re.compile(r"^[(（][^)）]{1,8}[)）]$")
CALL_CHARS = "!！?？♪♡★☆〜~・"
KANA_RE = re.compile(r"^[ぁ-んァ-ヶー]+$")
HAN_RE = re.compile(r"[一-龥]")


def classify(mine, theirs, a, b, i, j):
    """1つの差分を仕分ける。

    記号欠落 / 漢字かな / ルビ / コール / プチリリ側誤字 / 不明 の6分類。
    """
    ml, tl = letters(mine), letters(theirs)

    # 片方が空 = 一方にしか無い塊。
    if not mine or not theirs:
        extra = theirs or mine
        if RUBY_RE.match(extra):
            return "ルビ"
        if not mine and set(extra) == {INTERLUDE_MARK}:
            return "間奏記号(無視)"
        if extra and all(c in CALL_CHARS for c in extra):
            # **向きが肝心。** プチリリ側にあって手元に無い記号こそ、
            # 今回探している「取り込み時に落ちた ♡」の候補。
            return "記号欠落(手元)" if not mine else "記号余分(手元)"
        # 掛け声は括弧か記号で囲まれた短い塊であることが多い。
        if len(extra) <= 12 and (extra.startswith("(") or extra.startswith("（")
                                 or extra[-1:] in "!！"):
            return "コール"
        return "不明"

    # 文字と数字が同じ = 記号だけの違い。向きを見て分ける。
    if ml == tl:
        sym_mine = {c for c in mine if not c.isalnum()}
        sym_theirs = {c for c in theirs if not c.isalnum()}
        if sym_theirs - sym_mine == {INTERLUDE_MARK} and not sym_mine - sym_theirs:
            return "間奏記号(無視)"
        if sym_theirs - sym_mine and not sym_mine - sym_theirs:
            return "記号欠落(手元)"
        if sym_mine - sym_theirs and not sym_theirs - sym_mine:
            return "記号余分(手元)"
        return "記号差"

    # 片方が漢字、もう片方が同じ読みのかな、という形。
    if (HAN_RE.search(mine) and KANA_RE.match(theirs)) or \
       (HAN_RE.search(theirs) and KANA_RE.match(mine)):
        return "漢字かな"

    # 1文字だけ違う & 長さが同じ = 打ち間違いの形 (ENTERTAINMEN / 理田 など)。
    if len(ml) == len(tl) and sum(1 for x, y in zip(ml, tl) if x != y) == 1:
        return "プチリリ側誤字"
    if abs(len(ml) - len(tl)) == 1 and min(len(ml), len(tl)) >= 3:
        longer, shorter = (ml, tl) if len(ml) > len(tl) else (tl, ml)
        if shorter in longer:
            # 1文字の脱落。手元にあってプチリリに無いなら向こうの脱字。
            return "プチリリ側誤字" if len(ml) > len(tl) else "手元の欠落疑い"
    return "不明"


def cmd_diff(args):
    candidates = {r["song_id"]: r for r in read_tsv(CANDIDATES_TSV, CANDIDATE_COLS)}
    song_ids = [args.only] if args.only else sorted(candidates)

    conn = sqlite3.connect("file:%s?mode=ro" % args.db, uri=True)
    titles = {r[0]: r[1] for r in conn.execute("SELECT id, title FROM songs")}
    conn.close()

    rows, counts = [], {}
    for sid in song_ids:
        cand = candidates.get(sid, {})
        title = titles.get(sid, "")
        mine = local_lines(sid)
        path = cache_path(sid)

        if not os.path.exists(path):
            verdict = "候補なし" if cand.get("confidence") != "high" else "未取得"
            rows.append({"song_id": sid, "title": title, "verdict": verdict,
                         "local_lines": len(mine) if mine else 0, "petit_lines": 0,
                         "petit_id": cand.get("petit_id", ""), "ndiff": "",
                         "kinds": "", "examples": cand.get("note", "")})
            counts[verdict] = counts.get(verdict, 0) + 1
            continue

        with io.open(path, encoding="utf-8") as f:
            cached = json.load(f)
        theirs = [x for x in cached.get("lines", []) if nl(x)]
        if mine is None:
            verdict, ndiff, examples, kinds = "手元に歌詞なし", "", [], []
        else:
            verdict, ndiff, examples, kinds = compare(mine, theirs)

        rows.append({
            "song_id": sid, "title": title, "verdict": verdict,
            "local_lines": len(mine) if mine else 0, "petit_lines": len(theirs),
            "petit_id": cached.get("petit_id", ""), "ndiff": ndiff,
            "kinds": ",".join("%s*%d" % (k, kinds.count(k))
                              for k in sorted(set(kinds))),
            "examples": " | ".join(examples[:args.examples]),
        })
        counts[verdict] = counts.get(verdict, 0) + 1

    order = {"記号差のみ": 0, "文字差": 1, "大差": 2, "一致": 3}
    rows.sort(key=lambda r: (order.get(r["verdict"], 9), r["song_id"]))
    write_tsv(REPORT_TSV, REPORT_COLS, rows)

    print("%d曲を判定 → %s\n" % (len(rows), REPORT_TSV))
    for k, v in sorted(counts.items(), key=lambda kv: (order.get(kv[0], 9), kv[0])):
        print("  %-10s %d" % (k, v))
    return 0


# --------------------------------------------------------------------------
# list — 一覧ページ経由で petit_id を集める (検索ページを使わない経路)
# --------------------------------------------------------------------------
#
# 検索ページ (/search_lyrics) は数件で長時間の制限に入るので、候補集めには使えない。
# 代わりに**アーティスト歌詞一覧**を辿る。制限に入らないことを実測で確認済み。
#
#   /syllabary/<kana>.html      アーティスト50音索引。1ページに数千件の
#                               (artist_id, アーティスト名) が載っている。全71ページ。
#   /lyrics/artist/<id>         そのアーティストの歌詞一覧 (10件/ページ)
#   /lyrics/artist/<id>/<n>-1.html   その2ページ目以降
#
# アルバム一覧 (/lyrics/album/<アルバム名の UTF-8 hex>) も同じ形式で使えるが、
# master.sqlite の cd_title は公開曲 3,153 件中 378 件しか埋まっておらず、
# 中身も "…シリーズ#MS2P" のような内部表記なのでアルバム名として使えない。
# 一方 singer_label は 2,386 件埋まっているので、アーティスト経路を採る。

SYLLABARY = (
    "a ba be bi bo bu da de di do du e ga ge gi go gu ha he hi ho hu i "
    "ka ke ki ko ku ma me mi mo mu na ne ni nn no nu o pa pe pi po pu "
    "ra re ri ro ru sa se si so su ta te ti to tu u wa wo ya yo yu "
    "za ze zi zo zu"
).split()

ARTIST_LINK_RE = re.compile(
    r'href="/lyrics/artist/(\d+)"[^>]*>\s*(?:<span[^>]*>)?\s*([^<]+)')
ARTIST_PAGE_RE = re.compile(
    r'href="/lyrics/artist/\d+/(\d+)-1\.html"[^>]*title="page \d+"')


POSTER_RE = re.compile(
    r'投稿者：\s*</b>\s*<a href="/profile/[^"]*">\s*([^<]+)')


class Throttled(RuntimeError):
    """プチリリのアクセス制限ページを踏んだ。"""


def cached_page(client, path, key, refresh=False):
    """一覧ページを取得して gzip でキャッシュ。既にあれば**再取得しない**。"""
    os.makedirs(PAGES_DIR, exist_ok=True)
    dest = os.path.join(PAGES_DIR, "%s.html.gz" % key)
    if not refresh and os.path.exists(dest):
        with gzip.open(dest, "rt", encoding="utf-8") as fh:
            return fh.read(), True
    page = client.get_page(path)
    if page is None:
        return None, False
    if THROTTLE_RE.search(html_mod.unescape(page)):
        raise Throttled(path)
    with gzip.open(dest, "wt", encoding="utf-8") as fh:
        fh.write(page)
    return page, False


def build_artist_index(client, refresh=False):
    """artist_id -> アーティスト名。50音索引 71ページから作る。"""
    if not refresh and os.path.exists(ARTISTS_JSON):
        with io.open(ARTISTS_JSON, encoding="utf-8") as f:
            return json.load(f)

    artists = {}
    for i, kana in enumerate(SYLLABARY, 1):
        page, hit = cached_page(client, "/syllabary/%s.html" % kana,
                                "syllabary_%s" % kana, refresh)
        if page is None:
            continue
        for aid, name in ARTIST_LINK_RE.findall(page):
            name = html_mod.unescape(name).strip()
            if name:
                artists.setdefault(aid, name)
        sys.stderr.write("  索引 %2d/%d %-3s %s (累計 %d件)\n"
                         % (i, len(SYLLABARY), kana,
                            "cache" if hit else "取得", len(artists)))
    with io.open(ARTISTS_JSON, "w", encoding="utf-8") as f:
        json.dump(artists, f, ensure_ascii=False)
    return artists


def pick_artists(artists, songs, extra_terms=()):
    """対象曲の歌手名に当たるアーティストを選ぶ。

    既定は**対象曲の singer_label / unit_name** から作った短い集合だけを見る。
    語彙全体を総当たりすると遅いので、正規表現1本にまとめて1回の走査で済ませる。

    `extra_terms` (--broad で渡すアイマス語彙全体) を足すと対象は広がるが、
    辿るページ数も跳ね上がる。singer_label は曲によって空だったり表記が
    違ったりするので、取りこぼしを拾うにはこちらが要る。
    """
    labels = set(extra_terms)
    for song in songs:
        for label in (song.get("singer"), song.get("unit")):
            for part in re.split(r"[、,／/（）()]", label or ""):
                n = norm(part)
                if len(n) >= 3:
                    labels.add(n)
    if not labels:
        return []
    pattern = re.compile("|".join(sorted((re.escape(l) for l in labels),
                                         key=len, reverse=True)))

    # **当たるラベルが多い名義ほど先に辿る。** プチリリのアーティスト名は
    # 「天海春香(中村繪里子),如月千早(今井麻美),…」のような曲ごとの
    # クレジット文字列なので、多くのアイドル名を含む名義ほどこちらの対象曲に
    # 当たりやすい。名前の短い個人名義から辿ると空振りが続く (実測: 先頭80件で
    # 23曲しか付かなかった)。
    picked = []
    for aid, name in artists.items():
        hits = set(pattern.findall(norm(name)))
        if hits:
            picked.append((len(hits), aid, name))
    picked.sort(key=lambda x: (-x[0], len(x[2]), x[1]))
    return [(aid, name) for _, aid, name in picked]


def artist_rows(client, aid, max_pages):
    """そのアーティストの歌詞一覧の行を全ページ分。"""
    rows = []
    page, _ = cached_page(client, "/lyrics/artist/%s" % aid, "artist_%s_1" % aid)
    if page is None:
        return rows
    rows += parse_search_results(page)
    pages = [int(n) for n in ARTIST_PAGE_RE.findall(page)]
    last = min(max(pages), max_pages) if pages else 1
    for n in range(2, last + 1):
        page, _ = cached_page(client, "/lyrics/artist/%s/%d-1.html" % (aid, n),
                              "artist_%s_%d" % (aid, n))
        if page is None:
            break
        rows += parse_search_results(page)
    return rows


def strict_key(text):
    """曲名の完全一致用のキー。NFKC で幅を揃え、空白を落とし、大小を無視する。

    `norm` (記号も落とす) より厳しい。取り込み対象を選ぶときは、記号違いの
    同名曲を掴みたくないのでこちらを使う。
    """
    text = unicodedata.normalize("NFKC", text or "")
    return "".join(ch for ch in text if not ch.isspace()).casefold()


# master の歌唱欄が空の曲がある (学マスの一部)。その場合はブランドの名義で照合する。
# プチリリ側は「初星学園, 姫崎莉波」のようにブランド名を先頭に置くので、
# ブランドが一致すれば別ブランドの同名曲を掴む心配はない。
BRAND_ARTISTS = {
    "gakuen": ["初星学園"],
    "765as": ["765PRO ALLSTARS"],
    "cg": ["THE IDOLM@STER CINDERELLA GIRLS", "シンデレラガールズ"],
    "ml": ["765 MILLIONSTARS", "ミリオンライブ"],
    "sc": ["シャイニーカラーズ"],
    "sidem": ["SideM"],
}


def singer_keys(singer, brand=""):
    """歌唱欄からアイドル名・ユニット名を切り出す。空ならブランド名義で代替する。"""
    out = set()
    for part in re.split(r"[、,／/（）()\[\]]", singer or ""):
        part = part.strip()
        if len(part) >= 2:
            out.add(strict_key(part))
    if not out:
        out = {strict_key(n) for n in BRAND_ARTISTS.get(brand, [])}
    return out


def load_targets(path):
    """対象曲の TSV を読む。song_id / 曲名 / 歌唱 の3列を見る。"""
    rows = read_tsv(path, ["song_id", "曲名", "歌唱", "披露回数", "ブランド"])
    return [{"song_id": r["song_id"], "title": r["曲名"],
             "singer": r["歌唱"], "plays": r["披露回数"],
             "brand": r["ブランド"]}
            for r in rows if r["song_id"]]


def match_target(target, rows):
    """一覧ページの行から、その曲だと言い切れる候補だけ返す。

    条件は2つとも満たすこと:
      1. 曲名が**完全一致** (NFKC・空白無視・大小無視)。版名つきは採らない。
      2. アーティスト名にその曲の歌唱アイドル or ユニット名が含まれる。
    同名異曲や尺違いを掴まないための線引きなので、緩めないこと。
    """
    want = strict_key(target["title"])
    names = singer_keys(target["singer"], target.get("brand", ""))
    out = []
    for pid, ptitle, partist, palbum in rows:
        if strict_key(ptitle) != want:
            continue
        artist_k = strict_key(partist)
        if not any(n in artist_k for n in names):
            continue
        out.append((pid, ptitle, partist, palbum))
    return out


def collect_for_targets(client, artists, targets, existing, args):
    """指定した曲について、歌唱名から一覧ページを辿って候補を集める。"""
    akeys = {aid: strict_key(name) for aid, name in artists.items()}
    wanted = {}
    for target in targets:
        names = singer_keys(target["singer"], target.get("brand", ""))
        for aid, artist_k in akeys.items():
            if any(n in artist_k for n in names):
                wanted[aid] = wanted.get(aid, 0) + 1
    order = sorted(wanted, key=lambda a: -wanted[a])[:args.max_artists]
    print("歌唱名に当たるアーティスト %d件 (先頭 %d件を辿る)\n"
          % (len(wanted), len(order)))

    by_title = {}
    for target in targets:
        by_title.setdefault(strict_key(target["title"]), []).append(target)

    found = {}
    for i, aid in enumerate(order, 1):
        rows = artist_rows(client, aid, args.max_pages)
        hits = 0
        for row in rows:
            for target in by_title.get(strict_key(row[1]), []):
                sid = target["song_id"]
                if sid in found or not match_target(target, [row]):
                    continue
                found[sid] = {
                    "song_id": sid, "petit_id": str(row[0]),
                    "title": row[1], "artist": row[2],
                    "confidence": "high",
                    "note": "歌ネットに無し・プチリリ由来 (一覧 %s)" % aid,
                }
                hits += 1
        if hits:
            print("[%3d/%d] %-7s %d曲 %s" % (i, len(order), aid, hits,
                                             artists[aid][:36]))
    if found:
        write_tsv(CANDIDATES_TSV, CANDIDATE_COLS,
                  existing + [found[k] for k in sorted(found)])
    print("\n候補が付いた: %d曲 / %d曲" % (len(found), len(targets)))
    return 0


def cmd_list(args):
    # 一覧ページは検索ほど厳しくないが、まとまった数を辿るので間隔を長めに取る。
    client = PetitLyrics(min_interval=args.interval)
    ok, note = client.check_robots()
    print(note)
    if not ok:
        print("robots.txt が使用パスを禁じている。中止する。")
        return 1

    existing = read_tsv(CANDIDATES_TSV, CANDIDATE_COLS)
    done = {r["song_id"] for r in existing if r["confidence"] == "high"}
    if args.targets:
        # 対象曲を外から渡す経路 (歌ネットに無い曲を埋めるとき)。
        songs = load_targets(args.targets)
        targets = [s for s in songs if s["song_id"] not in done]
        print("対象 %d曲 (指定リスト) / 未取得 %d曲" % (len(songs), len(targets)))
    else:
        published = load_published()
        songs = load_song_meta(args.db, published)[:args.limit]
        targets = [s for s in songs if s["song_id"] not in done]
        print("対象 上位%d曲 / 未取得 %d曲" % (len(songs), len(targets)))
    if not targets:
        print("対象なし")
        return 0

    # 曲名 -> song_id。版名を落とした形も引けるようにしておく。
    by_title = {}
    for song in targets:
        for key in (norm(song["title"]), norm(base_title(song["title"]))):
            if key:
                by_title.setdefault(key, []).append(song)

    vocab, leading_vocab = load_vocab(args.db)
    found = {}
    try:
        print("アーティスト50音索引を用意中...")
        artists = build_artist_index(client, refresh=args.refresh_index)
        print("索引 %d件" % len(artists))

        if args.targets:
            return collect_for_targets(client, artists, targets, existing, args)
        extra = ()
        if args.broad:
            # 短い語 (「彩」「W」等) は無関係な名前に紛れて誤爆するので落とす。
            extra = [v for v in vocab if len(v) >= 4]
            print("語彙を拡張: アイマス関連 %d語を追加" % len(extra))
        picked = pick_artists(artists, targets, extra)
        print("対象曲の歌手名に当たるアーティスト %d件 (先頭 %d件を辿る)\n"
              % (len(picked), min(len(picked), args.max_artists)))

        seen_artists = 0
        for aid, name in picked[:args.max_artists]:
            seen_artists += 1
            rows = artist_rows(client, aid, args.max_pages)
            hits = 0
            for pid, ptitle, partist, palbum in rows:
                for key in (norm(ptitle), norm(base_title(ptitle))):
                    for song in by_title.get(key, []):
                        sid = song["song_id"]
                        if sid in found or sid in done:
                            continue
                        artist_n = norm(partist)
                        matched = [v for v in vocab if v and v in artist_n]
                        if not matched:
                            matched = [v for v in leading_vocab
                                       if v and artist_n.startswith(v)]
                        if not matched:
                            continue
                        found[sid] = {
                            "song_id": sid, "petit_id": str(pid),
                            "title": ptitle, "artist": partist,
                            "confidence": "high",
                            "note": "アーティスト一覧 %s から (曲名一致 + アイマス語彙)" % aid,
                        }
                        hits += 1
            print("[%3d/%d] %-4s %2d曲 %s"
                  % (seen_artists, min(len(picked), args.max_artists), aid,
                     hits, name[:40]))
            if len(found) >= len(targets):
                print("\n対象曲すべてに候補が付いた。")
                break
    except Throttled as exc:
        print("\nアクセス制限に当たった (%s)。ここで打ち切る。" % exc)
        print("  時間を置いて再実行すれば、キャッシュ済みのページは再取得せず続きから進む。")
    finally:
        if found:
            write_tsv(CANDIDATES_TSV, CANDIDATE_COLS,
                      existing + [found[k] for k in sorted(found)])
            print("\n%s に %d件追記 (対象 %d曲中)"
                  % (CANDIDATES_TSV, len(found), len(targets)))
    return 0


# --------------------------------------------------------------------------
# import — 取得した本文を lyrics_local/lyrics/<song_id>.json にする
# --------------------------------------------------------------------------
#
# 歌ネットに無かった曲を埋める経路。**採用の条件を緩めないこと** —
# 曲名が完全一致し、かつアーティスト名にその曲の歌唱アイドル/ユニット名が
# 含まれる候補だけを入れる。同名異曲や尺違いを掴むと、誤った歌詞が公開される。

# ♪ だけの行はカラオケ同期用の間奏記号であって歌詞ではない (§ 差分の仕分け)。
# 本文に混ぜず間奏マーカーに落とす。
# 括弧で囲った <♪> (♪) （♪） も同じ間奏記号。裸の ♪ だけを見ていると取りこぼす。
INTERLUDE_LINE_RE = re.compile(r"^[\s<>()（）\[\]【】「」♪]*♪[\s<>()（）\[\]【】「」♪]*$")


def petit_lines_to_text(lines):
    """プチリリの行配列を lyrics_json.text_to_lines に渡すテキストにする。

    - 空行はそのまま残す (段落の余白として text_to_lines が解釈する)
    - ♪ の連続だけの行は落とし、代わりに空行を2つ置いて間奏マーカーにさせる
    """
    out = []
    for line in lines:
        if INTERLUDE_LINE_RE.match(line or ""):
            out.extend(["", ""])
        else:
            out.append(line)
    return "\n".join(out)


def cmd_import(args):
    sys.path.insert(0, HERE)
    import lyrics_json

    targets = {t["song_id"]: t for t in load_targets(args.targets)} \
        if args.targets else {}
    candidates = {r["song_id"]: r for r in read_tsv(CANDIDATES_TSV, CANDIDATE_COLS)
                  if r["confidence"] == "high"}
    song_ids = [args.only] if args.only else sorted(candidates)

    made, skipped = [], []
    for sid in song_ids:
        cand = candidates.get(sid)
        path = cache_path(sid)
        if not cand or not os.path.exists(path):
            skipped.append((sid, "本文が未取得"))
            continue
        if targets and sid not in targets:
            skipped.append((sid, "対象リストに無い"))
            continue
        # **既存の歌詞は書き換えない。**
        if os.path.exists(os.path.join(LOCAL_LYRICS_DIR, "%s.json" % sid)):
            skipped.append((sid, "手元に既に歌詞がある"))
            continue

        with io.open(path, encoding="utf-8") as f:
            cached = json.load(f)
        target = targets.get(sid)
        if target and not match_target(target, [(cached.get("petit_id"),
                                                 cand["title"], cand["artist"], "")]):
            skipped.append((sid, "曲名/歌唱の照合に通らない"))
            continue

        lines = lyrics_json.text_to_lines(petit_lines_to_text(cached.get("lines", [])))
        if not [x for x in lines if x["kind"] == "lyric"]:
            skipped.append((sid, "本文が空"))
            continue

        poster = cached.get("poster") or ""
        source = "プチリリ %s%s" % (cached.get("petit_id"),
                                    " (%s)" % poster if poster else "")
        doc = lyrics_json.build_doc(sid, lines, source,
                                    note="歌ネットに無し・プチリリ由来")
        if args.apply:
            lyrics_json.write_doc(sid, doc)
        made.append((sid, doc["title"], cached.get("petit_id"), poster,
                     len(lines)))

    for sid, title, pid, poster, n in made:
        print("%-34s %-24s petit %-8s %-12s %d行"
              % (sid, title[:22], pid, poster[:12], n))
    print("\n作成 %d件 / 見送り %d件%s"
          % (len(made), len(skipped), "" if args.apply else " (--apply なしなので書き込んでいない)"))
    for sid, why in skipped:
        print("  skip %-34s %s" % (sid, why))
    return 0

# --------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--db", default=DEFAULT_DB)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("search", help="披露回数の多い順に曲名でプチリリを検索し候補を記録")
    p.add_argument("--limit", type=int, default=50)
    p.add_argument("--offset", type=int, default=0)
    p.add_argument("--refresh-published", action="store_true",
                   help="D1 から公開済み曲リストを取り直す")
    p.add_argument("--interval", type=float, default=8.0,
                   help="検索1件ごとの追加の待ち時間 (秒)。"
                        "検索ページは制限が厳しいので既定を長めにしてある")
    p.add_argument("--targets", help="対象曲の TSV (song_id / 曲名 / 歌唱)")
    p.set_defaults(func=cmd_search)

    p = sub.add_parser("list", help="アーティスト一覧を辿って候補を集める (検索を使わない)")
    p.add_argument("--limit", type=int, default=200, help="披露回数の上位何曲を対象にするか")
    p.add_argument("--max-artists", type=int, default=80, help="辿るアーティスト数の上限")
    p.add_argument("--max-pages", type=int, default=5, help="1アーティストあたりの一覧ページ数の上限")
    p.add_argument("--refresh-index", action="store_true", help="50音索引を取り直す")
    p.add_argument("--targets", help="対象曲の TSV (song_id / 曲名 / 歌唱 の3列を見る)")
    p.add_argument("--interval", type=float, default=2.5, help="1リクエストの最小間隔 (秒)")
    p.add_argument("--broad", action="store_true",
                   help="対象曲の歌手名だけでなくアイマス語彙全体でアーティストを選ぶ "
                        "(辿るページ数が大幅に増える)")
    p.set_defaults(func=cmd_list)

    p = sub.add_parser("fetch", help="high の候補の本文を取得してキャッシュ")
    p.add_argument("--limit", type=int, default=0)
    p.add_argument("--only")
    p.set_defaults(func=cmd_fetch)

    p = sub.add_parser("import", help="取得した本文を lyrics_local/lyrics/ の JSON にする")
    p.add_argument("--targets", help="対象曲の TSV。照合に使う")
    p.add_argument("--only")
    p.add_argument("--apply", action="store_true", help="実際に書き込む")
    p.set_defaults(func=cmd_import)

    p = sub.add_parser("diff", help="手元の歌詞とキャッシュを突き合わせて報告")
    p.add_argument("--only")
    p.add_argument("--examples", type=int, default=3, help="1曲あたりの差分の例の数")
    p.set_defaults(func=cmd_diff)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
