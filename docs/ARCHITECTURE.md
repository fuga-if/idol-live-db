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
- 具象アダプタを1箇所で組み立て、ポートとして供給。`XxxService.shared` 直参照 (実測 2026-09-23: MusicKit 61 / APIClient 74 / Auth 50 / Community 23 / UserMark 42) はここへ寄せる。

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
- **List/Detail の正式 ViewModel 化 (済)**: 3リスト (`IdolListViewModel` / `SongListViewModel` / `EventListViewModel`) + 2詳細 (`EventDetailViewModel` / `IdolDetailViewModel`)。いずれも `@MainActor @Observable final class` + `nonisolated init` でポート注入。View は `@AppStorage`・選択状態・`@Observable` サービス観測 (UserMark/CustomImage) のみ保持し、Request/Context/Query 構造体で条件を VM へ渡す。`SongDetailView` は薄いラッパ (データ取得なし) のため VM 不要 (2026-09-23 実測: 呼び出し元 0 件で未参照。`Views/Songs/SongDetailView.swift` を触る前に呼び出し経路を再確認すること)。
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
  **ポート総数 26** (`ImasLiveDB/Domain/Ports/` の `protocol` 宣言を数えた実数。
  「進捗 (2026-07)」の 19 は当時の数え漏れで、実際は歌詞・コール系 (`LyricsReading` /
  `LyricsSearchReading` / `SongDetailReading` / `CallGuideWriting` 等) が入っていなかった)。
  画面は `Views/CallGuideDashboard/` (`@MainActor @Observable` VM + View)。
  曲一覧の「コールガイドがある曲のみ」は Swift 前段で絞らず、解決済み集合を
  imas-core の `SongListFilterCriteria.call_guide_song_ids` へ渡す (タグ集合と同じ位置・同じ流儀)。
  取得失敗時は集合を渡さない (絞り込みを適用しない) 失敗規約もタグ側と揃えた。
- **Android は対象外**: Android 版には歌詞・コール機能自体が無い (`SongDetailScreen.kt` は
  `lyrics_url` リンクのみ) ため、「iOS の変更は必ず Android へ 1:1 横展開」の原則の適用外。
  ダッシュボード画面・曲一覧フィルタ・**内蔵お知らせも iOS のみ**。Android へ歌詞機能を移植する
  ときに、この節ごと持っていくこと。

### 進捗 (2026-09-24) — 歌詞クイズ
- **クイズ・ゲームに「歌詞クイズ」を追加** (iOS)。形式は 2 つ: 曲名当て (歌詞 1 行 → 曲名 4 択) と
  続きはどれ (曲名 + 歌詞 1 行 → 次の行 4 択、誤答は同じ曲の別の行)。採点はソロ曲クイズと同じ 3/2/1pt。
- 規則は `imas-core/src/domain/lyrics_quiz.rs` (出題順・曲名当ての 4 択・歌詞のどこを出すか・
  続きはどれの 4 択・50:50・ヒント・採点)。FFI は `inbound/lyrics_quiz.rs`。
- 母集団は Worker の `GET /lyrics/published` (公開中の song_id だけ。本文を含まないのでエッジキャッシュ可)。
  歌詞本文は出題のたびに `GET /songs/:id/lyrics` で 1 曲ずつ取る (先読みは次の 1 問まで)。
  ポート `LyricsQuizReading` (`extension LyricsAPI: LyricsQuizReading`)、**ポート総数 27**。
  振り返り・リザルト・シェアは曲名だけで組み、歌詞を載せない。
- **Android は対象外** (上の「コールガイド ダッシュボード」と同じ理由: Android に歌詞機能が無い)。
  コアは共有済みなので、Android へ歌詞の取得経路と JASRAC 掲示を移植するときに画面だけ足せばよい。

### 進捗 (2026-09-07) — アイドルの短縮名をコアへ
- **短縮名の規則 (nickname > given_name > name) を `imas-core` 1 本に**: `domain/snapshot.rs` の
  `idol_short_name` が正で、FFI へは `inbound/idol_queries.rs` の `idol_short_name` として出す
  (`theme_derive` と同じ「純粋な規則を 1 本の関数で出す」形。レコードではなく素の 3 列で受けるので、
  GRDB / Room から直に引いた行からも引ける)。
  `Idol.shortName` (Swift) と `Idol.shortName` (Kotlin) は、その呼び出しだけになった。
- **直した実害**: 規則は Swift に手書きされ、Android には**そもそも無かった**ため、Android の
  アバターは全部フルネームを丸に詰めていた (「アスラン=ベルゼビュートⅡ世」等)。
  Android のアイドルのアバター 17 箇所を `idol.shortName` に揃え、iOS と 1:1 にした
  (ユニットのアバターは対象外)。
- Web も同じ規則を使う (`web_export/emit/glyph.rs::idol_monogram` が `Idol::short_name` を
  4 文字までに切る)。**3 プラットフォームで顔の文字が一致する。**

