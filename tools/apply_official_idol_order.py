#!/usr/bin/env python3
"""apply_official_idol_order.py — ブランド内の並びを公式アイドル名鑑の掲載順に合わせる。

Usage:
    python3 tools/apply_official_idol_order.py            # 何が起きるか見るだけ
    python3 tools/apply_official_idol_order.py --apply    # master.sqlite に反映し db/master.sql を書き直す

## なぜ要るか

`idols.sort_order` はブランドごとの番号帯になった (tools/renumber_idol_sort_order.py) が、
**帯の中の並びは取り込み元の登録順のまま**で、根拠が無かった
(765AS が萩原雪歩から始まる、デレマスが大石泉から始まる、など)。

## 何を「公式順」とするか

**公式ポータルのアイドル名鑑 (idollist.idolmaster-official.jp/search) の掲載順。**
一次ソースがこれ以外に無い。名鑑はブランドごとに id を振っていて、その順が公式の並び:

- 765AS / デレマス / ミリオン / SideM / シャニマス … **五十音順**
  (シャニマスは初期 23 人が五十音、以降は加入順に後ろへ足されている)
- 学マス / 876 … **ロースター順** (花海咲季 から / 日高愛 から)

つまり**「ロースター順」という単一の規則は公式にも無い**。ブランドごとに違う並びを
公式がそのまま出しているので、その並びを写すのが唯一の正解になる。

## 名鑑に居ない人

音無小鳥 (アイドルではない)、シンデレラガールズ韓国版の 3 人、賀陽燐羽 (名鑑に未掲載)、
ラブライブのゲスト 48 人など。**帯の中の後ろに、今の並びのまま置く。**
名鑑に載ったら前へ移る。

## 名鑑の取り直し方

一覧はクライアント側で描かれるので `curl` では取れない。ブラウザで
`https://idollist.idolmaster-official.jp/search` を開き、次を実行して
`tools/data/official_idol_order.tsv` の見出し行より下を差し替える:

    [...document.querySelectorAll('a[href*="search/detail/"]')].map(a => {
      const t = a.innerText.trim().split('\\n').map(s => s.trim()).filter(Boolean);
      const li = a.closest('li') || a.parentElement;
      return [+a.getAttribute('href').split('/').pop(),
              (t[1] || '').replace(/[\\s　]+/g, ''),
              (li.className || '').replace('shadow cell', '').trim() || 'other'].join('\\t');
    }).join('\\n')
"""

from __future__ import annotations

import argparse
import os
import sqlite3
import subprocess
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DB_PATH = os.path.join(REPO, "ImasLiveDB", "Resources", "master.sqlite")
DUMP_PATH = os.path.join(REPO, "db", "master.sql")
ORDER_PATH = os.path.join(HERE, "data", "official_idol_order.tsv")

BLOCK = 1000


def key(name: str) -> str:
    """照合用の名前。全角/半角と空白の揺れだけを均す (別人を寄せない)。"""
    return unicodedata.normalize("NFKC", name).replace(" ", "").replace("　", "")


def load_official() -> dict[str, int]:
    order: dict[str, int] = {}
    with open(ORDER_PATH, encoding="utf-8") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            official_id, name, _brand = line.rstrip("\n").split("\t")
            order[key(name)] = int(official_id)
    return order


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    official = load_official()
    conn = sqlite3.connect(DB_PATH)
    brands = conn.execute("SELECT id, sort_order FROM brands ORDER BY sort_order").fetchall()

    updates: list[tuple[int, str]] = []
    unlisted: list[tuple[str, str]] = []
    for brand_id, brand_order in brands:
        rows = conn.execute(
            "SELECT id, name, sort_order FROM idols WHERE brand_id = ? ORDER BY sort_order, id",
            (brand_id,),
        ).fetchall()
        if not rows:
            continue
        # 名鑑に居る人が先 (名鑑の id 順)、居ない人は今の並びのまま後ろへ。
        listed = sorted(
            (r for r in rows if key(r[1]) in official), key=lambda r: official[key(r[1])]
        )
        rest = [r for r in rows if key(r[1]) not in official]
        unlisted += [(brand_id, r[1]) for r in rest]
        base = brand_order * BLOCK
        ordered = listed + rest
        if len(ordered) >= BLOCK:
            print(f"✗ {brand_id} が帯の幅 {BLOCK} を超える ({len(ordered)} 人)", file=sys.stderr)
            sys.exit(1)
        moved = sum(1 for n, r in enumerate(ordered) if r[2] != base + n + 1)
        print(f"{brand_id:<7} {len(listed):>3} 人を名鑑順に / 名鑑に無い {len(rest)} 人は末尾へ "
              f"(順番が変わるのは {moved} 人)  先頭 {ordered[0][1]}")
        for n, (idol_id, _, _) in enumerate(ordered, start=1):
            updates.append((base + n, idol_id))

    if unlisted:
        print("\n名鑑に載っていない (帯の末尾に置いた):")
        for brand_id, name in unlisted[:12]:
            print(f"  {brand_id:<7} {name}")
        if len(unlisted) > 12:
            print(f"  … 他 {len(unlisted) - 12} 人")

    # 名鑑にあってこちらに無い人 = 未登録のアイドル。黙って見逃さない。
    have = {key(r[0]) for r in conn.execute("SELECT name FROM idols")}
    missing = [n for n in official if n not in have]
    if missing:
        print(f"\n⚠️ 名鑑にあって DB に無い {len(missing)} 人: {', '.join(missing[:10])}")

    conn.executemany("UPDATE idols SET sort_order = ? WHERE id = ?", updates)
    flat = [r[0] for r in conn.execute(
        "SELECT b.sort_order FROM idols i JOIN brands b ON b.id = i.brand_id ORDER BY i.sort_order")]
    if flat != sorted(flat):
        print("✗ 振り直したらブランド順が崩れた", file=sys.stderr)
        sys.exit(1)
    print(f"\n✅ 公式順で並べるとブランド順になる ({len(flat)} 人)")

    if not args.apply:
        conn.rollback()
        print("\n(反映するには --apply)")
        return

    version = int(conn.execute("SELECT value FROM meta WHERE key = 'data_version'").fetchone()[0])
    conn.execute("UPDATE meta SET value = ? WHERE key = 'data_version'", (str(version + 1),))
    print(f"data_version {version} → {version + 1}")

    conn.commit()
    conn.close()
    with open(DUMP_PATH, "w", encoding="utf-8") as f:
        subprocess.run(["sqlite3", DB_PATH, ".dump"], stdout=f, check=True)
    sys.path.insert(0, HERE)
    import normalize_master_sql  # noqa: E402

    text = open(DUMP_PATH, encoding="utf-8").read()
    fixed, n = normalize_master_sql.normalize(text)
    if n:
        open(DUMP_PATH, "w", encoding="utf-8").write(fixed)
        print(f"  unistr() を {n} 箇所ほどいた")
    print(f"\n{DUMP_PATH} を更新した")


if __name__ == "__main__":
    main()
