# 公開データ API (`imas-data-api`) アーキテクチャ

> マスタ (アイドル・曲・ユニット) を**読むだけ**の公開 HTTP API。最初の利用者は別プロジェクトの
> yesno (当てっこゲーム)。LLM 向けの口は [`ARCHITECTURE-mcp.md`](ARCHITECTURE-mcp.md)、
> Web 出面は [`ARCHITECTURE-web.md`](ARCHITECTURE-web.md)、集計系の Worker は
> [`ARCHITECTURE-worker.md`](ARCHITECTURE-worker.md)。データの流れは [`DATA_PIPELINE.md`](DATA_PIPELINE.md)。
> アイドルの細かい項目 (`/v1/idols/:id/facts`) の定義・出どころ・タグとのつなぎは [`ARCHITECTURE-facets.md`](ARCHITECTURE-facets.md)。

> 状態: **実装済み・未デプロイ** (2026-10-10)。デプロイと本番 D1 の作成・同期はオーナーの操作 (§8)。

## 1. 決めたこと

| 論点 | 決定 |
|---|---|
| どの Worker か | **専用の Worker `imas-data-api`** (`imas-data-api/`)。`web/` (assets-only) にも `imas-live-api/` にも相乗りしない |
| データ源 | **専用の D1 `imas-master-db`** (`imas-live-db` とは別)。中身は `db/master.sql` の写しから組んだ「文書」と索引 |
| 判断の置き場 | **文書の組み立ては imas-core の `agent::tools::publish`** (`get_idol` / `idol_songs` / `get_song` / 話し方をそのまま束ねる)。Worker は D1 の行を返すだけ |
| 認証 | **なし** (公開・読み取り専用・CORS `*`)。代わりに §5 の費用の守りを多層に持つ |
| ドメイン | `idollivedb-api.fugaapp.site` (1 段。2 段 `api.idollivedb.…` は無料の証明書 `*.fugaapp.site` の対象外) |
| 版 | URL に `/v1/`。キーの追加は版を上げず、削除・改名・型の変更で上げる (`schema_version`) |

### なぜ「Rust を wasm で Worker から呼ぶ」にしなかったか

`agent::tools` は `Snapshot` (全曲・全公演・全セトリの逆引き索引) を前提にしている。Worker が
リクエストごとにそれを組むなら D1 の全行を読むことになり、D1 に置く意味 (読み取り行数の節約)
が消える。かといって部分的な Snapshot を作ると、ツール面と違う答えが出うる。そこで
**同期のときに一度だけ** imas-core が全部を組み、1 件ぶんの完成した JSON を `docs` 表に置く。
詳細 API は主キー 1 行を返すだけで、判断は 1 行も Worker に無い
([`ARCHITECTURE-mcp.md`](ARCHITECTURE-mcp.md) §2 の 2「判断の唯一の正は imas-core」)。
検索語の畳み込みだけは実行時に要るので、Web と同じ `imas-fold-wasm` (= `imas-text-fold`) を
Worker にも入れて、索引側 (同期時に Rust が畳む) と検索語側を同じ規則に通す。

トレードオフ: Worker から「任意の SQL」や「任意の絞り込み」は引けない。引けるのは §3 の
軸だけで、新しい軸は索引表と SQL を足す (`src/queries.ts` と `schema.sql`)。

## 2. 構成

```
 db/master.sql ─▶ imas-core web-export --api-sql ─▶ imas-data-api/.build/master-d1.sql
   (CloudKit の日次の書き出し)   (agent::tools::publish が文書を組む)      │  tools/sync_master_d1.py
                                                                      ▼  wrangler d1 execute (全置き換え)
 クライアント ─▶ Cloudflare エッジ ─▶ Worker (src/app.ts) ─▶ D1 imas-master-db
                  Cache API (版つきの鍵)   Rate Limiting (キャッシュ外のみ)
```

D1 の表 (`imas-data-api/schema.sql` が唯一の定義):

| 表 | 中身 |
|---|---|
| `docs(kind, id, body)` | 完成した文書 (JSON)。`idol` / `facts` (アイドルの項目の束) / `song` / `unit` / `brands` |
| `idols` / `songs` / `units` | 一覧用の索引行 (`ord` = 通し番号、名前、よみ、ブランド) |
| `song_idols(idol_id, song_ord)` | アイドルの持ち歌 (原唱 + ユニット名義)。`GET /v1/songs?idol=` |
| `terms(kind, term, ord)` | 前方一致の検索語 (名前・よみ・ローマ字・別名・曲名…を畳んだもの) |
| `meta` | 同期の版・日時・件数・クレジット |

