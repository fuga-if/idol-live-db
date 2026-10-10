# アイドルの項目 (ファセット) アーキテクチャ

> アイドルの情報を**細かい項目**に分けて、項目ごとに「値」と「出どころ」を持つ。最初の利用者は
> yesno (当てっこゲーム。アイドルの知識をカテゴリ別に Jev に渡して yes/no を判定させる)。
> 読む口は公開データ API の `GET /v1/idols/:id/facts` ([`ARCHITECTURE-data-api.md`](ARCHITECTURE-data-api.md))
> と MCP の `get_idol_facts` ([`ARCHITECTURE-mcp.md`](ARCHITECTURE-mcp.md))。
> 入れ方は [`data/README.md`](../data/README.md)、データの流れは [`DATA_PIPELINE.md`](DATA_PIPELINE.md)。

> 状態: **実装済み・未デプロイ** (2026-10-11)。CloudKit のスキーマ昇格・push・本番 D1 への反映はオーナーの操作 (§9)。

## 1. 決めたこと

| 論点 | 決定 |
|---|---|
| 定義の唯一の正 | `imas-core/src/domain/idol_facets.rs` の `FACETS`。`imas-core/facets.json` はその書き出しで、テストが一致を固定する (更新は `UPDATE_FACETS_JSON=1 cargo test idol_facets`)。タグ側・Python ツール・yesno は facets.json を読む |
| 項目の数 | 63 (7 カテゴリ)。足し引きは `FACETS` に 1 行 |
| 値の出どころ | `official` (マスタの公式の列・`idol_facets` / `idol_hairstyles` の公式の行) / `promoted` (タグの票から昇格して保存した値) / `tag` (タグの票。票数つき)。食い違ったら official > promoted > tag |
| 髪の持ち方 | 項目の値ではなく**髪型 1 つぶんのまとまり** `idol_hairstyles` (1 人に複数、`is_main` はちょうど 1 つ)。セカンドヘア・覚醒後のような「版」は髪型を足して表す |
| 髪以外の容姿・性格・好み・経歴 | `idol_facets` (1 値 1 行) |
| 組み立て | 純粋関数 `build_idol_facts` (imas-core domain)。入力はマスタ + `idol_facets` + `idol_hairstyles` + 話し方 + タグの票の写し。D1 には**同期のときに 1 度だけ**組んで `docs(kind='facts')` に置く |
| `description` | `summary` として**項目に振らず別に持つ** (長い自由文で、趣味・経歴・性格が混ざる。項目に割ると同じ情報が二重になる。Jev には要約として渡せる) |
| 体重・スリーサイズ | `/facts` には入れない (§6) |

## 2. 項目の一覧

値の型: 単一値 = `{"value","source"}` / 複数値 = `{"values":[{"value","source"}]}` / 数値・真偽 / 色 = `{"hex","name"}`。
「項目行」= `idol_facets` の行に書ける項目 (マスタの列がある項目は**列が勝ち、行は列が空のときの補い**。例: 性別が空の子)、
「髪型」= `idol_hairstyles`、「自動」= マスタの列・表から計算する項目 (`idol_facets` には書けない)。「確定」= 機械的な変換、「推定」= 他の値に負ける推定。
`照合専用` は Jev に渡さない全件 (質問に曲名・ユニット名・ライブ名が出たときの突き合わせ用)。
公式の列・表から来る値 (誕生日・身長・趣味・曲・ライブなど) の出どころは `official`。

