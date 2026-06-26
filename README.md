# ImasLiveDB

アイドルライブのセットリストを記録・検索する非公式ファンメイドのデータベースアプリ。
iOS / Android ネイティブアプリと、それを支える Cloudflare Worker バックエンドで構成される。

> **非公式・ファンメイド** — 本プロジェクトはいかなる公式運営とも関係がありません。
> キャラクター画像・歌詞・公式ロゴは一切収録せず、ジャケット画像は Apple MusicKit API 経由でのみ表示します。

---

## ライセンス / 利用条件

- **非商用ライセンス（[PolyForm Noncommercial 1.0.0](LICENSE.md)）** — 個人利用・改変・再配布は自由ですが、**商用利用は許可しません**（非公式ファンプロジェクトのため）。
- ソースは公開（source-available）ですが OSI 準拠の OSS ではありません。
- コントリビューション方法は [CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。

---

## 構成

| コンポーネント | ディレクトリ | スタック |
|---|---|---|
| iOS アプリ | `ImasLiveDB/` | SwiftUI (iOS 17+), GRDB, Nuke, MusicKit, xcodegen |
| Android アプリ | `ImasLiveDB-Android/` | Jetpack Compose, Retrofit, Coil, Firebase |
| バックエンド API | `imas-live-api/` | Cloudflare Workers, D1 (SQLite), CloudKit S2S |
| データ整備ツール | `tools/` | Python / Ruby (CloudKit seed・Apple Music 補完・整合性チェック) |

iOS と Android はファイル/コンポーネント構成を意図的に揃えており、片方の変更はもう片方に 1:1 で横展開する運用です。

各コンポーネントの設計方針: [iOS](docs/ARCHITECTURE.md) / [Android](docs/ARCHITECTURE-android.md) / [Worker](docs/ARCHITECTURE-worker.md)。データ所在・同期・マイグレーションの共通思想は [iOS 文書のデータ節](docs/ARCHITECTURE.md) と [DATA_PIPELINE.md](docs/DATA_PIPELINE.md)。

## データソースは「2系統」(重要)

データは性質ごとに保存先を分けています。混同するとデータフローを誤解します。

| データ種別 | 唯一の正 (source of truth) |
|---|---|
| **マスタ** (Brand / Idol / Event / Show / Song / Setlist / Unit) | **CloudKit Public DB** → 差分 sync でローカル GRDB へ |
| **構造化コミュニティ** (コーレス / 参考動画) | **CloudKit Public DB** |
| **集計系コミュニティ** (タグ / お気に入り / 投票 / ポール / 予想 / いいね / ランキング) | **Worker の D1 (SQLite)** |

- マスタを CloudKit に置くのは、アプリ更新なしで新規ライブを即時配信でき、無料枠がユーザー数連動で増えるため (ランニングコスト 0)。
- 集計系だけ D1 なのは、原子的カウンタ・サーバ集計・レート制限・device 重複排除が CloudKit では苦手なため。**CloudKit に寄せ直さないこと。**

---

## セットアップ

### iOS (`ImasLiveDB/`)

```bash
xcodegen generate          # project.yml → .xcodeproj 生成
xcodebuild build -scheme ImasLiveDB \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

- iOS 17.0+ / Swift 6 Concurrency 前提。
- CloudKit コンテナ `iCloud.com.fugaif.ImasLiveDB` への参加権限が必要 (オーナーから iCloud で招待)。
- バックエンド URL・コンテナ名は `ImasLiveDB/Services/APIEndpoints.swift` に定義。

> **Android は iOS のコア機能サブセット (部分移植)** です。ライブ/楽曲/アイドル/セトリ閲覧・
> CloudKit 同期・基本的なコミュニティ表示は動きますが、編集/投稿・モデレーション・予想・通知・
> 共有・ゲーム・App Attest 等の一部機能は未移植です。

1. CloudKit 集計 API トークンを `local.properties` か環境変数で渡す:

   ```properties
   # local.properties
   CLOUDKIT_API_TOKEN=<オーナーから受け取ったトークン>
   ```

   (`app/build.gradle.kts` が `BuildConfig.CLOUDKIT_API_TOKEN` に注入する)
2. Android Studio でビルド、または `./gradlew assembleDebug`。

> Firebase は現状未配線です (`google-services.json` は同梱しません)。導入する場合は正しい
> `applicationId` で生成し、Google Cloud で API キー制限をかけてください。

### バックエンド (`imas-live-api/`)

```bash
cd imas-live-api
npm install
cp .dev.vars.example .dev.vars   # シークレットを記入 (コミット厳禁)
npm run dev                      # wrangler dev でローカル起動
npm run deploy                   # 本番デプロイ (オーナーのみ)
```

- 非秘密の設定は `wrangler.jsonc` の `vars` (APPLE_BUNDLE_ID / ALLOWED_ORIGINS) と D1 binding に定義。
- 本番シークレット (`CLOUDKIT_KEY_ID` / `CLOUDKIT_PRIVATE_KEY` / `SESSION_JWT_SECRET` / `ADMIN_USER_IDS`) は `wrangler secret put` で登録する。

---

## 開発上の注意 (ハマりどころ)

- **`modifiedAt` の bump 忘れ**: iOS の差分同期は CloudKit のカスタム `modifiedAt` フィールド (システムの `___modTime` ではない) を見る。CloudKit に書く全パスで `modifiedAt = now` を必ず一緒に入れる。忘れると更新が永遠に取りこぼされる。
- **CloudKit スキーマ変更**: 新フィールドは Dashboard で Indexable 設定 → Dev→Production を Deploy しないと反映されない。スキーマは `tools/cloudkit_schema.ckdb` を正として `cktool` 経由で管理。
- **集計系 D1 はホットパス**: 集計系コミュニティ読みは D1 の固定無料枠 (ユーザー数で増えない) に乗る唯一のホットパス。コスト/性能のボトルネックになりうる (TTL キャッシュで緩和済み)。
- **master データの所在**: CloudKit が source of truth。git には `db/master.sql` (テキスト dump) が日次自動更新で載る。binary `master.sqlite` は gitignore で各自 `tools/build_db.sh` 生成 (apply ツールは自動生成)。詳細は [`docs/DATA_PIPELINE.md`](docs/DATA_PIPELINE.md)。

## データに協力する

- 新規データ追加 → [`data/<種類>/`](data/README.md)、既存レコード修正 → [`data/fixes/`](data/README.md)。出典付き JSON を PR。
- 検証・反映ツールは [`tools/apply_data.py`](tools/apply_data.py) 一本 (`--check` / `--apply` / `--push`)。
- パイプライン全体・鮮度の仕組みは [`docs/DATA_PIPELINE.md`](docs/DATA_PIPELINE.md)。

詳細な規約は各プラットフォームの `CLAUDE.md` を参照。

## 開発フロー / ブランチ戦略

| ブランチ | 役割 | 保護 |
|---|---|---|
| **`main`** | 公開・安定版（リリース基準）。アプリのリリースはこの状態から | 保護: PR + オーナー承認必須 |
| **`develop`** | 統合ブランチ。日常の開発はここに入れる | 保護: PR + オーナー承認必須（オーナー/メンテナは直接マージ可） |
| **`bot/data-refresh`** | 日次データ更新 bot 専用。CloudKit から最新の `db/master.sql` が自動 push される | 保護なし（bot 用） |

フロー:
- **メンテナ/オーナー**: `develop` に直接マージしながら開発 → **リリース時に `develop` → `main`** をマージ。
- **外部コントリビューター**: fork して `develop` への PR（オーナー承認でマージ）。
- **データ更新 bot**: `bot/data-refresh` に毎日 `db/master.sql` を出力 → オーナーが `bot/data-refresh` → `develop` の PR でレビュー&マージ。
- 公開リポなので main/develop は保護。詳細は [`docs/DATA_PIPELINE.md`](docs/DATA_PIPELINE.md)。

## ライセンス / 権利

**[PolyForm Noncommercial 1.0.0](LICENSE.md)**。非公式ファンプロジェクトのため**商用利用は不可**。非商用（個人利用・改変・再配布）は可。版権物（キャラ画像・歌詞・公式ロゴ）は含みません。
