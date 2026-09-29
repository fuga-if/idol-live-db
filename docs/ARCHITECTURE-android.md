# ImasLiveDB Android アーキテクチャ

> iOS の設計方針は [`ARCHITECTURE.md`](ARCHITECTURE.md)、バックエンドは [`ARCHITECTURE-worker.md`](ARCHITECTURE-worker.md)。
> データの所在・同期・マイグレーションの**両プラットフォーム共通の思想**は
> [`ARCHITECTURE.md`](ARCHITECTURE.md#データの所在同期マイグレーション-ios--android-共通の思想) を参照。

## 立ち位置

**iOS (ImasLiveDB) のコア機能サブセットを Jetpack Compose で部分移植した版。** ライブ/楽曲/アイドル/
セトリ閲覧・CloudKit 差分同期・基本的なコミュニティ表示は動く。編集/投稿・モデレーション・予想・
通知・共有・ゲーム・App Attest 等は未移植 (iOS 優先で進め、`/sync-ios-to-android` で順次横展開)。

iOS のような Hexagonal/Ports&Adapters は敷いていない。**Compose + ViewModel + Repository + 手動DI** の
素直な構成。規模が iOS より小さいため過剰な抽象化を避けている。

## 技術スタック

- **UI**: Jetpack Compose (Material3)
- **DB**: Room (SQLite)。iOS の GRDB に対応するローカルミラー
- **画像**: Coil
- **音声プレビュー**: ExoPlayer (`player/`)
- **ネットワーク**: **手書き `HttpURLConnection` + `org.json`** (Retrofit/OkHttp は不使用。OkHttp は Coil 推移依存のみ)
- **DI**: 手動 DI (`di/AppModule` のシングルトン。Hilt 不使用)

## パッケージ構成 (2026-09-23 実測)

```
com.fugaif.imaslivedb/
├── ui/                  # Compose 画面 (機能別。23 サブパッケージ)
│   ├── events/ idols/ songs/ units/ polls/ produce/
│   ├── schedule/ search/ settings/ stats/ mastery/ tags/ ledger/ introdon/ …
│   ├── components/      # 共通 Composable
│   ├── navigation/      # NavHost / ルート
│   └── theme/           # Material3 テーマ (iOS の ImasTheme に対応)
├── data/                # 14 サブパッケージ
│   ├── model/           # Room エンティティ (Brand/Song/Event/Idol/UserMark 等)
│   ├── db/              # AppDatabase + dao/   (単一 Room DB)
│   ├── repository/      # 画面が使うデータ取得 (DAO を束ねる。マスタ読みはスナップショット経由が主)
│   ├── core/             # SnapshotStoreProvider / SnapshotHydration (imas-core のスナップショットを
│   │                     #   ロードして FFI 越しにマスタを読む層。iOS の CoreSnapshotManager に相当)
│   ├── net/              # WorkerHttpClient (Worker への HTTP を 1 本に集約)
│   ├── sync/             # CloudKitClient + CloudKitSyncEngine (CloudKit S2S 差分同期)
│   └── community/        # CommunityApi・DeviceIdentity (Worker D1 への HTTP、device 識別)
├── di/                  # AppModule (手動 DI コンテナ・シングルトン)
├── widget/              # ホーム画面ウィジェット (担当画像等。マスタ読みはスナップショット経由)
└── player/              # ExoPlayer 音声プレビュー
```

サブパッケージ数は変わりやすいので目安。正確な現状は `find app/src/main/kotlin/.../ui -maxdepth 1 -type d` 等で確認すること。

## データフロー (iOS と同一思想)

- **マスタ**: CloudKit Public DB が唯一の正。`CloudKitSyncEngine` が S2S read-only トークン
  (`BuildConfig.CLOUDKIT_API_TOKEN`、`local.properties`/env から注入) で差分取得 → Room に投入。
  初回や空DB時は全件フル同期 (`brandCount()==0` 判定)。
  **画面がマスタを読む経路はスナップショット (`data/core/SnapshotStoreProvider` が imas-core の
  スナップショットをロードし、`data/repository/SnapshotRecordMappings` で Room モデルへ射影) が主で、
  Room への生 SQL フォールバックは無い** (X-01 / Q-04、2026-09 のリファクタで廃止。以前は
  スナップショット未ロード時に DAO の SQL へ落ちていたが、今は読み込み待ちにする。ネイティブ
  (imas-core) 無しで動く構成は要件から外れた)。
- **集計系コミュニティ** (タグ/投票/お気に入り 等): `data/net/WorkerHttpClient` (Worker への HTTP を
  1 本に集約) 経由で `CommunityApi` が Worker (D1) を都度叩く。リクエストヘッダは
  `X-Device-Id` (常時) と、ログイン済みなら `Authorization: Bearer <セッション JWT>` の両方を付ける
  (`WorkerHttpClient.kt`。「X-Device-Id のみ」ではない)。
- **`UserMark`** (担当/お気に入り): クラウドに無い**端末ローカル唯一データ**。Room の同一DBに同居するが、
  **破壊的マイグレーション禁止** (スキーマ変更時は Room `Migration` を書いて保全)。詳細は共通思想を参照。

## iOS との対応 (1:1 横展開の指針)

| iOS | Android |
|---|---|
| SwiftUI View | Compose 画面 (`ui/<機能>/`) |
| `@Observable` ViewModel | `ViewModel` + `StateFlow` |
| GRDB `AppDatabase` / Repository | Room `AppDatabase` + DAO / `data/repository` |
| `CloudKitSyncEngine` (GRDB) | `data/sync/CloudKitSyncEngine` (Room) |
| `CommunityAPI` | `data/community/CommunityApi` |
| `AppContainer` (Composition Root) | `di/AppModule` (手動 DI) |
| GRDB `DatabaseMigrations` | Room `Migration` (**対で書く**) |

## 既知の改善余地 (2026-09-23 時点)

- ネットワーク層が手書き `HttpURLConnection` → 型安全性が無い。Retrofit/Ktor + kotlinx.serialization 化が望ましい。
- **App Attest 相当 (Play Integrity) が未実装。** コミュニティ書き込みは `X-Device-Id` + (ログイン
  済みなら) `Authorization: Bearer` を付けるが、iOS の App Attest に相当するアプリ実体の検証は
  Android 側に無い。防御は Worker 側のレート制限/device 重複排除頼み。
- 一部 ViewModel に N+1 フェッチ (`PollsViewModel`)。並列化余地。
