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
| `index.ts` | エントリ。`fetch` ハンドラ = 全ルーティング (大きな switch 的ルーター) + `scheduled` (cron) 委譲。認証 (`getAuthUser`)・CORS・レスポンスヘルパもここ |
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

## 改善余地 (公開時点)

- `index.ts` が大きいルーター。リソース別サブモジュールへの分割余地 (重い処理は既に各モジュールへ委譲済み)。
- 不正 JSON ボディが一部 500 になる箇所あり (400 へ統一の余地)。
