# iOS / Android ロジック共通化 方式検討 (調査レポート)

> 状態: **方式を Rust + UniFFI に決定 (2026-08-24)。Phase 0 (疎通) 完了 (2026-08-25)。**
> `imas-core/` crate + `imas-core/build.sh`。JSTDay/JstDay が Rust 委譲になり、
> iOS 10 テスト + Android 11 テストが FFI 越しに全パス。次は Phase 1 (純粋 UseCase 16本)。
> 決定理由: 型の対称性 (iOS/Android どちらも二級市民にならない)。詳細は §5.4。
> KMP は Android 側に有利で iOS 側に Kotlin 型が漏れるため不採用。
> 対象: `ImasLiveDB/` (iOS) と `ImasLiveDB-Android/` (Android)。
> 関連: [`ARCHITECTURE.md`](ARCHITECTURE.md) / [`ARCHITECTURE-android.md`](ARCHITECTURE-android.md) / [`perf/AUDIT.md`](perf/AUDIT.md)
> 計測日: 2026-08-24 / iOS `MARKETING_VERSION 1.11.0` / Android `versionName 1.9.0`

---

## 0. 結論 (3行)

1. **「Rust で高速化」の前提は成立しない。** 検証済みボトルネックに言語実行速度由来の項目がひとつも無い。
2. **一方で共通化の必要性は「実際にデグレが発生している」レベルで実在する。** SQL の逐語二重管理、UseCase 16本中13本の Android 欠落、マイグレーション番号体系の乖離を実測で確認した。
3. **技術的な最大の障害は無かった。** 両OSともリアクティブDB監視 (`ValueObservation` / `Flow<T>` DAO) を **使用箇所ゼロ**。FFI 境界を跨げないストリーム API の再構築が不要という、この種の移行で普通は詰む所が最初から空いている。

→ 目的を **「速くする」から「単一の真実の源にして写経とデグレを構造的に不可能にする」** に置き直した上で採否を判断すべき。

---

## 1. 前提検証: 「Rust で高速化」は成り立つか

### 1.1 実測済みボトルネックの性質

[`perf/AUDIT.md`](perf/AUDIT.md) は全 finding を実コード・実 Bundle DB で裏取り済み。上位項目の根因を分類する:

| # | 項目 | severity | 根因の性質 | Rust化で改善するか |
|---|---|---|---|---|
| 1 | `DatabaseQueue` → `DatabasePool` | medium | GRDB の並行設定 | ✗ (設定変更で解決) |
| 2 | `reseedEventKindIfNeeded` 毎起動 ~100ms | medium | 無条件 463 UPDATE | ✗ (センチネル化で解決) |
| 3 | `reseedMasterTablesIfNeeded` 13万行 | medium | SQLite 書き込み I/O | △ (ATTACH一括化が本命) |
| 4 | 初回 `integrity_check` 16MB 全走査 | low | SQLite I/O | ✗ (`quick_check` で解決) |
| 5-6, 10-14 | 索引不足 10件 | medium〜low | SQLite クエリプラン | ✗ (索引追加で解決) |
| 7-9 | 画像デコード/リサイズ/キャッシュ | medium〜low | 画像パイプライン | ✗ (Nuke/Coil の設定) |
| 20 | DB アクセスの sync→async 化 | medium | メインスレッド占有 | ✗ (構造の問題) |

**critical / high は 1件も無い** (AUDIT 要約に明記)。**言語の実行速度が根因の項目はゼロ。**

### 1.2 唯一の CPU バウンドなホットパスは既に最適化済み

打鍵ごとの一覧絞り込みは [`Domain/UseCases/TextSearchIndex.swift`](../ImasLiveDB/Domain/UseCases/TextSearchIndex.swift) で対処済み。同ファイルのコメントに実測が残っている:

| やり方 | 2,000曲 1打鍵 |
|---|---|
| 毎回 `lowercased()` + `String.contains` | 1.38 ms |
| 事前小文字化 + `String.contains` | 5.66 ms |
| 事前小文字化 + `range(of:options:.literal)` | 1.47 ms |
| **事前小文字化 UTF-8 バイト列 + 部分列探索 (現状)** | **0.11 ms** |

