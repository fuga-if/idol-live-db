# refactor-instructions.md

> **状態 (2026-07-26): Phase 0〜5 に加え、Phase 6 の提案のうち検証可能なものも実施済み。**
> 実施内容は git log の `refactor(db)` / `refactor(worker)` / `ci` / `fix(worker)` / `docs` コミット群を参照。
>
> 追加で実施したもの:
> - 不正 JSON の 400 統一を**全ルート (19 箇所)** へ展開
> - Worker の共有基盤を `env.ts` / `auth.ts` / `users.ts` / `validation.ts` へ分離
> - `/polls/*` を `routes/polls.ts` へ切り出し (index.ts: 4,271 → 3,073 行)
> - iOS / Android のビルド・テストを CI 化
>
> 残っているのは **index.ts の残りルート分割**と、Out-of-scope に置いた項目
> (`Views/`→`Presentation/` 移動、Repository へのクエリ移動、`.shared` のポート化、
> Android ネットワーク層書き換え、依存追加)。切り出し手順は
> `docs/ARCHITECTURE-worker.md` に明文化済み。
>
> 以下は当時の調査結果と手順の記録として残す (数値は着手時点のもの)。

> 実装担当モデルへ: このファイルに書かれたことを、書かれた順番で完遂しろ。
> **調査は済んでいる。数値・行番号はすべて実測値** (2026-07-25 時点, branch `develop`)。
> 数値が現実と食い違ったら、それは前提が変わったということ。**推測で埋めず、止まって報告しろ。**

---

## Objective

**既存の挙動を 1 つも変えずに、変更しやすさを上げる。**

具体的には次の 4 つだけを取りに行く。それ以外はやらない。

1. **安全網を先に作る** — 現在 CI で守られているのは Domain 層の import 純粋性だけ。Worker は型チェックすら通っていない。
2. **実測で死んでいるコードを消す** — `AppDatabase.swift` に未参照の同期メソッドが 55 個ある。
3. **2 つの巨大ファイルの責務を分ける** — `AppDatabase.swift` (3,770 行) と `imas-live-api/src/index.ts` (4,271 行)。ただし**切り出しは「移動」であって「書き直し」ではない**。
4. **ボイラープレートの重複を潰す** — Worker のデバイス ID / レート制限 / JSON パースの定型が 20 回前後コピーされている。

**美しさは目的ではない。** 「古いから直す」もしない。上の 4 つに当たらない変更は out-of-scope。

---

## Project Understanding

### これは何か

**ImasLiveDB** — アイドルライブのセットリストを記録・検索する**非公式ファンメイド**アプリ。
iOS / Android ネイティブアプリ + Cloudflare Worker バックエンドのモノレポ。

| コンポーネント | ディレクトリ | スタック | 規模 (実測) |
|---|---|---|---|
| iOS アプリ | `ImasLiveDB/` | SwiftUI (iOS 17+) / GRDB / Nuke / MusicKit / xcodegen / Swift 6 strict concurrency | 287 ファイル・約 57,300 行 |
| iOS Widget | `ImasLiveDBWidget/` | WidgetKit (App Group 共有) | 小 |
| iOS テスト | `ImasLiveDBTests/` | XCTest | 14 ファイル・89 テスト関数 |
| Android アプリ | `ImasLiveDB-Android/` | Jetpack Compose / Room / Coil / 手動 DI | 177 ファイル・約 29,700 行・**テスト 1 ファイル** |
| バックエンド | `imas-live-api/` | Cloudflare Workers (TS) / D1 / CloudKit S2S | 16 ファイル・7,908 行 (うち `index.ts` が 4,271 行) |
| データ整備 | `tools/` | Python / Bash (git 追跡 19 ファイル) | — |
| 貢献データ | `data/` | 出典付き JSON (`events` / `fixes` / `idols` / `setlists` / `songs` / `units` / `venues`) | — |

ライセンスは **PolyForm Noncommercial 1.0.0** (商用不可・source-available)。
非公式ゆえの絶対制約が `CONTRIBUTING.md` §2 にある (キャラ画像・歌詞・公式ロゴを一切持たない)。

### 主要なユーザー体験

ライブ/公演/セットリスト/楽曲/アイドル/ユニットの閲覧 → 検索・フィルタ → 「担当」「お気に入り」「参加した」マーク →
コミュニティ機能 (タグ / みんなの投票(ポール) / 出演者予想 / セトリいいね / ペンライト色 / お気に入りランキング) →
オープン編集 (アプリからマスタを直して CloudKit へ反映) → ゲーム (イントロドン / カラーマッチ / クイズ) →
カレンダー・スケジュール・統計・共有カード生成・担当ウィジェット。

### データソースは 2 系統 (最重要・混同するとデータフローを誤解する)

| データ種別 | 唯一の正 |
|---|---|
| **マスタ** (Brand / Idol / Event / Show / Song / Setlist / Unit / Venue) | **CloudKit Public DB** → 差分 sync でローカル DB へ |
| **構造化コミュニティ** (コーレス / 参考動画) | **CloudKit Public DB** |
| **集計系コミュニティ** (タグ / お気に入り / 投票 / ポール / 予想 / いいね / ランキング) | **Worker の D1 (SQLite)** |

- iOS と Android は**同じ DB を見ていない**。各プラットフォームが自分専用のローカル DB (iOS=GRDB / Android=Room) を持ち、共有しているのは**クラウド側の唯一の正だけ**。
- `db/master.sql` は CloudKit の日次スナップショット (テキスト dump・git 管理)。binary `master.sqlite` は gitignore で各自生成。
- **`UserMark` (担当 / お気に入り / メモ / 参加済み) はクラウドに存在しない端末ローカル唯一データ。** マスタと同じ DB に同居しているが、消したら復旧手段が無い。

### 主要エントリーポイント

| コンポーネント | エントリ |
|---|---|
| iOS | `ImasLiveDB/App/ImasLiveDBApp.swift` → `ContentView.swift`。合成ルートは `App/AppContainer.swift` (65 行) |
| iOS DB | `ImasLiveDB/Database/AppDatabase.swift:9` (`AppDatabase.shared`) / `DatabaseMigrations.swift` (v1〜v27 の 26 本) |
| iOS 同期 | `ImasLiveDB/Services/CloudKitSyncEngine.swift` (18 レコード種を差分同期) |
| Worker | `imas-live-api/src/index.ts:794` の `export default { fetch, scheduled }` |
| Worker Cron | `src/apply.ts` (`wrangler.jsonc` の `crons: ["*/5 * * * *"]`) |
| Android | `ImasLiveDB-Android/app/src/main/kotlin/com/fugaif/imaslivedb/` — `ui/navigation/AppNavigation.kt` / `di/AppModule` |

