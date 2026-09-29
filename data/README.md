# data/ — データ投入口（追加も修正もここ）

アイドル・楽曲・ライブ等のデータに協力したい人のための投入口です。
`_template.json` をコピーして編集し、PR を送ってください。オーナーがレビュー後、
master.sqlite → CloudKit に一括反映します（直接 CloudKit に書く権限は不要）。

**2種類だけ覚えればOK:**

| やりたいこと | 置き場所 | 例 |
|---|---|---|
| **無いものを追加** | `data/<種類>/`（songs/setlists/events/shows/idols/units） | 新しい曲・ライブ・公演・セトリ・アイドルを足す |
| **あるものを修正** | `data/fixes/` | 配信日が違う・名前の誤字を直す |

## 流れ

1. ファイルを追加: 追加なら `data/<種類>/<topic>.json`、修正なら `data/fixes/<topic>.json`（各 `_template.json` をコピー）
2. **自己検証**（鍵不要）:
   ```bash
   python3 tools/apply_data.py --check
   ```
   id の存在/重複・参照先・brand_id・出典の有無をチェック。`✓ 全件妥当` で OK。
3. PR を送る。
4. オーナーがレビュー → `--apply --push` で反映。反映したファイルは `data/_applied/<種類>/` へ移す
   （`apply_data.py` はそこを読まない。PR 履歴と合わせて監査ログになる）。

## 追加（data/<種類>/）

| フォルダ | 追加するもの | 主なキー |
|---|---|---|
| `data/songs/` | 楽曲 | `id` `title` `brand_id` `song_type` `release_date` `original_singers[]` |
| | 合同曲なら + | `joint_brand_ids` (参加ブランドをカンマ区切り、`brand_id` 以外) `is_collab` |
| `data/setlists/` | セットリスト | `show_id` `songs[]`（`position` + `title`/`song_id` + `performers`） |
| `data/events/` | ライブ/イベント + 公演 | `events[]`（`id` `brand_id` `name` `kind` + `shows[]`） |
| `data/shows/` | 既にあるライブに公演を足す（ツアーの追加公演など） | `shows[]`（`id` `event_id` `name` `date` + 任意で `venue` `venue_id` `start_time` `sort_order`） |
| `data/idols/` | アイドル | `id` `name` `brand_id` `brands[]` |
| `data/units/` | ユニット | `id` `name` `brand_id` `members[]` |
| `data/creators/` | 作詞・作曲・編曲の作家 | `id` `name` `name_kana` |
| `data/unit_versions/` | ユニットのバージョン | `id` `unit_id` `name` (+ `code` `catchphrase` `valid_from` `valid_to`) |
| `data/costumes/` | ライブ衣装と、着た公演 | `id` `name` `wears[]`（`show_id` + 任意で `setlist_item_id` / `idol_id`） |

## 修正（data/fixes/）

既存レコードのフィールドを直す。対象テーブルは `idols / songs / events / shows / units / brands`。
```json
{ "fixes": [ { "table": "songs", "id": "対象id", "fields": { "release_date": "2024-09-04" } } ] }
```
曲の補足 (「ミリシタ 1 周年記念楽曲」のような由来・位置づけの 1 文) は songs の `note` に書く。
曲詳細 (iOS / Android / Web) の曲名の下にそのまま出るので、公式の出典があることだけを短く。
```json
{ "fixes": [ { "table": "songs", "id": "ml_union", "fields": { "note": "ミリシタ 1 周年記念楽曲" } } ] }
```
曲の原唱者が足りないときは `add_original_singers` に idol_id を並べる（`fields` と一緒でも、これだけでもよい）。
足すだけで、既存の原唱者は消えない（消す必要があるときは PR でオーナーに相談）。
```json
{ "fixes": [ { "table": "songs", "id": "ml_your_home_town", "add_original_singers": ["765as_双海亜美"] } ] }
```

## 値の決まり

- **brand_id**: `765as` / `cg` / `ml` / `sidem` / `sc`（シャニ）/ `gakuen`（学マス）/ `876` / `961` / `other`
- **song_type**: `solo` / `unit` / `all` / `tie_in` / `cover`
- **event kind**: `live` / `festival` / `release_event` / `radio` / `stream` / `other`
- **event event_type** (催しの性格): `anniversary` / `orchestra` / `external_event` /
  `birthday` / `release_event` / `broadcast` / `live`。
  配信があったかどうかは別の軸 (`shows.stream_platform`) なのでここには書かない。
  ミニライブのような**形式・規模も軸にしない** (理由は docs/DATA_PIPELINE.md)。
  **名前から決められなければ空のまま**にする
  (「オケマスを除けば」「周年では」の答えが推測で変わるため)。
  意味と優先順位は `docs/DATA_PIPELINE.md` 「events の種別 (event_type)」
- **id 規則**:
  - song: `{brand_id}_{タイトルのsnake_case}`
  - idol: `{brand_id}_{name}`
  - event: `ev_{slug}` / show: `sh_{slug}_{連番}`
  - setlist_item は自動採番（`{show_id}_{4桁position}`）
- **performers**（setlist）: `"all"`（= `all_performers` 全員）か `idol_id` 配列
- **衣装の `wears`**: `setlist_item_id` は分かるときだけ。省くと「この公演のどこか」の記録になる。
  `idol_id` も省いてよく、省くと「その場の全員」= 共通衣装。同じ曲でユニットごとに
  衣装が違うときだけ人ごとに書く。**着た公演が 1 つも無い衣装は入れない**

## 注意

- 事実情報は**必ず公式など一次ソースで確認**してから。**出典は投稿の `source` に書く（必須）**。
  ファイルの先頭に 1 つか、項目ごとに違うなら各項目に。値は URL か一次ソースの名前（CD の
  クレジット等）で、複数なら配列。DB に既にある値から導いたもの（曲名から起こした読み等）は
  `derived:<何から導いたか>` と書き、関係の無い URL を付けない。衣装は各衣装の `source_url` も
  出典に数える。`--check` は出典の無い投稿を落とす（中身が正しいかは見られないので、
  レビューで出典を開いて確かめる）。
- `apple_music_id` を入れる曲は `artwork_url` も入れる（一覧のジャケ写は `artwork_url` 直参照）。
- 楽曲は `original_singers`（原唱者）を必ず入れる（一覧の performer アイコン表示に必要）。
- 衣装に**画像は載せられない**（版権物を配らない方針）。名前と `source_url` で見分けられるようにする。
- 対象の id（show_id など）が分からなければアプリで探すか、PR 説明欄でオーナーに相談を。