| 項目 | 型 | 値の語彙 | 保存先 | 備考 |
|---|---|---|---|---|
| **プロフィール** (`profile`) | | | | |
| `gender` 性別 | 単一値 | 女性 / 男性 | 項目行 |  |
| `age` 年齢 | 数値 | 自由 | 項目行 |  |
| `age_band` 年齢帯 | 単一値 | 10歳未満 / 10代 / 20代 / 30代 / 40代以上 | 自動 | 確定 |
| `school_stage` 学校の段階 | 単一値 | 小学生 / 中学生 / 高校生 / 大学生 / 社会人 | 項目行 | 推定 |
| `birthday` 誕生日 | 単一値 | 自由 | 項目行 |  |
| `birth_month` 誕生月 | 数値 | 自由 | 自動 | 確定 |
| `constellation` 星座 | 単一値 | 牡羊座 / 牡牛座 / 双子座 / 蟹座 / 獅子座 / 乙女座 / 天秤座 / 蠍座 / 射手座 / 山羊座 / 水瓶座 / 魚座 | 項目行 |  |
| `height_cm` 身長 | 数値 | 自由 | 項目行 |  |
| `height_band` 身長帯 | 単一値 | 140cm未満 / 140cm台 / 150cm台 / 160cm台 / 170cm以上 | 自動 | 確定 |
| `blood_type` 血液型 | 単一値 | A / B / O / AB | 項目行 |  |
| `handedness` 利き手 | 単一値 | 右利き / 左利き / 両利き | 項目行 |  |
| `birthplace` 出身地 | 単一値 | 自由 | 項目行 |  |
| `birthplace_region` 出身地方 | 単一値 | 北海道 / 東北 / 関東 / 中部 / 近畿 / 中国 / 四国 / 九州・沖縄 / 海外 | 自動 | 確定 |
| `nationality` 国籍 | 単一値 | 自由 | 項目行 |  |
| `school` 学校 | 単一値 | 自由 | 自動 | 確定 |
| `grade` 学年 | 単一値 | 自由 | 項目行 |  |
| **容姿** (`appearance`) | | | | |
| `hair_color` 髪色 | 単一値 | 黒 / 茶 / 金 / 白・銀 / 赤 / オレンジ / ピンク / 緑 / 青 / 水色 / 紫 | 髪型 |  |
| `hair_color_secondary` 髪色 (2色目) | 単一値 | 黒 / 茶 / 金 / 白・銀 / 赤 / オレンジ / ピンク / 緑 / 青 / 水色 / 紫 | 髪型 |  |
| `hair_length` 髪の長さ | 単一値 | ロング / ボブ〜ミディアム / ショート | 髪型 |  |
| `hair_style` 髪型 | 複数値 | 22 語 (facets.json) | 髪型 |  |
| `bangs` 前髪 | 単一値 | ぱっつん / センター分け / 片目隠れ / おでこ | 髪型 |  |
| `hair_accessory` 髪飾り | 複数値 | リボン / ヘアバンド / ヘアピン / その他の髪飾り | 髪型 |  |
| `eye_color` 目の色 | 単一値 | 黒 / 茶 / 青 / 水色 / 緑 / 赤 / ピンク / 紫 / 金 / オレンジ / 灰 | 項目行 |  |
| `glasses` 眼鏡 | 真偽 | 自由 | 項目行 |  |
| `image_color` イメージカラー | 色 | 自由 | 項目行 |  |
| `features` 身体的な特徴 | 複数値 | 自由 | 項目行 | タグ可 |
| **性格・話し方** (`personality`) | | | | |
| `traits` 性格 | 複数値 | 自由 | 項目行 | タグ可 |
| `first_person` 一人称 | 複数値 | 自由 | 項目行 |  |
| `producer_call` プロデューサーの呼び方 | 複数値 | 自由 | 項目行 |  |
| `catchphrases` 口癖・決まり文句 | 複数値 | 自由 | 項目行 |  |
| `sentence_endings` 語尾 | 複数値 | 自由 | 項目行 |  |
| `dialect` 方言 | 単一値 | 自由 | 項目行 | タグ可 |
| `speech_style` 話し方 | 単一値 | 敬語 / タメ口 / 敬語とタメ口の混在 | 項目行 |  |
| `speech_notes` 話し方の要約 | 単一値 | 自由 | 項目行 |  |
| **経歴・特技** (`career`) | | | | |
| `hobbies` 趣味 | 複数値 | 自由 | 項目行 |  |
| `talents` 特技 | 複数値 | 自由 | 項目行 |  |
| `past_jobs` アイドルになる前の職業 | 複数値 | 自由 | 項目行 | タグ可 |
| `club` 部活・サークル | 複数値 | 自由 | 項目行 | タグ可 |
| `education` 学歴 | 単一値 | 自由 | 項目行 |  |
| `achievements` 実績 | 複数値 | 自由 | 項目行 | タグ可 |
| `debut_route` アイドルになった経緯 | 単一値 | スカウト / オーディション / 事務所の紹介 / その他 | 項目行 |  |
| `debut_date` デビュー日 | 単一値 | 自由 | 項目行 |  |
| **好み** (`likes`) | | | | |
| `favorite_foods` 好きな食べ物 | 複数値 | 自由 | 項目行 | タグ可 |
| `favorite_things` 好きなもの | 複数値 | 自由 | 項目行 | タグ可 |
| `dislikes` 苦手なもの | 複数値 | 自由 | 項目行 | タグ可 |
| **所属・関係** (`relations`) | | | | |
| `brand` ブランド | 単一値 | 自由 | 自動 |  |
| `agency` 所属事務所・学園 | 単一値 | 自由 | 自動 | 確定 |
| `unit_count` ユニットの数 | 数値 | 自由 | 自動 |  |
| `representative_units` 代表的なユニット | 複数値 | 自由 | 自動 |  |
| `units` 所属ユニット (全件) | 複数値 | 自由 | 自動 | 照合専用 |
| `frequent_costars` よく共演する人 | 複数値 | 自由 | 自動 |  |
| `family` 家族 | 複数値 | 自由 | 項目行 | タグ可 |
| `roommates` ルームメイト | 複数値 | 自由 | 項目行 | タグ可 |
| **楽曲・ライブ** (`works`) | | | | |
| `voice_actor` 声優 | 単一値 | 自由 | 自動 |  |
| `solo_song_count` ソロ曲の数 | 数値 | 自由 | 自動 |  |
| `unit_song_count` ユニット曲・合唱曲の数 | 数値 | 自由 | 自動 |  |
| `representative_songs` 代表曲 | 複数値 | 自由 | 自動 |  |
| `songs` 持ち歌 (全件) | 複数値 | 自由 | 自動 | 照合専用 |
| `performed_songs` ライブで歌った曲 (全件) | 複数値 | 自由 | 自動 | 照合専用 |
| `show_count` 出演公演数 | 数値 | 自由 | 自動 |  |
| `first_show` 初出演の公演 | 単一値 | 自由 | 自動 |  |
| `latest_show` 直近の出演公演 | 単一値 | 自由 | 自動 |  |
| `appeared_events` 出演したライブ (全件) | 複数値 | 自由 | 自動 | 照合専用 |

### 自動の項目の境目

