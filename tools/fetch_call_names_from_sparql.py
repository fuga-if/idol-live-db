#!/usr/bin/env python3
"""
fetch_call_names_from_sparql.py

im@sparql (MIT License, https://github.com/crssnky/imasparql) の呼称データ
(imas:CallName = 誰が誰をどう呼ぶか) を取得し、こちらのアイドル id に突き合わせて
data/personas/call_names.json に書き出す。キャラとのトーク・タイムラインの指示文が使う
(imas-core の agent::tools::persona が同梱して読む)。

- 突き合わせはアイドルの日本語名 (空白を除いて完全一致)。当たらない行は落とし、件数を出す。
- 呼ぶ相手がプロデューサーの行は to = "producer"。
- セリフ (imas:ScriptText) は台本の書き写しなので取り込まない。

usage:
  python3 tools/fetch_call_names_from_sparql.py           # 取得して書き出す
"""
import json
import sqlite3
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "ImasLiveDB" / "Resources" / "master.sqlite"
OUT = ROOT / "data" / "personas" / "call_names.json"
ENDPOINT = "https://sparql.crssnky.xyz/spql/imas/query"
PRODUCER = "https://sparql.crssnky.xyz/imasrdf/RDFs/detail/Producer"

QUERY = """
PREFIX schema: <http://schema.org/>
PREFIX imas: <https://sparql.crssnky.xyz/imasrdf/URIs/imas-schema.ttl#>
SELECT ?src ?srcName ?dest ?destName ?called WHERE {
  ?s a imas:CallName ; imas:Source ?src ; imas:Destination ?dest ; imas:Called ?called .
  ?src schema:name ?srcName . FILTER(lang(?srcName) = "ja")
  OPTIONAL { ?dest schema:name ?destName . FILTER(lang(?destName) = "ja") }
}
"""


def fetch():
    url = ENDPOINT + "?" + urllib.parse.urlencode({"query": QUERY})
    req = urllib.request.Request(url, headers={"Accept": "application/sparql-results+json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r)["results"]["bindings"]


def norm(name):
    return "".join(name.split())


def main():
    con = sqlite3.connect(DB)
    by_name = {}
    for idol_id, name in con.execute("SELECT id, name FROM idols WHERE is_external = 0"):
        by_name.setdefault(norm(name), []).append(idol_id)
    # 同名のアイドルがいる名前は突き合わせに使わない (取り違えるより落とす)。
    unique = {k: v[0] for k, v in by_name.items() if len(v) == 1}

    rows, unmatched = set(), set()
    for b in fetch():
        src = unique.get(norm(b["srcName"]["value"]))
        if b["dest"]["value"] == PRODUCER:
            dest = "producer"
        else:
            dest = unique.get(norm(b.get("destName", {}).get("value", "")))
        called = b["called"]["value"].strip()
        if not src or not dest or not called:
            unmatched.add((b["srcName"]["value"], b.get("destName", {}).get("value", b["dest"]["value"])))
            continue
        rows.add((src, dest, called))

    out = [{"from": f, "to": t, "called": c} for f, t, c in sorted(rows)]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"書き出し {len(out)} 件 → {OUT.relative_to(ROOT)} (突き合わせできず {len(unmatched)} 組)")


if __name__ == "__main__":
    main()