**0.11ms は 60fps の1フレーム (16.7ms) の 0.7%。** ここを Rust で仮に 10倍速くしても削れるのは 0.1ms で、体感は変化しない。

### 1.3 唯一 Rust に目がある箇所

seed import (13万行 INSERT)。ただし SQLite の書き込み律速であり、AUDIT #3 の本命対策も「ATTACH による一括コピー化」= SQL レベルの解決。rusqlite に置き換えても言語差による改善は小さい。

### 1.4 結論

**perf 課題 (DatabasePool化・索引追加・センチネル化・画像リサイズ) は Rust とは完全に独立に、そのまま実施する価値がある。** 共通化の議論とは切り離して扱う。

---

## 2. 現状のコード量 (実測)

### 2.1 iOS (`ImasLiveDB/`)

| ディレクトリ | ファイル数 | LOC |
|---|---:|---:|
| Views | 178 | 40,012 |
| Services | 49 | 8,265 |
| Database | 11 | 5,732 |
| Models | 39 | 4,038 |
| Domain | 37 | 1,680 |
| DesignSystem | 4 | 1,446 |
| App | 3 | 504 |
| Adapters | 14 | 493 |
| Extensions | 8 | 216 |
| Shared | 1 | 120 |
| **非UI計 (Domain+Services+Adapters+Models+Database)** | **150** | **20,208** |

### 2.2 Android (`ImasLiveDB-Android/`)

| ディレクトリ | ファイル数 | LOC |
|---|---:|---:|
| ui | 111 | 23,382 |
| data | 66 | 6,325 |
| player | 1 | 176 |
| di | 1 | 60 |

data の内訳: model 1,494 / dao 1,020 / repository 899 / sync 646 / community 994 / edit 330 / backup 309 / AppDatabase.kt 279 / auth 194 / games 160

---

## 3. 二重管理の実証 (ここが本題)

### 3.1 SQL が逐語的に二重管理されている

同一の SELECT 文が Swift 文字列リテラルと Room `@Query` に別々に書かれている。

```
iOS      ImasLiveDB/Database/AppDatabase+SongQueries.swift:418
Android  .../data/db/dao/SongDao.kt:44
         → SELECT sh.id AS show_id, e.id AS event_id, ... FROM setlist_items si
           JOIN shows sh ... JOIN events e ... 完全に同一
```

Android 側のコメントが二重管理を自白している:

```kotlin
/**
 * 現地回収済み公演一覧 ...
 * iOS AppDatabase.fetchCollectedShows と同じ判定 (show/event 単位の attended マーク)。
 */
```

規模: iOS `Database/` の SQL 4,820行 (5,732 − migrations 912) ↔ Android dao 1,020 + repository 899。
`SELECT` 出現数の比較でも乖離が見える — Stats だけで iOS 27 / Android 16。

### 3.2 Domain UseCase 16本中 13本が Android に存在しない

| UseCase (iOS) | Android 対応 |
|---|---|
| `IntroQuizChoices` | ✅ `ui/introdon/IntroDonModels.kt` |
| `JSTDay` | ✅ `data/model/JstDay.kt` |
| `WeightedSampling` | ✅ `data/model/WeightedSampling.kt` |
| `SongListFiltering` | ❌ (ViewModel にインライン再実装・下記3.3) |
| `IdolListFiltering` (182行) | ❌ |
| `EventListFiltering` | ❌ |
| `TimelineLayout` (131行) | ❌ |
| `SetlistDiff` (72行) | ❌ |
| `EventGrouping` | ❌ |
| `DailyPick` | ❌ |
| `EditPermissionRules` | ❌ |
| `OshiThemeResolution` | ❌ |
| `BackupImportSummary` | ❌ |
| `ImageTemplateJSON` | ❌ |
| `ShortYearMonth` | ❌ |
| `TextSearchIndex` | ❌ |