- `age_band`: 〜9 → 10歳未満 / 10〜19 → 10代 / 20代 / 30代 / 40 以上 → 40代以上。確定 (`derived: true`)。
- `school_stage` (推定): 6〜12 小学生 / 13〜15 中学生 / 16〜18 高校生 / 23 以上 社会人。**19〜22 は決めない** (大学生か社会人か不明)。
  学マスで学年 (`grade`) が分かる子は確定で高校生。`idol_facets` の行・タグの票があればそちらが勝つ。
  12 歳は中学 1 年のこともあるが、小学生に寄せた (小宮果穂 12 歳 → 小学生)。
- `birthplace_region`: 都道府県 → 北海道 / 東北 / 関東 / 中部 (新潟・山梨・長野・静岡を含む) / 近畿 (三重を含む。「関西」とも言う) / 中国 / 四国 / 九州・沖縄 / 海外。
  市の名前 (名古屋・神戸・札幌…) は都道府県に直す。「海の向こう」のような曖昧な出身地は項目ごと出さない。
- `height_band` は 140 未満 / 140 台 / … / 170 以上。`birth_month` は誕生日から。`image_color.name` は hex の色相・彩度・明度から
  (赤・オレンジ・黄・黄緑・緑・水色・青・紫・ピンク・茶・白・グレー・黒)。`agency` はブランドから (765 / ML → 765プロダクション、CG → 346、SideM → 315、SC → 283、学マス → 初星学園)。
- `birthplace` は「県・府・都」を落とした形に揃える。

### 数が多い項目: まとめと全件

| まとめ (Jev に渡す) | 全件 (照合専用) |
|---|---|
| `representative_songs` ライブで歌った回数の多い順に 5 (回数は `extra.performed_count`) | `songs` 持ち歌 (原唱 + ユニット名義) 全件 / `performed_songs` ライブで歌った曲 全件 |
| `representative_units` 恒常ユニット優先で 5 + `unit_count` | `units` 所属ユニット全件 |
| `latest_show` / `first_show` / `show_count` | `appeared_events` 出演したライブ (イベント単位) 全件 |
| `frequent_costars` 同じ公演に出た回数の多い順に 5 (共演は全件を持たない: 公演から導けるため) | — |

## 3. 保存先

### 3.1 マスタの列 (既存)

誕生日・年齢・身長・血液型・利き手・出身地・星座・趣味・特技・性別・イメージカラー・デビュー日・学年 (`attribute`)・
ブランド・声優・ユニット・曲・ライブは既存の列と表から読む。`official`。

### 3.2 `idol_hairstyles` (髪型のまとまり)

DDL は [`imas-core/src/domain/facets_schema.sql`](../imas-core/src/domain/facets_schema.sql)。

| 列 | 意味 |
|---|---|
| `id` | `ih_` + sha1(`idol_id|label`) の先頭 20 桁 |
| `idol_id` / `label` | `基本` / `セカンドヘア` / `覚醒後` / 自由な名前。1 人の中で重複しない |
| `is_main` | 1 人につき**ちょうど 1 つ**が 1 |
| `hair_color` / `hair_color_secondary` / `hair_length` / `bangs` | 語彙は facets.json |
| `styles` / `accessories` | 複数値。`、` 区切りの 1 文字列 |
| `origin` / `source_note` / `sort_order` | `official` か `promoted` / 出典メモ / 並び |

**main は 1 つ**を 3 重に守る: ① DB の部分一意索引 `UNIQUE (idol_id) WHERE is_main = 1` と `UNIQUE (idol_id, label)`、
② `apply_data.py --check` (髪型が 1 つ以上ある人の is_main が 1 個でなければ落とす。付け替えは `set_main`)、
③ Rust の `hairstyle_set_problems` とテスト。CloudKit には部分一意索引が無いので、②③ が本線。
`/facts` は、壊れたデータ (main が無い) でも決定的に動くよう「main が無ければ先頭」を main とみなす。

### 3.3 `idol_facets` (髪以外の項目)

| 列 | 意味 |
|---|---|
| `id` | `if_` + sha1(`idol_id|facet`[`|value` (複数値の項目だけ)]) の先頭 20 桁 (`apply_data.py` の `facet_row_id` と Rust の `facet_row_key` が同じ式) |
| `idol_id` / `facet` / `value` | 値は文字列で保存し、型 (数値・真偽・色) は定義で解釈する。語彙に合わない行は読み飛ばす |
| `origin` | `official` / `promoted` |
| `source_note` | 出典・昇格の根拠 (「tag 12票 2026-10」など)。`/facts` では `extra.note` に出る |

### 3.4 CloudKit・export・import

- レコード型 `IdolFacet` / `IdolHairstyle` を `tools/cloudkit_schema.ckdb` に足した。**Production への昇格はしていない** (§9)。
- `tools/lib/ck_tables.py` に表・型・`idol_id` での絞り込み (`--ids` / `scope_id`) を足した。`apply_data.py --push` は触ったアイドルの行だけを送る。
- 日次 export (`export_cloudkit.py`) は、recordType が昇格されるまで表を作らず `db/master.sql` の形を変えない。昇格後の最初の export で
  表が作られて取り込まれる。そのとき `facets_schema.sql` の DDL を `master_schema.sql` に移し、`schema_registry.rs` の `Auxiliary` を `Master` にする
  (`ddl_reproduces_the_bundled_schema` が `db/master.sql` との一致を固定しているため、先には移せない)。
- Snapshot には `idol_facets` / `idol_hairstyles` を読む (表が無い DB では空)。ブラウザ (wasm) の `tables.json` には配らない。

## 4. 組み立てと API

