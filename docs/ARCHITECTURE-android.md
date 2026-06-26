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

## パッケージ構成

```
com.fugaif.imaslivedb/
├── ui/                  # Compose 画面 (機能別)
│   ├── events/ idols/ songs/ units/ polls/ produce/
│   ├── schedule/ search/ settings/ stats/
│   ├── components/      # 共通 Composable
│   ├── navigation/      # NavHost / ルート
│   └── theme/           # Material3 テーマ (iOS の ImasTheme に対応)
├── data/
│   ├── model/           # Room エンティティ (Brand/Song/Event/Idol/UserMark 等)
│   ├── db/              # AppDatabase + dao/   (単一 Room DB)
│   ├── repository/      # 画面が使うデータ取得 (DAO を束ねる)
│   ├── sync/            # CloudKitClient + CloudKitSyncEngine (CloudKit S2S 差分同期)
│   └── community/       # CommunityApi (Worker D1 への HTTP)
├── di/                  # AppModule (手動 DI コンテナ・シングルトン)
└── player/             # ExoPlayer 音声プレビュー
```

## データフロー (iOS と同一思想)

- **マスタ**: CloudKit Public DB が唯一の正。`CloudKitSyncEngine` が S2S read-only トークン
  (`BuildConfig.CLOUDKIT_API_TOKEN`、`local.properties`/env から注入) で差分取得 → Room に投入。
  初回や空DB時は全件フル同期 (`brandCount()==0` 判定)。
- **集計系コミュニティ** (タグ/投票/お気に入り 等): `CommunityApi` が Worker (D1) を都度 HTTP で叩く。
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

## 既知の改善余地 (公開時点)

- ネットワーク層が手書き `HttpURLConnection` → 型安全性が無い。Retrofit/Ktor + kotlinx.serialization 化が望ましい。
- コミュニティ書き込みが `X-Device-Id` のみ (iOS の App Attest 相当が未実装)。防御は Worker 側のレート制限/device 重複排除頼み。Play Integrity 導入が今後の課題。
- 一部 ViewModel に N+1 フェッチ (`PollsViewModel`)。並列化余地。
