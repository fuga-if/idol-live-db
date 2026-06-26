# ImasLiveDB — iOS アプリ開発ガイド

> アイドルライブデータベース iOS版

## 作業スタイル

- **ブランチ運用 (公開リポ)**: 作業は `feature/<topic>` で切る（`develop` 起点。修正 `fix/`、雑務 `chore/`）。`main`/`develop` で直接作業しない。`develop` に集約 → リリース時に `develop` → `main`。main/develop は保護 (PR + オーナー承認必須・オーナーは bypass 可)。詳細は [README の開発フロー](README.md)。
- **時間を気にしない**: 深夜帯でも「明日に持ち越し」等の提案はしない。タスクが残っていれば進める。区切り提案や作業中断の示唆も不要。
- **長時間の push / 再構築も躊躇しない**: 数十分 〜 数時間かかる処理でも、進める価値があれば走らせる。
- **iOS を変更したら必ず Android に横展開する（標準手順）**: UI/データ/同期/コミュニティ等あらゆる変更は、同じセッション内で `ImasLiveDB-Android/` にも 1:1 で反映する（`/sync-ios-to-android` スキル）。Android は iOS とファイル/コンポーネント構成を揃えてあるので、同じ場所に同じ差分を当てる。横展開できない（基盤が無い等）場合のみユーザーに確認。「Androidは後で」と勝手に後回しにしない。

## クイックスタート

```bash
xcodegen generate          # project.yml → .xcodeproj 生成
xcodebuild build -scheme ImasLiveDB -destination 'platform=iOS Simulator,name=iPhone 16'
```

## 技術スタック

- SwiftUI + iOS 17.0+
- GRDB.swift（SQLite ORM）
- Nuke + NukeUI（画像キャッシュ）
- MusicKit（ジャケ写・再生）
- xcodegen（プロジェクト生成）

## ディレクトリ構造

```
ImasLiveDB/
├── App/           # @main エントリ、TabView
├── Models/        # GRDB Record型（Brand, Idol, Song等）
├── Database/      # AppDatabase, Migrations
├── Views/
│   ├── Events/    # Tab1: ライブ・セトリ
│   ├── Songs/     # Tab2: 楽曲
│   ├── Idols/     # Tab3: アイドル・キャスト
│   ├── Stats/     # Tab4: 統計
│   ├── Search/    # グローバル検索
│   ├── Settings/  # 設定
│   └── Components/ # 共通UIコンポーネント
├── Services/      # MusicKit, Sync等
├── Extensions/    # Color+Hex等
└── Resources/     # Assets, master.sqlite
```

## コーディング規約

### Swift

- **iOS 17+ API前提**: @Observable, SwiftUI最新API使用
- **Swift 6 Concurrency**: Sendable準拠、@MainActor適切に使用
- **GRDB Record**: 全モデルはCodable + FetchableRecord + PersistableRecord
- **TEXT PK**: 全テーブルのPKはTEXT型（`ml_kasuga_mirai` 形式）

### アーキテクチャ

- **MVVM**: View + @Observable ViewModel
- **AppDatabase**: シングルトン、全クエリを集約
- **Environment**: AppDatabaseは.environment()で注入

### データベース / データソース

#### Single source of truth は「2系統」に分かれる (重要・実装の実態)

データは性質で保存先を分けている。混同するとデータフローを誤解するので注意:

| データ種別 | 唯一の正 | iOS の読み | iOS の書き |
|---|---|---|---|
| **マスタ** (Brand / Idol / Event / Show / Song / SetlistItem / ImasUnit 等) | **CloudKit Public DB** | CloudKit 差分sync (`CloudKitSyncEngine`) → ローカル GRDB | `/edits` → 検証/モデレーション → CloudKit へ反映 → 差分syncで全端末へ |
| **構造化コミュニティ** (コーレス `SongCall` / 参考動画 `SongVideo`) | **CloudKit Public DB** | 上と同じ差分sync | Worker 経由で CloudKit へ |
| **集計系コミュニティ** (タグ / お気に入り / ペンラ投票 / ポール / 予想 / いいね / ランキング) | **Worker の D1 (SQLite)** ← CloudKitではない | 都度 Worker fetch + `CommunityAPI` のメモリTTLキャッシュ | Worker → D1 (原子的カウンタ・レート制限・device重複排除) |