### 3.3 既にロジックが乖離している (確認済みの実害)

[`SongListFiltering.swift`](../ImasLiveDB/Domain/UseCases/SongListFiltering.swift) の `applySongMarkFilters` は、Android では [`SongListViewModel.kt:188-195`](../ImasLiveDB-Android/app/src/main/kotlin/com/fugaif/imaslivedb/ui/songs/SongListViewModel.kt) にインライン再実装されている。

| 絞り込み | iOS | Android |
|---|---|---|
| 回収済み/未回収 | ✅ `collectedIds` 集合 | ⚠️ `collectedCounts` マップ (判定手段が別物) |
| お気に入り | ✅ | ✅ |
| 担当 (myPick) | ✅ | ✅ |
| **メモあり (`requireNote`)** | ✅ | ❌ **欠落** |
| **タグ集合絞り込み (`tagSongIds`)** | ✅ | ❌ **欠落** |
| **タグ票数降順ランキング (`rankByTagVotes`)** | ✅ | ❌ **欠落** |

「iOS変更は必ず同セッションで Android に 1:1 横展開」という運用ルールが存在するにもかかわらず、この規模では漏れる。**規律ではなく構造で解く対象。**

### 3.4 マイグレーションの番号体系が既に乖離

| | 方式 | バージョン |
|---|---|---|
| iOS | GRDB `registerMigration` | `v1_create_tables` 〜 `v28_idol_voice_actors` (**28本**) |
| Android | Room `Migration` | `version = 9`、`MIGRATION_4_5` 〜 `MIGRATION_8_9` (**5本**) |

Android は後発で seed DB から始まったため番号が独立。`ARCHITECTURE.md` が「スキーマを変えたら iOS(GRDB) と Android(Room) の両方に移行を1本ずつ書く」を**絶対規律**として明文化しているが、その規律のコストがそのまま二重管理コストである。

### 3.5 ゲーム/クイズは file-for-file の写経

| iOS | LOC | Android | LOC |
|---|---:|---|---:|
| `QuizComponents.swift` | 490 | `QuizComponents.kt` | 457 |
| `ColorMatchGameView.swift` | 430 | `ColorMatchGameScreen.kt` | 472 |
| `IdolQuizView.swift` | 298 | `IdolQuizScreen.kt` | 348 |
| `SongSingerQuizView.swift` | 227 | `SongSingerQuizScreen.kt` | 302 |
| `IdolQuizSetupView.swift` | 213 | `IdolQuizSetupScreen.kt` | 223 |
| `SongSingerQuizSetupView.swift` | 234 | `SongSingerQuizSetupScreen.kt` | 146 |
| `GameProgressStore.swift` | 154 | `GameProgressStore.kt` | 160 |
| **計** | **2,282** | **計** | **2,332** |

合計 LOC がほぼ一致 = 手で移植した証跡。出題生成・正誤判定・スコアリング・進捗保存は全部プラットフォーム非依存。

---

## 4. 共通化対象の全マッピング

### A. 共有可能 (純粋・プラットフォーム非依存)

