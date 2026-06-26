#!/usr/bin/env python3
"""im@sparql から全アイドルの姓・名 (+ ふりがな) を取得して JSON に保存する。

idols.name (フルネーム) をキーに master.sqlite とマッチするためのデータ。
"""
from __future__ import annotations

import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path


SPARQL_ENDPOINT = "https://sparql.crssnky.xyz/spql/imas/query"
QUERY = """
PREFIX schema: <http://schema.org/>
PREFIX imas: <https://sparql.crssnky.xyz/imasrdf/URIs/imas-schema.ttl#>
SELECT DISTINCT ?name ?familyName ?givenName ?kana ?alt
WHERE {
  ?idol a imas:Idol ;
    schema:name ?name ;
    schema:familyName ?familyName ;
    schema:givenName ?givenName .
  OPTIONAL { ?idol imas:nameKana ?kana }
  OPTIONAL { ?idol schema:alternateName ?alt . FILTER (lang(?alt) = "ja") }
  FILTER (lang(?name) = "ja" && lang(?familyName) = "ja" && lang(?givenName) = "ja")
}
"""
OUT_PATH = Path(__file__).resolve().parent / "idol_names.json"


def fetch() -> list[dict]:
    url = f"{SPARQL_ENDPOINT}?{urllib.parse.urlencode({'query': QUERY})}"
    req = urllib.request.Request(url, headers={"Accept": "application/sparql-results+json"})
    with urllib.request.urlopen(req) as r:
        data = json.load(r)
    records = []
    for b in data.get("results", {}).get("bindings", []):
        records.append({
            "name": b["name"]["value"],
            "family_name": b["familyName"]["value"],
            "given_name": b["givenName"]["value"],
            "kana": b.get("kana", {}).get("value", ""),
            "nickname": b.get("alt", {}).get("value", ""),
        })
    return records


def main() -> None:
    records = fetch()
    # full_name 単位でユニーク化 (ja のみ取れてても重複する可能性への保険)
    seen = {}
    for rec in records:
        n = rec["name"]
        if n not in seen:
            seen[n] = rec
    unique = list(seen.values())
    OUT_PATH.write_text(json.dumps(unique, ensure_ascii=False, indent=2))
    print(f"Fetched {len(records)} records, unique {len(unique)} full names", file=sys.stderr)
    print(f"Written to {OUT_PATH}")


if __name__ == "__main__":
    main()