**D1 に置かないもの**: 歌詞本文・歌詞の在り処 (`lyrics_url`)・試聴音源 (`preview_url`)・
コミュニティのタグ (タグは `imas-live-api` の `/idols/<id>/tags` がリアルタイムの正)。
Rust のテスト (`web_export::data_api` / `agent::tools::publish`) が、SQL 全文・列名・全文書に
実データの禁止値が出ないことを固定している (Web の T12 と同等)。

## 3. エンドポイント

すべて `GET` (と `HEAD` / `OPTIONS`)。応答は JSON、`Access-Control-Allow-Origin: *`、
`Cache-Control: public, max-age=3600` (404 は 60 秒)。エラーは `{"error":{"code","message"}}`。

| パス | 内容 |
|---|---|
| `/v1/meta` | `version` (同期の版)・`generated_at`・`idol_count` / `song_count` / `unit_count`・`schema_version`・`credits` |
| `/v1/brands` | ブランド一覧 (id・名前・短縮名・色) |
| `/v1/idols/:id` | アイドルの文書 (下) |
| `/v1/idols/:id/facts` | アイドルの**項目の束** (年齢帯・髪型・一人称・代表曲など。値ごとに出どころ)。[`ARCHITECTURE-facets.md`](ARCHITECTURE-facets.md) |
| `/v1/idols?brand=&q=&limit=&cursor=` | 一覧・検索 |
| `/v1/songs/:id` | 曲の文書 (= `get_song`) |
| `/v1/songs?brand=&q=&idol=&limit=&cursor=` | 一覧・検索。`idol` はそのアイドルの持ち歌 (`q` とは併用不可) |
| `/v1/units/:id` | ユニットの文書 (メンバー・持ち曲) |
| `/v1/units?brand=&q=&limit=&cursor=` | 一覧・検索 |

- `:id` は percent-encode した id (`gakuen_有村麻央` → `gakuen_%E6%9C%89…`)。
- `q` は**畳んだ語の前方一致** (大文字小文字・ひらがな/カタカナを吸収。名前・よみ・別名のどれでも)。
  部分一致 (語の途中) は当たらない。必要になったら FTS を足す (§9)。
- 一覧は `{"items":[…],"next_cursor":N|null}`。続きは `cursor=N`。`limit` は 1〜100 (既定 20)。
  `OFFSET` は使わない (読み飛ばしぶんも読み取り行に数えられるため)。総数は返さない。
- 一覧の行は索引だけ (`id` / `name` or `title` / `kana` / `brand_id` / `path`)。詳しくは `path` を引く。

### アイドルの文書 (抜粋: 有村麻央)

`get_idol` の出力に、`idol_songs` (持ち歌・ライブで歌った曲)・出演公演・話し方を足したもの。
同じ質問に MCP・アプリと違う答えを出さないため、キー名はツール面のまま。

```json
{
  "schema_version": 1,
  "id": "gakuen_有村麻央", "name": "有村麻央", "name_kana": "ありむらまお",
  "brand": {"id":"gakuen","name":"学園アイドルマスター","short_name":"学マス"},
  "birthday": "1月18日", "age": 17, "height": "157cm", "weight": 46, "three_size": "B85 W53 H85",
  "blood_type": "A", "constellation": "山羊座", "birth_place": "兵庫", "handedness": "right",
  "hobbies": "他人の面倒を見ること、観劇", "talents": "手先が器用、格闘技",
  "attribute": "1年", "color": "#A453A6",
  "description": "カッコいいアイドルを目指す3年生の女の子。…",
  "voice_actor": "七瀬つむぎ",
  "units": [{"id":"unit_ripplesign","name":"RippleSign","is_permanent":false}],
  "original_song_count": 16, "solo_count": 6,
  "original": [{"id":"gakuen_lespoir","title":"L’Espoir","release_date":"2026-08-21","artist_count":1}],
  "original_total": 16,
  "unit_songs": [{"id":"gakuen_ナイワ","title":"ナイワ","unit_name":"3年1組"}], "unit_songs_total": 2,
  "performed_song_count": 38,
  "performed": [{"id":"gakuen_初","title":"初","perform_count":21}], "performed_total": 38,
  "show_count": 25,
  "shows": [{"show_id":"sh_…","date":"2026-11-08","event_name":"…","venue":"Kアリーナ横浜","cast_role":"member"}],
  "shows_total": 25,
  "first_show": {…}, "latest_show": {…}
}
```