### 主要モジュールと責務 (iOS)

docs/ARCHITECTURE.md が採用する **Hexagonal (Ports & Adapters)** への**段階移行中**。
文書自身が「これは目標形であって完成形ではない」と明記している (ARCHITECTURE.md:16-25)。現状の実測:

| 場所 | 責務 | 実測 |
|---|---|---|
| `Domain/Ports/` | driven port (protocol) | 16 ファイル |
| `Domain/UseCases/` | 非自明なビジネスルールのみ | 4 ファイル (EventGrouping + 3 リストフィルタ) |
| `Adapters/Persistence/` | `GRDB*Repository` = 各 `XxxReading` の実装 | 13 ファイル。**中身は `AppDatabase` への 1:1 パススルー (意図された中間状態)** |
| `Database/AppDatabase.swift` | 実際のクエリ本体 + 起動時 DB セットアップ + reseed | **3,770 行 / 173 関数の神オブジェクト** |
| `Services/` | CloudKit 同期・API クライアント・認証・MusicKit・通知ほか | 44 ファイル |
| `Views/` | SwiftUI (機能単位で 21 サブディレクトリ) | 一部だけ ViewModel 化済み |
| `DesignSystem/` | ImasTheme (無限色エンジン) + ImasComponents | 据え置き対象 |

### データの流れ

```
CloudKit Public DB (マスタの唯一の正)
   │  ├── iOS: CloudKitSyncEngine → GRDB (Documents/master.sqlite)
   │  └── Android: CloudKitSyncEngine → Room
   │  ↑ Worker /edits (ユーザー編集を検証 → S2S 書き込み)
   │  ↑ tools/apply_data.py --apply --push (オーナーが data/*.json を反映)
   ↓ 日次 cron (.github/workflows/refresh-data.yml)
db/master.sql (git・diff 可) → tools/build_db.sh → 同梱 master.sqlite

Worker D1 (集計系コミュニティの唯一の正)
   ↑↓ iOS: CommunityAPI / APIClient    ↑↓ Android: data/community/CommunityApi
```

### 外部依存

- **CloudKit Public DB** (`iCloud.com.fugaif.ImasLiveDB`) — マスタ。Worker は S2S、iOS は CloudKit framework、Android は S2S read-only トークン。
- **Cloudflare D1** — 集計系。無料枠固定 (ユーザー数で増えない) = 唯一のコスト律速。
- **Apple Sign In / Google Sign In** — Worker が JWT を検証し、自前セッション JWT (HS256) を発行。
- **App Attest (iOS) / Play Integrity (Android)** — クローンただ乗り対策。`APP_ATTEST_MODE` で monitor/enforce 切替。
- **MusicKit / iTunes Search API** — ジャケット画像とプレビュー再生 (画像は同梱しない)。
- **Firebase Analytics** (iOS のみ配線済み。Android は未配線)。
- **App Store Connect API / fastlane** — メタデータ配信 (`.github/workflows/deliver.yml`)。

---

## Behaviors To Preserve

**以下はテストが無くても壊してはいけない。「動くはず」で進めるな。**

### P1. 起動時のマスタ再投入 (最高危険度)

`AppDatabase.copyMasterTables` (`Database/AppDatabase.swift:215-260`) と
`reseedMasterTablesIfNeeded` / `seedMigrationHistoryIfNeeded` (:277-364)。

- **2 段方式 (全テーブル DELETE → 全テーブル INSERT) は絶対に 1 段にまとめるな。** `ON DELETE CASCADE` は `defer_foreign_keys` の対象外で、子を INSERT した後に親を DELETE すると CASCADE で消える (コメント :235-239 に理由が書いてある)。
- **`preservedTables` (`user_marks` ほか) は絶対に触らない。** クラウドに無いユーザーデータで復旧不能。
- **FK 違反時は COMMIT で throw してロールバックする** — この挙動が「壊れたスナップショットを黙って適用しない」ゲート。`MasterReseedTests.swift` が守っている。
- 過去に**この領域の不備で App Store 審査 reject (起動クラッシュ) が起きている** (`seedMigrationHistoryIfNeeded` の v19 コメント :340-347)。

### P2. CloudKit 差分同期の `modifiedAt` 契約

差分同期はシステムの `___modTime` ではなく**カスタム `modifiedAt` フィールド**を見る (`CloudKitSyncEngine.swift`、`imas-live-api/src/cloudkit.ts`)。
**CloudKit に書く全パスで `modifiedAt = now` を一緒に入れる。** 抜けると更新が永遠に取りこぼされ、しかも無症状で気づけない。

同期境界の非自明な実装 (`CloudKitSyncEngine.swift:284-347`):
- チェックポイント再開 (`sync_ckpt_<recordType>`)、cursor 継続、同一 `modifiedAt` 境界の取りこぼし防止に **-1ms して再クエリ + `seen` で dedup**、`deleteOrphans`。
**この再開/重複排除ロジックを「整理」するな。**

### P3. Worker の公開 API 契約

`imas-live-api/README.md` と `docs/ARCHITECTURE-worker.md` に列挙されたエンドポイント群。
**iOS 実機・Android 実機・審査済みリリース版が本番の同一 Worker を叩いている。**
パス・メソッド・レスポンス JSON のキー名・ステータスコードを変えると**既存インストール済みアプリが壊れる**。

特に:
- `/auth/login` `/auth/refresh` `/auth/me` — セッション JWT (1 年有効)。
- `Cache-Control: public` を返す GET だけがエッジキャッシュ対象 (`index.ts:827-838`)。**ユーザー依存レスポンスに `Cache-Control: public` を付けると個人データが全ユーザーに漏れる。**
- `Authorization` ヘッダ付きリクエストは絶対にキャッシュしない。
- 認証は `Authorization` の JWT 発行者を覗いて Apple/自前セッションを振り分ける (`peekJwtIssuer` :530)。

### P4. マイグレーション規律

- **破壊的マイグレーション禁止** (Android `fallbackToDestructiveMigration` / iOS で DB 削除)。`UserMark` が無言で消える。
- **スキーマを変えたら iOS (GRDB) と Android (Room) の両方に移行を 1 本ずつ書く。**
- D1 の migration は `imas-live-api/migrations/` の連番 (現在 0024)。**適用済み migration ファイルを編集するな。**

### P5. Domain 層の純粋性

`ImasLiveDB/Domain/**` は `SwiftUI` / `GRDB` / `CloudKit` を import しない。
`tools/check_domain_purity.sh` が CI (`architecture-guard.yml`) で強制。**現在パスしている。**

