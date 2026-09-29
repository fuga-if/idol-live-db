# ImasLiveDB バックエンド (Cloudflare Worker) アーキテクチャ

> iOS は [`ARCHITECTURE.md`](ARCHITECTURE.md)、Android は [`ARCHITECTURE-android.md`](ARCHITECTURE-android.md)。
> データ所在の全体像は [`ARCHITECTURE.md` のデータ節](ARCHITECTURE.md#データの所在同期マイグレーション-ios--android-共通の思想) と
> [`DATA_PIPELINE.md`](DATA_PIPELINE.md)。

## 役割

`imas-live-api/` は Cloudflare Worker。**2つの責務**を持つ:

1. **集計系コミュニティの API** (タグ/お気に入り/投票/ポール/予想/いいね/ランキング) — D1 (SQLite) で原子的カウンタ・レート制限・device 重複排除・サーバ集計を提供。CloudKit が苦手な領域をここが担う。
2. **マスタのオープン編集フロー** (`/edits`) — ユーザー投稿の編集を検証・記録し、CloudKit Public DB (マスタの唯一の正) へ S2S で反映。差分 sync で全端末へ配信される。

> マスタの**読み取り API は持たない** (旧 `/brands` `/idols` 等は撤去)。アプリは CloudKit から直接差分同期する。Worker はマスタの「書き込み口」と集計系の「読み書き口」。

## 技術スタック

- Cloudflare Workers (TypeScript) / `wrangler`
- **D1** (SQLite) … 集計系コミュニティ + 編集キュー/監査 + レート制限
- **CloudKit Public DB** … マスタの唯一の正 (Worker は S2S で書き込み)
- 認証: Apple Sign In JWT 検証 (`aud` = bundle) → 自前セッション JWT (HS256)。さらに App Attest / Play Integrity でアプリ正規性を担保

## モジュール構成 (`src/`)

`index.ts` は薄いエントリ (362 行) に縮んでいる。ルーティングは `routes/` の各 `handleXxx` を
順に試し、未一致なら次へ渡す形 (「ルートを `routes/` へ切り出す手順」節のとおり)。

| ファイル | 役割 |
|---|---|
| `index.ts` | エントリ。`fetch` = `ROUTES` (上から順に試す) の委譲 + `scheduled` を `scheduled.ts` へ委譲。CORS・レスポンスヘルパ (`makeResponders`)・エッジキャッシュの可否判定もここ |
| `env.ts` | `Env` インターフェース (D1 binding + vars/secrets) の単一ソース |
| `auth.ts` | Apple / Google の ID トークン検証、自前セッション JWT の署名・検証、`getAuthUser`、退会によるセッション失効判定 (`isRevokedSession`) |
| `jwt.ts` | JWT の分解・HS256 署名検証・RS256 (JWKS) 検証・JWKS キャッシュ。クレーム判定は使う側 (`auth.ts` / `appattest.ts`) の責務 |
| `bytes.ts` | base64 / base64url / UTF-8 / 定数時間比較 / SHA-256 / PEM のバイト列小物。`jwt.ts` / `appattest.ts` / `cloudkit.ts` / `routes/lyrics.ts` が個別に持っていた重複を集約 |
| `time.ts` | D1 (SQLite) の日時文字列 ⇔ epoch 秒の変換 (iOS `APIClient` が秒 epoch を前提にデコードするための境界) |
| `users.ts` | `users` テーブルの共通操作 (`upsertUser` / `checkIsAdmin`) |
| `validation.ts` | リクエスト入力の共通バリデータ (`parsePositiveInt` / `validateOpaqueKey` / `escapeLike` / スコープ ID 検証) |
| `scheduled.ts` | Cron (`scheduled`) ハンドラ。5 分ごとの掃除 (`api_rate_limits` の分バケット・`transfer_codes`) と日次の掃除・集計 (下記「IP レート制限の枠と掃除」参照) |
| `rate_limit.ts` | D1 ベースのレート制限 (`INSERT…ON CONFLICT…RETURNING` で TOCTOU 排除)。IP 単位の枠 (`requireIpQuota`) は用途ごと (`"lyrics"` 等) に分けて渡す |
| `routes/context.ts` | ルートハンドラが受け取る `RouteContext` (リクエスト毎のレスポンダを引数で渡す) |
| `routes/guards.ts` | ルート入口で繰り返す確認 (端末 ID・IP の枠・本文・パスの値・BAN)。「値か、そのまま返せる `Response` か」を返し、呼び出し側は `if (x instanceof Response) return x;` で抜ける |
| `routes/app_attest.ts` | App Attest (iOS) / Play Integrity (Android) 検証・アプリ実体トークン発行・コミュニティ読み取りのゲート (`gateCommunityRead`) |
| `routes/app_links.ts` | AASA (`apple-app-site-association`) 配信・共有リンクのランディング |
| `routes/auth.ts` | `/auth/*` (ログイン・リフレッシュ・`/auth/me`) |
| `routes/users.ts` | `/users/*` |
| `routes/edits.ts` | `/edits` 投稿の受付・検証 (`master_validators.ts`) → CloudKit 反映、フィード |
| `routes/admin.ts` | `/admin/ban` `/admin/revert-user` `/admin/users/:id/edits` |
| `routes/setlist_predictions.ts` | `/me/predictions` `/shows/:id/predictions` `/shows/:id/songs/:id/performers` `/shows/:id/likes` `/shows/:id/songs/:id/like` |
| `routes/polls.ts` | `/polls/*` (みんなの投票) |
| `routes/device_aggregates.ts` | `/favorites/*` `/penlight/*` (device 単位の集計。認証不要) |
| `routes/tags.ts` | `/tags` `/idol-tags` `/unit-tags` の 3 プール + `/{songs,idols,units}/:id/tags` + `/{songs,idols,units}/:id/similar`。タグ専用ヘルパもここに閉じている |
| `routes/lyrics.ts` | 歌詞の配信・検索・投入 (`/songs/:id/lyrics` `/lyrics/search` `/admin/lyrics/*`)。**配信・検索は未認証可**、投入は運用者トークン/admin 必須。詳細は下の「歌詞・コールの認証」 |
| `routes/calls.ts` | コールガイドの保存 (`PUT /songs/:id/calls`) と整備状況の一覧 (`GET /calls/dashboard`)。一覧は件数・日時・表示名だけで歌詞の断片を含まないため公開キャッシュに載せる |
| `routes/song_detail.ts` | `GET /songs/:id/detail` (tags + similar + penlight + 任意で歌詞を 1 リクエストに束ねる) |
| `routes/transfer.ts` | `/transfer` (端末間の引き継ぎコード) |
| `routes/discord.ts` | Discord のロール受け取り。`POST /discord/link` (アプリから認可 URL を発行) → `GET /discord/callback` (サーバーに参加させ、編集 10 件以上なら「データ協力」)。`POST /discord/interactions` (スラッシュコマンド `/申請`、Ed25519 署名検証) → `GET /github/callback` (マージ済み PR があれば「コントリビューター」) |
| `discord.ts` | Discord / GitHub OAuth の REST 呼び出し・Interactions の署名検証・OAuth 後の結果ページ |
| `discord_digest.ts` | 5 分 cron で、前回から増えた編集・コールガイド・タグ・お題を #更新通知 に 1 通にまとめて投稿 (rowid の範囲で新しい行だけ読む。編集者は出さない。編集の中身は discord_edit_diff.ts) |
| `discord_edit_diff.ts` | edit_history の before/after から「項目: 変更前 → 変更後」と、セトリのスナップショットから追加・削除曲・曲順の入れ替えを組む |
| `discord_poll_results.ts` | 5 分 cron で、締め切ったお題の上位 3 つを #投票結果 (アナウンスチャンネル) に出して公開する (位置は discord_digest_cursors の poll_results。投票者は出さない) |
| `discord_live_threads.ts` | 日次 cron (00:17 JST) で、今日の公演ごとに #ライブ実況・感想 に公開スレッドを立てる (Show.date を CloudKit で引く。同じ日は discord_digest_cursors の live_threads で 1 回だけ) |
| `discord_releases.ts` | 5 分 cron で App Store の新しいバージョンを #お知らせ に (iTunes lookup)、日次 cron の JST 月曜だけ develop に入った feat/fix/perf を場所ごとにまとめて #開発中 に |
| `lyrics_calls.ts` | コール (clap / calls) のドメインロジック。ボディ検証・アンカーの数え方 (Unicode スカラー)・歌詞差し替え時の引き継ぎ |
| `lyrics_index.ts` | 歌詞本文検索の索引 (候補を絞ってから全走査するための補助索引) |
| `call_stats.ts` | コールの数え方と派生メタデータ (`song_call_stats` / `call_edit_history`, migrations/0032) の書き込み。数え方の定義はここが唯一の正 |
| `cloudkit.ts` | CloudKit S2S クライアント (`cloudKitModify` / `cloudKitLookup` / forceUpdate・softDelete ビルダ)。`modifiedAt` 強制注入 |
| `ck_schema.ts` | CloudKit Public DB スキーマ型情報の単一ソース |
| `master_validators.ts` | `/edits` のマスタ編集バリデーション |
| `edit_history.ts` | オープン編集の監査基盤 (`edit_batch` / `edit_history` の D1 ヘルパ) |
| `edit_requests.ts` | `/edits` の受付本体 (旧 `edits.ts` から分離)。`routes/edits.ts` が薄いハンドラとして呼ぶ |
| `setlist_snapshot.ts` | setlist 編集を show 単位スナップショットで履歴化 |
| `edit_good.ts` | 編集への「拍手」 |
| `feed.ts` | 編集フィード (`display_name` マスク含む。マスクの実装は `masking.ts`) |
| `masking.ts` | 表示名の先頭 8 文字マスク等、公開応答から個人特定情報を落とす処理 |
| `revert.ts` | 編集の差し戻し / ユーザー単位 revert / 管理者編集一覧 |
| `appattest.ts` | App Attest (iOS) / Play Integrity (Android) 検証の実装本体 (`routes/app_attest.ts` から呼ばれる) |
| `badges.ts` | 貢献バッジ判定 |

## 歌詞・コールの認証 (2026-09 に変わった点)

**`GET /songs/:id/lyrics` と `GET /lyrics/search` は Bearer 不要 (未認証で配る)。** 以前は認証必須
だったが、JASRAC の条件が要求するのは「まとめ取りできないこと (1 リクエスト 1 曲)」と
「リクエスト回数が数えられること」で、どちらも認証の有無とは独立している。今の守りは:

- **IP 単位のレート制限** (`rate_limit.ts` の `requireIpQuota(ctx, "lyrics", LYRICS_IP_LIMITS)`。
  120/分・1,000/日)。用途ごとに名前空間を分けており、他の枠 (`"edit"` 等) と混ざらない。
  会場の NAT で同じ IP に大勢が乗っても正常利用は 429 にならず、まとめ取りは日の上限で止まる。
- **`Cache-Control: no-store`** に加え、`index.ts` のエッジ共有キャッシュ対象判定
  (`edgeCacheEligible`) からパスを名指しで除外。認証で守っているのではなく、キャッシュに
  絶対に載らないことと、まとめ取りできないことで守っている。
- draft (未公開) の歌詞は `GET /songs/:id/lyrics` も `/lyrics/search` も admin にしか返さない
  (`checkIsAdmin`。未認証はここで 404)。

**歌詞・コールの投入・差し替えだけが引き続き認証を要求する**: `PUT /songs/:id/calls` は
一般ユーザーの Bearer (自分の入力として `edit` 枠、100/日) か運用者トークン
(`X-Push-Token` = `env.LYRICS_PUSH_TOKEN`、`lyrics_calls` 枠) のどちらか。
`PUT /admin/lyrics/:id` と `/admin/lyrics/status|quota` は運用者トークンか admin Bearer 必須。

## 主なエンドポイント群 (実在ルートは `index.ts` の `ROUTES` が正)

- 認証: `POST /auth/login` (Apple) / `POST /auth/refresh` / `GET /auth/me`
- オープン編集: `POST /edits` / `GET /edits` (feed) / `GET /me/edits` / `POST|DELETE /edits/:batchId/good` / `POST /edits/:batchId/revert` / `GET /master/:recordType/:recordName/history`
- 歌詞/コール: `GET /songs/:id/lyrics` (未認証可) / `GET /lyrics/search` (未認証可) / `PUT /songs/:id/calls` / `GET /calls/dashboard` / `POST /admin/lyrics/status` / `GET /admin/lyrics/quota` / `PUT /admin/lyrics/:id`
- 曲詳細の束ね: `GET /songs/:id/detail` (tags + similar + penlight。Bearer 付きなら歌詞も同梱)
- 集計系: `GET/POST /polls…` / `/shows/:id/predictions` / `/shows/:id/likes` / `/songs/:song_id/tags|similar` / `/tags…` / `/favorites…` / `/penlight…` / `/users/:id/badges`
- 引き継ぎ: `POST /transfer` / `GET /transfer/:code`
- Discord: `POST /discord/link` / `GET /discord/callback` / `POST /discord/interactions` / `GET /github/callback`
- 管理: `POST /admin/ban` / `POST /admin/revert-user` / `GET /admin/users/:id/edits`
- アプリ証明・着地: `GET /app/challenge` / `POST /app/attest|assert` / `GET /app/events/:id` / `GET /app/shows/:id` / `GET /.well-known/apple-app-site-association`

**撤去済み (X-03 で発見した食い違いの訂正)**: `GET /leaderboard`・`POST /admin/cloudkit/save`・
`POST /app/integrity` は 2026-09 のリファクタで実装から消えており、コードベース全体を
grep しても存在しない。旧版のこの文書がまだ挙げていたのを削った。

## IP レート制限の枠と掃除

`rate_limit.ts` の `requireIpQuota` は**用途ごとに名前空間を分けて**枠を持つ (`"lyrics"` など)。
1 つの IP が複数の用途を叩いても、片方の枠を使い切ってもう片方が巻き添えで止まることはない。

D1 の行の持ち方は `api_rate_limits` (分バケット = 正の鍵、日バケット = 負の鍵) の 1 表。
掃除は `scheduled.ts` が持つ (旧 `apply.ts` は無くなり、cron のタスクは 1 つずつ独立させてある。
1 つが失敗しても残りは走り、失敗は `cron_task_failed` の JSON 1 行でログに出る):

- **5 分ごと**: 1 日より古い**分**バケット (正の鍵) だけを消す。**日バケット (負の鍵) はここでは
  消さない** — 消すと IP の日の上限 (歌詞の 1,000/日) が 5 分ごとに 0 へ戻って効かなくなる。
- **日次**: 前日までの**日**バケットを消す (今日の行は残す)。あわせて `rate_limits` (7 日超)・
  `call_edit_history` (180 日超)・`transfer_codes` (期限切れ) の掃除と `song_tag_counts` の再計算。

分バケットの掃除頻度を落とさないのは、フルスキャンに近かった旧実装 (索引無し・1 回 1,006 行 ×
283 回/日 = 285,000 行/日) を索引 (`idx_api_rate_limits_bucket` / `idx_rate_limits_date`) と
頻度調整で直した経緯があるため。日次分だけを日次 cron に分けてある。

## セッションの失効 (退会)

`auth.ts` の `isRevokedSession` が、自前セッション JWT だけを対象に次を見る:

- `users` の行が無い (退会した) → 失効
- その行が作られた時刻より 10 分以上前に発行されたセッション JWT (退会後に同じ人が
  再登録した場合の、退会前トークンの持ち越し) → 失効

Apple / Google の ID トークンには関与しない (自前セッション JWT の検証にだけ噛む)。
`routes/guards.ts` の入口チェックがこれを通す。

## 歌詞の利用ログ (JASRAC リクエスト回数)

歌詞を**実際に返したときだけ** `{"event":"lyrics_read","song_id":"..."}` を 1 行
`console.log` する (`routes/lyrics.ts` の `logLyricsRead`。`GET /songs/:id/lyrics` と、
Bearer 付きで歌詞を同梱した `GET /songs/:id/detail` の両方)。

- **D1 に数えない。** 閲覧のたびに書くと、固定無料枠のホットパスが読み取りから
  読み書きに変わる。集計は Workers Logs 側 (`wrangler.jsonc` の
  `observability.enabled = true` / `head_sampling_rate = 1`) で行う。
- **出すのは event 名と song_id だけ。** uid・IP・端末 ID・歌詞本文は載せない
  (載せると Workers Logs が「誰が何を読んだか」の閲覧履歴になる)。
- 日次バッチ `tools/lyrics/collect_request_logs.py` が Telemetry Query API
  (`POST /accounts/{account_id}/workers/observability/telemetry/query`) で拾い、
  `data/lyrics_requests/YYYY-MM-DD.tsv` に畳む。
- ⚠️ **ログの保持は 3 日**。バッチが 3 日以上止まるとその分は取り返せない。
  既定で 3 日ぶん引き直すのは 1〜2 日の失敗を翌日が埋めるため。
- ログの形式 (JSON 1 行・キー名) はバッチのパーサと 1:1 の契約。片方だけ変えると
  集計が 0 になる。`test/lyrics_read_log.test.ts` が「歌詞を返したときだけ出る」ことを固定する。

詳細は [`JASRAC.md`](JASRAC.md)「リクエスト回数の集計」。

## セキュリティの要点

- **SQL は全件パラメータバインド** (動的 SQL 断片はサーバ定義の定数のみ。ユーザー値は常にバインド)。
- Apple JWT は `alg`/`iss`/`aud`/`exp`/`iat`/`kid` まで厳格検証。セッション JWT は `aud` 必須・secret 32 文字下限。
- 秘密 (`CLOUDKIT_PRIVATE_KEY` / `CLOUDKIT_KEY_ID` / `SESSION_JWT_SECRET` / `ADMIN_USER_IDS` / `GOOGLE_SERVICE_ACCOUNT`) は `wrangler secret` 運用。repo・`wrangler.jsonc` には置かない。
- エラー応答は `request id` のみ返し、D1/スキーマ詳細は秘匿。
- **クローンただ乗り対策** (App Attest/Play Integrity) は `APP_ATTEST_MODE` で monitor/enforce 切替。詳細は [`DATA_PIPELINE.md`](DATA_PIPELINE.md) と `appattest.ts`。

## データ鮮度 (CloudKit → git)

日次 cron で CloudKit → `db/master.sql` をエクスポートし、コントリビューターが最新マスタに対して
検証できるようにする (詳細 [`DATA_PIPELINE.md`](DATA_PIPELINE.md))。

## ルートを `routes/` へ切り出す手順

`index.ts` は元々 4,271 行の単一 `fetch` ハンドラだった。1 グループずつ切り出して縮めている
(2026-07 時点で 3,073 行)。新しく切り出す時は同じ手順を踏むこと:

1. **依存を先に外へ出す。** ルートが使う共有ヘルパが `index.ts` にあると、`routes/` から
   import し返して循環する。`auth.ts` / `users.ts` / `validation.ts` / `rate_limit.ts` の
   いずれか適切な持ち主へ先に移す (移動のみ。`tsc` が全参照を検証する)。
2. **移動前の応答を記録する。** `wrangler dev` を上げ、対象ルートの正常系・異常系を curl して
   ステータス・`Cache-Control`・本文を保存する。レート制限は状態依存なので、実行前に
   `rate_limits` / `api_rate_limits` を空にして再現性を出す。auth 必須ルートは
   `SESSION_JWT_SECRET` をローカルに置いて自分でセッション JWT を発行すれば通せる。
3. **`handleXxx(ctx: RouteContext): Promise<Response | null>` として移す。** 未一致なら `null` を
   返し、呼び出し元の if チェーンへ処理を戻す。`json` / `error` / `rateLimit*` はリクエスト毎の
   クロージャなので `RouteContext` で渡す。**本文は 1 行も書き換えない。**
4. **移動後に同じ curl を流し、差分ゼロを確認する。** 審査済みリリース版の iOS / Android が
   本番のこの API を叩いているので、レスポンスキー・ステータス・`Cache-Control` の変化は
   そのまま既存インストールの不具合になる。

## D1 スキーマの drift (解決済み)

`setlist_song_likes` の `CREATE TABLE` 欠落は `0025_setlist_song_likes.sql` で補完済み
(`IF NOT EXISTS` なので本番にあれば no-op)。

`setlist_predictions` / `setlist_prediction_votes` の `event_id` ↔ `show_id` の乖離
(migration は `event_id`・本番とコードは `show_id`) は `migrations/0038_setlist_predictions_show_id.sql`
で解決した。本番ではこの migration を流さない (表はすでにこの形)。`wrangler d1 migrations apply
--remote` を新環境に対して実行する前に、`0038_setlist_predictions_show_id.sql` を「本番では
適用済み」として `d1_migrations` に記録する手順が必要 (`imas-live-api/README.md`「D1 migration
適用」に手順あり)。ローカル・テスト・新環境の D1 はこの migration により本番と同じ `show_id` の
形になる。

## 改善余地

- `index.ts` はルーティングをほぼ `routes/` へ切り出し終え、362 行まで縮んだ。残っているのは
  横断的関心事 (CORS・レスポンダ・エッジキャッシュ可否判定・`scheduled` への委譲) と `ROUTES` の
  組み立てだけ。
- ~~不正 JSON ボディが一部 500 になる~~ → 解消済み (全ルートで 400 + `{"error":"invalid JSON body"}`)。