- `GET /v1/idols/:id/facts`: 同期 (`web-export --api-sql`) のとき `docs(kind='facts', id)` に 1 行ずつ置く。Worker は主キー 1 行を返すだけ
  (`/v1/idols/:id` と同じキャッシュ・レート制限・CORS)。1 件は最大約 60KB (D1 の 1 文 90KB 以下をテストで固定)。
- MCP / アプリ内トーク: `get_idol_facts` (id か name)。同じ `build_idol_facts`。タグの票は D1 (imas-live-api) にあるので**マスタの値だけ**。
- タグの票を足すには `web-export --facet-tags <path>` (§7)。
- 形:
  - `schema_version` / `id` / `name` / `categories` (7 カテゴリ。空でもキーはある) / `summary` (`description`) / `free_tags` (facet の無いタグ)。
  - `appearance` には、main の髪型が `hair_color` / `hair_length` / `hair_style` / `bangs` / `hair_accessory` / `hair_color_secondary` として入り、
    `main_hairstyle_label` (「基本」など) と `main_hairstyle_note` (出典メモ)、ほかの髪型は `other_hairstyles` (label つき、同じ項目キー) に並ぶ。
  - 項目の `extra`: ブランドの id、曲の id と回数、ユニットの id、共演者の id と回数など。キーの順は保証しない。
  - 一人称が場面で変わる子は値に場面が付く (「亜美（普段）」)。

### 例: 有村麻央 (学マス・髪型は未確認の表のため未投入)

```json
{
 "categories": {
  "appearance": {
   "image_color": {
    "source": "official",
    "value": {
     "hex": "#A453A6",
     "name": "紫"
    }
   }
  },
  "career": {
   "debut_date": {
    "source": "official",
    "value": "2024-05-16"
   },
   "hobbies": {
    "values": [
     {
      "source": "official",
      "value": "他人の面倒を見ること"
     },
     {
      "source": "official",
      "value": "観劇"
     }
    ]
   },
   "talents": {
    "values": [
     {
      "source": "official",
      "value": "手先が器用"
     },
     {
      "source": "official",
      "value": "格闘技"
     }
    ]
   }
  },
  "likes": {},
  "personality": {},
  "profile": {
   "age": {
    "source": "official",
    "value": 17
   },
   "age_band": {
    "derived": true,
    "source": "official",
    "value": "10代"
   },
   "birth_month": {
    "derived": true,
    "source": "official",
    "value": 1
   },
   "birthday": {
    "source": "official",
    "value": "1月18日"
   },
   "birthplace": {
    "source": "official",
    "value": "兵庫"
   },
   "birthplace_region": {
    "derived": true,
    "source": "official",
    "value": "近畿"
   },
   "blood_type": {
    "source": "official",
    "value": "A"
   },
   "constellation": {
    "source": "official",
    "value": "山羊座"
   },
   "gender": {
    "source": "official",
    "value": "女性"
   },
   "grade": {
    "source": "official",
    "value": "1年"
   },
   "handedness": {
    "source": "official",
    "value": "右利き"
   },
   "height_band": {
    "derived": true,
    "source": "official",
    "value": "150cm台"
   },
   "height_cm": {
    "source": "official",
    "value": 157
   },
   "school": {
    "derived": true,
    "source": "official",
    "value": "初星学園"
   },
   "school_stage": {
    "derived": true,
    "source": "official",
    "value": "高校生"
   }
  },
  "relations": {
   "agency": {
    "derived": true,
    "source": "official",
    "value": "初星学園"
   },
   "brand": {
    "extra": {
     "id": "gakuen",
     "short_name": "学マス"
    },
    "source": "official",
    "value": "学園アイドルマスター"
   },
   "frequent_costars": {
    "values": [
     {
      "extra": {
       "id": "gakuen_篠澤広",
       "shared_shows": 20
      },
      "source": "official",
      "value": "篠澤広"
     },
     {
      "extra": {
       "id": "gakuen_紫雲清夏",
       "shared_shows": 19
      },
      "source": "official",
      "value": "紫雲清夏"
     },
     {
      "extra": {
       "id": "gakuen_姫崎莉波",
       "shared_shows": 18
      },
      "source": "official",
      "value": "姫崎莉波"
     },
     {
      "extra": {
       "id": "gakuen_花海佑芽",
       "shared_shows": 16
      },
      "source": "official",
      "value": "花海佑芽"
     },
     {
      "extra": {
       "id": "gakuen_葛城リーリヤ",
       "shared_shows": 16
      },
      "source": "official",
      "value": "葛城リーリヤ"
     }
    ]
   },
   "representative_units": {
    "values": [
     {
      "extra": {
       "id": "unit_3年1組",
       "is_permanent": false
      },
      "source": "official",
      "value": "3年1組"
     },
     {
      "extra": {
       "id": "unit_ripplesign",
       "is_permanent": false
      },
      "source": "official",
      "value": "RippleSign"
     }
    ]
   },
   "unit_count": {
    "source": "official",
    "value": 2
   },
   "units": {
    "values": [
     {
      "extra": {
       "id": "unit_3年1組",
       "is_permanent": false
      },
      "source": "official",
      "value": "3年1組"
     },
     "… 全 2 件"
    ]
   }
  },
  "works": {
   "appeared_events": {
    "values": [
     {
      "extra": {
       "date": "2026-11-08",
       "id": "ev_学園アイドルマスター_live_tour_-標-_kアリーナ横浜公演_final"
      },
      "source": "official",
      "value": "学園アイドルマスター LIVE TOUR -標- Kアリーナ横浜公演 (FINAL)"
     },
     "… 全 13 件"
    ]
   },
   "first_show": {
    "extra": {
     "event_id": "ev_学園アイドルマスター_debut_live_初_tour_-初恋公演-_梅田クラブクアトロ公演",
     "show_id": "sh_L0962"
    },
    "source": "official",
    "value": "2024-10-14 学園アイドルマスター DEBUT LIVE 初 TOUR -初恋公演- 梅田クラブクアトロ公演"
   },
   "latest_show": {
    "extra": {
     "event_id": "ev_学園アイドルマスター_live_tour_-標-_kアリーナ横浜公演_final",
     "show_id": "sh_学園アイドルマスター_live_tour_-標-_kアリーナ横浜公演_final_2"
    },
    "source": "official",
    "value": "2026-11-08 学園アイドルマスター LIVE TOUR -標- Kアリーナ横浜公演 (FINAL)"
   },
   "performed_songs": {
    "values": [
     {
      "extra": {
       "id": "gakuen_初",
       "performed_count": 21
      },
      "source": "official",
      "value": "初"
     },
     "… 全 38 件"
    ]
   },
   "representative_songs": {
    "values": [
     {
      "extra": {
       "id": "gakuen_初",
       "performed_count": 21
      },
      "source": "official",
      "value": "初"
     },
     {
      "extra": {
       "id": "gakuen_campus_mode",
       "performed_count": 19
      },
      "source": "official",
      "value": "Campus mode!!"
     },
     {
      "extra": {
       "id": "gakuen_fluorite",
       "performed_count": 14
      },
      "source": "official",
      "value": "Fluorite"
     },
     {
      "extra": {
       "id": "gakuen_標",
       "performed_count": 13
      },
      "source": "official",
      "value": "標"
     },
     {
      "extra": {
       "id": "gakuen_feel_jewel_dream",
       "performed_count": 10
      },
      "source": "official",
      "value": "Feel Jewel Dream"
     }
    ]
   },
   "show_count": {
    "source": "official",
    "value": 25
   },
   "solo_song_count": {
    "source": "official",
    "value": 6
   },
   "songs": {
    "values": [
     {
      "extra": {
       "id": "gakuen_campus_mode"
      },
      "source": "official",
      "value": "Campus mode!!"
     },
     "… 全 16 件"
    ]
   },
   "unit_song_count": {
    "source": "official",
    "value": 10
   },
   "voice_actor": {
    "source": "official",
    "value": "七瀬つむぎ"
   }
  }
 },
 "id": "gakuen_有村麻央",
 "name": "有村麻央",
 "schema_version": 1,
 "summary": {
  "source": "official",
  "value": "カッコいいアイドルを目指す3年生の女の子。初星学園アイド…"
 }
}
```

