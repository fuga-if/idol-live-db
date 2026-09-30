#!/usr/bin/env python3
"""crawl_show_details.py — 今後のライブの公式ページから、空いている「特設 URL・開演時刻・会場」を
埋め、チケット価格の案を作る (daily-data-crawl §3.9)。

    # 見るだけ (既定)
    python3 tools/crawl_show_details.py --prices-out Scripts/crawl_review/$DATE.prices.tsv
    # 埋められるものを data/fixes/ に書き、apply_data.py で master.sqlite と CloudKit Production に入れる
    CLOUDKIT_KEY_ID=$KID python3 tools/crawl_show_details.py --apply

- 対象: 開催日が今日以降の公演を持つイベント。公式ページは lib/live_pages.event_pages で探す
  (特設 → 公式ポータルのスケジュール → ニュース)。
- 特設 URL: events.ticket_url が空で、見つけたページの中に特設 (live_event/<slug>/) があれば、
  その ticket/ (無ければトップ) を入れる。
- 開演時刻: 「2027年3月13日(土) 開場16:00 / 開演17:00」のような日付つきの行から日ごとの開演を読み、
  その日の公演数と開演の数が合うときだけ、空の shows.start_time に順に入れる。
  DB の値とページが違うものは入れずに出す (時刻変更の知らせ)。
- 会場: 「開催場所」「会場」の見出しの次の行を venues (正式名・旧名・別名) と突き合わせ、ページの会場が
  1 か所だけで 1 つの venue に決まるときだけ、venue_id が空の公演に venue_id (と venue_halls の hall) を入れる。
- 価格: 「〇〇席 15,000円(税込)」を拾い、show_tickets が無い公演について import_show_tickets.py の
  TSV の形で --prices-out に書くだけ (自動では入れない。人がページと突き合わせてから取り込む)。
- 空の列だけを埋める。既にある値は上書きしない。標準ライブラリだけで動かす。
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from lib.live_pages import (  # noqa: E402
    DATE, LIVE_EVENT, Cms, event_pages, fetch, fold_title, html_to_lines, special_site,
)

ROOT = TOOLS.parent
DB_PATH = ROOT / "ImasLiveDB" / "Resources" / "master.sqlite"

FULL_DATE = re.compile(r"(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日?|(\d{4})\s*[./]\s*(\d{1,2})\s*[./]\s*(\d{1,2})")
START = re.compile(r"開演\s*[:：]?\s*(\d{1,2})\s*[:：]\s*(\d{2})|(\d{1,2})\s*[:：]\s*(\d{2})\s*開演")
# 見出しだけの行か「会場：〇〇」。「会場内では…」のような注意書きは拾わない。
VENUE_HEAD = re.compile(r"^[★■●◆・]?\s*(?:開催場所|開催会場|会場)\s*(?:[:：]\s*(.*))?$")
PRICE = re.compile(r"(\d{1,3}(?:,\d{3})+|\d{3,6})\s*円\s*[(（]\s*税込[^)）]{0,20}[)）]")
PREFECTURE = re.compile(r"^(北海道|東京都|(?:京都|大阪)府|.{2,3}県)\s+")


# ---------------------------------------------------------------------------
# ページの読み取り
# ---------------------------------------------------------------------------

def parse_start_times(lines: list[str]) -> list[tuple[str, str]]:
    """(日付, 開演) をページの順に。日付のある行 (か、その日の直前の開演) から 2 行以内の開演を、
    その日のものとみなす (昼公演・夜公演が日付 1 つの下に並ぶ書き方がある)。"""
    out: list[tuple[str, str]] = []
    date = None
    since_date = 99
    timed = False
    for line in lines:
        m = FULL_DATE.search(line)
        if m:
            y, mo, d = (m[1], m[2], m[3]) if m[1] else (m[4], m[5], m[6])
            try:
                date = dt.date(int(y), int(mo), int(d)).isoformat()
                since_date = 0
            except ValueError:
                date = None
        t = START.search(line)
        if t and date and since_date <= 2:
            hh, mm = (t[1], t[2]) if t[1] else (t[3], t[4])
            out.append((date, f"{int(hh):02d}:{mm}"))
            since_date = 0
            timed = True
        elif not m and timed:
            date = None  # 開演の並びが切れたら、その日付はもう使わない (下の注記やグッズの時刻を拾わない)
        if m and not t:
            timed = False
        since_date += 1
    return out


def parse_venues(lines: list[str]) -> list[str]:
    """「開催場所」「会場」の見出しの次の行 (同じ行にあればそれ)。URL・注記は飛ばす。"""
    out = []
    for i, line in enumerate(lines):
        m = VENUE_HEAD.match(line)
        if not m:
            continue
        cand = (m[1] or "").strip() or next(
            (x for x in lines[i + 1:i + 3] if not x.startswith(("http", "※"))), "")
        cand = re.sub(r"\s*(MAP|マップ|アクセス)$", "", PREFECTURE.sub("", cand)).strip()
        if cand and len(cand) <= 40 and cand not in out:
            out.append(cand)
    return out


def parse_prices(lines: list[str]) -> list[tuple[str, int]]:
    """(券種名, 税込の円)。券種名は同じ行の前か、1 つ前の行。

    「チケット」の見出しより後だけを見て、グッズ・物販の見出しで止める (グッズの価格を拾わない)。
    """
    out = []
    in_ticket = False
    for i, line in enumerate(lines):
        if re.search(r"チケット|TICKET|Ticket", line) and len(line) <= 30:
            in_ticket = True
        elif re.search(r"グッズ|物販|GOODS|Goods", line) and len(line) <= 30:
            in_ticket = False
        m = PRICE.search(line)
        if not m or not in_ticket:
            continue
        name = line[:m.start()].strip(" :：/")
        if not name and i > 0 and not PRICE.search(lines[i - 1]):
            name = lines[i - 1].strip()
        price = int(m[1].replace(",", ""))
        if name and len(name) <= 30 and (name, price) not in out:
            out.append((name, price))
    return out


# ---------------------------------------------------------------------------
# DB との突き合わせ
# ---------------------------------------------------------------------------

@dataclass
class Show:
    id: str
    name: str
    date: str
    start_time: str
    venue: str
    venue_id: str
    has_tickets: bool


@dataclass
class EventPlan:
    event_id: str
    name: str
    url: str | None
    fixes: list[dict] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)
    prices: list[str] = field(default_factory=list)  # TSV 行


def venue_index(conn) -> list[tuple[str, str]]:
    """(畳んだ名前, venue_id)。正式名・旧名・別名を全部。"""
    out = []
    for vid, name, aliases in conn.execute("SELECT id, name, IFNULL(aliases, '') FROM venues"):
        for n in [name, *aliases.split(",")]:
            if n.strip():
                out.append((fold_title(n), vid))
    for vid, name in conn.execute("SELECT venue_id, name FROM venue_names"):
        out.append((fold_title(name), vid))
    return out


def match_venue(conn, index, text: str) -> tuple[str, str] | None:
    """ページの会場名 → (venue_id, hall)。1 つに決まらなければ None。"""
    key = fold_title(text)
    exact = {vid for n, vid in index if n == key}
    if len(exact) == 1:
        return exact.pop(), ""
    # 「パシフィコ横浜 国立大ホール」: 先頭が会場名、残りが venue_halls のホール名
    pre = sorted({(len(n), vid) for n, vid in index if n and key.startswith(n)}, reverse=True)
    if not pre or (len(pre) > 1 and pre[0][0] == pre[1][0] and pre[0][1] != pre[1][1]):
        return None
    vid = pre[0][1]
    rest = key[pre[0][0]:]
    for (hall,) in conn.execute("SELECT name FROM venue_halls WHERE venue_id = ?", (vid,)):
        if fold_title(hall) == rest:
            return vid, hall
    return None


def plan_event(conn, eid, name, ticket_url, shows: list[Show], urls: list[str], pages: dict[str, list[str]],
               index) -> EventPlan:
    plan = EventPlan(eid, name, next(iter(pages), None))
    # 特設 URL
    site = special_site(urls)
    if not ticket_url and site:
        ticket = site + "ticket/"
        plan.fixes.append({"table": "events", "id": eid, "fields": {"ticket_url": ticket if ticket in pages else site}})
    # 開演時刻: 開演の数がいちばん多いページを使う
    times = max((parse_start_times(ls) for ls in pages.values()), key=len, default=[])
    by_date: dict[str, list[str]] = {}
    for d, t in times:
        if t not in by_date.setdefault(d, []):
            by_date[d].append(t)
    shows_by_date: dict[str, list[Show]] = {}
    for s in shows:
        shows_by_date.setdefault(s.date, []).append(s)
    for d, day_shows in shows_by_date.items():
        page_times = by_date.get(d, [])
        if len(page_times) != len(day_shows):
            if page_times:
                plan.notes.append(f"{d}: 開演がページに {len(page_times)} つ・公演は {len(day_shows)} つ ({'・'.join(page_times)})")
            continue
        for s, t in zip(day_shows, page_times):
            if not s.start_time:
                plan.fixes.append({"table": "shows", "id": s.id, "fields": {"start_time": t}})
            elif s.start_time != t:
                plan.notes.append(f"{s.name} ({d}) の開演が DB は {s.start_time}・ページは {t}")
    # 会場: ページに 1 か所だけ
    venues = list(dict.fromkeys(v for ls in pages.values() for v in parse_venues(ls)))
    todo = [s for s in shows if not s.venue_id]
    if todo and len(venues) == 1:
        hit = match_venue(conn, index, venues[0])
        if hit:
            for s in todo:
                fields = {"venue_id": hit[0]}
                if hit[1]:
                    fields["hall"] = hit[1]
                if not s.venue:
                    fields["venue"] = venues[0]
                plan.fixes.append({"table": "shows", "id": s.id, "fields": fields})
        else:
            plan.notes.append(f"会場「{venues[0]}」が venues に無い (新しい会場なら data/venues/ で足す)")
    elif todo and len(venues) > 1:
        plan.notes.append(f"会場がページに複数 ({' / '.join(venues)})。公演ごとの会場は人が見る")
    # 価格の案
    no_tickets = [s for s in shows if not s.has_tickets]
    if no_tickets:
        best = max(((u, parse_prices(ls)) for u, ls in pages.items()), key=lambda x: len(x[1]), default=(None, []))
        for s in no_tickets:
            for name, price in best[1]:
                kind = "stream" if "配信" in name else "live_viewing" if "ライブビューイング" in name else "live"
                plan.prices.append("\t".join([s.id, kind, name, str(price), "0", "", best[0]]))
    return plan


def upcoming_events(conn, today: str):
    rows = conn.execute(
        """SELECT e.id, e.name, e.brand_id, IFNULL(e.joint_brand_ids, ''), IFNULL(e.ticket_url, '')
           FROM events e JOIN shows s ON s.event_id = e.id
           GROUP BY e.id HAVING MAX(s.date) >= ? ORDER BY MIN(s.date)""", (today,)).fetchall()
    for eid, name, brand, joint, url in rows:
        shows = [Show(*r[:6], bool(r[6])) for r in conn.execute(
            """SELECT s.id, s.name, s.date, IFNULL(s.start_time, ''), IFNULL(s.venue, ''), IFNULL(s.venue_id, ''),
                      EXISTS (SELECT 1 FROM show_tickets t WHERE t.show_id = s.id)
               FROM shows s WHERE s.event_id = ? AND s.date >= ? ORDER BY s.date, s.sort_order""", (eid, today))]
        brands = [b for b in [brand, *joint.split(",")] if b]
        yield eid, name, brands, url, shows


def crawl(conn, today: str, cms: Cms | None, fetcher=fetch) -> list[EventPlan]:
    index = venue_index(conn)
    plans = []
    for eid, name, brands, url, shows in upcoming_events(conn, today):
        urls = event_pages(name, brands, sorted({s.date for s in shows}), url or None, cms)
        pages = {}
        for u in urls:
            body = fetcher(u)
            if body:
                pages[u] = html_to_lines(body)
        if not pages:
            plans.append(EventPlan(eid, name, None, notes=["公式ページが見つからない"]))
            continue
        plans.append(plan_event(conn, eid, name, url, shows, urls, pages, index))
    return plans


# ---------------------------------------------------------------------------

def report(plans: list[EventPlan]) -> str:
    out = []
    for p in plans:
        if not (p.fixes or p.notes or p.prices):
            continue
        out.append(f"## {p.name}\n{p.url or '-'}")
        for f in p.fixes:
            out.append(f"- 埋める {f['table']} `{f['id']}` {json.dumps(f['fields'], ensure_ascii=False)}")
        out += [f"- {n}" for n in p.notes]
        if p.prices:
            out.append(f"- 価格の案 {len(p.prices)} 行 (--prices-out)")
        out.append("")
    return "\n".join(out)


def apply(db_path: Path, plans: list[EventPlan], today: str) -> int:
    fixes = [f for p in plans for f in p.fixes]
    if not fixes:
        print("埋めるものなし")
        return 0
    sources = sorted({p.url for p in plans if p.fixes and p.url})
    path = ROOT / "data" / "fixes" / f"{today.replace('-', '')}_crawl_show_details.json"
    path.write_text(json.dumps({
        "title": "公式ページから、今後の公演の空いていた特設 URL・開演時刻・会場を埋める",
        "author": "crawl_show_details.py",
        "source": " ".join(sources),
        "fixes": fixes,
    }, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    cmd = [sys.executable, str(TOOLS / "apply_data.py"), f"--db={db_path}", "--only", str(path),
           "--apply", "--push", "--production"]
    if subprocess.run([sys.executable, str(TOOLS / "apply_data.py"), f"--db={db_path}", "--check", "--only", str(path)],
                      cwd=str(ROOT)).returncode != 0 or subprocess.run(cmd, cwd=str(ROOT)).returncode != 0:
        print(f"⚠️ 反映に失敗。{path.relative_to(ROOT)} を直して同じコマンドで入れ直す:\n  " + " ".join(cmd))
        return 1
    dest = ROOT / "data" / "_applied" / "fixes" / path.name
    shutil.move(str(path), str(dest))
    print(f"✓ {len(fixes)} 件を反映。記録: {dest.relative_to(ROOT)}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--db", type=Path, default=DB_PATH)
    ap.add_argument("--today", default=dt.date.today().isoformat())
    ap.add_argument("--no-cms", action="store_true", help="公式ポータルの CMS API で探さない")
    ap.add_argument("--prices-out", type=Path, help="価格の案を import_show_tickets.py の TSV で書く")
    ap.add_argument("--apply", action="store_true", help="特設 URL・開演時刻・会場を反映する (要 CLOUDKIT_KEY_ID)")
    args = ap.parse_args()

    if args.apply and not os.environ.get("CLOUDKIT_KEY_ID"):
        print("--apply には環境変数 CLOUDKIT_KEY_ID (Production) が要る", file=sys.stderr)
        return 2
    conn = sqlite3.connect(str(args.db))
    plans = crawl(conn, args.today, None if args.no_cms else Cms())
    conn.close()
    print(report(plans))
    if args.prices_out:
        rows = [r for p in plans for r in p.prices]
        args.prices_out.write_text("".join(r + "\n" for r in rows), encoding="utf-8")
        print(f"価格の案 {len(rows)} 行 → {args.prices_out}")
    if args.apply:
        return apply(args.db, plans, args.today)
    return 0


if __name__ == "__main__":
    sys.exit(main())
