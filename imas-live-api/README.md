# imas-live-api

Cloudflare Workers + D1 で動く THE IDOLM@STER Live Database 投稿・投票 API。

## セットアップ

### 必須の secret 登録

```bash
npx wrangler secret put CLOUDKIT_KEY_ID
npx wrangler secret put CLOUDKIT_PRIVATE_KEY
npx wrangler secret put APPLE_BUNDLE_ID
# カンマ区切りで管理者の Apple UID を登録
npx wrangler secret put ADMIN_USER_IDS
```

### D1 migration 適用

```bash
# ローカル
npx wrangler d1 migrations apply imas-live-db

# リモート (本番)
npx wrangler d1 migrations apply imas-live-db --remote
```

## デプロイ

```bash
npx wrangler deploy
```

dry-run (デプロイせず型チェックのみ):

```bash
npx wrangler deploy --dry-run
```

## ローカル開発

```bash
npx wrangler dev
```

## Cron 確認

```bash
npx wrangler tail
```

Cron (scheduled) は `rate_limits` テーブルの日次掃除 (7 日より古いレコード削除) のみ。
旧 submission-apply パイプラインは即時オープン編集 (`POST /edits`) への移行で廃止済み。

## 主要エンドポイント

ルーティングは `src/index.ts` の `path` / `request.method` マッチで定義されている (フレームワーク不使用)。
以下が実在する全エンドポイント。`:xxx` はパスパラメータ。

### App Attestation / ランディング

| Method | Path | 認証 | 概要 |
|--------|------|------|------|
| GET | / | - | ヘルスチェック / バージョン |
| GET | /.well-known/apple-app-site-association | - | Universal Links 用 AASA |
| GET | /app/events/:id, /app/shows/:id | - | 共有リンクのランディング (CloudKit S2S 直読み) |
| GET | /app/challenge | - | App Attest チャレンジ発行 |
| POST | /app/attest | - | App Attest 鍵の登録 |
| POST | /app/assert | - | App Attest アサーション検証 |
| POST | /app/integrity | App token | Play Integrity (Android) 検証 |

### 認証 (Apple Sign in with Apple)

| Method | Path | 認証 | 概要 |
|--------|------|------|------|
| POST | /auth/login | - | Apple identity token でログイン → セッション JWT 発行 |
| POST | /auth/refresh | refresh token | アクセストークン更新 |
| GET | /auth/me | Bearer | 自分のユーザー情報 |

### オープン編集 (マスタ編集) / フィード

| Method | Path | 認証 | 概要 |
|--------|------|------|------|
| GET | /edits | 任意 | 編集フィード |
| POST | /edits | Bearer | マスタ編集を投稿 (即時反映) |
| GET | /me/edits | Bearer | 自分の編集一覧 |
| POST | /edits/:id/good | Bearer | 編集に Good |
| DELETE | /edits/:id/good | Bearer | Good 取り消し |
| POST | /edits/:id/revert | Bearer | 編集を差し戻し |
| GET | /master/:type/:id/history | - | 特定マスタレコードの編集履歴 |
| GET | /users/:id/badges | - | ユーザーのバッジ一覧 |
| GET | /leaderboard | - | 貢献ランキング |

### 出演者予想 / いいね (shows 配下)

| Method | Path | 認証 | 概要 |
|--------|------|------|------|
| GET | /me/predictions | Bearer | 自分のセトリ予想一覧 |
| GET | /shows/:id/predictions | 任意 | ショーのセトリ予想 |
| POST | /shows/:id/predictions | Bearer | セトリ予想を投稿 |
| DELETE | /shows/:id/predictions/:pid | Bearer | セトリ予想削除 |
| GET | /shows/:id/songs/:sid/performers | 任意 | 出演者予想 |
| POST | /shows/:id/songs/:sid/performers | Bearer | 出演者予想を投稿 |
| DELETE | /shows/:id/songs/:sid/performers/:idolId | Bearer | 出演者予想削除 |
| GET | /shows/:id/likes | 任意 | ショー内の曲いいね集計 |
| POST | /shows/:id/songs/:sid/like | Bearer | 曲にいいね |
| DELETE | /shows/:id/songs/:sid/like | Bearer | いいね取り消し |

### ポール (みんなの投票)

