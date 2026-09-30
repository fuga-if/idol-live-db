#!/usr/bin/env python3
"""crawl_show_cast.py — 出演者がまだ入っていない今後の公演について、公式特設ページの
出演者欄を読み、発表されていれば show_cast に入れる (daily-data-crawl §3.8)。

    # 見るだけ (既定)。公演ごとに「入れられる / 要判断 / 未発表」を出す
    python3 tools/crawl_show_cast.py
    # 「入れられる」公演を master.sqlite と db/master.sql に入れ、CloudKit Production に
    # 触った公演だけ押し、Discord の #新着データ に知らせる
    python3 tools/crawl_show_cast.py --apply --key-id="$KID"

- 対象: 開催日が今日 (--since) 以降で show_cast が 0 行の公演 (performer_type='cast')。
- 読む先: lib/live_pages.event_pages。特設 (events.ticket_url) → 公式ポータルのスケジュール →
  ニュース の順。見つからない催しは --url EVENT_ID=URL で渡す。
- 読み方: 「声優名（アイドル名 役）」だけの行と、DB のアイドル名だけを「/」で並べた行を出演者と
  みなす (出演作品の「…」〇〇役 は拾わない)。DAY1 / 第一公演 / 昼公演 / 2.27 Sat などの見出しで
  日を切り、見出しの日番号・公演番号・日付・公演名で公演に当てる。
  当てられないとき (日の切れ目が無いのに複数公演・見出しと公演数が合わない) は要判断。
- アイドルは名前 (空白・全角半角を無視) で引く。イベントのブランドで 1 人に決まらなければ要判断。
  声優名が idol_voice_actors と違う行も要判断 (読み違い・声優交代を人が見る)。
- 要判断の公演は --apply でも入れない。人が見て正しければ --shows <id> --allow-warnings で入れる。
  名前でアイドルが引けなかった行がある公演は、どうやっても入れない。
- 標準ライブラリだけで動かす。
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

from lib import discord_notify  # noqa: E402
from lib.live_pages import (  # noqa: E402
    DAY_NO, Cms, event_pages, expand, fetch, header_hint, html_to_lines, is_header,
)
from lib.text import nfkc_drop_spaces  # noqa: E402

ROOT = TOOLS.parent
DB_PATH = ROOT / "ImasLiveDB" / "Resources" / "master.sqlite"
MASTER_SQL = ROOT / "db" / "master.sql"

# 「声優名（アイドル名 役）」だけの 1 行。出演作品の「作品」〇〇役、は 「」 と 、 で弾く。
ROLE_LINE = re.compile(
    r"^(?P<va>[^「」『』（）()、。:：/]{1,24}?)\s*[（(]\s*(?P<char>[^（）()「」、]{1,24}?)\s*役\s*[)）]$"
)


def fold(name: str) -> str:
    """人名の照合用。空白と全角半角に加えて、異体字の髙・﨑を畳む。"""
    return nfkc_drop_spaces(name).replace("髙", "高").replace("﨑", "崎")


# ---------------------------------------------------------------------------
# ページの読み取り
# ---------------------------------------------------------------------------

# 「（〇〇役）」を含むのに 1 行の出演者として読めなかった行 (2 人が 1 行に並ぶなど)。
ROLE_ANYWHERE = re.compile(r"[（(][^（）()「」]{1,24}役\s*[)）]")


@dataclass
class Segment:
    headers: list[str]
    cast: list[tuple[str, str]] = field(default_factory=list)  # (声優名, アイドル名)
    unread: list[str] = field(default_factory=list)  # 役を含むのに読めなかった行


def names_line(line: str, known: set[str]) -> list[str] | None:
    """「浅倉 透 / 樋口 円香」のようにアイドル名だけを並べた行なら名前の並び。

    全部が DB のアイドル名に当たるときだけ出演者の行とみなす (他の「/」区切りを拾わない)。
    """
    parts = [p for p in re.split(r"\s*[/／]\s*", line) if p]
    if len(parts) < 2 or any(len(p) > 16 for p in parts):
        return None
    return parts if all(fold(p) in known for p in parts) else None


def split_role_lists(lines: list[str]) -> list[str]:
    """「A(甲役) / B(乙役) /」のように 1 行に並べた出演者を 1 人 1 行に割る。"""
    out = []
    for line in lines:
        if "「" not in line and ROLE_ANYWHERE.search(line) and re.search(r"[/／]", line):
            out += [part for part in re.split(r"\s*[/／]\s*", line) if part]
        else:
            out.append(line)
    return out


def parse_cast(page: str, known: set[str] | frozenset = frozenset()) -> list[Segment]:
    """出演者の行を、直前の見出しごとの塊に分ける。出演者の無い塊は捨てる。"""
    # 塊の見出しは、出演者の直前に続けて並ぶ見出しの 1 組だけ。ページ上部の開催日程などを
    # 拾わないよう、見出しでも出演者でもない行が挟まったら組を切る (更新日の行は素通し)。
    # 1 組の中で日付や日番号が割れていれば header_hint が曖昧として返す。
    # 見出しから出演者まで 3 行より離れていたら、その見出しは出演者のものではない
    # (開催概要の日付の後に会場・URL が続き、ずっと下に全公演共通の出演者がある、など)。
    segments: list[Segment] = []
    pending: list[str] = []
    broken = False
    gap = 0
    for line in split_role_lists(html_to_lines(page)):
        m = ROLE_LINE.match(line)
        names = None if m else names_line(line, known)
        if m or names:
            if gap > 3:
                pending = []
            if pending or not segments:
                segments.append(Segment(pending))
                pending = []
            if m:
                segments[-1].cast.append((m["va"].strip(), m["char"].strip()))
            else:
                segments[-1].cast += [("", n) for n in names]
            broken = False
            gap = 0
        elif is_header(line):
            # DAY1 などの日番号の見出しは新しい組の始まり (直前に並ぶ開催日程を持ち込まない)。
            if broken or DAY_NO.search(line):
                pending = []
                broken = False
            pending.append(line)
            gap = 0
        elif "Update" not in line:
            broken = True
            gap += 1
            if segments and not pending and "「" not in line and ROLE_ANYWHERE.search(line):
                segments[-1].unread.append(line)
    return segments


# ---------------------------------------------------------------------------
# DB との突き合わせ
# ---------------------------------------------------------------------------

@dataclass
class Show:
    id: str
    name: str
    date: str
    has_cast: bool


@dataclass
class Plan:
    show: Show
    idol_ids: list[str]
    warnings: list[str]
    unresolved: list[str]
    event_name: str = ""

    @property
    def status(self) -> str:
        if self.unresolved:
            return "unresolved"
        return "warn" if self.warnings else "ok"


@dataclass
class EventResult:
    event_id: str
    event_name: str
    url: str | None
    plans: list[Plan]
    note: str = ""


def target_events(conn, since: str) -> list[tuple[str, str, str, str | None, list[Show]]]:
    """since 以降に出演者が 0 人の公演を持つイベント (id, name, brands, ticket_url, 全公演)。"""
    rows = conn.execute(
        """SELECT DISTINCT e.id FROM events e JOIN shows s ON s.event_id = e.id
           WHERE s.date >= ? AND IFNULL(s.performer_type, 'cast') = 'cast'
             AND NOT EXISTS (SELECT 1 FROM show_cast c WHERE c.show_id = s.id)""",
        (since,),
    ).fetchall()
    out = []
    for (eid,) in rows:
        name, brand, joint, url = conn.execute(
            "SELECT name, brand_id, joint_brand_ids, ticket_url FROM events WHERE id = ?", (eid,)
        ).fetchone()
        shows = [
            Show(sid, sname, sdate, bool(n))
            for sid, sname, sdate, n in conn.execute(
                """SELECT s.id, s.name, s.date, (SELECT COUNT(*) FROM show_cast c WHERE c.show_id = s.id)
                   FROM shows s WHERE s.event_id = ? ORDER BY s.date, s.sort_order""",
                (eid,),
            )
        ]
        brands = ",".join(b for b in [brand, *(joint or "").split(",")] if b)
        out.append((eid, name, brands, url, shows))
    out.sort(key=lambda r: min(s.date for s in r[4]))
    return out


def assign(segments: list[Segment], shows: list[Show], same_cast: bool = False) -> tuple[dict[str, Segment], str]:
    """塊を公演に当てる。当てられなければ ({}, 理由)。

    same_cast: 人がページを見て「全公演同じ出演者」と確かめたイベント。塊が 1 つなら全公演に当てる。
    """
    if not segments:
        return {}, "出演者の記載なし"
    if same_cast:
        if len(segments) != 1:
            return {}, f"全公演共通として読むには塊が 1 つであること (塊{len(segments)})"
        return {s.id: segments[0] for s in shows}, ""
    year_hint = int(shows[0].date[:4])
    by_date: dict[str, list[Show]] = {}
    for s in shows:
        by_date.setdefault(s.date, []).append(s)
    result: dict[str, Segment] = {}
    positional = len(segments) == len(shows)
    # 日番号で引けるのは、1 日 1 公演かつ公演名が重複しない (会場ごとに DAY1/DAY2 を持つツアーでない) ときだけ。
    by_day_no = len(by_date) == len(shows) and len({s.name for s in shows}) == len(shows)
    for i, seg in enumerate(segments):
        hint = header_hint(seg.headers, year_hint)
        folded = [fold(h) for h in seg.headers]
        named = [s for s in shows if any(fold(s.name) and fold(s.name) in h for h in folded)]
        show = None
        if hint is not None:
            day_no, date, tod, show_no = hint
            by_no = shows[day_no - 1] if day_no and by_day_no and 1 <= day_no <= len(shows) else None
            if show_no and not day_no and 1 <= show_no <= len(shows):
                by_no = shows[show_no - 1]
            by_dt = None
            if date and date.isoformat() in by_date:
                same_day = by_date[date.isoformat()]
                if len(same_day) == 1:
                    by_dt = same_day[0]
                elif tod:
                    by_dt = same_day[0] if tod in ("昼", "マチネ") else same_day[-1]
            if by_no and by_dt and by_no is not by_dt:
                show = None  # 日番号と日付が別の公演を指す
            elif len(named) == 1 and (by_dt or by_no or named[0]) is named[0]:
                show = named[0]
            elif by_dt or by_no:
                show = by_dt or by_no
            elif not seg.headers and len(shows) == 1 and len(segments) == 1:
                show = shows[0]
            elif positional and not (day_no or date or show_no) and (seg.headers or len(shows) == 1):
                show = shows[i]
        if show is None:
            head = " / ".join(seg.headers) or "見出しなし"
            return {}, f"「{head}」の{len(seg.cast)}人をどの公演か決められない (公演{len(shows)}・塊{len(segments)})"
        if show.id in result:
            return {}, f"{show.name} に塊が 2 つ当たった"
        result[show.id] = seg
    return result, ""


def resolve(conn, seg: Segment, brands: list[str]) -> tuple[list[str], list[str], list[str]]:
    """塊の (アイドル id, 注意, 引けなかった行)。"""
    ids: list[str] = []
    warnings: list[str] = []
    unresolved: list[str] = []
    idols = conn.execute("SELECT id, brand_id, name, aliases FROM idols").fetchall()
    extra = dict(conn.execute("SELECT idol_id, GROUP_CONCAT(brand_id) FROM idol_brands GROUP BY idol_id"))
    warnings += [f"読めなかった行: {line}" for line in seg.unread]
    for va, char in seg.cast:
        key = fold(char)
        hits = [
            (iid, b) for iid, b, n, aliases in idols
            if key == fold(n) or key in {fold(a) for a in (aliases or "").split(",") if a.strip()}
        ]
        in_brand = [iid for iid, b in hits if b in brands or set((extra.get(iid) or "").split(",")) & set(brands)]
        cands = in_brand or [iid for iid, _ in hits]
        if len(cands) != 1:
            unresolved.append(f"{va or '-'}（{char} 役）: {'候補なし' if not cands else '候補 ' + ','.join(cands)}")
            continue
        iid = cands[0]
        if not in_brand:
            warnings.append(f"{char} はイベントのブランド外 ({iid})")
        # 括弧は落として比べる (DB に「中島ヨシキ）」のような閉じ括弧の混じった名前がある)。
        vas = [re.sub(r"[()]", "", fold(v)) for (v,) in conn.execute(
            "SELECT name FROM idol_voice_actors WHERE idol_id = ? AND IFNULL(valid_to, '') = ''", (iid,)
        )]
        if va and vas and re.sub(r"(さん|様)$", "", fold(va)) not in vas:
            warnings.append(f"{char} の声優がページは {va}・DB は {','.join(vas)}")
        if iid not in ids:
            ids.append(iid)
    return ids, warnings, unresolved


def crawl(conn, today: str, overrides: dict[str, str], fetcher=fetch, cms: Cms | None = None,
          since: str | None = None, same_cast: frozenset = frozenset()) -> list[EventResult]:
    """since (既定は today) 以降の出演者 0 人の公演について、公式ページを読んで案を作る。"""
    since = since or today
    known = {fold(n) for (n,) in conn.execute("SELECT name FROM idols")}
    results = []
    for eid, name, brands, ticket_url, shows in target_events(conn, since):
        dates = sorted({s.date for s in shows})
        urls = expand(overrides[eid]) if eid in overrides else event_pages(name, brands.split(","), dates, ticket_url, cms)
        if not urls:
            results.append(EventResult(eid, name, None, [], "公式ページが見つからない (--url で渡す)"))
            continue
        best: tuple[str, list[Segment]] | None = None
        for url in urls:
            page = fetcher(url)
            if not page:
                continue
            segs = parse_cast(page, known)
            if segs and (best is None or sum(len(s.cast) for s in segs) > sum(len(s.cast) for s in best[1])):
                best = (url, segs)
        if best is None:
            results.append(EventResult(eid, name, urls[0], [], "出演者の記載なし"))
            continue
        url, segs = best
        todo = [s for s in shows if not s.has_cast and s.date >= since]
        mapping, why = assign(segs, todo if eid in same_cast else shows, eid in same_cast)
        if why:
            results.append(EventResult(eid, name, url, [], why))
            continue
        plans = []
        for show in todo:
            if show.id in mapping:
                ids, warns, unres = resolve(conn, mapping[show.id], brands.split(","))
                plans.append(Plan(show, ids, warns, unres, name))
        missing = [s.name for s in todo if s.id not in mapping]
        results.append(EventResult(eid, name, url, plans, f"記載なしの公演: {'・'.join(missing)}" if missing else ""))
    return results


# ---------------------------------------------------------------------------
# 反映
# ---------------------------------------------------------------------------

def sql_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def missing_in_master_sql(sql_path: Path, rows: list[tuple[str, str]]) -> list[tuple[str, str]]:
    """公演かアイドルが正本に無い行 (足すと外部キーが壊れる)。"""
    text = sql_path.read_text(encoding="utf-8")
    return [
        (show_id, idol_id) for show_id, idol_id in rows
        if f"""INSERT INTO "shows" VALUES({sql_quote(show_id)},""" not in text
        or f"""INSERT INTO "idols" VALUES({sql_quote(idol_id)},""" not in text
    ]


def append_master_sql(sql_path: Path, rows: list[tuple[str, str]]) -> list[str]:
    """正本の show_cast の並びの末尾に行を足す。公演かアイドルが正本に無い行は足さない (外部キー)。"""
    skipped_rows = set(missing_in_master_sql(sql_path, rows))
    text = sql_path.read_text(encoding="utf-8")
    lines = []
    for show_id, idol_id in rows:
        line = f"""INSERT INTO "show_cast" VALUES({sql_quote(show_id)},{sql_quote(idol_id)},'member');\n"""
        if (show_id, idol_id) not in skipped_rows and line not in text and line not in lines:
            lines.append(line)
    if lines:
        last = [m.end() for m in re.finditer(r"""^INSERT INTO "show_cast" VALUES.*\n""", text, re.M)]
        at = last[-1] if last else text.index(");\n", text.index('CREATE TABLE "show_cast"')) + 3
        sql_path.write_text(text[:at] + "".join(lines) + text[at:], encoding="utf-8")
    return [f"{s} / {i}" for s, i in rows if (s, i) in skipped_rows]


def apply(db_path: Path, sql_path: Path, plans: list[Plan], key_id: str, key_file: Path,
          notify: bool) -> None:
    backup = db_path.with_name(db_path.name + dt.datetime.now().strftime(".bak_%Y%m%d_%H%M%S"))
    shutil.copy2(db_path, backup)
    print(f"バックアップ: {backup.name}")
    rows = [(p.show.id, iid) for p in plans for iid in p.idol_ids]
    # 正本に足せない行は同梱 DB にも入れない (片方だけに入ると以後の実行では対象外になり、直らない)。
    missing = set(missing_in_master_sql(sql_path, rows))
    for show_id, idol_id in sorted(missing):
        print(f"⚠️ db/master.sql に公演かアイドルが無いので入れていない: {show_id} / {idol_id}")
    rows = [r for r in rows if r not in missing]
    if not rows:
        return
    append_master_sql(sql_path, rows)
    conn = sqlite3.connect(str(db_path))
    with conn:
        conn.executemany("INSERT OR IGNORE INTO show_cast (show_id, idol_id, cast_role) VALUES (?, ?, 'member')", rows)
    conn.close()
    print(f"master.sqlite と db/master.sql: {len(rows)} 行")

    show_ids = ",".join(dict.fromkeys(s for s, _ in rows))
    cmd = [sys.executable, str(TOOLS / "seed_cloudkit.py"), f"--key-id={key_id}", f"--key-file={key_file}",
           f"--db={db_path}", "--production", "--tables", "show_cast", "--ids", show_ids]
    if subprocess.run(cmd, cwd=str(ROOT)).returncode != 0:
        # 反映済みの公演は次の実行では対象外になるので、押し直しは seed_cloudkit を直接呼ぶ。
        print("⚠️ CloudKit への push に失敗。これで押し直す (冪等):\n  " + " ".join(cmd).replace(key_id, "$KID"))
        return
    if notify:
        lines = [discord_notify.cast_line([(p.show.id, f"{p.event_name} {p.show.name}", len(p.idol_ids)) for p in plans])]
        print("✓ Discord に投稿" if discord_notify.post_report(lines) else "(Discord へは出していない)")


# ---------------------------------------------------------------------------

def report(results: list[EventResult]) -> str:
    mark = {"ok": "✅ 入れられる", "warn": "⚠️ 要判断", "unresolved": "❌ 引けない名前あり"}
    out = []
    for r in results:
        out.append(f"## {r.event_name}\n{r.url or '-'}")
        for p in r.plans:
            out.append(f"- {mark[p.status]} {p.show.name} ({p.show.date}) {len(p.idol_ids)}人 `{p.show.id}`")
            out += [f"    - {w}" for w in p.warnings + p.unresolved]
        if r.note:
            out.append(f"- {r.note}")
        out.append("")
    return "\n".join(out)


def apply_rows(args) -> int:
    """--rows の TSV を反映する (--apply と同じ経路。出演者がもう入っている公演は触らない)。"""
    if not args.key_id:
        print("--rows には --key-id (CloudKit Production) が要る", file=sys.stderr)
        return 2
    by_show: dict[str, list[str]] = {}
    for line in args.rows.read_text(encoding="utf-8").splitlines():
        cols = line.split("\t")
        if len(cols) >= 2 and cols[0].strip():
            by_show.setdefault(cols[0].strip(), []).append(cols[1].strip())
    conn = sqlite3.connect(str(args.db))
    plans = []
    for show_id, idol_ids in by_show.items():
        row = conn.execute("SELECT s.name, s.date, e.name FROM shows s JOIN events e ON e.id = s.event_id WHERE s.id = ?",
                           (show_id,)).fetchone()
        unknown = [i for i in idol_ids if not conn.execute("SELECT 1 FROM idols WHERE id = ?", (i,)).fetchone()]
        has_cast = conn.execute("SELECT 1 FROM show_cast WHERE show_id = ?", (show_id,)).fetchone()
        if row is None or unknown or has_cast:
            why = "公演が無い" if row is None else f"アイドルが無い: {','.join(unknown)}" if unknown else "出演者が入っている"
            print(f"⚠️ {show_id}: {why} ので入れない")
            continue
        plans.append(Plan(Show(show_id, row[0], row[1], False), list(dict.fromkeys(idol_ids)), [], [], row[2]))
    conn.close()
    if plans:
        apply(args.db, args.master_sql, plans, args.key_id, args.key_file, not args.no_notify)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--db", type=Path, default=DB_PATH)
    ap.add_argument("--master-sql", type=Path, default=MASTER_SQL)
    ap.add_argument("--today", default=dt.date.today().isoformat())
    ap.add_argument("--since", help="この日以降の公演を見る (既定は今日。終わった公演をまとめて埋めるとき用)")
    ap.add_argument("--same-cast", action="append", default=[], metavar="EVENT_ID",
                    help="ページを見て全公演同じ出演者と確かめたイベント。一覧が 1 つなら全公演に当てる")
    ap.add_argument("--no-cms", action="store_true", help="公式ポータルの CMS API で探さない")
    ap.add_argument("--rows", type=Path, metavar="TSV",
                    help="ページから読めなかった公演を人が調べて入れる: show_id<TAB>idol_id[<TAB>出典] の TSV を反映する")
    ap.add_argument("--url", action="append", default=[], metavar="EVENT_ID=URL",
                    help="特設ページを指定する (ticket_url が無い・特設でない催し)")
    ap.add_argument("--apply", action="store_true", help="入れられる公演を反映する")
    ap.add_argument("--shows", help="反映する公演 id (カンマ区切り)。省略時は入れられる公演すべて")
    ap.add_argument("--allow-warnings", action="store_true", help="要判断の公演も入れる (--shows と一緒に使う)")
    ap.add_argument("--key-id", default=os.environ.get("CLOUDKIT_KEY_ID", ""))
    ap.add_argument("--key-file", type=Path, default=TOOLS / "eckey.pem")
    ap.add_argument("--no-notify", action="store_true", help="Discord に知らせない")
    ap.add_argument("--json", type=Path, help="結果を JSON でも書き出す")
    args = ap.parse_args()

    if args.rows:
        return apply_rows(args)
    overrides = dict(u.split("=", 1) for u in args.url)
    conn = sqlite3.connect(str(args.db))
    results = crawl(conn, args.today, overrides, cms=None if args.no_cms else Cms(),
                    since=args.since, same_cast=frozenset(args.same_cast))
    conn.close()
    print(report(results))
    if args.json:
        args.json.write_text(json.dumps([
            {"event_id": r.event_id, "event": r.event_name, "url": r.url, "note": r.note,
             "shows": [{"show_id": p.show.id, "show": p.show.name, "date": p.show.date, "status": p.status,
                        "idol_ids": p.idol_ids, "warnings": p.warnings, "unresolved": p.unresolved}
                       for p in r.plans]}
            for r in results], ensure_ascii=False, indent=2), encoding="utf-8")

    if not args.apply:
        return 0
    wanted = set(args.shows.split(",")) if args.shows else None
    if args.allow_warnings and not wanted:
        print("--allow-warnings は --shows で公演を絞って使う", file=sys.stderr)
        return 2
    if not args.key_id:
        print("--apply には --key-id (CloudKit Production) が要る", file=sys.stderr)
        return 2
    plans = [
        p for r in results for p in r.plans
        if (wanted is None or p.show.id in wanted)
        and (p.status == "ok" or (p.status == "warn" and args.allow_warnings))
    ]
    if not plans:
        print("反映する公演なし")
        return 0
    apply(args.db, args.master_sql, plans, args.key_id, args.key_file, not args.no_notify)
    return 0


if __name__ == "__main__":
    sys.exit(main())