### P6. 非公式プロジェクトとしての制約

キャラクター画像・歌詞・公式ロゴを一切持たない。ジャケットは MusicKit API 経由のみ。
**画像ファイルやテキストリソースを追加する変更はこの制約に触れる。**

### P7. ランニングコスト 0

インフラ従量課金をゼロに保つのが絶対制約。
D1 (固定無料枠) が唯一のホットパスで、TTL キャッシュ + エッジキャッシュで緩和している。
**キャッシュを外す / D1 クエリ数を増やす変更はこの制約に反する。**

---

## Non-Negotiables

1. **最初に `git status` を確認する。** 作業開始時点で 3 系統の未コミット変更が同時進行している (下記「作業中の変更」)。**自分の変更と混ぜるな。**
2. **編集前に Baseline Commands を実行し、結果を記録する。** 「元から失敗していた」を後から言い訳にできないようにする。
3. **1 コミット = 1 論理的変更。** `git revert` で単独で戻せる粒度。
4. **`git add <file>...` で個別指定する。** `git add -A` / `git add .` は使わない (並行作業中のファイルを巻き込む)。
5. **無関係な整形・ついでのリファクタをしない。** 空白調整・import 並べ替え・命名変更を「ついでに」やらない。
6. **既存挙動を勝手に変えない。** レスポンス JSON のキー、SQL の結果集合、UI の見た目、ログ文言、いずれも。
7. **各フェーズごとに検証する。** フェーズをまたいでまとめて検証しない。
8. **ブランチを切る。** `develop` 起点で `refactor/<topic>`。`main` / `develop` で直接作業しない。
9. **iOS を変えたら同セッションで Android に 1:1 横展開する** (`CONTRIBUTING.md` §3)。**ただしこのリファクタでは iOS/Android の挙動を変えないので、原則として横展開対象は発生しない。** 発生したら、それは挙動を変えた合図 — 止まって報告しろ。
10. **秘密を絶対にコミットしない。** リポジトリルートに `.env` / `*.p12` / `*.cer` / `*.mobileprovision` / `tools/eckey.pem` が実在する (すべて gitignore 済み)。`git add` の対象に含めるな。

---

## Stop And Ask Conditions

**以下に当たったら、実装せずに止めて質問しろ。** 「たぶんこうだろう」で進めるな。

- 消そうとしているコードが本当に不要か、grep 以外の根拠が必要になった (Preview / `#if DEBUG` / 文字列経由の参照など)。
- Worker のレスポンス JSON のキー名・ステータスコード・パスを変える必要が出た。
- D1 / GRDB / Room の**スキーマ**、または保存済みデータのマイグレーションに触れる必要が出た。
- 認証 (Apple/Google JWT・セッション JWT・App Attest/Play Integrity)、レート制限、CORS、エッジキャッシュの**判定条件**を変える必要が出た。
- 通知 (`NotificationService`) / 外部連携 (MusicKit・CloudKit・App Store Connect) の呼び出し条件を変える必要が出た。
- テストと実装が矛盾している (テストが通らない = 実装が正しいのか、テストが正しいのか判断できない)。
- 設計案が複数あり、どちらもコードから正解を決められない。
- 新しい依存パッケージを追加したくなった。
- Baseline Commands のいずれかが**このリファクタと無関係な理由で**失敗した。
- ファイルを跨いで 500 行以上動かす必要が出た。

質問は**まとめて 1 回**にしろ。1 問ずつ止まるな。質問待ちの間は、答えに依存しない作業を進めておけ。

---

## Baseline Commands

**Phase 0 で全部実行し、出力を記録する。** 現時点での既知の結果も併記してある — 一致しなければ前提が変わっている。

### 必ず実行する (速い)

```bash
# 1. Domain 純粋性 (CI と同じ)  — 既知: PASS
bash tools/check_domain_purity.sh

# 2. Worker 型チェック — 既知: FAIL (1 件)
#    src/index.ts(430,53): error TS2304: Cannot find name 'KeyUsage'.
cd imas-live-api && npx tsc --noEmit; cd ..

# 3. Worker デプロイ dry-run (実際にはデプロイしない)
cd imas-live-api && npx wrangler deploy --dry-run; cd ..

# 4. 未コミット変更の把握
git status --porcelain
git stash list
```

### iOS (時間がかかる。Phase 0 と各フェーズ末で実行)

```bash
xcodegen generate
xcodebuild build -scheme ImasLiveDB \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' | tail -30
xcodebuild test -scheme ImasLiveDB \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' | tail -40
```

- 既知: テストは 14 ファイル・89 テスト関数。**Phase 0 で通過数を必ず記録しろ** (後のフェーズはこの数以上でなければならない)。
- シミュレータ名が無ければ `xcrun simctl list devices available` で実在するものに読み替える。

### Android

```bash
cd ImasLiveDB-Android
# ⚠️ 既定 JDK が 25 で、Gradle 8.11.1 は JDK 25 を未サポート。必ず 21 を指定する。
JAVA_HOME=$(/usr/libexec/java_home -v 21) ./gradlew assembleDebug
JAVA_HOME=$(/usr/libexec/java_home -v 21) ./gradlew test
cd ..
```

- 既知: ユニットテストは `IdolSortOrderTest.kt` の 1 ファイルのみ。
- `db/master.sql` から seed DB を生成する `generateSeedDb` タスクが preBuild に紐付いている (`sqlite3` が必要)。

### CI (参考: 現在動いているのはこれだけ)

| ワークフロー | トリガ | 内容 |
|---|---|---|
| `architecture-guard.yml` | push(main/develop) / PR、`ImasLiveDB/Domain/**` 変更時 | `tools/check_domain_purity.sh` |
| `refresh-data.yml` | 日次 cron 03:00 JST | CloudKit → `db/master.sql`、FK 整合性ゲート、`bot/data-refresh` へ push |
| `deliver.yml` | push(main)、`fastlane/metadata/**` | App Store メタデータ配信 |

**iOS のビルド/テストも Worker の型チェックも CI に無い。** これが最大の構造的な穴。

### 作業中の変更 (混ぜるな)

作業開始時点で以下が未コミット。**別トピックの進行中作業なので、触るな・stash するな・コミットに巻き込むな。**