| Method | Path | 認証 | 概要 |
|--------|------|------|------|
| GET | /polls | 任意 | ポール一覧 |
| GET | /polls/results | 任意 | ポール結果まとめ |
| GET | /polls/achievements/:id | - | ポール達成バッジ |
| GET | /polls/:id | 任意 | ポール詳細 |
| POST | /polls | Bearer | ポール作成 |
| DELETE | /polls/:id | Bearer (作成者/admin) | ポール削除 |
| POST | /polls/:id/votes | Bearer | 投票 |
| DELETE | /polls/:id/votes/:vid | Bearer | 投票取り消し |

### お気に入り / ペンライト (device 集計)

| Method | Path | 認証 | 概要 |
|--------|------|------|------|
| POST | /favorites/toggle | X-Device-Id | お気に入りトグル |
| GET | /favorites/ranking | - | お気に入りランキング |
| GET | /penlight/palette | - | ペンライト色パレット |
| POST | /penlight/vote | X-Device-Id | ペンライト色投票 |
| DELETE | /penlight/vote | X-Device-Id | ペンライト色投票取り消し |
| GET | /penlight/votes/:songId | - | 曲のペンライト色集計 |

### タグ / 類似曲

| Method | Path | 認証 | 概要 |
|--------|------|------|------|
| GET | /tags | - | タグ一覧 (検索/カテゴリ/ソート) |
| POST | /tags | Bearer | タグ作成 |
| GET | /tags/:id | - | タグ詳細 |
| PUT | /tags/:id | Bearer | タグ編集 |
| GET | /tags/:id/history | - | タグ編集履歴 |
| POST | /tags/:id/report | X-Device-Id | タグ通報 |
| GET | /songs/:id/tags | - | 曲のタグ一覧 |
| POST | /songs/:id/tags | Bearer | 曲にタグ付与 |
| DELETE | /songs/:id/tags/:tid | Bearer | 曲のタグ削除 |
| GET | /songs/:id/similar | - | 類似曲 (タグ共起ベース) |

### 管理 (admin)

| Method | Path | 認証 | 概要 |
|--------|------|------|------|
| POST | /admin/cloudkit/save | admin Bearer | CloudKit へ直接保存 |
| POST | /admin/ban | admin Bearer | ユーザー BAN |
| POST | /admin/revert-user | admin Bearer | ユーザーの全編集を差し戻し |
| GET | /admin/users/:id/edits | admin Bearer | 特定ユーザーの編集一覧 |

admin エンドポイントは `Authorization: Bearer <セッション JWT>` ヘッダーが必要で、
`ADMIN_USER_IDS` に含まれるか `users.is_admin = 1` のユーザーのみアクセス可能。

---

## CloudKit スキーマ設定（手動）

### Soft Delete 用 `deletedAt` フィールドのインデックス設定

iOS クライアントは差分同期時に `deletedAt != nil` のレコードをローカルDBから物理削除する
soft delete パターンを使用しています。`deletedAt` フィールドが CloudKit Dashboard で
**Queryable / Sortable** に設定されていないと、差分クエリが機能しません。

#### 設定手順

1. [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/) を開く
2. コンテナ `iCloud.com.fugaif.ImasLiveDB` を選択
3. **Schema** → **Record Types** を開く
4. 以下の全レコードタイプに対して手順 5〜7 を繰り返す:
   - `Brand`, `Idol`, `CastMember`, `Event`, `ImasUnit`, `Show`, `Song`
   - `IdolCast`, `IdolBrand`, `UnitMember`, `SongArtist`, `ShowCast`
   - `SetlistItem`, `SetlistPerformer`
5. レコードタイプを選択し、フィールド一覧から `deletedAt` を選ぶ
   - まだ存在しない場合は **Add Field** → Type: `Date/Time` → Name: `deletedAt` で追加
6. **Indexes** タブで **Add Index** を押し以下を追加:
   - `QUERYABLE` (フィルタで使用)
   - `SORTABLE` (ソートで使用、差分クエリの最適化)
7. **Save** をクリック

#### 確認方法

CloudKit Records Viewer で以下のクエリが実行できれば設定完了:

```
Record Type: Idol
Filter: deletedAt IS NOT NULL
```

#### Soft Delete の実行

`deletedAt` に現在時刻をセットして push する (`tools/seed_cloudkit.py` 等の CloudKit 書き込みパス経由)。
`modifiedAt` も同時に bump すること (iOS 差分同期が取りこぼさないため)。

> **注意**: 過去に CloudKit Dashboard や API で **forceDelete** した（レコード自体を消した）
> エントリは soft delete できません。それらは iOS クライアントが `performFullSync` を実行する
> 際の orphan 削除（safety net）によってローカルDBから自動的に除去されます。
