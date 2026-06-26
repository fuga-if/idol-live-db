# data/ — データ投入口（追加も修正もここ）

アイドル・楽曲・ライブ等のデータに協力したい人のための投入口です。
`_template.json` をコピーして編集し、PR を送ってください。オーナーがレビュー後、
master.sqlite → CloudKit に一括反映します（直接 CloudKit に書く権限は不要）。

**2種類だけ覚えればOK:**

| やりたいこと | 置き場所 | 例 |
|---|---|---|
| **無いものを追加** | `data/<種類>/`（songs/setlists/events/idols/units） | 新しい曲・ライブ・セトリ・アイドルを足す |
| **あるものを修正** | `data/fixes/` | 配信日が違う・名前の誤字を直す |

## 流れ

1. ファイルを追加: 追加なら `data/<種類>/<topic>.json`、修正なら `data/fixes/<topic>.json`（各 `_template.json` をコピー）
2. **自己検証**（鍵不要）:
   ```bash
   python3 tools/apply_data.py --check
   ```
   id の存在/重複・参照先・brand_id・出典の有無をチェック。`✓ 全件妥当` で OK。
3. PR を送る。
4. オーナーがレビュー → `--apply --push` で反映。反映後ファイルは削除（PR 履歴が監査ログ）。

## 追加（data/<種類>/）

| フォルダ | 追加するもの | 主なキー |
|---|---|---|
| `data/songs/` | 楽曲 | `id` `title` `brand_id` `song_type` `release_date` `original_singers[]` |
| `data/setlists/` | セットリスト | `show_id` `songs[]`（`position` + `title`/`song_id` + `performers`） |
| `data/events/` | ライブ/イベント + 公演 | `events[]`（`id` `brand_id` `name` `kind` + `shows[]`） |
| `data/idols/` | アイドル | `id` `name` `brand_id` `brands[]` |
| `data/units/` | ユニット | `id` `name` `brand_id` `members[]` |

## 修正（data/fixes/）

既存レコードのフィールドを直す。対象テーブルは `idols / songs / events / shows / units / brands`。
```json
{ "fixes": [ { "table": "songs", "id": "対象id", "fields": { "release_date": "2024-09-04" }, "source": "https://出典" } ] }
```

すべてのエントリに **`source`（出典URL・一次ソース）が必須**です。

## 値の決まり

- **brand_id**: `765as` / `cg` / `ml` / `sidem` / `sc`（シャニ）/ `gakuen`（学マス）/ `876` / `961` / `other`
- **song_type**: `solo` / `unit` / `all` / `tie_in` / `cover`
- **event kind**: `live` / `festival` / `release_event` / `radio` / `stream` / `other`
- **id 規則**:
  - song: `{brand_id}_{タイトルのsnake_case}`
  - idol: `{brand_id}_{name}`
  - event: `ev_{slug}` / show: `sh_{slug}_{連番}`
  - setlist_item は自動採番（`{show_id}_{4桁position}`）
- **performers**（setlist）: `"all"`（= `all_performers` 全員）か `idol_id` 配列

## 注意

- 事実情報は**必ず公式など一次ソースで確認**してから（`source` に URL）。
- `apple_music_id` を入れる曲は `artwork_url` も入れる（一覧のジャケ写は `artwork_url` 直参照）。
- 楽曲は `original_singers`（原唱者）を必ず入れる（一覧の performer アイコン表示に必要）。
- 対象の id（show_id など）が分からなければアプリで探すか、PR 説明欄でオーナーに相談を。