### 例: 天海春香 / 双海亜美 / 小宮果穂 / 桜庭薫 (抜粋: profile・appearance・personality の一部)

天海春香 (髪型は調査の表の初期値。話し方は出典つきの公式データ):
```json
{
 "schema_version": 1,
 "id": "765as_天海春香",
 "categories": {
  "profile": {
   "age": {
    "source": "official",
    "value": 17
   },
   "age_band": {
    "derived": true,
    "source": "official",
    "value": "10代"
   },
   "school_stage": {
    "derived": true,
    "source": "official",
    "value": "高校生"
   }
  },
  "appearance": {
   "hair_accessory": {
    "values": [
     {
      "source": "official",
      "value": "リボン"
     }
    ]
   },
   "hair_color": {
    "source": "official",
    "value": "茶"
   },
   "hair_length": {
    "source": "official",
    "value": "ボブ〜ミディアム"
   },
   "hair_style": {
    "values": [
     {
      "source": "official",
      "value": "ストレート"
     }
    ]
   },
   "image_color": {
    "source": "official",
    "value": {
     "hex": "#E22B30",
     "name": "赤"
    }
   },
   "main_hairstyle_label": "基本",
   "main_hairstyle_note": "Wikipediaは2つのリボンのみ記載。色・長さは公式のカード絵で確認"
  },
  "personality": {
   "first_person": {
    "values": [
     {
      "source": "official",
      "value": "私"
     }
    ]
   },
   "producer_call": {
    "values": [
     {
      "source": "official",
      "value": "プロデューサーさん"
     }
    ]
   },
   "speech_style": {
    "source": "official",
    "value": "敬語とタメ口の混在"
   }
  }
 }
}
```
双海亜美 (一人称・呼び方は場面つき):
```json
{
 "schema_version": 1,
 "id": "765as_双海亜美",
 "categories": {
  "profile": {
   "age": {
    "source": "official",
    "value": 13
   },
   "age_band": {
    "derived": true,
    "source": "official",
    "value": "10代"
   },
   "school_stage": {
    "derived": true,
    "source": "official",
    "value": "中学生"
   }
  },
  "appearance": {
   "hair_color": {
    "source": "official",
    "value": "茶"
   },
   "hair_length": {
    "source": "official",
    "value": "ボブ〜ミディアム"
   },
   "hair_style": {
    "values": [
     {
      "source": "official",
      "value": "サイドテール"
     }
    ]
   },
   "image_color": {
    "source": "official",
    "value": {
     "hex": "#FFE43F",
     "name": "黄"
    }
   },
   "main_hairstyle_label": "基本",
   "main_hairstyle_note": "Wikipediaは向かって左で結ぶ。長さは真美より短めでミディアムとした"
  },
  "personality": {
   "first_person": {
    "values": [
     {
      "source": "official",
      "value": "亜美（普段）"
     },
     {
      "source": "official",
      "value": "私（営業・あいさつの一部）"
     }
    ]
   },
   "producer_call": {
    "values": [
     {
      "source": "official",
      "value": "兄ちゃん（メールでは「兄(C)」）"
     }
    ]
   }
  }
 }
}
```
小宮果穂 (12 歳 → `school_stage` は推定の「小学生」。髪型は未確認の表のため未投入):
```json
{
 "schema_version": 1,
 "id": "sc_小宮果穂",
 "categories": {
  "profile": {
   "age": {
    "source": "official",
    "value": 12
   },
   "age_band": {
    "derived": true,
    "source": "official",
    "value": "10代"
   },
   "school_stage": {
    "derived": true,
    "source": "official",
    "value": "小学生"
   }
  },
  "appearance": {
   "image_color": {
    "source": "official",
    "value": {
     "hex": "#E5461C",
     "name": "オレンジ"
    }
   }
  }
 }
}
```
桜庭薫 (前髪「片目隠れ」。**眼鏡は研究の表に無いため未投入**。入れるには `data/idol_facets/` に `{"idol_id":"sidem_桜庭薫","facet":"glasses","value":true}`、
入ると `appearance.glasses = {"value": true, "source": "official"}` になる):
```json
{
 "schema_version": 1,
 "id": "sidem_桜庭薫",
 "categories": {
  "profile": {
   "age": {
    "source": "official",
    "value": 26
   },
   "age_band": {
    "derived": true,
    "source": "official",
    "value": "20代"
   },
   "school_stage": {
    "derived": true,
    "source": "official",
    "value": "社会人"
   }
  },
  "appearance": {
   "bangs": {
    "source": "official",
    "value": "片目隠れ"
   },
   "hair_color": {
    "source": "official",
    "value": "黒"
   },
   "hair_length": {
    "source": "official",
    "value": "ショート"
   },
   "image_color": {
    "source": "official",
    "value": {
     "hex": "#1945BA",
     "name": "青"
    }
   },
   "main_hairstyle_label": "基本",
   "main_hairstyle_note": "公式ではなく非公式 Wiki のアイコン画像(Idol File)を目視。顔アイコンのため長さ・髪型は大まか。長さは耳にかかる程度"
  }
 }
}
```

