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

| ファイル | 役割 |
|---|---|
| `index.ts` | エントリ。`fetch` ハンドラ = ルーティング + `scheduled` (cron) 委譲。CORS・レスポンスヘルパ (`makeResponders`)・エッジキャッシュもここ。**切り出し済みのルート群は `routes/` へ委譲する** |
| `env.ts` | `Env` インターフェース (D1 binding + vars/secrets) の単一ソース |
| `auth.ts` | Apple / Google の ID トークン検証、自前セッション JWT の署名・検証、`getAuthUser` |
| `users.ts` | `users` テーブルの共通操作 (`upsertUser` / `checkIsAdmin`) |
| `validation.ts` | リクエスト入力の共通バリデータ (`parsePositiveInt` / `validateOpaqueKey` / `escapeLike` / スコープ ID 検証) |
| `routes/context.ts` | ルートハンドラが受け取る `RouteContext` (リクエスト毎のレスポンダを引数で渡す) |
| `routes/device_aggregates.ts` | `/favorites/*` `/penlight/*` (device 単位の集計。認証不要) |
| `routes/polls.ts` | `/polls/*` (みんなの投票) |
| `routes/tags.ts` | `/tags` `/idol-tags` `/unit-tags` の 3 プール + `/{songs,idols,units}/:id/tags` + `/{songs,idols,units}/:id/similar`。タグ専用ヘルパもここに閉じている |
| `routes/setlist_predictions.ts` | `/me/predictions` `/shows/:id/predictions` `/shows/:id/songs/:id/performers` `/shows/:id/likes` `/shows/:id/songs/:id/like` |
| `cloudkit.ts` | CloudKit S2S クライアント (`cloudKitModify` / `cloudKitLookup` / forceUpdate・softDelete ビルダ)。`modifiedAt` 強制注入 |
| `ck_schema.ts` | CloudKit Public DB スキーマ型情報の単一ソース |
| `edits.ts` | `/edits` 投稿の受付・検証 (`master_validators.ts`) → CloudKit 反映 |
| `master_validators.ts` | `/edits` のマスタ編集バリデーション |
| `edit_history.ts` | オープン編集の監査基盤 (`edit_batch` / `edit_history` の D1 ヘルパ) |
| `setlist_snapshot.ts` | setlist 編集を show 単位スナップショットで履歴化 |
| `edit_good.ts` | 編集への「拍手」 |
| `feed.ts` | 編集フィード (`/feed`、display_name マスク含む) |
| `revert.ts` | 編集の差し戻し / ユーザー単位 revert / 管理者編集一覧 |
| `appattest.ts` | App Attest (iOS) / Play Integrity (Android) 検証 + アプリ実体トークン発行 (クローンただ乗り対策) |
| `rate_limit.ts` | D1 ベースのレート制限 (`INSERT…ON CONFLICT…RETURNING` で TOCTOU 排除) |
| `badges.ts` | 貢献バッジ判定 |
| `apply.ts` | Cron (`scheduled`) ハンドラ。`rate_limits` の日次掃除等 |

## 主なエンドポイント群 (実在ルートは `index.ts` のルートマッチが正)

- 認証: `POST /auth/login` (Apple) / `GET /auth/me`
- オープン編集: `POST /edits` / `GET /edits` (feed) / `GET /me/edits` / `POST|DELETE /edits/:batchId/good` / `POST /edits/:batchId/revert` / `GET /master/:recordType/:recordName/history`
- 集計系: `GET/POST /polls…` / `/shows/:id/predictions` / `/shows/:id/likes` / `/songs/:song_id/tags|similar` / `/tags…` / `/favorites…` / `/penlight…` / `/leaderboard` / `/users/:id/badges`
- 管理: `POST /admin/cloudkit/save` / `POST /admin/ban` / `POST /admin/revert-user` / `GET /admin/users/:id/edits`
- アプリ証明: `GET /app/challenge` / `POST /app/attest|assert|integrity`

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

## ⚠️ D1 スキーマの drift (未解決・要オーナー確認)

**`migrations/` だけから作った D1 は、本番と同じスキーマにならない。** ローカル開発・新環境・
災害復旧で「動かない」原因になるので、本番の実スキーマを確認したうえで migration を補うこと。

| 対象 | 状態 |
|---|---|
| `setlist_song_likes` | `CREATE TABLE` がどの migration にも無かった → **`0025_setlist_song_likes.sql` で補完済み** (`IF NOT EXISTS` なので本番にあれば no-op)。**適用前に本番の `PRAGMA table_info` と一致するか確認すること。** |
| `setlist_predictions` / `setlist_prediction_votes` | migration は **`event_id`**、コードは **`show_id`**。rename の migration が存在しない (後発の `setlist_performer_predictions` は正しく `show_id`)。**未解決。** |

`event_id → show_id` を直すには本番の現状を先に見る必要がある:

```bash
npx wrangler d1 execute imas-live-db --remote \
  --command "PRAGMA table_info(setlist_predictions);"
```

- 本番が既に `show_id` なら → 「ローカルだけ古い」ので、追いつくための migration を書く。
  ただし D1 の migration は本番でも走るため、素の `ALTER TABLE ... RENAME COLUMN` は
  本番側で `no such column: event_id` になって失敗する。テーブル作り直し (新テーブルへ
  `INSERT SELECT` → `DROP` → `RENAME`) など、両方の状態で成立する形にする必要がある。
- 本番が `event_id` のままなら → 予想セトリ機能は本番でも壊れている。まず動作を確認する。

**推測で migration を書かないこと。** ユーザーの投票データが入っているテーブル。

## 改善余地

- `index.ts` は 1,256 行 (着手時 4,271 行) まで縮んだ。残っているのは横断的関心事
  (CORS・レスポンダ・エッジキャッシュ・App Attest・Universal Links) と、
  `/auth/*` `/users/me` `/admin/*` `/edits` 系 `/leaderboard` `/transfer`。
  さらに切り出すなら `/auth/*` + `/users/me` あたりが次の単位。
- ~~不正 JSON ボディが一部 500 になる~~ → 解消済み (全ルートで 400 + `{"error":"invalid JSON body"}`)。