```
 M ImasLiveDB-Android/.../data/db/AppDatabase.kt          ┐
 M ImasLiveDB-Android/.../data/db/dao/ShowDao.kt          │ Venue / 開催形態の
 M ImasLiveDB-Android/.../data/model/Show.kt              │ Android 横展開 (進行中)
 M ImasLiveDB-Android/.../data/repository/EventRepository.kt │
 M ImasLiveDB-Android/.../ui/events/*.kt                  │
?? ImasLiveDB-Android/.../data/model/Venue.kt             ┘
 M ImasLiveDB-Android/.../ui/polls/PollDetailScreen.kt    ┐ 共有カードの
?? ImasLiveDB-Android/.../ui/share/                       │ Android 横展開 (進行中)
?? ImasLiveDBTests/SocialShareTests.swift                 ┘
 M imas-live-api/src/index.ts (76 行の差分)               ← Worker 側の対応変更 (進行中)
?? ImasLiveDB-Android/.kotlin/                            ← ビルド生成物
```

⚠️ **`imas-live-api/src/index.ts` は未コミット変更を抱えている。** Phase 5 (Worker 分割) は
この変更がコミット/破棄されるまで着手するな。競合したら止まって報告しろ。

---

## Debt Map

各項目の **判定** 欄が `実装可` のものだけ手を付ける。`提案のみ` は**コードを書かず、Reporting Format の「提案」欄に書く**。

---

### D1. Worker の型チェックが通っていない 🔴 最優先

| | |
|---|---|
| **根拠** | `npx tsc --noEmit` → `src/index.ts(430,53): error TS2304: Cannot find name 'KeyUsage'.` 1 件で exit 2。`tsconfig.json` の `lib` が `["ES2022"]` のみで DOM/WebCrypto 型が入っていない |
| **なぜ負債か** | 型チェックが通らない = 型による安全網が実質ゼロ。7,908 行の TS が `strict: true` を掲げながら検証されていない。CI に載せることもできない |
| **影響範囲** | `imas-live-api/` 全体。ランタイム挙動には影響しない (`wrangler` は esbuild で型を無視してバンドルする) |
| **変更リスク** | **低**。`KeyUsage` は Web Crypto の型で、`importHmacKey` の引数注釈にしか使われていない |
| **改善案** | (a) `@cloudflare/workers-types` が提供する型で解決するか確認 → (b) 駄目なら `KeyUsage` をローカル型エイリアス (`type KeyUsage = "sign" \| "verify" \| ...`) で定義。**`any` で潰すな。`lib` に `"DOM"` を足すな** (Worker に存在しない DOM API が型上見えてしまう) |
| **検証方法** | `npx tsc --noEmit` が exit 0。`npx wrangler deploy --dry-run` が成功 |
| **判定** | **実装可 (Phase 1)** |

---

### D2. 検証の安全網が CI に無い 🔴

| | |
|---|---|
| **根拠** | `.github/workflows/` は 3 本のみ。`architecture-guard.yml` は `ImasLiveDB/Domain/**` 変更時しか走らない。iOS のビルド/テスト、Worker の型チェック、Android のビルドは CI に一切無い |
| **なぜ負債か** | リファクタの安全性がローカル実行の記憶に依存する。89 個の iOS テストが CI で守られていない |
| **影響範囲** | 全コンポーネント |
| **変更リスク** | **低** (ワークフロー追加のみ)。ただし GitHub Actions の実行時間コストが発生する |
| **改善案** | `imas-live-api/package.json` に `"typecheck": "tsc --noEmit"` を追加し、`imas-live-api/**` 変更時に走る軽量ワークフローを 1 本追加する。**iOS の macOS runner ワークフローは追加しない** (実行時間コストが大きく、`project_zero_running_cost` 制約への判断が要る → 提案に留める) |
| **検証方法** | `npm run typecheck` がローカルで exit 0。ワークフロー YAML の構文を `actionlint` or GitHub 上で確認 |
| **判定** | **Worker typecheck ワークフローのみ実装可 (Phase 1)。iOS/Android CI は提案のみ** |

---

### D3. `AppDatabase.swift` に未参照の同期メソッドが 55 個 🟡

| | |
|---|---|
| **根拠** | `Database/AppDatabase.swift` は 3,770 行 / 173 関数。うち `foo()` と `fooAsync()` の対が **88 組**。そのうち **55 組の同期版は `AppDatabase.swift` の内部からも外部 (`ImasLiveDB` / `ImasLiveDBTests` / `ImasLiveDBWidget` の全 Swift ファイル) からも一度も呼ばれていない** |
| **なぜ負債か** | ・読む人が「同期版と非同期版のどちらを使うのか」を毎回判断させられる<br>・クエリを直す時に 2 箇所直す必要があると誤認する (実際は共通の `private static func fooQuery(_ db:)` に集約済みなので、消しても実装は 1 つも失われない)<br>・約 350 行の純粋な水増し |
| **影響範囲** | `AppDatabase.swift` のみ。呼び出し側は 1 箇所も変わらない |
| **変更リスク** | **低**。ただし grep は SwiftUI Preview / `#if DEBUG` ブロック内も走査済み。念のため**削除は 1 コミットにまとめず、5〜10 個ずつ複数コミットに分ける** |
| **改善案** | 55 個の同期版のみを削除する。`private static func fooQuery` (実装本体) と `fooAsync` は残す。**「同期版が残っている 33 組」には触るな** (実際に使われている) |
| **検証方法** | 削除ごとに `xcodebuild build` → 全削除後に `xcodebuild test` で 89 テスト全通過。`grep -rn "\.<消した名前>(" ImasLiveDB ImasLiveDBTests ImasLiveDBWidget --include='*.swift'` が 0 件 |
| **判定** | **実装可 (Phase 2)** |

対象 55 個 (実測。**実装前に自分でも再確認しろ**):

```
fetchAlbums fetchAllIdolsForPicker fetchAllPerformers fetchAllShows fetchAllSongsForPicker
fetchAllUnits fetchAttendedEventTypeSets fetchBrandSongCounts fetchCalendarEntries
fetchCallResponsesForSong fetchCastShowCountRanking fetchCdSeriesList fetchCollectedShows
fetchDatabaseStats fetchEditRecordShowId fetchEditRecordSongId fetchEditRecordTitle
fetchEventAttendance fetchEventIdsAtVenue fetchEventNames fetchEventReleases fetchEventStats
fetchEventsWithDate fetchIdol fetchIdolCastNames fetchIdolPerformedSongs fetchIdolShows
fetchIdolSongHistory fetchIdolSongs fetchIdolUnits fetchIdolsByVoiceActor fetchLatestShow
fetchOriginalArtistIds fetchOriginalSongIds fetchPerformedUnitIds fetchRelatedSongs
fetchSeries fetchSeriesGroups fetchSetlist fetchShowCastIdols fetchShowIdolIds fetchShows
fetchSongArtists fetchSongCollectedCounts fetchSongPerformanceHistory fetchSongPlayCountRanking
fetchSyncDiagnostics fetchUnit fetchUnitIdsWithSongs fetchUnitMembers fetchUnitSongs
fetchVenueDirectory fetchVenuesMatching fetchVideosForSong fetchYearlyShowCounts
```