### 例: 髪型が複数ある子 (テストの固定値。星井美希と、セカンドヘアのある子)

`imas-core` のテスト (`美希は基本の髪型と覚醒後の髪型を持つ` / `セカンドヘアのある子の髪型は…`) が固定している形。美希 (基本: 金・ロング・ウェーブ・アホ毛 / 覚醒後: 茶・ショート):
```json
"appearance": {
  "hair_color": {"value": "金", "source": "official"},
  "hair_length": {"value": "ロング", "source": "official"},
  "hair_style": {"values": [{"value": "ウェーブ", "source": "official"}, {"value": "アホ毛", "source": "official"}]},
  "main_hairstyle_label": "基本",
  "other_hairstyles": [{"label": "覚醒後", "hair_color": {"value": "茶", "source": "official"}, "hair_length": {"value": "ショート", "source": "official"}}]
}
```
Jev に渡す文面 (`jev_lines`): `髪: 金色のロング（ウェーブ、アホ毛） (基本)。覚醒後: 茶色のショート`。
デレステのセカンドヘア (例として島村卯月、**値は例示用の仮**): 基本 = 茶・ロング・ストレート、`セカンドヘア` = 茶・ロング・ポニーテール →
`other_hairstyles` に `{"label": "セカンドヘア", "hair_style": {"values": [{"value": "ポニーテール"}]}, …}`、
Jev へは `セカンドヘア: 茶色のロング（ポニーテール）`。「ポニーテールにすることもありますか？」には「セカンドヘアではポニーテール」と答えられる。
**デレステのセカンドヘアの有無を示す元データは、マスタにも既存のデータにも無い** (調査が要る)。有る子を `data/idol_hairstyles/` に label `セカンドヘア` で足していく。

## 5. 値の出どころと優先順位

1. マスタの列 (`rank 0`) — 誕生日・身長・趣味・特技・色・声優・ブランドなど。
2. `idol_facets` / `idol_hairstyles` の `origin = official` の行。
3. `origin = promoted` の行 (タグから昇格したもの)。
4. タグの票 (`source: tag`、`votes` つき)。票が 3 未満の値は載せない (`MIN_TAG_VOTES`)。
5. 推定の自動項目 (`school_stage`) は 2〜4 のどれにも負ける。

- 単一値・数値・真偽・色: 最も強い 1 つ。複数値: 強い出どころの値が 1 つでもあれば**その出どころの値が全部**で、弱い出どころの値は足さない
  (公式の「好きな食べ物: お菓子」にファンの「ケーキ」を混ぜない)。タグだけのときは票の多い順。
- 自動の確定項目 (`age_band` など) と照合専用の全件は `idol_facets` の行で上書きできない。
- 話し方 (`data/personas/*.json` と im@sparql の呼称) は personality の `first_person` / `producer_call` / `catchphrases` / `sentence_endings` / `speech_style` / `speech_notes` の `official`。
  出典 URL は載せない。話し方データのある子 (765AS と ML の一部) だけ。

## 6. 返さないもの

