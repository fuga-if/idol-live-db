# パフォーマンス改善 実施計画レポート (AUDIT)

> 検証済みボトルネックの統合・優先順位付け・実施計画。全 finding は実コード/実 Bundle DB (`ImasLiveDB/Resources/master.sqlite`, data_version=6) で裏取り済み。

## 要約

検証の結果、全 finding は **実在** が確認されたが、当初の impact 評価には過大評価が多く、検証後の severity は **medium が最大** であった (critical/high なし)。最も投資対効果が高い構造的改善は次の3つに集約される。

1. **`DatabaseQueue` → `DatabasePool` 置換** — 5つの finding が同一の根因を別角度から指摘。WAL を有効化しているのに reader/writer 並行が殺されている。CloudKit 同期や起動時 reseed の大量 write 中に UI read が直列ブロックされる体感ラグを解消する。**1箇所の型変更**で全 read/write API はそのまま動く、最も効果の高い単一修正。
2. **起動パスの重処理削減** — `reseedMasterTablesIfNeeded` (アプリ更新直後1回・約13万行を行単位 INSERT)、`reseedEventKindIfNeeded` (毎起動 ~100ms の無条件 463 UPDATE)、初回コピー時の `integrity_check` (16MB 全走査)。いずれもメインスレッド同期でホワイトスクリーンを伸ばす。ATTACH 一括コピー化 / センチネル化 / `quick_check` 化で軽減。
3. **索引の網羅性回復** — `seedMigrationHistoryIfNeeded` が v1/v2 を「適用済み」と誤マークするため、Bundle DB に焼かれていない宣言索引が新規インストールで永久に作られない構造バグ。実効的に効くのは `idx_song_artists_idol` 1本だが、`CREATE INDEX IF NOT EXISTS` を pre-mark しない新規 migration に集約するのが恒久対策。

「今すぐ安全に適用 (safeToApplyNow)」群は DB 層・保存層に閉じ、UI 改修と独立で回帰リスクが低い。「要設計判断」群は DB アクセスの async 化で、シグネチャ変更が全呼び出し側 (123箇所) に波及し View 構造変更を伴うため UI 改修と一体で扱う。

---

## 1. 深刻度順 優先実施リスト

検証後 severity と投資対効果で並べた実施順序。

| # | 項目 | severity | 区分 | 効果規模 |
|---|---|---|---|---|
| 1 | `DatabaseQueue` → `DatabasePool` 置換 (5 finding 統合) | medium | 今すぐ | 大: 同期/reseed write 中の UI read 並行化 |
| 2 | `reseedEventKindIfNeeded` のセンチネル化 (毎起動 ~100ms 除去) | medium | 今すぐ | 中: 全ユーザー毎起動の定常コスト除去 |
| 3 | `reseedMasterTablesIfNeeded` を ATTACH 一括コピー化 (13万行) | medium | 今すぐ | 中: アプリ更新直後初回起動のフリーズ解消 |
| 4 | 初回コピー時 `integrity_check` → `quick_check` | low(検証後) | 今すぐ | 小: 新規インストール初回起動 ~70ms 短縮 |
| 5 | `idx_song_artists_idol` 追加 + 索引網羅性回復 migration | medium | 今すぐ | 小〜中: idol→曲逆引き/担当曲 bulk の全走査回避 |
| 6 | `idx_unit_members_idol` 追加 | medium | 今すぐ | 小: アイドル詳細ユニット取得の全走査回避 |
| 7 | `IdolAvatarView` に Resize processor 付与 | medium | 今すぐ | 中: 一覧アバターのフル解像度デコード抑止 |
| 8 | `BulkImageImporter`/`CustomImageService` 保存時ダウンサンプリング | medium | 今すぐ | 中: ストレージ肥大とデコードコスト削減 |
| 9 | グローバル `ImagePipeline` に aggressive DataCache 設定 | low(検証後) | 今すぐ | 小: 曲アートワークの永続キャッシュ |
| 10 | `idx_events_kind` (kind, brand_id) 複合索引追加 | low(検証後) | 今すぐ | 小: イベント一覧ブランド絞り込み |
| 11 | `idx_idol_brands_brand` (brand_id, idol_id) 複合索引追加 | low(検証後) | 今すぐ | 小: ブランド別アイドル一覧 |
| 12 | songs 索引追加 (`title_kana`/`release_date`) | low(検証後) | 今すぐ | 小: 楽曲タブ既定ソート/年絞り込み |
| 13 | idols 誕生月索引 + calendar の Calendar/TimeZone hoisting | low(検証後) | 今すぐ | 小: 真因は SQL でなく Swift 側生成 |
| 14 | `idx_shows_venue` 追加 | low | 今すぐ | 極小: 会場別公演一覧 |
| 15 | `fetchUnitIndex` のアプリ寿命級メモ化 + sync 時 invalidate | low(検証後) | 今すぐ | 小: イベント詳細毎の再構築排除 |
| 16 | 楽曲ソート集計を結果セット song_id に絞る | low(検証後) | 今すぐ | 極小: 既にカバリング索引で <1ms |
| 17 | CloudKit 差分 sync の境界再クエリ早期終了 | low(検証後) | 今すぐ | 極小: 変更あり type の余分1往復削減 |
| 18 | `seedMigrationHistoryIfNeeded` の table_info 重複除去 + 早期 return | low | 今すぐ | 極小: メタデータ照会の重複排除 |
| 19 | `queryLimit` とコメント/chunkSize の不整合修正 | low | 今すぐ | なし: ドキュメント整合のみ |
| 20 | DB アクセス全体の sync → async 化 (2 finding 統合) | medium | 要設計判断 | 中: メインスレッド占有を実質ゼロに |