再確認コマンド:

```bash
for n in fetchAlbums fetchAllShows ...; do
  c=$(grep -rn "\.${n}(" ImasLiveDB ImasLiveDBTests ImasLiveDBWidget --include='*.swift' | grep -c .)
  echo "$n $c"
done
```

---

### D4. `AppDatabase` が「起動時 DB セットアップ」と「全ドメインのクエリ」を兼ねている 🟡

| | |
|---|---|
| **根拠** | `AppDatabase.swift:56-364` が DB セットアップ (`openDatabase` / `verifyIntegrityOrDelete` / `reseedMasterTablesIfNeeded` / `copyMasterTables` / `reseedEventKindIfNeeded` / `seedMigrationHistoryIfNeeded`)、`:366-3770` が Event/Setlist/Song/Idol/Stats/Unit/Venue/… の全クエリ |
| **なぜ負債か** | 責務が 2 つ。起動フローを読みたい人が 3,400 行のクエリ群をスクロールする。逆にクエリを足す人が起動フローの地雷 (P1) の隣で作業する |
| **影響範囲** | 起動パス全体。**過去に App Store reject を起こした領域を含む (P1)** |
| **変更リスク** | **中**。ただし「同一 type の extension へファイル分割」なら**シンボルもアクセス制御も一切変わらない** (Swift の extension はファイルを跨げる。`private` は同一ファイル内スコープなので、`private static func` を使う側と同じファイルに置けば安全) |
| **改善案** | **純粋なファイル移動のみ**行う:<br>`Database/AppDatabase.swift` → セットアップ + `dbQueue` + reseed 状態のみ (約 360 行)<br>`Database/AppDatabase+EventQueries.swift` / `+SongQueries.swift` / `+IdolQueries.swift` / `+UnitQueries.swift` / `+StatsQueries.swift` / `+CalendarQueries.swift` / `+VenueQueries.swift` — 既存の `// MARK: -` 区切りをそのまま境界に使う<br>**関数のシグネチャ・本体・順序・コメントを 1 文字も変えるな。`private` → `internal` への昇格が必要になったら、それは分割線が間違っている合図** |
| **検証方法** | 分割ファイルごとにコミットし、都度 `xcodebuild build` + `xcodebuild test`。`git diff --stat` の削除行数と追加行数がほぼ一致すること (= 移動だけ)。`project.yml` はディレクトリ単位で拾うので変更不要 |
| **判定** | **実装可 (Phase 3)。ただし「セットアップ側 (`:1-364`) のコードには一切手を触れない」ことが条件** |

---

### D5. `imas-live-api/src/index.ts` が 4,271 行の単一ルーター 🟡

| | |
|---|---|
| **根拠** | `export default { fetch }` の中に **83 個の `request.method === "..."` 分岐**、**196 個の `env.DB.prepare(`**、**26 個の `getAuthUser(` 呼び出し**が直書きされている。`docs/ARCHITECTURE-worker.md:65` も「改善余地」として自己申告済み |
| **なぜ負債か** | ・1 エンドポイントを直すのに 4,271 行のファイルを開く<br>・if チェーンの線形マッチなので、後ろの方のルートは 80 回以上の文字列比較を通る<br>・認証・レート制限・バリデーション・SQL・レスポンス整形が 1 スコープに同居し、どのルートがどのガードを通っているか目視でしか確認できない |
| **影響範囲** | **本番の全 API。審査済みリリース版の iOS/Android が叩いている (P3)** |
| **変更リスク** | **高**。`json` / `error` / `rateLimitSimple` / `cors` などのレスポンダは `makeResponders(request, env)` のクロージャで、`url` / `path` / `requestId` / `ctx` もスコープ変数。**素朴に切り出すと引数の受け渡しを間違えて静かに壊れる** |
| **改善案** | **一気にやらない。** 最も独立した 1 グループだけを試験的に切り出す:<br>`/favorites/*` + `/penlight/*` (device 集計のみ・auth 不要・他ルートと状態を共有しない、`index.ts:2591-2843`) を `src/routes/device_aggregates.ts` へ移す。<br>シグネチャは `export async function handleDeviceAggregates(ctx: RouteContext): Promise<Response \| null>` とし、`RouteContext` に `{ request, env, url, path, requestId, json, error, rateLimitSimple }` を詰める。`null` を返したら未マッチで元の if チェーンに戻る。<br>**成功して初めて次のグループを検討する (そのときは改めて承認を取れ)** |
| **検証方法** | ・`npx tsc --noEmit` exit 0<br>・`npx wrangler deploy --dry-run` 成功<br>・`npx wrangler dev` を起動し、移したルート全部に `curl` を打って**移動前後でステータスコードとレスポンス JSON が完全一致**することを確認 (移動前の出力を先に保存しておく)<br>・`Cache-Control` ヘッダが移動前と一致すること (エッジキャッシュの挙動に直結。P3) |
| **判定** | **`/favorites/*` + `/penlight/*` の 1 グループのみ実装可 (Phase 5)。それ以外のルート分割は提案のみ** |

---

### D6. Worker のボイラープレート重複 🟡

| | |
|---|---|
| **根拠** | `index.ts` 内で `request.headers.get("X-Device-Id")` + 未指定エラーの定型が **22 回**、`dryCheckIpRateLimit` / `commitIpRateLimit` の対が **17 回**、`CF-Connecting-IP` 取得が **20 回** コピーされている |
| **なぜ負債か** | ガードを 1 箇所足し忘れると、そのルートだけ無防備になる。実際「どのルートが IP レート制限を通っているか」は目視でしか分からない |
| **影響範囲** | 書き込み系エンドポイント全般 |
| **変更リスク** | **中**。ヘルパ化そのものは安全だが、**適用漏れ/適用過多があると防御が変わる** |
| **改善案** | `requireDeviceId(request): string \| null` と `withIpRateLimit(...)` のヘルパを `index.ts` 内に定義し、**D5 で切り出す `/favorites/*` + `/penlight/*` の範囲だけ**に適用する。残り 20 箇所は触らない (適用範囲を広げると差分が読めなくなる) |
| **検証方法** | D5 と同じ curl 比較。特にレート制限に引っかかるまで叩いて 429 が同じ条件で返ることを確認 |
| **判定** | **D5 の範囲内でのみ実装可 (Phase 5)** |