- 持ち歌 (`original` / `unit_songs`) は**全件**、ライブで歌った曲 (`performed`) は回数順の上位 50、
  出演公演 (`shows`) は新しい順の上位 30。切ったときは `*_truncated: true` と `*_total`。
- `speech` (一人称・プロデューサーの呼び方・口癖・語尾・口調・仲間の呼び方) は**話し方データのある子だけ**
  (現在は765AS と ML のうち出典つきで確かめた子)。出典 URL は載せない。仲間の呼び方は im@sparql (MIT) 由来で、
  `/v1/meta` の `credits` に表記がある。無い子は `speech` キーごと無い。
- 値が無い項目はキーごと無い (`null` を返さない)。

## 4. 読み取り行数の見積もり (D1 の請求単位)

| リクエスト | キャッシュ当たり | キャッシュ外れ (D1 を読む行数) |
|---|---|---|
| 詳細 `/v1/{idols,songs,units}/:id`, `/brands` | 0 | **1** (主キー。最大 39KB の行) |
| 一覧 (絞りなし / `brand`) | 0 | `limit + 1` ≤ **101** |
| `songs?idol=` | 0 | ≤ 101 + 101 = **約 200** |
| `?q=` (前方一致) | 0 | 一致した語 M + 本体 M。実データの 1 文字の最悪は曲 230 語 + 189 行 ≈ **420**、名前 2 文字以上ならほぼ数十行 |
| 版の確認 (`meta.version`) | isolate ごとに 1 分に 1 回 | 1 |
| 同期 (書き込み) | — | 約 **4 万行** (文書 5,012 + 索引・検索語・持ち歌 約 2.5 万 + 索引) |

無料枠 (D1: 読み取り 500 万行/日・書き込み 10 万行/日) に対し、最悪の `q` ばかり 1 日 1 万回
キャッシュ外れしても 420 万行で収まる計算だが、**§5 が先に効く**。同期は 1 日 2 回までが目安。

## 5. 費用の守り (`imas-live-db` で無料枠を焼いた前例への答え)

1. **フルスキャン無し**: 全クエリが主キーか索引。`test/queries.test.ts` が全組み合わせの
   `EXPLAIN QUERY PLAN` で `SCAN` が出ないことを固定。`LIMIT` 必須、`OFFSET` 禁止もここで検査。
2. **エッジキャッシュ** (`caches.default`): キーは**同期の版**+正規化したパス・クエリ
   (引数の順序違いは同じ鍵)。応答は 1 時間 (404 は 60 秒)。同期のたびに `meta.version` が
   変わるので古い応答が新しいデータと混ざらない。キャッシュ当たりは D1 も Rate Limiting も通らない。
   注意: Cache API は**データセンターごと**なので、全世界で見たときの当たり率は 1 つの
   拠点より低い。
3. **LIMIT とページング**: 1 ページ最大 100 行、前方一致の語は最大 64 文字、引数は検査して
   不正なら D1 に行く前に 400。
4. **Rate Limiting バインディング**: キャッシュに外れたリクエストだけを IP ごと 60 回/分で絞る
   (`wrangler.jsonc` の `ratelimits`)。超えたら 429 + `Retry-After`。
5. **超えたとき**: D1 の無料枠を超えると D1 が失敗するだけで課金されない。Worker は 503 を返し、
   キャッシュに残っている応答は返し続ける。Workers の無料枠 (10 万リクエスト/日) は
   アセット配信と違って**全リクエストが Worker 呼び出し**を食う点が Web と違う。キャッシュ当たりも
   Worker は起動するので、人気が出て 10 万/日を超えそうなら Workers Paid (月 $5) が要る。
   これが「ランニングコスト 0」の限界で、**yesno のような少数の利用者の間は無料枠に収まる**。
   超える見込みが出たら、静的 JSON (Workers Static Assets は無制限・無料) に戻す案がある (§9)。

## 6. 同期 (マスタ → D1)

