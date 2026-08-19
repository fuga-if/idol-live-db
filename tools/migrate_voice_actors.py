#!/usr/bin/env python3
"""migrate_voice_actors.py — 声優を期間つきの履歴テーブルへ移す。

Usage:
    python3 tools/migrate_voice_actors.py            # 何が起きるか見るだけ
    python3 tools/migrate_voice_actors.py --apply    # master.sqlite に反映

なぜテーブルにするか:
    `idols.voice_actors` は "現役,過去CV" のカンマ区切りで、期間を持てない。
    実際そのせいで九十九一希の初代 (徳武竜也) が消えていて、2019年以前の楽曲や
    ライブが誰の声だったのか辿れなくなっていた。姫野かのんも同じ道をたどる。

    さらにこの列は4種類の別物が同居していた:
      1. 本当の交代      … 萩原雪歩 / 三峰結華 / 九十九一希 / 姫野かのん
      2. 同一人物の改名  … 馬場このみ (高橋未奈美 → 髙橋ミナミ)
      3. 表記ゆれ        … 鷺沢文香 (中黒が ・ と ･ で違うだけ)
      4. 舞台版キャスト  … SideM 11人。声優ではないので持たない

    4 は割り当てまでズレていた (Wikipedia の対応表と 11人中10人が不一致)。

形は venue_names に倣う。`valid_to IS NULL` が現任。
初代の valid_from は idols.debut_date (キャラの実装日) を使う。
"""

import argparse
import os
import sqlite3
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DB_PATH = os.path.join(REPO, "ImasLiveDB", "Resources", "master.sqlite")
DUMP_PATH = os.path.join(REPO, "db", "master.sql")

# 舞台版キャストが混ざっているアイドル。2人目を捨てる。
# (SideM に声優交代は無い。九十九一希の交代は下の HISTORY で別途扱う)
STAGE_CAST_IDOLS = {
    "sidem_天道輝", "sidem_桜庭薫", "sidem_柏木翼", "sidem_伊瀬谷四季",
    "sidem_冬美旬", "sidem_榊夏来", "sidem_秋山隼人", "sidem_花園百々人",
    "sidem_若里春名", "sidem_天峰秀", "sidem_眉見鋭心",
}

# 取り込み時の残骸。声優名から取り除く。
NAME_FIXES = {"八代拓）": "八代拓", "渡辺紘）": "渡辺紘"}

# 調べて確定させた履歴。ここに載せたアイドルは voice_actors を参照せずこの通りに入れる。
# (from, to, name)。to が None なら現任。
HISTORY = {
    # 2010-07-04 のライブで交代を発表。浅倉杏美の初登板はアイマス2 (2011)。
    "765as_萩原雪歩": [("2005-07-26", "2010-07-04", "落合祐里香"),
                     ("2010-07-04", None, "浅倉杏美")],
    # 成海瑠奈の芸能界引退に伴う交代。2022-01-18 に後任を発表。
    "sc_三峰結華": [("2018-04-24", "2021-12-01", "成海瑠奈"),
                  ("2022-01-18", None, "希水しお")],
    # 徳武竜也の声優業廃業 (2019-12-31)。2020-01-28 に後任を発表。
    # 旧 voice_actors には後任しか残っておらず、初代が消えていた。
    "sidem_九十九一希": [("2015-04-30", "2019-12-31", "徳武竜也"),
                       ("2020-01-28", None, "比留間俊哉")],
    # 2026-08-18 に村瀬歩の卒業を発表。後任は未定なので現任の行を作らない。
    "sidem_姫野かのん": [("2014-07-17", "2026-08-18", "村瀬歩")],
    # 声優交代ではなく同一人物の改名 (2020-12-20)。期間で分けると
    # 2020年以前の音源が誰名義だったかが残る。
    "ml_馬場このみ": [("2013-02-27", "2020-12-20", "高橋未奈美"),
                    ("2020-12-20", None, "髙橋ミナミ")],
    # 中黒が ・(U+30FB) と ･(U+FF65) で違うだけの同一人物。1行にまとめる。
    "cg_鷺沢文香": [(None, None, "M・A・O")],
}