---

### D7. Worker の不正 JSON が 500 になる 🟡

| | |
|---|---|
| **根拠** | `index.ts` に `request.json()` が 24 箇所、うち `.catch(() => null)` でガードされているのは **5 箇所のみ**。残り 19 箇所は不正な body で例外 → catch-all で 500。`docs/ARCHITECTURE-worker.md:66` に既知として「400 へ統一の余地」と明記 |
| **なぜ負債か** | クライアントのバグがサーバエラーとして観測され、本物の障害と区別できない。500 はリトライ対象にもなりうる |
| **影響範囲** | POST/PUT/DELETE の全ルート。**ステータスコードの変更 = API 契約の変更 (P3)** |
| **変更リスク** | **中**。「不正 body に 500 を返す」に依存しているクライアントは常識的には存在しないが、確認していない |
| **改善案** | D5 で切り出す範囲のみ `await request.json().catch(() => null)` + `if (!body) return error("invalid JSON body")` に統一する。**範囲外の 19 箇所は触らない** |
| **検証方法** | `curl -X POST --data 'not-json'` で 400 が返ること。正常系のレスポンスが不変であること |
| **判定** | **D5 の範囲内でのみ実装可 (Phase 5)。全体適用は提案のみ (Q4 参照)** |

---

### D8. Android に事実上テストが無い 🟡

| | |
|---|---|
| **根拠** | `app/src/test/` 配下に `ui/idols/IdolSortOrderTest.kt` の 1 ファイルのみ。Kotlin 177 ファイル・約 29,700 行に対して |
| **なぜ負債か** | Android 側は「iOS の変更を 1:1 横展開する」運用 (`CONTRIBUTING.md` §3) なのに、横展開が正しく効いたかを機械的に確認する手段が無い |
| **影響範囲** | Android 全体 |
| **変更リスク** | **低** (テスト追加のみ) |
| **改善案** | **このリファクタでは新規テストを書かない** (Non-Negotiables 5 の「無関係な作業をしない」に該当)。ただし `./gradlew assembleDebug` と `./gradlew test` が Phase 0 で通ることは確認し、通らなければ報告する |
| **検証方法** | 上記 |
| **判定** | **提案のみ** |

---

### D9. Android に git 追跡された重複 gradle wrapper 🟢

| | |
|---|---|
| **根拠** | `ImasLiveDB-Android/ImasLiveDB-Android/` に `gradlew` / `gradlew.bat` / `gradle/wrapper/gradle-wrapper.jar` が git 追跡されている。`settings.gradle.kts` は `include(":app")` のみでこのディレクトリを参照しない。README / CI / スキル定義のいずれからも参照が無い |
| **なぜ負債か** | 実行可能な `gradlew` が 2 つ存在し、どちらが正か分からない。`gradle-wrapper.jar` はバイナリなので中身も確認されない |
| **影響範囲** | 無し (どこからも参照されていない) |
| **変更リスク** | **低**。ただし「本当に不要か」の最終判断はオーナーのもの → Q1 で確認する |
| **改善案** | Q1 が Yes なら `git rm -r ImasLiveDB-Android/ImasLiveDB-Android` |
| **検証方法** | `grep -rn "ImasLiveDB-Android/ImasLiveDB-Android" . --exclude-dir={.git,node_modules,build}` が 0 件。削除後に `JAVA_HOME=$(/usr/libexec/java_home -v 21) ./gradlew assembleDebug` が通る |
| **判定** | **Q1 の回答待ち。回答があれば実装可 (Phase 2)** |

---

### D10. マイグレーション既適用判定に 2 つの方式が混在 🟠

| | |
|---|---|
| **根拠** | `seedMigrationHistoryIfNeeded` (`AppDatabase.swift:277-364`) は同梱 DB のスキーマを嗅ぎつけて `grdb_migrations` に識別子を事前挿入する方式。v1〜v22 の一部を手作業で列挙している。一方 v23 以降 (`DatabaseMigrations.swift:673-`) は migration 本体が `PRAGMA table_info` チェックや `ifNotExists` で冪等になっており、事前挿入を必要としない |
| **なぜ負債か** | 新しい migration を足す人が「どちらの方式に従うのか」を判断できない。旧方式を選ぶと `seedMigrationHistoryIfNeeded` に条件追加を忘れて**新規インストール時に起動クラッシュ**する (v19 のコメントが実際にその事故を記録している) |
| **影響範囲** | 起動パス。**P1 の最高危険領域** |
| **変更リスク** | **非常に高**。判定条件を 1 つ間違えると新規インストールが起動しなくなり、Apple 審査 reject に直結する |
| **改善案** | **コードを触らない。** `DatabaseMigrations.swift` の先頭に「**v23 以降は migration 本体を冪等に書く。`seedMigrationHistoryIfNeeded` への追記は不要**」という規約コメントを追加するだけに留める。既存の v1〜v22 の記述は 1 行も変えない |
| **検証方法** | `xcodebuild build` + `xcodebuild test` (コメント追加のみなので挙動不変) |
| **判定** | **コメント追加のみ実装可 (Phase 4)。ロジック変更は提案のみ** |

---

### D11. `Adapters/Persistence` の 13 Repository が 1:1 パススルー 🟠

| | |
|---|---|
| **根拠** | `AppContainer.swift:24-64` が 13 の `GRDB*Repository` を `AppDatabase.shared` を包むだけで生成。各 Repository はポートのメソッドを `AppDatabase` の同名メソッドへ委譲するのみ |
| **なぜ負債か** | 一見「転送するだけの層」= アンチパターンに見える |
| **影響範囲** | 読み取りパス全体 |
| **変更リスク** | — |
| **改善案** | **何もしない。** `docs/ARCHITECTURE.md:21` が「これは設計上の妥協ではなく、ビッグバン書き換えを避けるための**意図した中間状態**」と明言している。クエリ本体を Repository へ移すのは「触る機能から順次」という確定方針で、リファクタ専用セッションでまとめてやる作業ではない |
| **検証方法** | — |
| **判定** | **触るな (out-of-scope)** |

---

### D12. `Views/` が docs の目標配置 `Presentation/` に未移動 🟠

