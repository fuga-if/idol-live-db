#!/usr/bin/env python3
"""
enrich_idol_profiles_from_sparql.py

im@sparql (https://sparql.crssnky.xyz/spql/imas/query) からアイドルのプロフィールを取得し、
master.sqlite の **空欄だけ** を gap-fill する (既存値は上書きしない)。
attribute は DB がブランド別タクソノミ (cute/cool/passion 等) で im@sparql の Vo/Da/Vi と
別物なので **対象外**。

usage:
  python3 tools/enrich_idol_profiles_from_sparql.py            # dry-run (差分表示のみ)
  python3 tools/enrich_idol_profiles_from_sparql.py --apply    # 反映
"""
import json
import sqlite3
import sys
import urllib.parse
import urllib.request
from pathlib import Path

DB = str(Path(__file__).resolve().parent.parent / "ImasLiveDB" / "Resources" / "master.sqlite")
ENDPOINT = "https://sparql.crssnky.xyz/spql/imas/query"

QUERY = """
PREFIX schema: <http://schema.org/>
PREFIX imas: <https://sparql.crssnky.xyz/imasrdf/URIs/imas-schema.ttl#>
SELECT ?name ?birthPlace ?birthDate ?height ?weight ?Bust ?Waist ?Hip ?BloodType ?Constellation ?Hobby ?cv WHERE {
  ?s schema:name ?name . FILTER(lang(?name)="ja")
  OPTIONAL { ?s schema:birthPlace ?birthPlace }
  OPTIONAL { ?s schema:birthDate ?birthDate }
  OPTIONAL { ?s schema:height ?height }
  OPTIONAL { ?s schema:weight ?weight }
  OPTIONAL { ?s imas:Bust ?Bust }
  OPTIONAL { ?s imas:Waist ?Waist }
  OPTIONAL { ?s imas:Hip ?Hip }
  OPTIONAL { ?s imas:BloodType ?BloodType }
  OPTIONAL { ?s imas:Constellation ?Constellation }
  OPTIONAL { ?s imas:Hobby ?Hobby }
  OPTIONAL { ?s imas:cv ?cv FILTER(isLiteral(?cv)) }
}
"""

# im@sparql の値 -> (DB列, 変換関数)。単値はそのまま、Hobby は集合→「、」結合。
SCALAR = {
    "birthPlace": "birth_place",
    "birthDate": "birthday",
    "BloodType": "blood_type",
    "Constellation": "constellation",
}
FLOAT = {"height": "height", "weight": "weight", "Bust": "bust", "Waist": "waist", "Hip": "hip"}


def fetch():
    url = ENDPOINT + "?" + urllib.parse.urlencode({"query": QUERY})
    req = urllib.request.Request(url, headers={"Accept": "application/sparql-results+json"})
    with urllib.request.urlopen(req, timeout=90) as r:
        return json.load(r)


def aggregate(data):
    """name -> {col: value}. Hobby/cv は複数行をまとめる。"""
    out = {}
    for b in data["results"]["bindings"]:
        name = b["name"]["value"]
        e = out.setdefault(name, {"hobby": set(), "cv": set()})
        for k, col in SCALAR.items():
            if k in b and col not in e:
                e[col] = b[k]["value"]
        for k, col in FLOAT.items():
            if k in b and col not in e:
                try:
                    e[col] = float(b[k]["value"])
                except ValueError:
                    pass
        if "Hobby" in b:
            e["hobby"].add(b["Hobby"]["value"])
        if "cv" in b:
            e["cv"].add(b["cv"]["value"])
    # Hobby/cv を確定
    for name, e in out.items():
        if e["hobby"]:
            e["hobbies"] = "、".join(sorted(e.pop("hobby")))
        else:
            e.pop("hobby", None)
        if e["cv"]:
            # CV は単一が基本。複数なら "、" 結合 (デュオ役等)。
            e["voice_actors"] = "、".join(sorted(e.pop("cv")))
        else:
            e.pop("cv", None)
    return out


def main():
    apply = "--apply" in sys.argv
    sp = aggregate(fetch())
    print(f"im@sparql: {len(sp)} idols fetched")

    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row
    rows = conn.execute("SELECT * FROM idols").fetchall()

    fill_cols = list(SCALAR.values()) + list(FLOAT.values()) + ["hobbies", "voice_actors"]
    counts = {c: 0 for c in fill_cols}
    matched = 0
    unmatched = []
    updates = []  # (id, {col:val})

    for row in rows:
        prof = sp.get(row["name"])
        if not prof:
            unmatched.append(row["name"])
            continue
        matched += 1
        setvals = {}
        for col in fill_cols:
            cur = row[col]
            is_empty = cur is None or (isinstance(cur, str) and cur.strip() == "")
            if is_empty and col in prof and prof[col] not in (None, ""):
                setvals[col] = prof[col]
                counts[col] += 1
        if setvals:
            updates.append((row["id"], setvals))

    print(f"DB idols: {len(rows)} / im@sparql名一致: {matched} / 一致せず: {len(unmatched)}")
    print("gap-fill 予定 (空欄のみ):")
    for c in fill_cols:
        if counts[c]:
            print(f"  {c:13} +{counts[c]}")
    print(f"更新対象アイドル: {len(updates)}人")
    if unmatched:
        print(f"\n[im@sparqlに無い/名前不一致 {len(unmatched)}人(新ブランド等→二次ソース対象)]")
        print("  " + "  ".join(unmatched[:40]) + (" ..." if len(unmatched) > 40 else ""))

    if apply and updates:
        for idol_id, setvals in updates:
            cols = ", ".join(f"{c}=?" for c in setvals)
            conn.execute(f"UPDATE idols SET {cols} WHERE id=?", list(setvals.values()) + [idol_id])
        conn.commit()
        print(f"\n✅ applied: {len(updates)} idols updated")
    elif not apply:
        print("\n(dry-run。--apply で反映)")
    conn.close()


if __name__ == "__main__":
    main()