- **なぜ集計系だけ D1 か**: CloudKit は原子的インクリメント・サーバ集計(件数/ランキング)・レート制限・device重複排除が苦手。投票数やお気に入り数は D1(SQL・トランザクション・batch)が適材適所。**これを CloudKit に寄せようとしないこと** (改悪になる)。
- マスタを CloudKit に置く理由: アプリ更新せず新規ライブ追加・修正を即時配信でき、無料枠がユーザー数連動で自動増加する (ランニングコスト0)。
- ⚠️ **集計系コミュニティ読みは D1 の固定無料枠**(ユーザー数で増えない)に乗る唯一のホットパス。伸びたらここがコスト/性能のボトルネック。TTLキャッシュで緩和済み。

> **Worker D1 の master ミラー問題は解消済み (2026-06 対応完了):**
> - 旧Webアプリ (imas-live-app, https://imas-live-app.vercel.app) は **HTTP 503 でダウン**しており、D1 master ミラー (`songs`/`idols`/`events`/`shows` 等) は 2026-01 以降 CloudKit と同期されず化石化していた。
> - 対応: Web アプリ専用の master JSON API (`/brands` `/idols` `/songs` `/events` `/search` `/stats` `/sql` `/version` `/patch` + 各 `:id` 配下) を Worker から**撤去**。
> - 唯一 D1 master に生きて依存していた Universal Link フォールバック (`/app/events/:id` `/app/shows/:id`, `renderAppFallbackPage`) は **`cloudKitLookup` で CloudKit S2S 直読みに移行**。共有リンクのランディングが常に最新名を出す。AASA (`/.well-known/apple-app-site-association`) は維持。
> - 集計系コミュニティ endpoint (タグ/お気に入り/投票/ポール/ランキング) は元々 D1 master に JOIN せず自己完結なので影響なし。
> - 残骸: D1 の master テーブル実体 (`songs`/`idols`/… のレコード) は読む口が無くなったので残っていても無害 (物理 DROP は未実施・任意)。
> - iOS 側 `PatchService` (/patch /version) も撤去済み (CloudKit syncに置換されデッドだった)。

#### Bundle 同梱 master.sqlite はオフライン用初期スナップショット

- 初回起動時にDocumentsへコピー、CloudKit同期不可時の fallback として機能
- アプリリリース時の **CloudKit のスナップショット**を Bundle に含める運用
- master.sqlite を直接編集してリリースする運用は **しない** (CloudKit との乖離を生む)
- Bundle DB の更新フローは `tools/seed_cloudkit.py` で CloudKit → Bundle DB エクスポートが基本

#### スキーマ追加時の必須手順 (新カラム追加例)

新しいフィールドをマスタモデルに追加する場合は **以下を全部やる**:

1. **CloudKit Dashboard** (`icloud.developer.apple.com`) で対象 Record Type にフィールド定義 + Queryable index 設定
2. **CKRecordMapper** に読み取りコード追加 (CKRecord → Model)
3. **CloudKit Development に既存全レコードを再 push** (`tools/seed_cloudkit.py`)
4. **Dashboard で field を Indexable / Sortable に設定 + Save** ← 重要 (やらないと Pending Changes に乗らない)
5. **Deploy Schema Changes (Dev → Production)** 押下
6. **CloudKit Production に再 push** (`--production` フラグ付き)
7. **Bundle master.sqlite** にも反映 (CloudKit からエクスポート or 直接 ALTER)
8. **DatabaseMigrations** に v_n migration 追加 (既存ユーザーの Documents DB に ALTER + データ反映)
9. **AppDatabase.openDatabase** に必要なら起動時 reseed ロジック (CloudKit pull で上書きされる対策)
10. **seedMigrationHistoryIfNeeded** に新 v_n の判定追加 (Bundle DB が既に持っていれば skip)

> ⚠️ **CloudKit S2S で auto-create された field は Dashboard で「Add Index」しないと
> Production への Deploy Schema Changes に出てこない。** これを忘れると Production push が
> `Field xxx not found in {RecordType}` で全件 BAD_REQUEST になる。

#### 差分同期で取りこぼさないルール (絶対)

iOS の差分同期は CloudKit 上の **custom `modifiedAt` フィールド** を見ている (predicate:
`modifiedAt > lastSync`)。CloudKit システム標準の `___modTime` ではない。

**CloudKit に書き込む全パスで `modifiedAt: Date.now()` を必ず一緒に injectする。**
忘れるとそのレコードは更新されたのに iOS の差分同期で永遠に取りこぼされる。

| パス | チェックポイント |
|---|---|
| `tools/seed_cloudkit.py` | `build_fields()` が `modifiedAt` を強制注入 → 直接使えば OK |
| `tools/insert_future_events.py` / `tools/sync_song_apple_music.py` 等 (CloudKit へ書く各スクリプト) | 各 `forceUpdate` で `next_modified_ms()` を入れる |
| `imas-live-api/src/cloudkit.ts` `buildForceUpdate()` | 関数内で `Date.now()` を強制注入済 |
| **CloudKit Dashboard 手動編集** | ⚠️ システム `___modTime` だけ更新され custom `modifiedAt` は更新されない → Dashboard で直編集した後は seed_cloudkit.py で再 push して `modifiedAt` を bump する |

「CloudKit には書いたのに iOS で見えない」「全データ同期では出るが差分同期では出ない」
症状が出たら、まず疑うのは `modifiedAt` の bump 漏れ。

#### スキーマ管理は cktool 経由が正

Dashboard の手作業 (Add Index → Save → Deploy) は罠が多いので、`tools/cloudkit_schema.ckdb` を
唯一の正としてコード管理する。Apple 公式 `cktool` (Xcode 同梱) でフロー自動化:

```bash
# 認証 (一度だけ。Management Token は CloudKit Dashboard 右上 → Manage Tokens)
xcrun cktool save-token <MGMT_TOKEN> --type management

# 現状取得 → 編集 → Dev に import → 動作確認 → Production deploy
xcrun cktool export-schema --team-id GQ3WP34LFW --container-id iCloud.com.fugaif.ImasLiveDB \
    --environment DEVELOPMENT > tools/cloudkit_schema.ckdb
# ファイル編集 (フィールド追加など)
xcrun cktool validate-schema --environment DEVELOPMENT --file tools/cloudkit_schema.ckdb \
    --team-id GQ3WP34LFW --container-id iCloud.com.fugaif.ImasLiveDB
xcrun cktool import-schema   --environment DEVELOPMENT --file tools/cloudkit_schema.ckdb \
    --team-id GQ3WP34LFW --container-id iCloud.com.fugaif.ImasLiveDB --validate
# Production deploy は cktool では unsupported (BadRequestException) なので
# Dashboard で Environment=Development → 左サイドバー Deploy Schema Changes... → Deploy のクリック1回が必要
```

`CKRecordMapper` だけ修正して CloudKit にフィールドが無い、というケースは
**毎同期で新カラムが default 値に上書きされる**ため避けること。

#### その他のDBルール

- WALモード有効
- 外部キー制約ON
- パッチはupsert（INSERT OR REPLACE）で冪等に適用
- TEXT PK（`ml_kasuga_mirai` 形式）

#### マイグレーション規律 (iOS / Android 共通・絶対)

> iOS と Android は**別々のローカル DB** (GRDB / Room) を各端末に持ち、共有しているのは
> CloudKit / Worker D1 (クラウド側の正) だけ。詳細思想は `docs/ARCHITECTURE.md`「データの所在・同期・マイグレーション」。

- **破壊的マイグレーションは使わない** (Android `fallbackToDestructiveMigration` / iOS で DB 削除)。
  マスタは CloudKit から再同期で戻るが、**`UserMark` (担当/お気に入り) 等のクラウドに無いローカル唯一データが無言で消える**。
- スキーマを変えたら **iOS (GRDB `DatabaseMigrations`) と Android (Room `Migration`) の両方に移行を 1 本ずつ対で書く**。
  これも「iOS↔Android 1:1 横展開」の一部 (`/sync-ios-to-android`)。
- マスタテーブルは migration 内で drop+recreate して CloudKit 再同期に委ねてよいが、ローカル唯一データは必ず保全する。

### 版権

- キャラ絵・歌詞・公式ロゴは一切使用しない
- ジャケ写はMusicKit API経由のみ
- アプリ名に「アイマス」「アイドルマスター」は入れない

## 人格プロンプト

あなたは「プロデューサー」です。アイマスのプロデューサーとして、765プロ・シンデレラ・ミリオン・SideM・シャニマス・学マス・ヴイアラ、全ブランドのアイドルたちのライブデータを最高のUXで届けるアプリを作っています。丁寧で誠実、ファンの気持ちがわかる開発者として振る舞ってください。

## データソース

- 既存Webアプリ: https://github.com/fuga-if/imas-live-app
- ソースデータ: src/data/idols.json, songs.json, setlist.json
- 変換スクリプト: tools/convert_data.py