| | |
|---|---|
| **根拠** | `docs/ARCHITECTURE.md:144-166` のフォルダ構成 (目標) に対し、実体は `ImasLiveDB/Views/` (21 サブディレクトリ) / `ImasLiveDB/Services/` (44 ファイル) / `ImasLiveDB/Database/` |
| **なぜ負債か** | 文書と実体が食い違い、新規参加者が目標形を現状と誤読する |
| **影響範囲** | 全 View。`project.yml` はディレクトリを再帰的に拾うのでビルド設定変更は不要 |
| **変更リスク** | **中**。物理移動自体は安全だが、差分が数百ファイルに及び、進行中の Android 横展開作業や他の未コミット変更と激しく競合する |
| **改善案** | **今はやらない。** `docs/ARCHITECTURE.md:165` が既に「既存ファイルの物理移動は段階的。触る機能から寄せる」と規定している |
| **判定** | **提案のみ (out-of-scope)** |

---

### D13. `.shared` シングルトンの直参照が残る 🟠

| | |
|---|---|
| **根拠** | 実測: `AppContainer.shared` 218、`APIClient.shared` 71、`MusicKitService.shared` 57、`AuthService.shared` 48、`UserMarkService.shared` 31、`CommunityAPI.shared` 20。`Views/` 配下の 27 ファイルが Service を直接参照 |
| **なぜ負債か** | テスト時にフェイクを差せない。ただし `AppContainer.shared` 経由は `docs/ARCHITECTURE.md:91` で明示的に許容されている |
| **影響範囲** | 該当する機能単位 |
| **変更リスク** | **中**。ポート化は「その機能の ViewModel 化 + テスト追加」とセットでないと意味が薄い (ARCHITECTURE.md:174) |
| **改善案** | **機能単位で行う作業なので、このリファクタでは手を付けない。** どの機能から着手すべきかを Reporting Format の「提案」欄に、使用箇所数の多い順で列挙する |
| **判定** | **提案のみ (out-of-scope)** |

---

### D14. Android のネットワーク層が手書き `HttpURLConnection` 🟠

| | |
|---|---|
| **根拠** | `data/community/CommunityApi.kt` 794 行。`org.json` で手動パース。`docs/ARCHITECTURE-android.md:68` が既知の改善余地として記載 |
| **なぜ負債か** | 型安全性が無く、Worker のレスポンス形状変更を実行時まで検出できない |
| **影響範囲** | Android のコミュニティ機能全部 |
| **変更リスク** | **高**。Retrofit/Ktor + kotlinx.serialization 導入は依存追加 + 全呼び出し書き換え |
| **改善案** | **提案のみ。** Non-Negotiables 「新しい依存パッケージを追加したくなったら止まる」に該当 |
| **判定** | **提案のみ (out-of-scope)** |

---

### D15. Android `PollsViewModel` の N+1 フェッチ 🟠

| | |
|---|---|
| **根拠** | `docs/ARCHITECTURE-android.md:70` に既知として記載 |
| **なぜ負債か** | ポール一覧を開くたびに D1 へのリクエストが件数分発生 → P7 (ランニングコスト 0) に直接効く |
| **影響範囲** | Android のポール一覧 |
| **変更リスク** | **中**。`ui/polls/PollsScreen.kt` は現在**未コミット変更を抱えている** (作業中) |
| **改善案** | **触るな。** 進行中の作業と競合する |
| **判定** | **提案のみ (out-of-scope)** |

---

## Implementation Phases

**順番を守れ。前フェーズの検証が通るまで次に進むな。各フェーズの終わりに必ずコミットしろ。**

### Phase 0 — 現状と検証の記録 (コード変更なし)

1. `git status --porcelain` / `git stash list` / `git log --oneline -5` を記録。
2. `develop` 起点で `refactor/<topic>` ブランチを切る。
3. Baseline Commands を**全部**実行し、出力 (成功/失敗、テスト通過数、エラー全文) を記録。
4. D3 の 55 個リストを自分で再検証し、実測値が一致するか確認。
5. **ここまでで判明した差異があれば、実装に入る前に報告しろ。**

**成果物**: baseline レポート (コミット不要)。

---

### Phase 1 — 安全網を先に作る

1. **D1**: `KeyUsage` の型エラーを修正 → `npx tsc --noEmit` を exit 0 にする。1 コミット。
2. **D2**: `imas-live-api/package.json` に `"typecheck": "tsc --noEmit"` を追加。1 コミット。
3. **D2**: `.github/workflows/worker-guard.yml` を追加 (`imas-live-api/**` の push/PR で `npm ci && npm run typecheck`)。1 コミット。

**検証**: `cd imas-live-api && npm run typecheck` exit 0 / `npx wrangler deploy --dry-run` 成功。

---

### Phase 2 — 明らかに安全な整理

1. **D9**: Q1 が Yes なら `git rm -r ImasLiveDB-Android/ImasLiveDB-Android`。1 コミット。回答が無ければスキップして報告。
2. **D3**: 未参照の同期メソッド 55 個を削除。**5〜10 個ずつ、6〜10 コミットに分ける。** 各コミット後に `xcodebuild build`。

**検証**: 全削除後に `xcodebuild test` で **Phase 0 と同数以上**のテストが通過。`bash tools/check_domain_purity.sh` PASS。

---

### Phase 3 — 小さな責務分離 (iOS)

**D4**: `AppDatabase.swift` を既存の `// MARK: -` 境界で extension ファイルへ分割する。

- **`:1-364` (セットアップ / reseed / migration seed) には一切触るな。** ここが P1 の最高危険領域。
- 1 ファイル切り出すごとに 1 コミット + `xcodebuild build`。
- 各コミットの `git diff --stat` で「削除行数 ≒ 追加行数」を確認する。**乖離していたら移動以外のことをしている。**
- `private static func` を参照する側と同じファイルに置けなくなったら、**そこが分割線として間違っている。アクセス修飾子を緩めて回避するな。分割線を引き直せ。**

**検証**: 分割完了後 `xcodebuild build` + `xcodebuild test` (Phase 0 と同数以上)。`xcodegen generate` を再実行して `.xcodeproj` が壊れないこと。

---

### Phase 4 — 境界の明文化 (ドキュメントのみ)

**D10**: `Database/DatabaseMigrations.swift` の先頭に、migration 追加時の規約コメントを追加する。

> v23 以降は migration 本体を冪等に書く (`PRAGMA table_info` チェック / `ifNotExists`)。
> `AppDatabase.seedMigrationHistoryIfNeeded` への追記は不要。旧 v1〜v22 の事前挿入方式は互換のため残すが、新規には使わない。

`docs/ARCHITECTURE.md` の「進捗」節に、このリファクタで動かした内容を追記する。**方針そのものは書き換えるな。**

**検証**: `xcodebuild build`。

---

### Phase 5 — Worker の 1 グループ切り出し (最後・最も慎重に)

⚠️ **前提: `imas-live-api/src/index.ts` の未コミット変更が解消されていること。** 残っていたら着手せず報告しろ。