**API は「CloudKit の最新の、FK 検査を通った書き出し」を毎日反映する。** CloudKit で直した値
(例: 学マスの学年) は、翌日 03:00 JST (または手動実行) に API に届く。develop の `db/master.sql` は
PR で入るまで古いので入力にしない。yesno などの利用者は、この鮮度を前提にしてよい。

- 自動: `.github/workflows/refresh-data.yml` の `sync-data-api` ジョブ。`export` → `check` (FK 検査) が
  緑のときだけ、export の artifact をそのまま `tools/sync_master_d1.py --remote --yes --master-sql` で流す。
  検査に落ちた日は流さず、API には前日までのデータが残る。`workflow_dispatch` で手動実行もできる
  (CloudKit に push した直後に反映したいとき)。Cloudflare の資格情報 (environment `cloudflare`) が無ければ飛ばす。
- 手元: `python3 tools/sync_master_d1.py --local` (ローカル D1)、`--remote` は流すコマンドを**表示するだけ**、
  `--remote --yes` で本番。既定の入力は `bot/data-refresh` の最新。`--from-cloudkit` / `--from-develop` /
  `--master-sql PATH` で変えられる。
- 本番へは D1 の REST API (`/d1/database/<id>/query`) に文の切れ目で約 90KB ずつ POST する
  (`wrangler d1 execute --remote --file` が叩く `/import` は API トークンでも OAuth でも
  `Authentication error [code: 10000]` で落ちる。2026-10-11 の CI で確認)。塊ごとに別の書き込みなので、
  同期中の数分は表が空・途中の状態になりうる。落ちたら頭から流し直す。
- 全置き換え (DROP → CREATE → INSERT)。何度流しても同じ。`meta.version` (日付 + SQL の内容ハッシュ) が
  内容が変わると新しくなり、エッジのキャッシュ鍵が切り替わる。
- **`apply_data.py --push` の最後には足さない。** push は CloudKit への書き込みで、翌日の cron か手動実行が
  それを取り直して流す。トークンの作り方・secret は [`DATA_PIPELINE.md`](DATA_PIPELINE.md) の「公開データ API への同期」。

## 7. テスト

| 場所 | 固定すること |
|---|---|
| `imas-core` `agent::tools::publish` | 文書がツール面 (`get_idol` / `idol_songs`) と同じ答え、全アイドル・曲・ユニットで文書が組める、持ち歌が大きさで切れない、禁止値・タグが出ない |
| `imas-core` `web_export::data_api` | SQL がそのまま流せる、件数が台帳と一致、同じ入力でバイト一致、**列名・SQL 全文に歌詞/試聴が無い** (T12 相当)、1 文 90KB 以下 |
| `imas-data-api/test` | 全クエリの実行計画にフルスキャンが無い、列に歌詞/試聴が無い、ルーティング・400・404・405・CORS・キーセット・キャッシュ当たり時に D1 を読まない・429・版でキャッシュ鍵が変わる |

```bash
cd imas-core && cargo test --locked --lib --features web-export data_api && cargo test --locked --lib publish
cd imas-data-api && npm ci && npm run wasm && npm run check && npm test
```

## 8. デプロイ (オーナーが打つ。ここではしていない)

```bash
cd imas-data-api
npx wrangler d1 create imas-master-db          # 1 度だけ。返った database_id を wrangler.jsonc に書く
python3 ../tools/sync_master_d1.py --remote --yes # SQL を組んで本番 D1 に流す (以降は毎日 CI が流す)
npm run wasm && npx wrangler deploy            # カスタムドメインは wrangler が用意する
curl https://idollivedb-api.fugaapp.site/v1/meta
```

## 9. 次の段

- **Web を API 経由にする** (オーナーの希望)。今は Web が自前の JSON を持っている。API が
  Web の要る形 (一覧・検索・イベント・公演・セトリ) を覆うまで、イベント / 公演 / 会場の文書
  (`get_event` / `get_show`) と部分一致検索を足す必要がある。そのとき Web の表示規則
  (`web_export` の DTO) と `agent::tools` が二重にならないよう、規則の置き場を整理すること。
- 部分一致検索 (FTS5 trigram は 3 文字未満に当たらない点に注意)。
- 無料枠を超える見込みが出たら、同じ文書を Workers Static Assets の静的 JSON として配る
  (読み取りが無制限・無料になる代わりに、検索・絞り込みは事前に作った索引ファイルだけになる)。
