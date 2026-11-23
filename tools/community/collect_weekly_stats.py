#!/usr/bin/env python3
"""collect_weekly_stats.py — 終わった週の再生回数と、お気に入り数を週ごとに写し取る。

週次チャート (先週比・初登場・連続ランクイン) の材料。

なぜ要るのか:
    D1 の song_play_counts は 1 曲 1 行で、累計・今週・先週しか持たない
    (imas-live-api/migrations/0052)。週が変わると 2 週前の数は消えるので、
    過去の週の順位は後から作れない。お気に入りは累計しか無い。
    ここで週に 1 枚ずつ残しておけば、順位は後からいつでも出せる。

仕組み:
    GET /community/song-stats (全曲の数。鍵は要らない) を読み、
    「いま終わっている最新の週」W (JST の月曜始まり) の 1 枚を
    data/community_weekly/<W の月曜>.tsv に書く。

        song_id  preview  full  favorites
        preview / full = W の 1 週間に再生された回数 (試聴 / フル再生)
        favorites      = W が終わった時点のお気に入り数 (累計)

    W の再生回数は行の week から読む (plays.ts の UPSERT と同じ読み替え):
        week == 今週      → prev_week_*
        week == W         → week_*      (今週まだ 1 回も再生されていない曲)
        それより古い / 無い → 0

    毎日走らせる。
      - 再生回数は毎回書き直す。端末は貯めた分を後から送るので、W の数は
        週が明けてからも少し増える。
      - お気に入り数は最初に書いた値を変えない。累計なので、後の日に
        取り直すと「W が終わった時点」でなくなる。
    週の増分 (その週に付いたお気に入り) は、前の週のファイルとの差で出す。

⚠️ 遡れるのは W だけ。このバッチが 1 週間止まると、その週の再生回数は
   取り返せない (D1 にもう無い)。

使い方:
    python3 tools/community/collect_weekly_stats.py --out-dir data/community_weekly
"""
from __future__ import annotations  # macOS 同梱の Python 3.9 でも `str | None` 注釈を許す

import argparse
import datetime as dt
import json
import sys
import urllib.request
from pathlib import Path

API_URL = "https://imas-live-api.tokata3011.workers.dev/community/song-stats"
HEADER = ["song_id", "preview", "full", "favorites"]
JST = dt.timezone(dt.timedelta(hours=9))


def jst_week_of(epoch_seconds: int) -> dt.date:
    """その時刻の JST の週の月曜 (plays.ts jstWeekOf / imas-core week_of と同じ)。"""
    day = dt.datetime.fromtimestamp(epoch_seconds, JST).date()
    return day - dt.timedelta(days=day.weekday())


def fetch_stats(opener=urllib.request.urlopen, now: int | None = None) -> dict:
    # エッジは 30 分 (+ 古いまま 60 分) 持つ。週の変わり目に前の週の応答を掴むと
    # お気に入りの写し取りが 1 日遅れるので、問い合わせを毎回変えて作りたてを読む。
    stamp = now if now is not None else int(dt.datetime.now(dt.timezone.utc).timestamp())
    req = urllib.request.Request(f"{API_URL}?t={stamp}", headers={"User-Agent": "weekly-stats-collector"})
    with opener(req, timeout=60) as res:
        return json.load(res)


def finished_week_rows(stats: dict) -> tuple[dt.date, dict[str, tuple[int, int, int]]]:
    """(終わった最新の週の月曜, {song_id: (preview, full, favorites)})。全部 0 の曲は入れない。"""
    songs = stats.get("songs")
    generated_at = stats.get("generated_at")
    if not isinstance(songs, list) or not songs or not isinstance(generated_at, int):
        raise ValueError("song-stats の応答が空か、形が違う")
    current = jst_week_of(generated_at)
    finished = current - dt.timedelta(days=7)
    rows: dict[str, tuple[int, int, int]] = {}
    for s in songs:
        week = s.get("week")
        if week == current.isoformat():
            preview, full = s.get("prev_week_preview", 0), s.get("prev_week_full", 0)
        elif week == finished.isoformat():
            preview, full = s.get("week_preview", 0), s.get("week_full", 0)
        else:
            preview, full = 0, 0
        favorites = s.get("favorites", 0)
        if preview or full or favorites:
            rows[s["song_id"]] = (int(preview), int(full), int(favorites))
    return finished, rows


def read_tsv(path: Path) -> dict[str, tuple[int, int, int]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].split("\t") != HEADER:
        raise ValueError(f"{path}: 見出しが違う")
    out = {}
    for line in lines[1:]:
        song_id, preview, full, favorites = line.split("\t")
        out[song_id] = (int(preview), int(full), int(favorites))
    return out


def merge(existing: dict[str, tuple[int, int, int]] | None,
          fresh: dict[str, tuple[int, int, int]]) -> dict[str, tuple[int, int, int]]:
    """再生回数は取り直した値、お気に入りは最初に書いた値。"""
    if existing is None:
        return fresh
    merged = {}
    for song_id in existing.keys() | fresh.keys():
        preview, full, _ = fresh.get(song_id, (0, 0, 0))
        favorites = existing.get(song_id, (0, 0, 0))[2]
        if preview or full or favorites:
            merged[song_id] = (preview, full, favorites)
    return merged


def write_tsv(path: Path, rows: dict[str, tuple[int, int, int]]) -> None:
    body = ["\t".join(HEADER)]
    body += [f"{song_id}\t{p}\t{f}\t{fav}" for song_id, (p, f, fav) in sorted(rows.items())]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(body) + "\n", encoding="utf-8")


def collect(out_dir: Path, stats: dict) -> Path:
    week, fresh = finished_week_rows(stats)
    path = out_dir / f"{week.isoformat()}.tsv"
    existing = read_tsv(path) if path.exists() else None
    write_tsv(path, merge(existing, fresh))
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()
    path = collect(args.out_dir, fetch_stats())
    print(f"{path}: {len(read_tsv(path))} 曲")
    return 0


if __name__ == "__main__":
    sys.exit(main())