1. `npx wrangler dev` を起動し、`/favorites/*` と `/penlight/*` の全エンドポイントに `curl` を打って**レスポンス JSON・ステータスコード・`Cache-Control` ヘッダを保存**する (移動前スナップショット)。
2. **D5**: `src/routes/device_aggregates.ts` へ `/favorites/*` + `/penlight/*` を移す。`RouteContext` 経由で `json` / `error` / `rateLimitSimple` / `url` / `env` を受け取り、未マッチなら `null` を返す。**ルート本体のロジックは 1 行も書き換えるな (移動のみ)。** 1 コミット。
3. **D6**: 移した範囲内でのみ `requireDeviceId` / IP レート制限のヘルパを適用。1 コミット。
4. **D7**: 移した範囲内でのみ `request.json().catch(() => null)` + 400 応答に統一。1 コミット。

**検証**: 各コミットで `npm run typecheck` exit 0 + `npx wrangler deploy --dry-run` 成功。
最後に手順 1 と同じ `curl` を全部打ち直し、**手順 4 のステータス変更 (500 → 400) 以外に差分が 1 バイトも無い**ことを確認する。差分があったら**その場でコミットを revert して報告しろ。**

**デプロイはするな。** `npx wrangler deploy` は実行禁止 (オーナーの操作)。

---

### Phase 6 — 提案のみ (コードを書かない)

D2 の iOS/Android CI、D8、D11、D12、D13、D14、D15、および Phase 5 で得た知見に基づく Worker の残りルート分割案を、
Reporting Format の「提案」欄に**優先度と根拠つきで**書く。**承認なしに着手するな。**

---

## Verification Requirements

### 全フェーズ共通

- 各コミットの前に、そのフェーズの検証コマンドを実行する。
- `xcodebuild test` の**通過数が Phase 0 の記録を下回ったら、その時点で止まる。**
- `bash tools/check_domain_purity.sh` は全フェーズで PASS を維持する。
- `git diff --stat` を毎コミットで確認し、意図しないファイルが含まれていないことを見る。

### フェーズ別

| Phase | 必須検証 |
|---|---|
| 0 | 全 Baseline Commands。結果を全文記録 |
| 1 | `npm run typecheck` exit 0 / `wrangler deploy --dry-run` 成功 |
| 2 | 各コミット後 `xcodebuild build`、最後に `xcodebuild test` (Phase 0 以上) / Android を触ったなら `assembleDebug` |
| 3 | 各コミット後 `xcodebuild build`、最後に `xcodegen generate` + `xcodebuild test` (Phase 0 以上) |
| 4 | `xcodebuild build` |
| 5 | 各コミット後 `npm run typecheck` + `wrangler deploy --dry-run`、最後に `wrangler dev` + curl 差分ゼロ確認 |

### やってはいけない検証の省略

- 「ビルドが通ったからテストは省略」→ 禁止。
- 「移動しただけだから検証不要」→ 禁止。Phase 3 の分割で `private` のスコープが壊れる可能性が実在する。
- 「curl は主要な 1 本だけ」→ 禁止。Phase 5 は移したルート**全部**。

---

## Reporting Format

作業の最後に、以下の形式で報告しろ。**憶測を書くな。実行していないコマンドは「未実行」と書け。**

```markdown
## 1. Baseline (Phase 0)

| コマンド | 結果 | 備考 |
|---|---|---|
| bash tools/check_domain_purity.sh | PASS/FAIL | |
| cd imas-live-api && npx tsc --noEmit | 出力全文 | |
| xcodebuild build -scheme ImasLiveDB ... | PASS/FAIL | |
| xcodebuild test -scheme ImasLiveDB ... | N passed / M failed | ← 以降の基準値 |
| JAVA_HOME=... ./gradlew assembleDebug | PASS/FAIL/未実行 | |
| JAVA_HOME=... ./gradlew test | N passed | |

作業開始時の未コミット変更: (git status --porcelain の出力)

## 2. 実施した変更

| Phase | コミット | 内容 | 検証結果 |
|---|---|---|---|
| 1 | abc1234 | KeyUsage 型エラー修正 | tsc exit 0 |
| ... | | | |

各コミットで「何を移動/削除したか」と「挙動が変わっていないと言える根拠」を 1〜2 行で。

## 3. 実施しなかったこと / 中断したこと

- 項目、理由、どこで止まったか。

## 4. 検証の最終結果

| コマンド | 結果 | Phase 0 との比較 |
|---|---|---|

Phase 5 を実施した場合、curl 差分の確認結果 (エンドポイントごとに一致/不一致)。

## 5. 質問 (Stop And Ask に該当したもの)

## 6. 提案 (Phase 6 — コードは書いていない)

| 項目 | 優先度 | 根拠 | 想定リスク |
|---|---|---|---|
```

---

## Out-of-scope Items

**以下は今回やらない。「ついでに」も禁止。手を出したくなったら止まって提案しろ。**

1. `Views/` → `Presentation/` の物理移動 (D12)。
2. `Adapters/Persistence` の Repository にクエリ本体を移す作業 (D11)。**意図された中間状態であり、直すべき欠陥ではない。**
3. `.shared` シングルトンのポート化 / 注入化 (D13)。機能単位の作業。
4. `AppDatabase.swift:1-364` (起動セットアップ / reseed / `seedMigrationHistoryIfNeeded`) のロジック変更 (D10, P1)。
5. `CloudKitSyncEngine` の再開・重複排除ロジックの「整理」(P2)。
6. Worker の `/favorites` `/penlight` **以外**のルート分割 (D5)。
7. D1 / GRDB / Room のスキーマ変更、migration の追加・編集。
8. Android のネットワーク層書き換え (D14)、`PollsViewModel` の N+1 修正 (D15)。
9. 依存パッケージの追加・アップグレード (wrangler v3→v4、GRDB、AGP、Kotlin、テストフレームワーク導入を含む)。
10. iOS/Android の CI ワークフロー追加 (macOS runner のコスト判断が要る)。
11. 新規テストの追加 (D8)。**既存テストを壊さないことだけが今回の責務。**
12. UI・文言・ログ出力・ライセンス表記・`data/` 配下のデータ・`db/master.sql` の変更。
13. `npx wrangler deploy` の実行、CloudKit への書き込み、TestFlight 配信。
14. 進行中の未コミット変更 (Venue / 共有カードの Android 横展開、`index.ts` の 76 行差分) への介入。stash も revert も禁止。
15. 一括置換スクリプトによる機械的修正。**1 件ずつ判断して直す** (`CONTRIBUTING.md` §4)。