- 歌詞・`lyrics_url`・`preview_url` (曲の項目は曲名・id・回数だけ。テストが全アイドルで検査)。
- **体重・スリーサイズ**: アプリは出している (`/v1/idols/:id` と `get_idol` には従来どおり入る) が、当てっこの質問に使う理由が無く、
  身体の数値は公開 API の新しい口で増やさない。`/facts` の `height_cm` / `height_band` だけ。
- 話し方の出典 URL。
- タグの個別の票者 (票数だけ)。

## 7. タグとのつなぎ

### 7.1 入力の形 (タグ側の担当との約束)

`web-export --facet-tags <path>` は次の JSON を読む (`TagFacetInput`)。imas-live-api の `idol_tag_master` と `idol_tags` から
同期で作る (取り込みの CI は別の担当):

```json
{ "gakuen_有村麻央": [ {"tag": "関西弁", "facet": "dialect", "facet_value": "関西弁", "category": "personality", "votes": 7},
                      {"tag": "お嬢様", "facet": null, "facet_value": null, "category": "free", "votes": 4} ] }
```
- `facet` と `facet_value` は `idol_tag_master` の追加列 (nullable)。`facet` は facets.json の `taggable: true` の項目だけ:
  `features` `traits` `dialect` `past_jobs` `club` `achievements` `favorite_foods` `favorite_things` `dislikes` `family` `roommates`。
  語彙のある項目で語彙に無い `facet_value` は捨てる。`facet` が無く `category = personality` のタグは `traits`、それ以外は `free_tags` に入る。
- 版 (variant) は**タグに持たせない**。髪型はマスタの `idol_hairstyles` だけが持つ。

### 7.2 タグの `facet` 列を作るか — 決定: 作る。ただし `taggable` 項目だけ (容姿・髪には使わない)

- 髪・目・眼鏡・色などの容姿は、最初から公式の項目として入れる (調査の表 → `data/idol_hairstyles/`)。タグ→項目の昇格の仕組みは要らない。
- 性格・好み・経歴・家族・方言のように**公式の列もデータも無く、ファンの知識で集めるしかない**ものは、タグで集めて項目に昇格する流れを残す。
  タグ側には `facet` / `facet_value` の 2 列 (管理者が付ける。利用者は付けられない) だけ要る。今は何も付けなくても動く (`free_tags` に入る)。
- 公式の列がある項目 (血液型・星座・利き手・出身地・学校の段階) に当たるタグ (本番に `A型` `しし座` `左利き` `千葉県出身` `高校生` `中学生` `小学生` `大学・短大・専門学生` がある)
  は `facet` を付けない。公式の値が必ず勝つので重複で、画面から退役させる候補 (オーナーが決める)。
- 本番のタグで項目にできそうなもの (提案): `メガネ` → `glasses`、`ほくろ` → `features`、`方言` → `dialect`、`姉・兄` `妹・弟` `双子` `一人っ子` → `family`、
  `他の職種から転向` `元モデル・読モ` `元子役` `医療系` `事務員` `土方バイト` → `past_jobs`、`スカウト` `オーディション` → `debut_route`、
  `生徒会` → `club`、`甘いもの好き` `ラーメン` `りんご` → `favorite_foods`/`favorite_things`、性格のタグ (クール・ツンデレ…) → `traits`。

### 7.3 昇格の流れ

```
利用者がタグに投票 (idol_tags.vote_count)
  └ 同期: facet / facet_value のあるタグ → TagFacetInput → /facts に source: tag (票数つき、3 票以上)
       └ オーナーが候補を見て確かめる (出典があれば出典も)
            └ data/idol_facets/<topic>.json に origin: promoted で書く (source_note に「tag 12票 2026-10」)
                 └ apply_data.py --check → --apply --push (CloudKit) → 日次 export → /facts は source: promoted
                      (公式の値が見つかったら origin: official の行で置き換える。ファンの票は以後ずっと負ける)
```
昇格候補の一覧を自動で出す道具は次の段 (票数・割合の閾値はオーナーが決める)。

## 8. 髪のタグの退役 (オーナーの決定)

髪色・髪の長さ・髪型・前髪・髪飾りは公式の項目にしたので、利用者が作った髪のタグ 20 語は退役する。

1. **写し**: 本番の `idol-tags` を読み取り専用で取り、`data/research/appearance_20261010/hair_tags_production_snapshot_20261010.json`
   に写した (どのアイドルにどのタグが何票。346 人 649 件)。
2. **確認表**: 調査の表の「基本」と食い違うものを `hair_tags_vs_review_20261010.csv` にまとめた。タグの値が基本と一致するものは載せていない。
   列: ブランド・名前・項目・タグの値・票数・表の基本の値・案 (`default` = 表に値が無いので補う案 / `要確認` = 食い違い。別の髪型 (セカンドヘア等) かもしれない)・
   確認 (**基本に直す / 別の髪型として足す: label を書く / 捨てる**)・調査の表の状態・セカンドヘアの手がかり (マスタに列が無いので「なし」)。
   タグには「基本かセカンドヘアか」の区別が無いので、勝手に決めない。
3. **migration**: `imas-live-api/migrations/0050_retire_hair_idol_tags.sql` は該当 20 語の `idol_tags` / `device_idol_tag` / 説明履歴 / 報告 / `idol_tag_master` の行を消す。
   **作っただけで本番には当てていない。** テスト (`retire_hair_idol_tags.test.ts`) で、当てたあとタグ一覧・詳細・アイドルごとのタグから髪のタグだけが消え、
   ほかのタグは残ることを確かめた。