| # | 領域 | iOS | Android | 備考 |
|---|---|---|---|---|
| A1 | Domain UseCase | `Domain/UseCases/` 16本 1,000 | 3本のみ | 純粋関数。依存ゼロ |
| A2 | 行モデル (DBレコード) | `Models/` のうち Song/Idol/Event/Show/Venue/SetlistItem/... 約1,100 | `data/model/` 1,494 | 双方 struct/data class の素の形 |
| A3 | クエリ結果型 | `Database/QueryTypes.swift` 870 | `data/model/QueryResults.kt` 379 | 完全対応 |
| A4 | SQL 読み取り層 | `Database/*Queries.swift` 4,820 | dao 1,020 + repository 899 | **最大の二重管理** |
| A5 | スキーマ + マイグレーション | `DatabaseMigrations.swift` 912 | `AppDatabase.kt` 279 | 番号体系が既に乖離 (3.4) |
| A6 | ゲーム/クイズ ロジック | `Views/Games/` の非View部 | `ui/games/` + `data/games/` | 2,282 ↔ 2,332 (3.5) |
| A7 | Worker API DTO + 呼び出し | `CommunityAPI` 623 + `APIClient` 311 + `EditService` | `CommunityApi.kt` 812 + `EditApi.kt` 330 | HTTP transport は分離可 |
| A8 | CloudKit レコード変換・差分マージ | `CKRecordMapper` 354 + `CloudKitSyncEngine` 509 の判定部 | `SyncMappers.kt` 189 + `CloudKitSyncEngine.kt` 169 | **通信は共有不可 (B1)** |
| A9 | Seed import | `AppDatabase+Sync.swift` 297 の reseed | `SeedImporter.kt` 134 | |
| A10 | バックアップ整合判定 | `BackupExportImportService` + `UserMarkBackup` + `BackupImportSummary` | `BackupExportImportService.kt` 214 | |
| A11 | 無限色エンジン (色計算のみ) | `ImasTheme.swift` 338 + `BrandPalette` 28 | `ImasTheme.kt` 207 + `Color.kt` 75 | 色変換は純粋な数値計算 |
| A12 | ローカル投票/貢献ログ | `LocalPollVoteLog` / `LocalContributionLog` | 同名 .kt (92 / 59) | |

### B. 部分共有 (契約は共有・transport は各OS)

| # | 領域 | 理由 |
|---|---|---|
| B1 | **CloudKit 同期の通信** | **iOS = CloudKit.framework (ネイティブ) / Android = CloudKit Web Services (HTTP + API token)。transport が非対称。** レコード変換と差分判定 (A8) だけ共通化し、通信は各OSに残すのが素直 |
| B2 | 認証トークン保管 | iOS Keychain / Android EncryptedSharedPreferences。ロジックは共有、保管は各OS |
| B3 | HTTP クライアント | URLSession / OkHttp。Rust `reqwest` で統一する選択肢もあるが、証明書ピンニング・App Attest との兼ね合いで要検討 |
| B4 | ファイル配置 | App Group / `getFilesDir()`。パスは各OSから渡す |

### C. 共有不可 (OS SDK 依存)

| 領域 | iOS LOC | Android LOC |
|---|---:|---:|
| View 全体 (SwiftUI / Compose) | 40,012 | 23,382 |
| DesignSystem のコンポーネント部 | `ImasComponents.swift` 908 | `ui/components/` |
| 音声 (AVAudioEngine / ExoPlayer) | `IntroAudioEngine.swift` 396 | `AudioPreviewManager.kt` 176 |
| MusicKit プレビュー | `MusicKitService` | (Android は別実装) |
| 音声認識 / 通知 / ウィジェット / Live Activity | `SpeechRecognitionService` ほか | 部分的に非実装 |
| 画像パイプライン (Nuke / Coil) | — | — |
| App Attest / Firebase | `AppAttestService` | — |

### 共有可能量の見積り

| | iOS 側 | Android 側 |
|---|---:|---:|
| 現状の非UIコード | 20,208 | 6,325 |
| うち A (共有可) 相当 | 約 9,000〜10,000 | 約 4,500〜5,000 |
| Rust コアに集約した場合の推定 | 約 6,000〜7,000 (Rust 1本) | |

※ A6/A11 は View に埋まっている分の抽出が前提。iOS 側の見積りは `Database` (5,732) + `Domain` (1,680) + `Models` の DB レコード部 (約1,100) + `Adapters` (493) を核に、Services から A7/A8/A9/A10 相当を加算したもの。

---

## 5. 方式比較

### 5.1 Rust + UniFFI

**構成**: `imas-core` crate (rusqlite + serde) → UniFFI で Swift binding (xcframework) と Kotlin binding (.so + JNA) を生成。

