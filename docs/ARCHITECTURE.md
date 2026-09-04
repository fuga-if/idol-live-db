# ImasLiveDB iOS アーキテクチャ方針 (Hexagonal / Ports & Adapters)

> **この文書は iOS (`ImasLiveDB/`) の設計方針。** 他コンポーネントは別ファイル:
> - Android (`ImasLiveDB-Android/`) → [`ARCHITECTURE-android.md`](ARCHITECTURE-android.md)
> - バックエンド Worker (`imas-live-api/`) → [`ARCHITECTURE-worker.md`](ARCHITECTURE-worker.md)
> - データ所在・同期・マイグレーションの**全コンポーネント共通の思想**は本書下部「[データの所在・同期・マイグレーション](#データの所在同期マイグレーション-ios--android-共通の思想)」+ [`DATA_PIPELINE.md`](DATA_PIPELINE.md)
>
> ※ Android は iOS と同じ Hexagonal は敷かず、規模に見合った Compose+ViewModel+Repository 構成 (詳細は Android 文書)。

> 状態: **方針確定 / 段階移行中**。新規・改修コードはこの方針に寄せる。既存は触る機能から順次移行 (ビッグバン書き換えはしない)。
>
> 採用は **Hexagonal Architecture (Ports & Adapters)**。Clean / Onion と核 (依存性逆転) は同じだが、
> 「ドメイン核 + ポート + アダプタ」「2系統バックエンド = 同じポートの裏の複数アダプタ」を素直に表現でき、
> Clean の4リングより非ドグマ的なのでこの語彙を採用する。

## 現状の正直な自己評価 (この文書は「目標形」であって「完成形」ではない)

このリポジトリを最初に読む人へ。**現状は「見せかけの Clean Architecture」ではなく、進行中の Strangler 移行の途中**であることを正直に明記する。誤読を避けるため、目標と現状を切り分ける:

- **物理構成は今も単一モジュール (1 つの app target)**。下記「フォルダ構成」は SwiftPM ターゲット分割ではなく、フォルダ + 命名 + 依存ルールによる**論理分離**。Domain/Adapters/UseCases という層は**目標形**であり、全コードがそこに収まっているわけではない。
- **Repository は当面 `AppDatabase` への薄い委譲 (1:1 パススルーに近い)**。`XxxReading` ポートを切って `GRDB*Repository` が `AppDatabase` のクエリ API をそのまま呼ぶ段階で、神オブジェクトの解体はまだ途中。これは設計上の妥協ではなく、ビッグバン書き換えを避けるための**意図した中間状態**。
- **View からの `AppContainer.shared` 直参照は残っている**。合成ルート経由 (`AppContainer.shared`) は許容しているが、本来は注入で渡したい箇所がまだ `.shared` を引いている。`.shared` 撤去は使用箇所の多い順に進める途中。
- **完全に縦貫できているのは投票機能のパイロット 1 本**。他機能は「触る時に寄せる」方針で、未移行の View は従来構造のまま残る。

つまり、Domain / Ports / UseCases / Adapters というラベルは**到達目標を示す地図**であり、放棄された改修跡でも完成済みの構造でもない。各機能の実際の到達度は末尾「進捗」を参照。

## なぜやるか (この4つを同時に取りに行く)

1. **テスト容易性** — ロジックをフェイクアダプタで単体テストする。最大の payoff。
2. **ロジックの View 外出し** — 投票・カバー判定・回収集計・表記ルール等を View から剥がす。
3. **保守性・見通し** — `AppDatabase` 神オブジェクトと `.shared` 乱立を解消。
4. **将来の Android / マルチ展開** — ※下記「Android の現実」を踏まえた上で。

### Android の現実 (期待値合わせ)
Swift のコードは Android (Kotlin) と**共有できない**。再利用できるのは:
- **Worker (D1) と CloudKit のスキーマ = プラットフォーム非依存の契約**。Android も同じバックエンドを叩く。既に揃っている。
- **ドメイン核 (ポートの定義とユースケースのルール) を純粋化・文書化したもの** = Android で「写経」する設計図。

マルチ展開の準備とは「**ビジネスルールを UI/フレームワークから剥がし、ポート (契約) を明示する**」こと。Swift コードの移植ではない。

---

## 中心概念: 核・ポート・アダプタ

```
            ┌──────────── Driving (primary) ────────────┐
            │  Presentation (SwiftUI View + ViewModel)   │   ← UI もアダプタ
            └───────────────────┬───────────────────────┘
                                │ calls
                    ┌───────────▼───────────┐
                    │      Domain 核         │   Entity / UseCase
                    │   (何にも依存しない)    │
                    └───────────┬───────────┘
                                │ depends on (port = protocol)
            ┌───────────────────▼───────────────────────┐
            │  Driven (secondary) Adapters                │
            │  GRDB / Worker API / CloudKit / MusicKit    │   ← ポートの実装
            └─────────────────────────────────────────────┘
```

- **Port (ポート)** = ドメインが定義する **protocol**。外界とのやり取りの口。
  - *Driven port* (例 `CommunityVoting`, `EventReading`): ドメインが「外に依頼する」口。アダプタが実装する。
  - *Driving port* (任意): UI がドメインを叩く口。SwiftUI では ViewModel がそのまま担うので**プロトコル化は基本不要** (儀式回避)。
- **Adapter (アダプタ)** = ポートの実装。GRDB / Worker / CloudKit / MusicKit、そして UI(Presentation) も driving adapter。
- **合成ルート (`AppContainer`)** = どのアダプタをどのポートに差すかを1箇所で決める。

**依存の絶対ルール: 依存は常に Domain 核へ向く。Domain 核は何にも依存しない。**
- **Domain は `SwiftUI` / `GRDB` / `CloudKit` を import しない** (Foundation のみ)。これが守れているか = 一次検査 (`Domain/` を grep して該当 import 0)。
- アダプタ (Data / Presentation) は Domain に依存してよい。誰も Presentation に依存しない。

> **2系統バックエンドはこれで素直に表現できる**: マスタ読みポート `XxxReading` の裏に *GRDB アダプタ*、
> コミュニティ系ポート (`CommunityVoting` 等) の裏に *Worker アダプタ*。同じ核が複数アダプタを差し替えられる。

---

## 各要素の責務

### Domain 核 (純粋 Swift)
- **Entity**: データの形。**GRDB Record 構造体をそのまま Entity として使ってよい** (下記「現実的判断」)。
- **Port (protocol)**: `Domain/Ports/`。例 `CommunityVoting`, `EventReading`, `SongReading`, `Authenticating`, `MarkStore`。
- **UseCase**: `Domain/UseCases/`。**非自明なビジネスルールがある時だけ**作る (カバー判定・投票可否・回収集計等)。
  - ⚠️ 単純な CRUD passthrough に UseCase を噛ませない。その場合 ViewModel がポートを直接呼ぶ。

### Adapters (ポートの実装)
- **Persistence (GRDB)**: `AppDatabase` を**ドメイン別 Repository に分割**し、各 `XxxReading` ポートを実装。`DatabaseQueue` を共有。
- **Remote (Worker)**: `CommunityAPI` が `CommunityVoting` 等を実装 (`extension CommunityAPI: CommunityVoting {}`)。
- **Infrastructure**: CloudKit 同期・`CKRecordMapper`・MusicKit ラッパ。**過度にポート化しない** (CloudKit 同期の抽象化は破綻するので据え置き)。

### Presentation = Driving Adapter (SwiftUI)
- **ViewModel** (`@Observable`): ポート (protocol) にのみ依存し、注入で受け取る。View の `init` (nonisolated) から生成するため **VM の `init` も `nonisolated`**。
- **View**: ViewModel にのみ依存。**View 内で `AppDatabase` 直叩き・`XxxService.shared` 到達を禁止** (合成ルート `AppContainer.shared` 経由は可)。

### Composition Root (`AppContainer`)
- 具象アダプタを1箇所で組み立て、ポートとして供給。`XxxService.shared` 直参照 (MusicKit 56 / APIClient 46 / Auth 42 / Community 35 / UserMark 26 …) はここへ寄せる。

---

## データの所在・同期・マイグレーション (iOS / Android 共通の思想)

> ⚠️ **iOS と Android は「同じ DB」を見ていない。** 各端末・各プラットフォームが**自分専用のローカル DB** を持ち、共有しているのは**クラウド側の唯一の正だけ**。ここを取り違えるとデータフローを誤解する。

```
        ┌──── source of truth (共有・クラウド) ────┐
        │  CloudKit Public DB … マスタ + 構造化コミュニティ │
        │  Worker D1 (SQLite) … 集計系コミュニティ          │
        └───────────────┬─────────────────────────┘
            差分 sync で取り込む │ (各アプリが自分のローカルへ)
        ┌──────────────┴───────────────┐
   iOS: GRDB (master.sqlite)      Android: Room (master.sqlite)
   ← 別ファイル・別実装・別スキーマ定義・別マイグレーション
```

### 原則
1. **クラウド (CloudKit / D1) が唯一の正。** ローカル DB は「クラウドのキャッシュ/ミラー」。だから**マスタは破壊的に作り直しても CloudKit から再同期で戻る**。
2. **ローカル DB は各プラットフォームで独立。** iOS=GRDB / Android=Room。テーブル構成は意図的に揃えるが、同一ファイルでもエンジンでもない。**スキーマ変更時の移行も両方で対に書く** (iOS: `DatabaseMigrations`(GRDB) / Android: Room `Migration`)。これが「iOS↔Android 1:1 横展開」の実体の一部。
3. **「クラウドに無いローカル唯一データ」を破壊から守る。** `UserMark` (担当 / お気に入り) は CloudKit にもサーバにも無く、**端末ローカル限定** (現状クラウド同期もしない)。マスタと同居していても、スキーマ更新で**消してはいけない**。

### マイグレーション規律 (絶対)
- **破壊的マイグレーション (Android `fallbackToDestructiveMigration` / iOS で DB 削除) は使わない。** これをやると `UserMark` 等のローカル唯一データが無言で消える。
- スキーマを変えたら **iOS (GRDB) と Android (Room) の両方に移行を 1 本ずつ書く**。マスタテーブルは migration 内で drop+recreate して CloudKit 再同期に委ねてもよいが、**ローカル唯一データは必ず保全する**。
- 過去にこの規律が無く、Android が `fallbackToDestructiveMigration` で担当/お気に入りを消す地雷を抱えていた → 単一 DB + 実マイグレーション方式に統一して解消済み (2026-06)。

---

## ラベルより効く2原則 (これを外すと「なんちゃってレイヤー」)

1. **機能で縦に切る (feature vertical slice) を第一、レイヤーは第二。**
   「VM は全部ここ、Repository は全部あそこ」と水平に積まない。`Polls/` の中に View+VM が同居する形を維持。
2. **儀式は「元が取れる所」にだけ。** trivial CRUD に空っぽの VM/UseCase を被せない (転送するだけの層はアンチパターン)。

---

## 現実的判断 (ドグマ回避の明文化)

1. **マスタの Entity と GRDB Record を二重定義しない。** Record を Entity 兼用。依存方向は「Domain/UseCase は GRDB クエリ API を呼ばず、ポート越しのみ」で守る。
2. **コミュニティ DTO は既に分離済み** (`Poll` 等)。維持。
3. **CloudKit 同期エンジンはポート化しない。** インフラ詳細として据え置き。
4. **trivial CRUD に UseCase を作らない。**
5. **driving port (UI→ドメインの口) は基本プロトコル化しない。** ViewModel が兼ねる。
6. **物理モジュール分割 (SwiftPM ターゲット) は当面しない。** フォルダ + 命名 + 依存ルールで論理分離。効いてきたら検討。

---

## フォルダ構成 (目標)

```
ImasLiveDB/
├── Domain/
│   ├── Entities/          # = 現 Models (GRDB Record 兼用)
│   ├── Ports/             # protocol (driven ports)。例 CommunityVoting
│   └── UseCases/          # 非自明ルールのみ
├── Adapters/
│   ├── Persistence/       # AppDatabase 分割後の *Repository (XxxReading 実装) + Migrations
│   ├── Remote/            # CommunityAPI, APIClient (Worker アダプタ)
│   └── Infrastructure/    # CloudKitSyncEngine, CKRecordMapper, MusicKit ラッパ
├── Presentation/          # SwiftUI = driving adapter。機能単位 (現 Views/ を踏襲)
│   ├── <Feature>/         #   View + ViewModel
│   └── Components/        #   共通 UI + 表示ユーティリティ
├── DesignSystem/          # 既存 (DS トークン・Imasコンポーネント) 据え置き
└── App/
    ├── AppContainer.swift # 合成ルート (ポートにアダプタを差す)
    └── ImasLiveDBApp.swift
```

> 既存ファイルの物理移動は段階的。まず Domain/Ports に新規ポートを置き、`Views/` → `Presentation/`、
> `Services/`・`Database/` → `Adapters/` は触る機能から寄せる。

---

## テスト戦略 (これが無いと意味が薄い)
- **テストターゲット `ImasLiveDBTests`** (導入済)。
- UseCase / ViewModel を **フェイクアダプタ** で単体テスト (例: `FakeCommunityVoting`)。
- ポートがあるおかげで Preview にもフェイクを差して安定化できる。
- リファクタは**「移行 + その機能のテストを書く」をセット**で。

---

## 移行戦略 (Strangler / 機能単位)

1. **パイロット (済): 「みんなの投票」** を縦に1本貫いて型を確立。
   `CommunityVoting` ポート → `CommunityAPI` アダプタ → `Poll*ViewModel` → View → 単体テスト11本。
2. 型が固まったら横展開。**触る機能から寄せる**。
3. 並行して `AppDatabase` を `XxxReading` ポート + Repository アダプタへ薄く割る (一度に全部やらない)。
4. `.shared` は使用箇所の多い順に `AppContainer` 注入へ移す。

### 進捗 (2026-06)
- **投票機能**を縦に1本貫通 (`CommunityVoting` + `CommunityAPI` + `Poll*ViewModel` 3本)。
- **読みポート 12 + 書きポート 4 + CommunityVoting = 16 ポート**。各 `GRDB*Repository` が `AppDatabase` へ委譲 (Strangler, `nonisolated async` でオフメイン)。View 層の `AppDatabase` 直叩き (fetch/search/upsert/replace/raw dbQueue) は **0 件**。
- **純粋 UseCase 4本** (`EventGrouping` + 3リストフィルタ)。絞り込み・グルーピングは DB 非依存で単体テスト済。
- **List/Detail の正式 ViewModel 化 (済)**: 3リスト (`IdolListViewModel` / `SongListViewModel` / `EventListViewModel`) + 2詳細 (`EventDetailViewModel` / `IdolDetailViewModel`)。いずれも `@MainActor @Observable final class` + `nonisolated init` でポート注入。View は `@AppStorage`・選択状態・`@Observable` サービス観測 (UserMark/CustomImage) のみ保持し、Request/Context/Query 構造体で条件を VM へ渡す。`SongDetailView` は薄いラッパ (データ取得なし) のため VM 不要。
- **テスト 36本** 全パス (投票11 + フィルタ/グルーピング22 + IdolListViewModel 3)。

### 進捗 (2026-07)
- **タグ機能 (Views/Tags/ 13ファイル) をポート化**: `CommunityTagReading` (13メソッド) + `CommunityTagWriting` (12メソッド) を新設し、`extension CommunityAPI: CommunityTagReading/CommunityTagWriting {}` で適合、`AppContainer` に登録。`CommunityAPI.shared` 直叩きは Views/Tags 配下で **0 件**。
  - **ポート総数 19** (読み12 + 書き4 + CommunityVoting + CommunityTagReading + CommunityTagWriting)。
  - **VM 化 (4画面)**: `TagListViewModel` (一覧+フィルタ+検索デバウンス)、`SongTagPickerViewModel` / `IdolTagPickerViewModel` / `UnitTagPickerViewModel` (検索デバウンス+選択+付与+曲版はシェア導線組立)。いずれも `Poll*ViewModel` と同じ `@MainActor @Observable` + `nonisolated init` + ポート注入の型。
  - **VM を導入しなかった9画面**: `TagDetailView` 系3画面・`TagCreateSheet`・`TagEditSheet`・`TagHistoryView`・`TagActivityView`・`TagFilterPicker`・`TagColorPicker`。「fetch+display」または「1回のCRUD呼び出し+dismiss」のみで、既存の `MyVotesView`(フェッチ+多ソース解決、VM無し) / `PollCreateSheet`(単発作成、VM無し) / `PollHallOfFameView`(フェッチのみ、VM無し) と同等の複雑度のため、View から `AppContainer.shared.communityTagReading/communityTagWriting` を直接呼ぶ既存パターンに揃えた (ドキュメント上の許容: 「View: ViewModel にのみ依存 (合成ルート `AppContainer.shared` 経由は可)」)。`TagColorPicker` はそもそもデータ取得を持たない純 UI 部品。
- **レイヤ違反の機械チェックを CI 化**: `tools/check_domain_purity.sh` を `.github/workflows/architecture-guard.yml` として push(main/develop)/PR 時に実行するようにした (`ImasLiveDB/Domain/**` 変更時)。違反があれば exit 1 でジョブが落ちる。
- **`AppDatabase` の神オブジェクト解体 (第一段)**: 3,770 行 / 173 関数だった `Database/AppDatabase.swift` を、
  **起動時 DB セットアップ + reseed だけの 364 行**に縮めた。クエリ群は MARK 境界をそのまま分割線にして
  `AppDatabase+<領域>Queries.swift` (Event / Song / Idol / Stats / Calendar / Sync / UserMarks の 7 ファイル) へ
  **純粋移動**した (シグネチャ・本文・順序・コメントは不変)。
  - 分割線は「`private` メンバーの実依存」で引いた。`hasSetlistCondition` / `eventWithDate` を共有する
    Event Queries と Filtered Fetch は同じファイル、`realLiveKinds` を共有する Auto Collected と
    Collection Dashboard も同じファイル。**アクセス修飾子を緩めて分割線を通すことはしない**
    (`private` → `internal` が必要になったら分割線の方が間違っている)。
  - これは Repository へクエリ実体を移す作業の前段。Repository が `AppDatabase` へ 1:1 委譲している
    中間状態は**意図通りのまま**で変えていない。
  - 併せて、`fooAsync()` と対で存在しながらどこからも呼ばれていない同期版 **54 個 (253 行)** を削除した
    (実体は共通の `private static func fooQuery` なので実装は 1 つも失われていない)。残るペアは 34 組。
- **マイグレーション追加規約を明文化**: 既適用判定に旧方式 (`seedMigrationHistoryIfNeeded` の事前挿入) と
  新方式 (マイグレーション本体を冪等に書く) が混在していたため、**v23 以降は新方式**と
  `DatabaseMigrations.swift` の先頭に固定した。旧方式のロジックは互換のため不変。
- **Worker の型チェックを CI 化**: `imas-live-api` は `tsc --noEmit` が通っていなかった (TS2304)。
  修正のうえ `npm run typecheck` を追加し、`.github/workflows/worker-guard.yml` で
  typecheck + `wrangler deploy --dry-run` を回すようにした。
- **iOS / Android のビルド・テストも CI 化**: `ios-guard.yml` (macos, xcodegen → `tools/build_db.sh`
  → `xcodebuild test`) と `android-guard.yml` (ubuntu, JDK 21, `assembleDebug` + `test`) を追加。
  公開リポジトリなので macOS runner も無料枠で、ランニングコスト 0 制約に抵触しない。
  シミュレータ名は runner イメージで変わるため `tools/pick_simulator.py` で実在するものを選ぶ。
  署名はアドホック (`CODE_SIGN_IDENTITY="-"`)。`CODE_SIGNING_ALLOWED=NO` にすると Keychain が
  `SecItemCopyMatching -34018` で失敗しテストが落ちるので使わない。
- **Worker の単一ルーターを分解 (第一段)**: `imas-live-api/src/index.ts` を **4,271 → 3,073 行**に縮めた。
  - 共有基盤を持ち主のモジュールへ: `env.ts` (Env 型) / `auth.ts` (Apple・Google・セッション JWT +
    `getAuthUser`) / `users.ts` (`upsertUser` / `checkIsAdmin`) / `validation.ts` (入力バリデータ) /
    `rate_limit.ts` (IP レート制限・`VOTE_LIMIT`)。
  - ルート群を `routes/` へ: `device_aggregates.ts` (`/favorites/*` `/penlight/*`)、`polls.ts` (`/polls/*`)。
    `handleXxx(ctx): Promise<Response | null>` で未一致なら元の if チェーンへ戻す形。
  - **不正 JSON の 500 を全 19 箇所で 400 に統一**。`docs/ARCHITECTURE-worker.md` の既知課題を解消。
  - 切り出し手順と検証方法は [`ARCHITECTURE-worker.md`](ARCHITECTURE-worker.md) に明文化した。
- **Worker の単一ルーターを分解 (第二段)**: さらに `routes/tags.ts` (タグ 3 プール + 類似、1,281 行) と
  `routes/setlist_predictions.ts` (予想セトリ / 出演者予想 / いいね、472 行) を切り出し、
  **`index.ts` は 4,271 → 1,256 行 (−71%)**。残るのは横断的関心事と `/auth/*` `/admin/*` `/edits` 系。
- **D1 スキーマの drift を 2 件検出**: `setlist_song_likes` は `CREATE TABLE` がどの migration にも
  無く (`0025` で補完)、`setlist_predictions` 系は migration が `event_id` なのにコードは `show_id`
  (未解決)。**`migrations/` だけから作った D1 は本番と一致しない。** 詳細と対処方針は
  [`ARCHITECTURE-worker.md`](ARCHITECTURE-worker.md) の「D1 スキーマの drift」節。

### 進捗 (2026-09) — コールガイド ダッシュボード
- **コールガイドの整備状況を読むポートを新設**: `CallGuideDashboardReading` (1メソッド) +
  `extension CallGuideAPI: CallGuideDashboardReading`、`AppContainer.callGuideDashboardReading` に登録。
  DTO はポートと同じファイルに同居させた (`LyricsSearchReading` の前例に揃える。「この応答に
  歌詞・コール本文を足してはいけない」という契約上の警告と DTO 定義を離さないため)。
  **ポート総数 20**。画面は `Views/CallGuideDashboard/` (`@MainActor @Observable` VM + View)。
  曲一覧の「コールガイドがある曲のみ」は Swift 前段で絞らず、解決済み集合を
  imas-core の `SongListFilterCriteria.call_guide_song_ids` へ渡す (タグ集合と同じ位置・同じ流儀)。
  取得失敗時は集合を渡さない (絞り込みを適用しない) 失敗規約もタグ側と揃えた。
- **Android は対象外**: Android 版には歌詞・コール機能自体が無い (`SongDetailScreen.kt` は
  `lyrics_url` リンクのみ) ため、「iOS の変更は必ず Android へ 1:1 横展開」の原則の適用外。
  ダッシュボード画面・曲一覧フィルタ・**内蔵お知らせも iOS のみ**。Android へ歌詞機能を移植する
  ときに、この節ごと持っていくこと。

### レイヤ違反の検査
- `Domain/` 配下で `import SwiftUI|GRDB|CloudKit` を grep して 0 を保つ。**`tools/check_domain_purity.sh`** が自動チェック (違反で exit 1)。pre-commit / CI 組み込み候補。

---

## やらないことリスト
- ビッグバン書き換え / 全 View 一斉改修。
- マスタ Entity の DTO 二重定義。
- CloudKit 同期のポート化。
- trivial CRUD の UseCase 化 / 空っぽの転送レイヤ。
- 2系統バックエンド境界 (CloudKit マスタ / D1 集計) の変更。ランニングコスト0制約も不変。