# debut_date が空だったアイドル。実装日を調べて埋める。
# valid_from の根拠になるので、履歴を作る前にこちらを直す。
DEBUT_FIXES = {
    # 初代アイマス稼働時 (2005-07-26) から事務員として登場している。
    "765as_音無小鳥": "2005-07-26",
    # スターリットシーズン (2021-10-14 発売) の新アイドルとして初出。
    "961_奥空心白": "2021-10-14",
    # 極月学園のアイドルとして CV 込みで公開された日。
    "gakuen_賀陽燐羽": "2024-12-12",
}

SCHEMA = """
CREATE TABLE IF NOT EXISTS idol_voice_actors (
  id TEXT PRIMARY KEY NOT NULL,
  idol_id TEXT NOT NULL,
  name TEXT NOT NULL,
  valid_from TEXT,
  valid_to TEXT
);
CREATE INDEX IF NOT EXISTS idx_idol_voice_actors_idol ON idol_voice_actors(idol_id);
"""


def build_rows(db) -> list[tuple]:
    """履歴を作る対象はアイマスのアイドルだけ。

    brand_id='other' は歌枠でカバーした曲の原唱者 (ラブライブ等) として名前が
    あるだけで、このアプリが声優交代を追う対象ではない。debut_date も入っていない。
    """
    rows = []
    for idol_id, name, raw, debut in db.execute(
        "SELECT id, name, voice_actors, debut_date FROM idols WHERE brand_id IS NOT 'other'"
    ):
        if idol_id in HISTORY:
            for start, end, actor in HISTORY[idol_id]:
                rows.append((f"{idol_id}__{actor}", idol_id, actor,
                             start if start else debut, end))
            continue
        if not raw:
            continue
        names = [NAME_FIXES.get(n.strip(), n.strip()) for n in raw.split(",")]
        names = [n for n in names if n]
        if idol_id in STAGE_CAST_IDOLS:
            names = names[:1]   # 2人目は舞台版キャスト
        # 先頭 = 現役 という旧規約。ここまでで複数残るのは想定外なので知らせる。
        if len(names) > 1:
            print(f"  [warn] {name}: 複数残った {names} — 先頭のみ採用", file=sys.stderr)
            names = names[:1]
        rows.append((f"{idol_id}__{names[0]}", idol_id, names[0], debut, None))
    return rows


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    db = sqlite3.connect(DB_PATH)
    if args.apply:
        for idol_id, date in DEBUT_FIXES.items():
            db.execute("UPDATE idols SET debut_date=? WHERE id=? AND"
                       " (debut_date IS NULL OR debut_date='')", (date, idol_id))
    else:
        # dry-run でも埋めた後の件数が見えるように、メモリ上だけ反映する。
        for idol_id, date in DEBUT_FIXES.items():
            db.execute("UPDATE idols SET debut_date=? WHERE id=? AND"
                       " (debut_date IS NULL OR debut_date='')", (date, idol_id))
    rows = build_rows(db)
    have_from = sum(1 for r in rows if r[3])
    print(f"作る行: {len(rows)} 件 / valid_from あり {have_from} 件")
    print(f"履歴を持つアイドル: {len(HISTORY)} 人")
    print(f"舞台キャストを落としたアイドル: {len(STAGE_CAST_IDOLS)} 人")

    if not args.apply:
        print("\n=== 履歴のあるアイドル ===")
        for idol_id in HISTORY:
            for r in [x for x in rows if x[1] == idol_id]:
                print(f"  {idol_id}: {r[2]}  {r[3] or '?'} 〜 {r[4] or '(現任)'}")
        print("\n(--apply で master.sqlite に反映する)")
        return

    db.executescript(SCHEMA)
    db.execute("DELETE FROM idol_voice_actors")
    db.executemany(
        "INSERT INTO idol_voice_actors (id, idol_id, name, valid_from, valid_to)"
        " VALUES (?,?,?,?,?)", rows)
    # 列を落とす。履歴テーブルが正になったので、同じ値を2箇所で持たない。
    db.execute("ALTER TABLE idols DROP COLUMN voice_actors")
    db.commit()
    print(f"\nidol_voice_actors に {len(rows)} 行 / idols.voice_actors を削除した")

    with open(DUMP_PATH, "w", encoding="utf-8") as f:
        subprocess.run(["sqlite3", DB_PATH, ".dump"], stdout=f, check=True)
    print(f"{DUMP_PATH} を更新した")


if __name__ == "__main__":
    main()