| 観点 | 評価 |
|---|---|
| 単一の真実の源 | ◎ 1つの crate。写経が物理的に不可能になる |
| テスト | ◎ `cargo test` で完結。CI が最も安く速い。実 fixture DB を1回書けば両OSに効く |
| 型の対称性 | ◎ Swift/Kotlin 両方に素の struct/data class が生成される。どちらか一方が二級市民にならない |
| 既存資産の廃棄 | GRDB と Room を両方捨てる |
| リアクティブ監視 | **問題なし** — 両OSとも使用箇所ゼロ (`ValueObservation` 0件 / `Flow<T>` DAO 0件) |
| iOS ビルド統合 | XcodeGen (`project.yml`) に xcframework 宣言を追加。Widget は DB 非依存なので配布先は1ターゲットのみ |
| Android ビルド統合 | cargo-ndk + Gradle タスク。4 ABI 分のビルドが必要 |
| バイナリサイズ | rusqlite bundled SQLite +1〜2MB / ABI。Android は abiFilters か App Bundle で分割 |
| 非同期 | UniFFI の async 対応で Swift `async` / Kotlin `suspend` に落ちる |
| デバッグ | △ Swift/Kotlin/Rust の3トールチェーンを跨ぐ。スタックトレースが FFI で切れる |
| コントリビュータ | △ [`oss_plan.md`](oss_plan.md) が OSS 化を想定。Rust 追加は参加障壁を上げる |
| 速度 | 本件では無関係 (§1) |

### 5.2 Kotlin Multiplatform (KMP) + SQLDelight

**構成**: `shared` モジュール (commonMain) + SQLDelight で型付き SQL を共有 → Android は直接、iOS は Kotlin/Native の .framework。

| 観点 | 評価 |
|---|---|
| 単一の真実の源 | ◎ 同上 |
| テスト | ○ commonTest。ただし iOS ターゲットのテスト実行は Kotlin/Native ビルドが重い |
| 型の対称性 | **✗ 非対称。** Android は完全にネイティブだが、iOS 側は Kotlin 型が漏れる (`KotlinInt`, `KotlinThrowable`, suspend 関数の completion handler 化)。Swift 側が二級市民になる |
| 既存資産の廃棄 | Room を捨てる (SQLDelight へ)。GRDB も捨てる |
| SQL の書き心地 | ◎ SQLDelight の `.sq` は SQL をそのまま書けてコンパイル時検証もある。A4 との相性は Rust より良い |
| iOS ランタイム | Kotlin/Native ランタイム + GC が iOS アプリに載る |
| Android 側の自然さ | ◎ そのまま Kotlin。coroutines/Flow がシームレス |
| ビルド統合 | ○ Gradle 一本で両方。iOS は CocoaPods/SPM 経由 |
| デバッグ | ○ Rust より1段階マシ (2言語) |
| コントリビュータ | ◎ 既に Kotlin が入っているので言語追加ゼロ |
| 速度 | 本件では無関係 |

### 5.3 現状維持 + 規律強化 (共通化しない)

| 観点 | 評価 |
|---|---|
| 単一の真実の源 | ✗ 存在しない。3.3 の乖離が今後も発生し続ける |
| 対策の限界 | `/sync-ios-to-android` スキルと運用ルールは既にある。それでも 13/16 欠落と 3項目の機能欠落が発生した。**規律の追加投入で解ける問題ではないことが実証済み** |
| 唯一の利点 | 各OSが最適な形 (GRDB の Codable / Room の KSP 検証) をそのまま使える |

### 5.4 軸ごとの比較

| 軸 | Rust+UniFFI | KMP+SQLDelight | 現状維持 |
|---|:---:|:---:|:---:|
| 二重管理の解消 | ◎ | ◎ | ✗ |
| 型の対称性 (両OS対等) | ◎ | △ (iOS が二級) | ◎ |
| SQL の記述性 | ○ (rusqlite は文字列 + 手動マップ) | ◎ (`.sq` 型付き) | ○ |
| テストの一元化 | ◎ | ○ | ✗ |
| デバッグのしやすさ | △ | ○ | ◎ |
| OSS コントリビュータ受け入れ | △ | ◎ | ◎ |
| iOS ランタイム汚染 | ○ (GCなし) | △ (K/N ランタイム) | ◎ |
| 実行速度 | 本件では無関係 | 本件では無関係 | 本件では無関係 |

