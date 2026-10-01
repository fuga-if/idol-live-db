# data/personas

キャラとのトーク・タイムライン (アプリ内のオプトイン機能、試作) で使う「話し方」のデータ。
imas-core (`agent::tools::speech`) がアプリに同梱して読む。DB や CloudKit には入れていない。

- `<brand>.json` — 1 人ずつ出典を確かめた話し方。`idol_id` / `name` / `first_person` /
  `producer_call` / `politeness` / `endings` / `catchphrases` / `tone_notes` / `sources` の配列。
  一人称・呼び方は文字列 / 文字列の配列 / `{form, scene}` の配列のどれでもよい。
  ブランドを足したら `imas-core/src/agent/tools/speech.rs` の `PERSONA_FILES` に 1 行足す。
- `call_names.json` — 誰が誰をどう呼ぶか (`from` / `to` (`producer` はプロデューサー) / `called`)。
  [im@sparql](https://github.com/crssnky/imasparql) の呼称データ (imas:CallName) を
  `tools/fetch_call_names_from_sparql.py` でこちらのアイドル id に突き合わせたもの。
  im@sparql は MIT License (`LICENSE-imasparql.txt`)。

セリフ (コミュの台本) は書き写しなので入れない。