4. **当てる順番**: ① 確認表の「基本に直す / 別の髪型として足す」を `data/idol_hairstyles/` に反映 (`--apply --push`) →
   ② CloudKit の昇格・日次 export・同期で `/facts` に髪が出ていることを確かめる → ③ アプリ・Web がプロフィールの髪を出せるようにする
   (次の段) → ④ migration 0050 を本番の `imas-live-db` に当てる。先に当てると、画面から髪の情報が一度消える
   (写しはリポジトリに残るので復元はできる)。
5. 取り下げ: 容姿の公式タグの `migrations/0050_idol_appearance_tags.sql` (本番に**未適用**だった) と初期値の票 `data/fixes/idol_tag_votes_appearance_20261010.json`、
   `apply_data.py` の `add_official_tags` (D1 に運営の票を入れる SQL の仕組み) は削除した。運営の票の端末 ID (`official:`) の拒否は imas-live-api に残してある
   (利用者がその接頭辞を名乗れないだけのもので、将来また公式タグを使うときのため)。

## 9. 運用 (オーナーが打つ手順)

```bash
# 1. データを入れる前の検証 (鍵不要)
python3 tools/apply_data.py --check
# 2. マスタに反映 (CloudKit へ出す前の確認)
python3 tools/apply_data.py --apply --only appearance_20261010.json
# 3. CloudKit の本番スキーマに IdolFacet / IdolHairstyle を昇格 (Dashboard)。
#    tools/cloudkit_schema.ckdb の差分を CloudKit Dashboard の Development → Production に「Deploy Schema Changes」。
python3 tools/check_ckdb_schema.py --base origin/develop       # 事前に「足すだけ」を確かめる
# 4. 反映
python3 tools/apply_data.py --apply --push --production --only appearance_20261010.json
git mv data/idol_hairstyles/appearance_20261010.json data/_applied/idol_hairstyles/
# 5. 翌日の日次 export で db/master.sql に表が入る → facets_schema.sql の DDL を master_schema.sql に移し、
#    schema_registry の idol_facets / idol_hairstyles を Master にする (別コミット)
# 6. 公開データ API に反映 (既存の同期。facts 文書も一緒に組まれる)
python3 tools/sync_master_d1.py --remote --yes   # または Actions → Refresh master data
```
- 未確認の 111 人 (`data/idol_hairstyles/unconfirmed_appearance_20261010.json`) は `--check` は通り、`--apply` は入れない。確認できた行は別ファイルに移して投入する。
- 間違えた行を消す口は無い (fixes は値の直しだけ)。消すときは `tools/pending_cloudkit_deletions_*.tsv` の台帳に書く。

## 10. yesno での使われ方

1. `GET /v1/idols/:id/facts` を 1 回引く (キャッシュ 1 時間)。
2. カテゴリごとに Jev へ渡す: `facets.json` の各項目の `label` を見出しに、`jev: false` を除き、`source: tag` には「（ファン投票 N票）」、推定 (`derived` かつ `auto: estimate`) には「（推定）」を添える。
   髪は main を先に、`other_hairstyles` を「覚醒後: 茶色のショート」のように短く添える。imas-core / MCP 側には同じ規則の `jev_lines` がある。
3. 質問に曲名・ユニット名・ライブ名が出たら、`songs` / `performed_songs` / `units` / `appeared_events` の全件で照合してから、そのカテゴリの文面を渡す。
4. 「10代か」は `age_band`、「関西出身か」は `birthplace_region = 近畿`、「ポニーテールにすることもあるか」は main と `other_hairstyles` の `hair_style`、
   「何曲ソロがあるか」は `solo_song_count`。語彙にある項目は完全一致で判定できる。

## 11. テスト

| 場所 | 固定すること |
|---|---|
| `imas-core` `domain::idol_facets` | キー・語彙の重複なし、`facets.json` と定義の一致、年齢帯・学校の段階・身長帯・出身地方・色名の境目、全アイドルで組める・値が語彙に収まる・禁止値が出ない・1 件 80KB 未満、出どころの優先 (公式 > 昇格 > タグ・足切り・複数値)、髪型の main / 他の髪型、`jev_lines`、行 id の式 |
| `imas-core` `web_export::data_api` | `facts` 文書が D1 の SQL に入る (件数 = アイドル数) |
| `tools/test/test_apply_facets.py` | 投入・語彙・重複・main がちょうど 1 つ・DB の部分一意索引・set_main・fixes・id の式 |
| `imas-data-api/test` | `/v1/idols/:id/facts` が主キー 1 行で返る・404・400 |
| `imas-live-api/test/retire_hair_idol_tags.test.ts` | 退役の migration で髪のタグだけが画面から消える |

```bash
cd imas-core && cargo test --locked --features agent,web-export --lib idol_facets
python3 -m unittest discover -s tools/test -p 'test_apply_facets.py'
cd imas-data-api && npm test
```

## 12. 次の段

- アプリ (iOS / Android) と Web のプロフィール画面に、髪型・項目を出す (今は `/facts` と MCP だけ)。
- 昇格候補を自動で出す道具 (票数・割合の閾値)。
- デレステのセカンドヘアなど、髪型が複数ある子の調査。
- 未確認 111 人の確認。髪色が 2 色以上の子の 2 色目。
- 項目の編集 UI (今は `data/` の JSON と PR)。
