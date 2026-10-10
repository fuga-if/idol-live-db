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
| `data/idol_hairstyles/` `data/idol_facets/` | アイドルの髪型・項目 | 下の「アイドルの項目」 |
| `data/ticket_sales/` | チケット受付（抽選・先着・リセール・当日券） | `event_id` `kind` `name` `source_url` + 任意で `show_ids[]` `starts_at`/`ends_at`/`result_at` `url` `note` `sort_order` |

## 修正（data/fixes/）

既存レコードのフィールドを直す。対象テーブルは `idols / songs / events / shows / units / brands / ticket_sales / idol_facets / idol_hairstyles`
（`venues` `venue_names` `creators` `setlist_items` も対象）。チケット受付の締切延長などは
`{ "fixes": [ { "table": "ticket_sales", "id": "対象id", "fields": { "ends_at": "2026-04-20 23:59" } } ] }`。
```json
{ "fixes": [ { "table": "songs", "id": "対象id", "fields": { "release_date": "2024-09-04" } } ] }
```
曲の日付は 3 つある。`release_date` は**初出** (ゲームへの実装・MV の公開・アニメの放送を含め、
最初に世に出た日)、`cd_release_date` は最初に収録された CD の発売日、`streaming_date` は配信開始日。
ライブでの初披露はセトリから出すので書かない (画面の「初出」は release_date と初披露の早いほう)。
初出が何だったか (「TVアニメ第14話 新OP」) は `first_appearance_note` に短く書くと、初出の行に添えて出る。
```json
{ "fixes": [ { "table": "songs", "id": "765as_change", "fields": { "cd_release_date": "2011-11-09" } } ] }
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

## アイドルの項目 (性格・好み・髪型など)

アイドルの細かい情報は、プロフィールの列 (誕生日・身長など) のほかに**項目 (ファセット)** として持つ。
項目の一覧・値の語彙は `imas-core/facets.json` (唯一の正は `imas-core/src/domain/idol_facets.rs`)。
設計と使われ方は [`docs/ARCHITECTURE-facets.md`](../docs/ARCHITECTURE-facets.md)。

| 置き場所 | 持つもの |
|---|---|
| `data/idol_hairstyles/` | **髪型**。1 人に複数 (基本 / セカンドヘア / 覚醒後 …)。`is_main: true` がちょうど 1 つ |
| `data/idol_facets/` | 髪以外の項目 (目の色・眼鏡・性格・好きな食べ物・経歴・方言 …)。1 値 1 行 |

```json
{ "source": "https://…", "idol_hairstyles": [
  { "idol_id": "765as_星井美希", "label": "基本", "is_main": true,
    "hair_color": "金", "hair_length": "ロング", "styles": ["ウェーブ", "アホ毛"] },
  { "idol_id": "765as_星井美希", "label": "覚醒後", "is_main": false,
    "hair_color": "茶", "hair_length": "ショート" } ] }
```
```json
{ "source": "https://…", "idol_facets": [
  { "idol_id": "sidem_桜庭薫", "facet": "glasses", "value": true },
  { "idol_id": "765as_天海春香", "facet": "favorite_foods", "values": ["お菓子"], "source_note": "…" } ] }
```
- 髪型の列: `hair_color` `hair_color_secondary` `hair_length` `styles[]` `bangs` `accessories[]`
  (値は facets.json の語彙)。**main の付け替え**は `{"set_main": [{"idol_id": "…", "label": "覚醒後"}]}`。
- `idol_facets` の `facet` は facets.json の `store: "idol_facets"` の項目だけ。年齢帯・出身地方・色名など
  自動で決まるもの (`computed`) と髪 (`idol_hairstyles`) は書けない。`origin` は `official`(既定) か
  `promoted` (タグの票から昇格した値)。単一値の項目は 1 人 1 行で、直すなら `data/fixes/`
  (`{"table": "idol_facets", "id": "<行 id>", "fields": {"value": "…"}}`。行 id は
  `if_` + sha1(`idol_id|facet`[`|value` 複数値だけ]) の先頭 20 桁で、`tools/apply_data.py` の `facet_row_id`)。
- ファイルの先頭に `"unconfirmed": "理由"` を書くと、`--check` は通すが `--apply` は入れない
  (確認待ちの下書き置き場)。
- 反映は他の投稿と同じ (`--check` → `--apply --push`)。**CloudKit の IdolFacet / IdolHairstyle は
  Production に未昇格**のあいだ、`--push` は失敗する。手順は ARCHITECTURE-facets.md §8。

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
  - ticket_sales も自動採番（`event_id` + `name` から決まる。id は書かない）
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
