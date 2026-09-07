#!/usr/bin/env python3
"""migrate_song_collab.py — 合同曲 (コラボ曲) を songs に持たせる。

Usage:
    python3 tools/migrate_song_collab.py            # 何が起きるか見るだけ
    python3 tools/migrate_song_collab.py --apply    # master.sqlite に反映し db/master.sql を書き直す

## なぜ要るか

VOY@GER・なんどでも笑おう・POPLINKS TUNE!!!!! のようなシリーズ横断の曲が、
「765AS も参加している」というだけで brand_id='765as' に入っていた。ブランド別の曲一覧では
765AS の曲として出るのに、デレマス・ミリオンの一覧には出ない。

`events` はこの形をすでに持っている (`brand_id` + `joint_brand_ids` のカンマ区切り、合同ライブ
15 件)。曲にも同じ 2 列を足し、参加ブランド全部の一覧に出せるようにする。

## 合同曲と「在籍の重なり」を混同しない (この移行のいちばんの勘所)

原唱者のブランドが割れていても合同曲とは限らない:

- ML の曲 121 曲は原唱者に 765AS が混じる。ML の在籍に 765AS の 13 人が含まれるからで、
  合同ではない。これらに joint_brand_ids を入れると 765AS の曲一覧が ML の曲で溢れる。
- 876 の曲 4 曲は秋月涼 (brand_id='sidem') が入る。涼は Dearly Stars 出身で SideM に移った
  ためで、これも合同ではない。

なので **joint_brand_ids は合同曲にだけ入れる**。判断は下の COLLAB_SONG_IDS が持つ
(データから機械的に導くと上の 2 つを取り違える)。`is_collab` は今後の曲に人が立てる札で、
`is_collab=1` なら joint_brand_ids は空でない、という不変条件を core のテストが守る。
"""

from __future__ import annotations

import argparse
import os
import sqlite3
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DB_PATH = os.path.join(REPO, "ImasLiveDB", "Resources", "master.sqlite")
DUMP_PATH = os.path.join(REPO, "db", "master.sql")

# 合同曲。原唱者が 3 ブランド以上にまたがるもの全部 (19 曲) と、
# 「THE IDOLM@STER Best of 765+876=!!」の 2 曲 (765AS × 876 の企画盤)。
COLLAB_SONG_IDS = [
    "765as_the_idolmster_-rio_hamamoto_remix-",
    "765as_go_my_way_-esti_remix-",
    "765as_→→→sp",
    "765as_アイ_need_youfor_wonderful_story",
    "765as_kawaii_ウォーズ",
    "765as_poplinks_tune",
    "765as_voyger",
    "765as_なんどでも笑おう",
    "765as_ダンスダンスダンス",
    "765as_全力ドリーミングガールズ",
    "765as_crystloud",
    "765as_grtitude",
    "765as_session",
    "765as_アイシテの呪縛je_vous_aime",
    "765as_夏のbang",
    "765as_idol_power_rainbow",
    "cg_お願いシンデレラ_-山本真央樹_remix-",
    "765as_アイ_must_go",
    "765as_異次元bigbang",
    "765as_lost",
    "765as_the_愛",
]


def participating_brands(conn: sqlite3.Connection, song_id: str) -> list[str]:
    """原唱者の所属ブランドを brands.sort_order 順に。"""
    rows = conn.execute(
        """SELECT DISTINCT i.brand_id FROM song_artists sa
           JOIN idols i ON i.id = sa.idol_id
           JOIN brands b ON b.id = i.brand_id
           WHERE sa.song_id = ? AND sa.role = 'original'
           ORDER BY b.sort_order""",
        (song_id,),
    ).fetchall()
    return [r[0] for r in rows]


def add_columns(conn: sqlite3.Connection) -> None:
    cols = {r[1] for r in conn.execute("PRAGMA table_info(songs)")}
    if "joint_brand_ids" not in cols:
        conn.execute("ALTER TABLE songs ADD COLUMN joint_brand_ids TEXT")
    if "is_collab" not in cols:
        conn.execute("ALTER TABLE songs ADD COLUMN is_collab INTEGER NOT NULL DEFAULT 0")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    conn = sqlite3.connect(DB_PATH)
    add_columns(conn)

    missing = [
        sid for sid in COLLAB_SONG_IDS
        if not conn.execute("SELECT 1 FROM songs WHERE id = ?", (sid,)).fetchone()
    ]
    if missing:
        print("✗ 存在しない song id:", ", ".join(missing), file=sys.stderr)
        sys.exit(1)

    for sid in COLLAB_SONG_IDS:
        brand_id = conn.execute("SELECT brand_id FROM songs WHERE id = ?", (sid,)).fetchone()[0]
        others = [b for b in participating_brands(conn, sid) if b != brand_id]
        joint = ",".join(others)
        title = conn.execute("SELECT title FROM songs WHERE id = ?", (sid,)).fetchone()[0]
        print(f"  {title[:34]:<34} {brand_id:<6} + {joint}")
        conn.execute(
            "UPDATE songs SET joint_brand_ids = ?, is_collab = 1 WHERE id = ?",
            (joint or None, sid),
        )

    if not args.apply:
        conn.rollback()
        print(f"\n({len(COLLAB_SONG_IDS)} 曲。反映するには --apply)")
        return

    conn.commit()
    conn.close()
    with open(DUMP_PATH, "w", encoding="utf-8") as f:
        subprocess.run(["sqlite3", DB_PATH, ".dump"], stdout=f, check=True)
    # sqlite3 3.49+ の .dump は制御文字入りの文字列を unistr() で書く。古い sqlite3 でも
    # 読める形に均す (tools/normalize_master_sql.py と同じ理由)。
    sys.path.insert(0, HERE)
    import normalize_master_sql  # noqa: E402

    text = open(DUMP_PATH, encoding="utf-8").read()
    fixed, n = normalize_master_sql.normalize(text)
    if n:
        open(DUMP_PATH, "w", encoding="utf-8").write(fixed)
        print(f"  unistr() を {n} 箇所ほどいた")
    print(f"\n{DUMP_PATH} を更新した ({len(COLLAB_SONG_IDS)} 曲)")


if __name__ == "__main__":
    main()