### 進捗 (2026-09-23) — SQL フォールバック廃止・reseed の allow-list 化・コアへの規則移送

大規模リファクタ (指示書 `refactor-instructions.md` の P2〜P6・Q-01〜Q-16) で、マスタの読みと
reseed の判断がさらにコアへ寄った。

- **マスタ読みの SQL フォールバックを廃止 (X-01 / Q-04)。** それまで両 OS とも「スナップショット
  (Rust 側でロード済みの全件メモリ表) が無ければ GRDB / Room への生 SQL に落ちる」という二重経路
  だったが、**フォールバックを消し、スナップショット未ロードの間は読み込み待ちにする**方針に統一した
  (iOS はコミット `bf157c75`、Android は `f6ca2acf`)。ネイティブ (imas-core) 無しで動く Android 環境は
  要件から外れた。メモリ警告時にスナップショットを unload することもしない。「Repository は
  `AppDatabase` への薄い委譲」という本書冒頭の記述は、マスタ読みに関する限りこの変更で
  「スナップショット 1 経路」に単純化されている (投票等の集計系コミュニティ API 呼び出しは対象外)。
- **reseed で入れ直す対象表を、コアのマスタスキーマ台帳からの allow-list で決める (P5-05)。**
  `reseed_master_target_tables(bundleTables:localTables:)` が `schema_ddl::table_names()`
  (= `master_schema.sql` の表一覧) にあり、かつ同梱 DB と端末の両方に実在する表だけを
  同梱 DB の並びで返す。`sqlite_` 前置と `meta` は除く。`user_marks` / `personal_tags` /
  `expenses` / `song_videos` のようなローカル唯一データは台帳に無いので、同名の表が
  同梱 DB に紛れ込んでも reseed の対象にならない。旧実装の `untouchedTables` (スキーマ適用の
  結果に依存する保護表の組み方) には依存しないため、スキーマ適用に失敗した端末でも reseed が
  止まらなくなった。共通列 (`reseed_common_columns`) と要約文言 (`reseed_summary_label`) も
  同じコアの関数に統一。
- **コアに移した表示・判断規則の一覧。** このリファクタで iOS / Android の手書きロジックの
  多数をコア (`imas-core/src/domain/`) の純粋関数へ移送し、両 OS から FFI 経由で呼ぶ形に揃えた
  (セトリの区切り見出し・オリメン札・プロフィール整形・ブランド色解決・語彙 (曲種別/催しの種別/
  参加形態/タグカテゴリ)・通知の予定表・週表示のレイアウト・検索行の説明文・回収ダッシュボード・
  出演状況の塊・イントロドンの得点規則・YouTube URL 解析・色の読み上げ名・チケット代を聞くかの
  判断・会場と年のグルーピング・次の出演/似ているアイドルの選び方・入力欄の文字数上限と投票の
  数え方・共有文面・バックアップの対象行・「最近見たもの」の並べ替え・ライブ名の短縮 等)。
  移送の考え方はリポジトリの `CLAUDE.md`「着手時に最初に決めること」と同じ:
  「OS SDK に触らないと書けないものだけが各 OS 側、それ以外の判断は全部コア」。
  1 件ごとの FFI 差分・置き換え箇所・挙動が変わる点は `git log` のコミットメッセージ
  (`R-A-*` / `R-B-*` / `R-C-*` / `Q-08*` の ID で検索可能) と、各コミットに対応する
  core-rules チームの配線メモを参照。
- **LLM 向けツール面 (MCP サーバ / CLI) を `feature = "agent"` に隔離 (D-CORE-14 / Q-16)。**
  `imas-core/src/agent/` (ツールのカタログ・応答の組み立て・入出力) は既定 off の Cargo feature
  で、iOS / Android のビルド (既定 feature set) には一切コンパイルされない。詳細は
  [`ARCHITECTURE-mcp.md`](ARCHITECTURE-mcp.md)。
- **テストの既定 DB を `db/master.sql` からの復元にした (P6-01)。** 実データを読む Rust の
  テストは `test_support::test_db` に集約され、既定で `db/master.sql` を SQLite に復元した
  ものを読む (`IMAS_CORE_TEST_DB` で差し替え可能)。CI とローカルが同じ入力でテストするため、
  「CI は緑・手元は赤」のような環境差を減らす。

### レイヤ違反の検査
- `Domain/` 配下で `import SwiftUI|GRDB|CloudKit` を grep して 0 を保つ。**`tools/check_domain_purity.sh`** が自動チェック (違反で exit 1)。**CI 組み込み済み** (`.github/workflows/architecture-guard.yml`。`ImasLiveDB/Domain/**` 変更時に push(main/develop)/PR で実行)。

---

## やらないことリスト
- ビッグバン書き換え / 全 View 一斉改修。
- マスタ Entity の DTO 二重定義。
- CloudKit 同期のポート化。
- trivial CRUD の UseCase 化 / 空っぽの転送レイヤ。
- 2系統バックエンド境界 (CloudKit マスタ / D1 集計) の変更。ランニングコスト0制約も不変。