---

## 6. 移行計画 (方式採用時・垂直スライス方式)

**原則: 1ドメインずつ切り替え、都度 iOS/Android 両方をビルド・動作確認・コミット。既存の GRDB/Room 経路はスライス完了まで並走させる。途中で止めても壊れない状態を常に維持。**

| Phase | 内容 | 完了判定 |
|---|---|---|
| **0. 疎通** | crate 骨組み + binding 生成 + iOS xcframework / Android cargo-ndk のビルド配線。`JSTDay` 1関数だけ FFI を跨がせる | 両OSで同じ結果が返る。CI で両方ビルド通過 |
| **1. 純粋 UseCase** | A1 の16本を移送。**Android に欠落している13本がこの時点で埋まる** | 既存 iOS テストを Rust 側に移植して全通過 |
| **2. 曲スライス** | A2/A3/A4 の songs 系。`SongDao` / `AppDatabase+SongQueries` を退役。**3.3 の乖離3項目がここで解消** | 曲一覧・詳細・絞り込みが両OSで同一挙動 |
| **3. アイドル/ユニット** | 同上 | |
| **4. イベント/公演/セトリ** | `EventQueries` 902行 = 最大。分割して進める | |
| **5. 統計/カレンダー/タイムライン** | A4 残り + `TimelineLayout` | |
| **6. ゲーム** | A6。View を残し出題生成・判定・進捗のみ移送 | 2,282+2,332 → Rust 側1本 |
| **7. スキーマ/マイグレーション** | A5。**「iOS/Android で移行を対に書く」規律がここで不要になる** | ⚠️ 最大リスク。下記7参照 |
| **8. 同期/バックアップ (任意)** | A8/A9/A10。transport は各OSに残す (B1)。**A7 は除外 → §7.5** | ⚠️ Worker リファクタ (#83) の完了待ち |
| **9. 色エンジン (任意)** | A11 | |

Phase 7 を最後に置くのは、`master.sqlite` の所有権移転が最も失敗コストが高いため。Phase 2〜6 で FFI 越しの読み取りが安定してから着手する。

---

## 7. 未解決の判断事項 / リスク

1. **Phase 7 のデータ破壊リスク (最大)**
   - `UserMark` (担当/お気に入り) は **CloudKit にもサーバにも無い端末ローカル限定データ**。マイグレーション失敗 = 復旧不能。
   - `journal_mode=DELETE` の維持が必須 (既存ユーザの Documents DB への反映条件)。rusqlite 側で明示設定が要る。
   - 破壊的マイグレーション禁止の規律を Rust 側で完全再現する必要がある。
2. **B1 の CloudKit 非対称をどう扱うか**
   - 案(a) 現状維持: 変換・マージのみ共有、通信は各OS。
   - 案(b) 統一: Rust から CloudKit Web Services を叩き両OSで共通化。iOS が CloudKit.framework の再試行制御・エラー分類を失う。API token をアプリに埋める必要が iOS 側にも生じる。
   - **要判断。** 現時点では (a) を推す。
3. **OSS 化 (`oss_plan.md`) との整合**
   - Rust 採用はコントリビュータの参加障壁を上げる。KMP なら既存の Kotlin 資産の延長。OSS 化の優先度次第で結論が変わる。
4. **CI の構成**
   - Rust: 4 Android ABI + iOS device/sim の計6ターゲットをビルドするクロスコンパイル環境が要る。
5. **Android のバイナリサイズと ABI**
   - bundled SQLite を含めて 4 ABI 分。App Bundle での分割配信が前提。
6. **iOS の GRDB 依存の残存範囲**
   - Phase 2〜6 の並走期間中は GRDB と rusqlite が同一 DB ファイルを開く。**同時オープンの排他制御を設計すること** (WAL でも writer は1つ)。

---

## 7.5. バックエンド (Worker) の Hono 移行との関係

[issue #83](https://github.com/fuga-if/idol-live-db/issues/83) で `imas-live-api` (Cloudflare Workers / TypeScript / 10,535行) に
テストを入れ、その上で [Hono](https://hono.dev) 移行を検討する議論が進行中 (contributor @Comamoca)。
現時点でテスト29件が入り、`POST /edit-requests` が `validateMasterEdit` を通していなかった実バグも1件修正済み。

### 結論: 層が違うので競合しない。ただし1点だけ交差する

| | Hono 移行 (#83) | 本件 (クライアント共通化) |
|---|---|---|
| 対象 | サーバ (`imas-live-api/`) | クライアント (`ImasLiveDB/` + `ImasLiveDB-Android/`) |
| 言語 | TypeScript | Swift / Kotlin (→ Rust or KMP) |
| 依存関係 | なし | なし |

**交差するのは §4-A7 (Worker API クライアント) のみ:**

```
iOS      CommunityAPI.swift 623 + APIClient.swift 311 + EditService
Android  CommunityApi.kt 812 + EditApi.kt 330
         → 同じ HTTP 契約を2言語で手書き
```

### これが方式選定に効く点

1. **A7 は「共通コアに手書きで移す」より「スキーマから生成する」ほうが筋が良い。**
   現状の Worker は zod も OpenAPI も導入しておらず、検証は `master_validators.ts` の手書き正規表現 + フィールドルール。
   Hono 移行時に `@hono/zod-openapi` を採れば OpenAPI spec が出せる。そこから Swift / Kotlin / Rust の
   クライアントを **生成** できるので、A7 の二重管理は Rust/KMP の採否とは独立に解ける。
   → **A7 は共通コアのスコープから外し、OpenAPI 生成に委ねる案を第一候補にすべき。**
   これにより共通コアのスコープは「DB + ドメインロジック」に純化する。

2. **順序: Worker のリファクタが動いている間、Phase 8 (A7/A8) には着手しない。**
   契約が動いている最中にクライアント側の API 層を作り直すと、二重に不安定になる。
   Phase 1〜7 (DB + ドメイン) は Worker と完全に独立なので、並行して進めて問題ない。

3. **OSS コントリビュータ軸の重みが上がる (§5.1 / §7-3)。**
   [`oss_plan.md`](oss_plan.md) は「保留」扱いだが、**実際には既に外部コントリビュータが TypeScript で
   稼働している**。Rust 採用の参加障壁は仮定の話ではなく実在の考慮事項になる。
   一方で影響範囲はクライアント側に閉じており、#83 の作業領域 (Worker/TS) とは重ならない。

### 実務上の注意

`master_validators.ts` の検証ルール (HEX `#RRGGBB`、Apple Music ID、ISO日付、YouTube URL、enum、文字長上限) は
**クライアント側の入力検証と論理的に同じ契約**。現状これも三重管理 (Worker / iOS / Android) になっている可能性が高い。
OpenAPI + zod スキーマからの生成が実現すれば、ここも同時に解消できる。

---

## 8. 推奨

- **§1 の perf 課題は本検討と切り離して即実施。** 言語選択と無関係に効果が確定している。
- **共通化そのものは実施を推す。** 3.3 が示す通り、運用規律では解けないことが実証済み。
- **方式は Rust + UniFFI に決定。** 型の対称性を最優先した。
  トレードオフとして受け入れるもの: SQL の記述性 (rusqlite は文字列 + 手動マップ、SQLDelight の `.sq` に劣る) /
  デバッグが3トールチェーンに跨ること / OSS コントリビュータの参加障壁。
- **A7 (Worker API クライアント) は共通コアのスコープから外す。** #83 の Hono 移行で OpenAPI を出せるなら、
  手書き共通化より生成のほうが上位互換。共通コアは「DB + ドメインロジック」に純化する。
- 実施する場合は **Phase 0 の疎通だけ先に通し、FFI の実コストを見てから Phase 1 以降の採否を再判断** するのが安全。
