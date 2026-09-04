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

## テスト

```bash
npm test          # 1 回実行
npm run test:watch
npm run typecheck # src と test の両方
```

[@cloudflare/vitest-pool-workers](https://github.com/cloudflare/workers-sdk/tree/main/packages/vitest-pool-workers)
で **Workers ランタイム上**で実行する。`Request` / `Response` / `crypto` が本番と同じ実装になるので、
Node の polyfill と挙動が割れる事故 (署名検証・ヘッダの大小文字・`Response.json` 等) を踏まない。

`vitest.config.ts` は `wrangler.jsonc` をそのまま読む。`nodejs_compat` は pool の要件なので
テスト実行時だけ `miniflare.compatibilityFlags` で足しており、本番 Worker のフラグは変えていない。

D1 を叩くハンドラは、いまのところ `prepare().bind().first()` だけのスタブを渡してテストしている
(`test/edit_requests.test.ts` の `stubDb`)。実 D1 が要るテストを書くときは
`poolOptions.workers.miniflare.d1Databases` と `migrations/` の適用を足す。

## Cron 確認

```bash
npx wrangler tail
```

Cron (scheduled) は掃除だけ:

- `rate_limits` の日次掃除 (7 日より古いレコード削除)
- `call_edit_history` の掃除 (180 日より古い行を削除。`GET /calls/dashboard` が読むのは
  常に直近 30 件なので、古い行は誰も見ない)
- `api_rate_limits` / `transfer_codes` の期限切れ掃除 (`index.ts` の `scheduled`)

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

### 引き継ぎコード (ユーザー生成ローカルデータの端末間転送)

| Method | Path | 認証 | 概要 |
|--------|------|------|------|
| POST | /transfer | Bearer | 引き継ぎコードを発行 (24時間有効) |
| GET | /transfer/:code | Bearer | コードでペイロード取得 (取得と同時に消費・再取得不可) |

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
| POST | /tags/:id/report | X-Device-Id | タグ通報 (3 件で under_review) |
| DELETE | /tags/:id | admin Bearer | タグ削除 (soft delete: status='removed') |
| GET | /songs/:id/tags | - | 曲のタグ一覧 |
| POST | /songs/:id/tags | Bearer | 曲にタグ付与 |
| DELETE | /songs/:id/tags/:tid | Bearer | 曲のタグ削除 |
| GET | /songs/:id/similar | - | 類似曲 (タグ共起ベース) |
| GET | /idols/:id/similar | - | 似てるアイドル (タグ共起ベース) |
| POST | /unit-tags | X-Device-Id | ユニットタグ作成 |
| GET | /unit-tags | - | ユニットタグ一覧 (検索/カテゴリ/ソート) |
| GET | /unit-tags/:id | - | ユニットタグ詳細 |
| PUT | /unit-tags/:id | Bearer | ユニットタグ編集 |
| GET | /unit-tags/:id/history | - | ユニットタグ編集履歴 |
| POST | /unit-tags/:id/report | X-Device-Id | ユニットタグ通報 |
| DELETE | /unit-tags/:id | admin Bearer | ユニットタグ削除 (soft delete) |
| GET | /units/:id/tags | - | ユニットのタグ一覧 |
| POST | /units/:id/tags | X-Device-Id | ユニットにタグ付与 |
| DELETE | /units/:id/tags/:tid | X-Device-Id | ユニットのタグ削除 |
| GET | /units/:id/similar | - | 似てるユニット (タグ共起ベース) |

### 歌詞 / コールガイド

| Method | Path | 認証 | 概要 |
|--------|------|------|------|
| GET | /songs/:id/lyrics | Bearer | 歌詞 1 曲 (コール込み)。`no-store` |
| GET | /lyrics/search | Bearer | 歌詞本文の横断検索 (返すのは song_id とスニペットのみ) |
| PUT | /songs/:id/calls | Bearer | コールガイドの保存 (曲単位の全置換)。`no-store` |
| GET | /calls/dashboard | - | コールガイドの整備状況 (件数・日時・表示名のみ)。`public, max-age=1800` |
| POST | /admin/lyrics/status | 運用者/admin | 歌詞の公開状態の一括切替 |
| GET | /admin/lyrics/quota | 運用者/admin | 掲載曲数 (JASRAC 年次報告用) |
| PUT | /admin/lyrics/:id | 運用者/admin | 歌詞の投入・差し替え |

⚠️ **歌詞本文とコール本文が出るのは Bearer 必須・`no-store` の経路だけ。**
JASRAC 許諾の条件が「一括ダウンロードできない形式での配信」なので、認証を外すと
`index.ts` の `edgeCacheEligible` が真になり、エッジ共有キャッシュに歌詞が載る。

`GET /calls/dashboard` はその例外ではなく、**歌詞の断片を 1 文字も含まない**ので
公開キャッシュに置ける。返すのは以下だけ (`src/routes/calls.ts`):

- `songsWithCalls[]` … `songId` / `callLines` / `callCount` / `updatedAt` / `updatedBy` (最大 200 件)
- `recentEdits[]` … `id` / `songId` / `at` / `by` / `callLines{Before,After}` / `callCount{Before,After}` / `summary` (最大 30 件)
- `taggedWithoutCalls[]` … 「コール曲」タグ付きで歌詞があるのにコールが無い song_id (票数降順・最大 100 件)
- `callTag` … `tagId` / `tagName` / `tagged` / `withCalls` / `withoutLyrics` (タグが無ければ `null`)

曲名は返さない (D1 に曲マスタは無く、端末の master.sqlite が song_id から解決する)。
生の uid も返さない (表示名は `feed.ts` の `maskDisplayName` を通す)。
クエリパラメータは受け付けない — キャッシュキーを 1 つに保つため。

件数は `song_call_stats` / `call_edit_history` (migrations/0032) に畳んであり、
一覧で `lines_json` を舐めない。読み取り行数の実測は本番適用後に:

```bash
# 0) 事前確認: calls が配列でない行が無いか (0 でないと backfill の件数がその行だけ 0 になる)。
#    2 引数の json_array_length は非配列で NULL を返すので migration は落ちないが、
#    「壊れた行がある」こと自体は先に知っておく。
npx wrangler d1 execute imas-live-db --remote --command \
  "SELECT COUNT(*) AS broken FROM song_lyrics sl, json_each(sl.lines_json) je
    WHERE json_valid(sl.lines_json)
      AND json_extract(je.value, '\$.calls') IS NOT NULL
      AND json_type(je.value, '\$.calls') NOT IN ('array', 'null');"

# 反映順は migration → 検証 SELECT → deploy (逆にすると PUT が 500 になる)
npx wrangler d1 migrations apply imas-live-db --remote
npx wrangler d1 execute imas-live-db --remote --command \
  "SELECT COUNT(*) AS songs, SUM(call_count) AS calls, SUM(call_lines) AS lines FROM song_call_stats;"
# → songs = 3 (2026-09 時点でコールが入っている曲数)。0 なら backfill の WHERE が効いていない
npx wrangler deploy
# キャッシュミス 1 回あたりの読み取り行数 (meta.rows_read) を実測する
npx wrangler d1 execute imas-live-db --remote --json --command \
  "SELECT st.song_id FROM song_tags st WHERE st.tag_id = (SELECT id FROM tags WHERE name = 'コール曲');"
```

`song_call_stats` は派生データなので、ズレたら作り直せる。migration の backfill は
素の `INSERT` (適用は 1 回きり) なので、**再実行するときは下の冪等版**を使う
(`INSERT OR REPLACE` なので何度流しても同じ結果になる。件数と `updated_at` を
実体から作り直し、`updated_by_uid` は相関副問い合わせで既存値を持ち越すので
「最後にコールを書いた人」は消えない):

```sql
INSERT OR REPLACE INTO song_call_stats (song_id, call_lines, call_count, updated_at, updated_by_uid)
SELECT sl.song_id,
       (SELECT COUNT(*) FROM json_each(sl.lines_json) je
         WHERE COALESCE(json_array_length(je.value, '$.calls'), 0) > 0
            OR json_extract(je.value, '$.clap') IS NOT NULL),
       (SELECT COALESCE(SUM(COALESCE(json_array_length(je.value, '$.calls'), 0)), 0)
          FROM json_each(sl.lines_json) je),
       sl.updated_at,
       (SELECT cs.updated_by_uid FROM song_call_stats cs WHERE cs.song_id = sl.song_id)
  FROM song_lyrics sl
 WHERE json_valid(sl.lines_json)
   AND EXISTS (SELECT 1 FROM json_each(sl.lines_json) je
                WHERE COALESCE(json_array_length(je.value, '$.calls'), 0) > 0
                   OR json_extract(je.value, '$.clap') IS NOT NULL);
```

### 曲詳細バンドル

| Method | Path | 認証 | 概要 |
|--------|------|------|------|
| GET | /songs/:id/detail | 任意 (Bearer で歌詞同梱) | tags + similar + penlight を 1 リクエストで返す |

曲詳細を 1 回開くたびに 3 リクエスト (`/penlight/votes/:id` + `/songs/:id/tags` +
`/songs/:id/similar`) 飛んでいたのを 1 本に束ねたもの。Worker 無料枠 (10万リクエスト/日) で
捌ける同時利用者が 3 倍になる。既存 3 エンドポイントは段階移行のため残してある。

- 応答は `{ songId, tags, similar, penlight, lyrics }`。`tags` / `similar` / `penlight` は
  **既存エンドポイントの応答そのまま**を入れ子にしている (iOS が既存モデルでデコードできる契約)。
- `lyrics` は Bearer 付きのときだけ入る。未認証・歌詞未投入・`status != 'published'` はすべて `null`。
- 個々の取得が失敗しても全体は落とさず、失敗した部分だけ `null` にして 200 を返す。
- `similar_limit` (既定 50 / 最大 50) で類似曲の候補件数を指定できる。
- キャッシュ: 未認証かつ `X-Device-Id` なし → `public` (エッジ共有)。`X-Device-Id` あり →
  `private, no-store` (`my_tag_ids` / `my_vote` が他人に配られないよう、index.ts 側で
  共有キャッシュから読み書きとも除外)。Bearer あり → `no-store` (歌詞)。

### 管理 (admin)

| Method | Path | 認証 | 概要 |
|--------|------|------|------|
| POST | /admin/cloudkit/save | admin Bearer | CloudKit へ直接保存 |
| POST | /admin/ban | admin Bearer | ユーザー BAN |
| POST | /admin/revert-user | admin Bearer | ユーザーの全編集を差し戻し |
| GET | /admin/users/:id/edits | admin Bearer | 特定ユーザーの編集一覧 |
| DELETE | /tags/:id | admin Bearer | 曲タグ削除 |
| DELETE | /idol-tags/:id | admin Bearer | アイドルタグ削除 |
| DELETE | /unit-tags/:id | admin Bearer | ユニットタグ削除 |

admin エンドポイントは `Authorization: Bearer <セッション JWT>` ヘッダーが必要で、
`ADMIN_USER_IDS` に含まれるか `users.is_admin = 1` のユーザーのみアクセス可能。

タグ削除は物理削除ではなく `status='removed'` の soft delete。読み取り経路 (一覧 /
詳細 / 付与 / 曲・アイドル・ユニット別 / 類似) はすべて `status != 'removed'` を見るので
これだけで全経路から消える。付与実績は残るため、誤操作なら `status` を戻せば復旧できる。
通報 3 件で付く `under_review` は「印」であって非表示にはしない (削除は人が判断する)。

⚠️ 一覧は `max-age=60`、詳細は `max-age=300` のエッジキャッシュに載るので、削除が
全ユーザーに行き渡るまで最大 5 分かかる。

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
