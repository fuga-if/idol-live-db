#!/usr/bin/env python3
"""add_anniversaries.py — 年表の節目 (anniversaries) を足す。

Usage:
    python3 tools/add_anniversaries.py            # 何が入るか見るだけ
    python3 tools/add_anniversaries.py --apply    # master.sqlite に反映

出典は各シリーズの Wikipedia 沿革 + 公式ニュース。公式サイトは RSS も sitemap も
無く、ニュース一覧は 403 で記事は内部 CMS API 越しなので、全記事を舐める方式は取らない。
整理済みの沿革から拾い、日付は公式記事で裏を取る。

粒度は既存21件に揃える。「稼働・配信開始」「サービス終了」「TVアニメ」「劇場版」
「受賞」だけを入れ、機能追加やイベント単発 (○○コラボ / ガチャ更新) は入れない。
年表は俯瞰するためのもので、細かい出来事を並べると節目が埋もれる。

⚠️ anniversaries は CloudKit 同期の対象外。同梱 master.sqlite の data_version を
   上げた reseed でしか既存ユーザーに届かない。
"""

import argparse
import os
import sqlite3
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DB_PATH = os.path.join(REPO, "ImasLiveDB", "Resources", "master.sqlite")
DUMP_PATH = os.path.join(REPO, "db", "master.sql")

# (brand_id, date, label, kind)
# kind: service_start / app_start / anime_start / movie_release / cd_debut
#     / service_end / award
ENTRIES = [
    # ---- 765AS: 家庭用移植とシリーズの節目 ----
    ("765as", "2007-01-25", "「THE IDOLM@STER」(Xbox 360)発売", "service_start"),
    ("765as", "2011-02-24", "「アイドルマスター2」発売", "service_start"),
    ("765as", "2025-03-26", "「アイドルマスター ツアーズ」稼働開始", "service_start"),

    # ---- シンデレラガールズ ----
    ("cg", "2014-11-17", "モバマス アプリ版配信開始", "app_start"),
    ("cg", "2015-07-10", "TVアニメ第2期放映開始", "anime_start"),
    ("cg", "2023-03-30", "モバマス サービス終了", "service_end"),
    ("cg", "2025-08-21", "デレステ(DMM版) サービス終了", "service_end"),

    # ---- ミリオンライブ ----
    ("ml", "2013-04-24", "CDシリーズ「LIVE THE@TER PERFORMANCE」開始", "cd_debut"),
    ("ml", "2018-03-19", "グリマス サービス終了", "service_end"),
    ("ml", "2026-07-15", "52週連続CD「SPECIAL SOLO RECORDS」完走・ギネス世界記録達成", "award"),

    # ---- SideM ----
    ("sidem", "2014-02-28", "モバゲー版SideM サービス開始(初回)", "service_start"),
    ("sidem", "2023-01-05", "モバゲー版SideM サービス終了", "service_end"),

    # ---- シャイニーカラーズ ----
    ("sc", "2019-03-13", "シャニマス アプリ版配信開始", "app_start"),
]

SOURCES = {
    "award": "https://idolmaster-official.jp/news/01_19422",
}


def entry_id(brand: str, date: str, kind: str) -> str:
    return f"ann_{brand}_{date.replace('-', '')}_{kind}"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    db = sqlite3.connect(DB_PATH)
    known = {r[0] for r in db.execute("SELECT id FROM anniversaries")}
    brands = {r[0] for r in db.execute("SELECT id FROM brands")}
    # 同じブランドの同じ日に同じ種別が既にあるなら重ねない。
    existing_keys = {(r[0], r[1], r[2])
                     for r in db.execute("SELECT brand_id, date, kind FROM anniversaries")}

    rows, skipped = [], []
    for brand, date, label, kind in ENTRIES:
        if brand not in brands:
            skipped.append(f"{label} (brand '{brand}' が存在しない)")
            continue
        key = (brand, date, kind)
        if key in existing_keys:
            skipped.append(f"{label} (同ブランド・同日・同種別が既にある)")
            continue
        rid = entry_id(brand, date, kind)
        if rid in known:
            skipped.append(f"{label} (id 重複)")
            continue
        rows.append((rid, brand, label, date, kind, 0))

    print(f"追加: {len(rows)} 件 / 見送り: {len(skipped)} 件")
    for r in rows:
        print(f"  {r[3]}  [{r[1]}] {r[2]}  ({r[4]})")
    for s in skipped:
        print(f"  - {s}")

    if not args.apply:
        print("\n(--apply で master.sqlite に反映する)")
        return

    db.executemany(
        "INSERT INTO anniversaries (id, brand_id, label, date, kind, sort_order)"
        " VALUES (?,?,?,?,?,?)", rows)
    db.commit()
    print(f"\nanniversaries に {len(rows)} 件追加した"
          f" (合計 {db.execute('SELECT count(*) FROM anniversaries').fetchone()[0]} 件)")

    with open(DUMP_PATH, "w", encoding="utf-8") as f:
        subprocess.run(["sqlite3", DB_PATH, ".dump"], stdout=f, check=True)
    print(f"{DUMP_PATH} を更新した")


if __name__ == "__main__":
    main()