---

## 2. 区分分類

### A. 今すぐ安全に適用 (safeToApplyNow = true)

DB 層・保存層・画像パイプラインに閉じ、UI コードに触れず独立適用可能。回帰リスク低。

- #1 `DatabaseQueue` → `DatabasePool`
- #2 `reseedEventKindIfNeeded` センチネル化
- #3 `reseedMasterTablesIfNeeded` ATTACH 一括コピー化
- #4 `integrity_check` → `quick_check`
- #5〜#6, #10〜#14 索引追加 (新規 migration + Bundle DB 反映)
- #7 `IdolAvatarView` Resize processor
- #8 保存時ダウンサンプリング
- #9 グローバル `ImagePipeline` DataCache
- #15 `fetchUnitIndex` メモ化
- #16 楽曲ソート集計の絞り込み
- #17 CloudKit 境界再クエリ早期終了
- #18 table_info 重複除去
- #19 queryLimit コメント整合

### B. 要設計判断 (safeToApplyNow = false)

- #20 **DB アクセス全体の sync → async 化** — メソッドを `async throws` に変えるとシグネチャが変わり、全 123 箇所の呼び出し側に波及する。View body / 計算プロパティ / 同期クロージャ (例: `SongSearchScreen.searchAction`) からの呼び出しは単純 `await` 化できず `.task`/`@State` 退避という UI 構造変更が必要。**判断事項**: 「既に async/Task 文脈にある重い一覧ロード (loadSongs 等) だけ先行 async 化」する段階適用とするか、UI 全面改修とセットで一括変換するか。`@unchecked Sendable` は移行を妨げないので維持。
- 関連して **AppDatabase の遅延 async 初期化 (App を loading 状態で即描画)** も要判断。`environment(appDatabase)` の非 Optional 前提と全 View の依存を変える大改修のため、起動パスの軽量化 (#2〜#4) とは切り離す。

---

## 3. 各項目の確定修正・対象ファイル・期待効果

### #1 DatabaseQueue → DatabasePool 置換 【最重要】
- **対象**: `ImasLiveDB/Database/AppDatabase.swift:12, 53-101, 87` (`let dbQueue: DatabaseQueue` / `openDatabase` の生成 / テスト用 `init(dbQueue:)`)
- **確定修正**:
  1. プロパティ型を `DatabasePool` (理想は `any DatabaseWriter` で抽象化) に変更。
  2. `openDatabase()` の戻り値型と L87 の `DatabaseQueue(path:configuration:)` を `DatabasePool(path:configuration:)` に。
  3. テスト用 `init(dbQueue:)` の引数型を合わせる (`any DatabaseWriter` 推奨でテスタビリティ向上)。
  4. `prepareDatabase` の WAL/foreign_keys 設定は接続ごとに適用されるので現状維持で可 (Pool は WAL 必須、本コードは満たす)。
  5. `verifyIntegrityOrDelete` (L37) / bundle・tmp 用の使い捨て `DatabaseQueue` (L71, L121, `DatabaseMigrations.swift:355`) は read-only/使い捨てなのでそのまま。
  6. 全 95箇所の `.read`/`.write` 呼び出しは `DatabaseWriter`/`DatabaseReader` 共通 API なので無改修。
- **期待効果**: CloudKit 全同期 (`upsertChunked` が SetlistPerformer 72,827 / SongArtist 20,720 を単一 write tx で処理) や起動時 reseed の長尺 write 中も、一覧/詳細の read が WAL スナップショットから並行実行され体感ラグ解消。`IdolListView`/`IdolDetailView` の `async let` fan-out read が実並列化。
- **留意**: Pool reader は MVCC スナップショット分離。ただし本コードは write 完了後に画面側が再 loadData する流れ (`EventDetailView.swift:180,183`) で read-after-write を同一 tx に依存しないため回帰しない。

### #2 reseedEventKindIfNeeded のセンチネル化
- **対象**: `ImasLiveDB/Database/AppDatabase.swift:190`
- **確定修正**: 起動同期パスから外し、CloudKit sync 完了後に1回だけ走らせるのが原理的に正しい (kind 上書きは CloudKit pull 直後に起きるため)。`openDatabase()` L90 の同期呼び出しを削除し、`CloudKitSyncEngine` の pull 完了ハンドラ末尾で `Task.detached(priority:.utility)` として呼ぶ。即効策としては最低限 L90 を detached ラップに変えるだけでもメインスレッドブロックは解消。`event_kind_seed_applied` 固定フラグ方式は CloudKit の後追い上書き自己修復目的を壊すため非推奨。
- **期待効果**: 全ユーザーが毎起動で被る ~100ms (実機旧機種で数百ms) の無条件 463 UPDATE をメインスレッドから恒久除去。

### #3 reseedMasterTablesIfNeeded を ATTACH 一括コピー化
- **対象**: `ImasLiveDB/Database/AppDatabase.swift:144-185` (特に L144-151 のメモリ dump、L160-173 の行単位 INSERT)
- **確定修正**: `dbQueue.write` 内で `ATTACH DATABASE '<tmp/bundle>' AS bundle`、テーブルごとに `DELETE FROM main.t; INSERT INTO main.t(<safeCols>) SELECT <safeCols> FROM bundle.t`。`SELECT *` は使わずスキーマドリフト吸収のため `safeCols` (両側共通カラム) を明示。`masterRows` の全メモリロードも不要化。13万回の `execute` → 十数回の `INSERT...SELECT`。foreign_keys=OFF/トランザクション枠は現状踏襲。tmp copy は guard (L131) より後ろへ移動し reseed 不要時はコピーしない。
- **期待効果**: アプリ更新で data_version が bump された直後の初回起動 (約13万行: setlist_performers 72,827 / song_artists 20,720 / setlist_items 12,936 ほか) の数秒級フリーズをほぼ解消。
- **留意**: per-table do/catch + safeCols フォールバックは新方式でも維持。修正後 cold start を1回踏ませ `lastReseedStatus` (`MyPageView.swift:785`) が従来と一致することを確認。

### #4 integrity_check → quick_check
- **対象**: `ImasLiveDB/Database/AppDatabase.swift:39` (`verifyIntegrityOrDelete`、呼出 L68)
- **確定修正**: `PRAGMA integrity_check` を `PRAGMA quick_check` に変更 (正常時の `"ok"` 判定は流用可)。同期 fail-fast を保ったまま約6倍高速化 (16MB で 80ms → 13ms 実測)。detached 化案は破損 DB で一瞬走る correctness 後退を生むため不採用。
- **期待効果**: 新規インストール初回起動のみのメインスレッド占有を ~70ms 短縮。

### #5 idx_song_artists_idol 追加 + 索引網羅性回復
- **対象**: `ImasLiveDB/Database/AppDatabase.swift:963-978, 2069-2077` / `DatabaseMigrations.swift` 末尾
- **確定修正**: 新規 migration (例 `v20_ensure_indexes`) を追加し、`seedMigrationHistoryIfNeeded` に **判定を入れない** (= pre-mark させず必ず実行)。`db.create(index: "idx_song_artists_idol_role", on: "song_artists", columns: ["idol_id", "role"], ifNotExists: true)`。複合 (idol_id, role) で `fetchIdolSongs` と `fetchSongIdsWithAnyArtist` (role='original' AND idol_id IN ...) 両方をカバー。`seed_cloudkit.py` エクスポート側でも同索引を焼き二重担保。
- **期待効果**: PK (song_id,idol_id,role) では効かない idol_id 単独/先頭フィルタの song_artists 20,720 行全走査を回避。idol→曲逆引き・担当曲 bulk 絞り込みが SEARCH 化。

### #6 idx_unit_members_idol 追加
- **対象**: `ImasLiveDB/Database/AppDatabase.swift:950-960` (`fetchIdolUnits`) / `DatabaseMigrations.swift`
- **確定修正**: 上記 `v20_ensure_indexes` に `db.create(index: "idx_unit_members_idol", on: "unit_members", columns: ["idol_id"], ifNotExists: true)` を同梱。Bundle DB (`Resources/master.sqlite`) にも直接 `CREATE INDEX IF NOT EXISTS` で焼き込み、新規インストールにも効かせる。
- **期待効果**: アイドル詳細表示 (`IdolDetailView.swift:310`, `DetailSheet.swift:869`) 毎の unit_members 5,286 行 SCAN を SEARCH 化。実害は軽微だがコストゼロで確実に改善。

### #7 IdolAvatarView に Resize processor 付与
- **対象**: `ImasLiveDB/Views/Components/IdolAvatarView.swift:16-21`
- **確定修正**: `import Nuke` を追加し、body で `let px = Int(size * UIScreen.main.scale)` を算出、`LazyImage(url: url)` に `.processors([ImageProcessors.Resize(size: CGSize(width: px, height: px), unit: .pixels)])` を付与 (`ArtworkImageView.swift:27` / `IdolListView.swift:381` と同形)。理想は3者を共通の「縮小付き円形 LazyImage」に統合。
- **期待効果**: StackedAvatars/IdolGridView/EventDetailView/PerformerDetailSheet で多重使用されるアバターが、表示サイズ (20〜64pt) でデコードされ、フル解像度デコードの CPU/メモリとスクロールジャンクを抑止。size 別に縮小済みがキャッシュされる。

### #8 保存時ダウンサンプリング
- **対象**: `ImasLiveDB/Services/CustomImageService.swift:99-130` (`write`/`cropSquareNonisolated`)
- **確定修正**: `cropSquareNonisolated` 後の正方形 CGImage を `target = min(640, side)` の bitmap context (CoreGraphics、Task.detached 内なので MainActor 非依存) で描き直してから `jpegData(0.8)`。提案の `CGImageSourceCreateThumbnailAtIndex` は CGImage から直接作れないため、CGContext 描画方式を採る。
- **期待効果**: アバター最大表示 64pt(=192px@3x) に対し 640px 上限で保存。ストレージ肥大とデコードコスト両方を削減。既存保存分は遡及しないが新規/再インポートから効く。

### #9 グローバル ImagePipeline に DataCache
- **対象**: `ImasLiveDB/App/ImasLiveDBApp.swift` (`init()`)
- **確定修正**: 他の起動処理より前で `ImagePipeline.shared = ImagePipeline { $0.dataCache = try? DataCache(name: "com.fugaif.ImasLiveDB.images"); $0.dataCachePolicy = .automatic }`。`import Nuke` 追加。全 LazyImage が Resize processor 付きなので `.automatic` で元 JPEG が永続化され、再起動後はディスクから再 DL 不要。アイドル/ブランド画像はローカル file URL なので対象外 (scoping 正しい)。
- **期待効果**: 曲アートワーク (mzstatic CDN リモート URL 1,878件) の永続キャッシュ。URLCache evict 後の再 DL を回避。

### #10 idx_events_kind (kind, brand_id) 複合索引
- **対象**: `Resources/master.sqlite` / `DatabaseMigrations.swift:301`
- **確定修正**: Bundle DB に `CREATE INDEX IF NOT EXISTS idx_events_kind ON events(kind, brand_id);` を焼き、`DatabaseMigrations` の v7 宣言も複合に合わせ新 migration で既存ユーザーにも反映。反映後は CLAUDE.md の reseed workflow に従い data_version bump + journal_mode=DELETE 維持。
- **期待効果**: 単独 kind は選択性が低い (live+festival=532/829=64%) ため純利益小だが、ブランド絞り込みパスで GROUP BY 用 temp b-tree が消える。優先度低。

### #11 idx_idol_brands_brand (brand_id, idol_id) 複合索引
- **対象**: `ImasLiveDB/Database/AppDatabase.swift:918-934` / `DatabaseMigrations.swift:248`
- **確定修正**: v6 の `if !hasIdolBrands` 条件分岐から外し、新規 `v20_ensure_indexes` で無条件に `CREATE INDEX IF NOT EXISTS idx_idol_brands_brand ON idol_brands(brand_id, idol_id)`。Bundle DB にも追加。
- **期待効果**: ブランド別アイドル一覧の駆動表を idol_brands 側に反転し covering 化。データ規模 (idol_brands 365行) が極小なのでマイクロ最適化。`fetchEventAbsenceInfo`/`AbsenceSectionView` は事実上デッドコードで別途削除候補 (本修正対象外)。

### #12 songs 索引追加
- **対象**: `ImasLiveDB/Database/AppDatabase.swift:657-735, 1354-1378` / `DatabaseMigrations.swift`
- **確定修正**: `v20_song_query_indexes` で `CREATE INDEX IF NOT EXISTS idx_songs_title_kana(title_kana)`, `idx_songs_release_date(release_date)` の **2本だけ** (実効的)。Bundle DB にも焼く。song_type/cd_series は選択性低・ORDER BY title_kana 併用で効果限定。lyricist/arranger は LIKE '%name%' で b-tree を使えないため**除外**。`fetchIntroDonSongs` は ORDER BY RANDOM() で必ず full scan のためソートには効かない。
- **期待効果**: 楽曲タブ既定ソート (カナ順) と年絞り込みの SCAN+temp b-tree を改善。全件 ~6ms 規模なので体感差は小。

### #13 idols 誕生月索引 + calendar hoisting
- **対象**: `ImasLiveDB/Database/AppDatabase.swift:1414-1438, 1622-1629` / `CalendarView.swift` の `birthdayDate(for:in:)`
- **確定修正**: (a) birthMonth (LIKE '--MM-%') 用に `idx_idols_birthday ON idols(birthday)` を任意追加 (prefix index が効く)。**ただし** カレンダーの `birthday IS NOT NULL` は 344/393=87% ヒットで optimizer が索引を使わないため無効 — これは誤った期待。(b) 真のコストは `birthdayDate(for:in:)` 内で 344行ぶん毎回 `Calendar(identifier:.gregorian)`+`TimeZone(identifier:"Asia/Tokyo")` を生成している点。static な `jstCalendar` を1度だけ生成し使い回す (hoisting)。
- **期待効果**: 索引より calendar の生成 hoisting の方が実コスト (月送り毎の繰り返し全件処理) に効く。constellation/blood_type/birth_place は単発タップ導線でホットパスでなく見送り可。

### #14 idx_shows_venue 追加
- **対象**: `ImasLiveDB/Database/AppDatabase.swift:1489-1500` (`fetchShows(.venue)`) / `DatabaseMigrations.swift`
- **確定修正**: `db.create(index: "idx_shows_venue", on: "shows", columns: ["venue"], ifNotExists: true)` を新 migration に追加 (会場絞り込み導線が残る前提)。Bundle DB にも反映。ORDER BY date DESC も効かせるなら (venue, date) 複合が理想だが、391 distinct/最大89行の規模では単独で十分。
- **期待効果**: 会場タップ (`SetlistView.swift:83` → `FilteredShowsView`) の shows 1,320 行走査を SEARCH 化。実効インパクト極小。

### #15 fetchUnitIndex のメモ化
- **対象**: `ImasLiveDB/Database/AppDatabase.swift:1196-1223` (呼出 `EventDetailView.swift:261`, `SetlistView.swift:300`)
- **確定修正**: UnitIndex を AppDatabase に遅延構築のロック保護キャッシュとして保持。無効化フックを (a) CloudKit sync apply 完了 (`CloudKitSyncEngine.swift:281-290`)、(b) `reseedMasterTablesIfNeeded`、(c) units/unit_members/songs.unit_id を書き換えるローカル編集パス、の全てに付ける。呼び出し側は `fetchUnitIndex()` のまま透過的にキャッシュ返却。`fetchBrands` のメモ化は brands 9行で実益ほぼゼロのため**見送り**。
- **期待効果**: イベント詳細を開く毎の units≈1536 + unit_members≈5286 + songs DISTINCT の3辞書再構築を排除。唯一のリスクは無効化漏れの stale cache。

### #16 楽曲ソート集計の絞り込み
- **対象**: `ImasLiveDB/Database/AppDatabase.swift:748-765, 772-799`
- **確定修正**: `totalSongPerformanceCountMap` を結果セットの `song_id IN (...)` に絞り performanceCount/collectedRate ソート時のみ呼ぶ。attended 側は触らず、`fetchSongCollectedCounts()` (`SongListView.swift:413` で毎ロード実行) の結果を loadSongs 内でソートにも再利用して二重引きを避ける。提案のカウント維持テーブルは 1.3万行規模に過剰で不採用。
- **期待効果**: 既にカバリング索引で <1ms のため体感ゼロ。優先度最下位。

### #17 CloudKit 差分 sync の境界再クエリ早期終了
- **対象**: `ImasLiveDB/Services/CloudKitService.swift:55-92` (`fetchAllRecords`)
- **確定修正**: 内側 cursor ループ完了時に「最終ページ件数が queryLimit 未満」なら境界に未取得レコードなしとみなし maxDate-1ms 再クエリをスキップして break。最終ページが満杯のときだけ従来通り再クエリで境界担保。0件 type の14往復は CloudKit クエリモデル上不可避なので変更しない。recordName secondary sort 切替はスキーマ変更を伴うため別タスク。
- **期待効果**: incremental sync で変更のあった少数 type の余分1往復と、大量 seed 時の二重転送を削減。correctness バグではなく純転送節約。

### #18 seedMigrationHistoryIfNeeded の重複除去 + 早期 return
- **対象**: `ImasLiveDB/Database/AppDatabase.swift:230, 252`
- **確定修正**: (1) events の `table_info` を関数冒頭で1回取得し使い回す (`eventsColumns2` 削除)。(2) 早期 return は「件数>0」ではなく **最終シード識別子の存在** (`SELECT 1 FROM grdb_migrations WHERE identifier='v19_drop_cast'`) で判定 — v8/v9/v11/v12/v13 が未シードのサブセット設計のため「空でなければ return」は不可。
- **期待効果**: メタデータ照会の重複排除。絶対値は数ms 未満で体感影響なし。

### #19 queryLimit コメント整合
- **対象**: `ImasLiveDB/Services/CloudKitService.swift:12, 51-53`
- **確定修正**: L51-53 のコメントを実コードに合わせ「queryLimit=200」→「400 (L12 定数)」に訂正し、誤った積算モデル記述を「maxIterations は -1ms ずらし外周回数の上限であって総件数の上限ではない」に修正。`fetchByRecordNames` の chunkSize=200 (L108) は別 API のレートリミット対策なので**変更しない**。
- **期待効果**: ランタイム影響なし。ドキュメント整合のみ (将来のチューニング判断ミス防止)。

### #20 DB アクセス全体の sync → async 化 【要設計判断】
- **対象**: `ImasLiveDB/Database/AppDatabase.swift:282-2166` (約95クエリメソッド) / 呼出 123箇所 (`SongListView.swift:362,396,413` ほか)
- **確定修正方針**: (1) ホットパス (`search`, `MyPageView.loadAll` の連続7クエリ→1 read ブロックに束ねる, `fetchCalendarEntries`, `loadSongs` 系) から `func ... async throws` + `try await dbQueue.read {}` に段階移行。(2) 既に async/Task 文脈の経路は素直に await 化。(3) View body/計算プロパティ/同期クロージャ (`SongSearchScreen.searchAction`) からの呼び出しは `.task`/`onChange`+`@State` 退避という UI 構造変更が必要。(4) `@unchecked Sendable` は維持 (移行を妨げない)。
- **reason (要判断の理由)**: メソッドを async に変えるとシグネチャが全呼び出し側に伝播し、View body/同期クロージャからの呼び出しは単純 await 化不可で UI 構造変更を伴う。「重い一覧経路のみ先行」か「UI 全面改修と一括」かの設計判断が必要。実測ではデフォルト一覧 ~18ms / performerIdolsMap 全件 ~43ms (Mac値) で、実機でも最大 ~200ms 程度。フリーズではなくフレーム落ち。
- **期待効果**: SQL が GRDB 専用 DispatchQueue で実行され、結果受信時のみ MainActor 復帰。メインスレッド占有がクエリ時間 → ほぼゼロ。#1 Pool 化と組み合わせると並行性が完全に活きる。
