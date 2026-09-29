# コントリビューションガイド / 参加規約

ImasLiveDB は**非公式ファンメイドの非商用プロジェクト**です。コントリビュート・利用する時点で、以下の規約に同意したものとみなします。

## はじめての方へ

来てくださってありがとうございます！ 全部読まなくても大丈夫です。やりたいことから読む場所を選んでください。

| やりたいこと | 読むところ | 鍵・権限 |
|---|---|---|
| データを足す・直す (曲・ライブ・セトリ・アイドル…) | [4. データ修正の流れ](#4-データ修正の流れ) / [`data/README.md`](data/README.md) | 不要 |
| アプリ・Web の機能追加や不具合修正 | [3. 開発フロー](#3-開発フロー) / [`README.md`「セットアップ」](README.md#セットアップ) | 動作確認には必要 (下記) |
| 多言語対応 (翻訳) | [6. 多言語対応](#6-多言語対応-i18n) | 画面の翻訳は不要 |
| DB の構造を変える (列を足す等) | [5. スキーマを変えたいとき](#5-スキーマ-db-の構造-を変えたいとき) | 不要 (本番反映はオーナー) |

- **質問・相談は気軽に。** Issue でも、PR の途中 (Draft PR) でも構いません。日本語以外 (English / 한국어) でも大丈夫です。
- **大きめの変更は、手を動かす前に Issue で方向性だけ相談**してもらえると、手戻りなく進められます。
- 手元で**アプリを動かして確かめるには**、CloudKit コンテナへの招待 (iOS) や API トークン (Android) がオーナーから必要です。Issue で「動作確認用に欲しい」と言ってください。無くてもビルドと PR は出せます。
- PR を出すと CI が自動で検査します。赤くなっても**落ちた理由と直し方が job summary / 該当行の注釈に出る**ようにしてあります。分からなければそのまま PR で聞いてください。

## 1. ライセンス / 利用規約

- 本プロジェクトは **[PolyForm Noncommercial 1.0.0](LICENSE.md)** で提供されます。
- **非商用**であれば、利用・改変・再配布は自由です。
- **商用利用は許可しません**（本人・所属組織問わず）。非公式ファンプロジェクトのためです。
- ソースは公開（source-available）ですが、OSI 準拠の OSS ではありません。
- コントリビュート（PR）した内容は、本プロジェクトで同ライセンスのもと利用されることに同意したものとみなします。

## 2. 非公式・版権の遵守 (絶対)

- 本プロジェクトはいかなる公式運営とも無関係な**非公式ファンメイド**です。
- **キャラクター画像・歌詞・公式ロゴは一切使用しない。**
- ジャケット画像は **MusicKit API 経由のみ**で表示する (画像ファイルを同梱しない)。
- アプリ名・表示に「アイマス」「アイドルマスター」等の固有名称を入れない。

## 3. 開発フロー

メンテナンスはオーナー主導です。基本方針:

- 外部の方は fork して `develop` 向けに PR を出してください。大きめの機能や構造変更は、着手前に Issue で方向性を相談してもらえると手戻りがありません。
- **作業ブランチは `feature/<topic>` で切る**（`develop` 起点。修正は `fix/<topic>`、雑務は `chore/<topic>` でも可）。`main`/`develop` で直接作業しない。完了したら `develop` への PR。
- **iOS と Android はできるだけ 1:1 で揃える** (Claude Code を使うなら `/sync-ios-to-android` で iOS の差分を Android へ移せます)。
  片方しか触れない・ビルドできない場合は、**PR にその旨を書いてもらえればオーナー側で横展開します**。片方だけの PR でも歓迎です。
- 大きめの実装後はビルド → 動作確認 → 修正のループを全パスするまで回す。UI を変えたら PR にスクリーンショットを貼ってもらえると、レビューがとても速くなります。
- コミットは 1 機能 / 1 論理的変更単位。差し戻し (`git revert`) しやすい粒度を保つ。
- コミット時は `git add <file>...` で個別指定する (`git add -A` / `git add .` は使わない)。

詳細な設計規約・ビルド手順は各プラットフォームの `docs/ARCHITECTURE*.md` を参照 (`CLAUDE.md` はオーナー/メンテナ向けの内部メモで `.gitignore` により追跡外。コントリビューターには配布されない)。

## 4. データ修正の流れ

| データ種別 | 方法 |
|---|---|
| **マスタ (アプリから)** | アプリ内 `/edits` フロー → 検証・モデレーション → CloudKit へ反映 → 差分 sync で全端末配信 |
| **マスタ (PR から)** | `data/` に JSON を追加して PR。**追加**は `data/<種類>/`、**修正**は `data/fixes/`（詳細は [`data/README.md`](data/README.md)） |
| **集計系コミュニティ** (タグ / 投票 等) | Worker (D1) 経由。レート制限・device 重複排除あり |

- PR で出す時は送信前に `python3 tools/apply_data.py --check` で自己検証できる (鍵不要)。`--check` は出典の無い投稿を落とす。
- 各エントリに**出典URL (一次ソース) 必須**。オーナーがレビュー後 `--apply --push` で master.sqlite → CloudKit に一括反映。反映済みのファイルは `data/_applied/<種類>/` へ移される (`apply_data.py` はそこを読まない。PR 履歴と合わせた監査ログ)。

- マスタの事実情報 (アイドル名・楽曲情報など) を直す時は、**必ず公式サイトを確認してから**修正する (推測で書き換えて別キャラの情報になる事故を防ぐ)。
- 一括スクリプトでの機械的修正よりも、1 件ずつ判断して直す方を優先する (デグレ防止)。

## 5. スキーマ (DB の構造) を変えたいとき

**コントリビューターは PR を出すところまで。本番への反映はマージ後にオーナーが行います。**
CloudKit の鍵や Dashboard の権限は不要です。

### 変える場所

「列を 1 本足す」でも、層ごとに正本が分かれています。関係する層だけ触ってください。
**全部を 1 人でやりきる必要はありません。** 触る場所が分からなければ、`cloudkit_schema.ckdb` への追記だけの PR や、
Issue での提案から始めてもらえれば、残りは相談しながら進めます。

| 層 | 触るファイル | 本番への反映 |
|---|---|---|
| **CloudKit** (マスタの source of truth) | `tools/cloudkit_schema.ckdb` に**追記**<br>アプリに読ませるなら `imas-core/src/domain/ck_record_mapping.rs` (レコード ↔ 行の変換) も | マージ後にオーナーが手動 (下記) |
| **端末の SQLite** (iOS / Android) | `db/master.sql` / `imas-core/src/domain/master_schema.sql` / iOS `DatabaseMigrations` / Android Room `Migration`<br>(`db/master.sql` の作り直しには注意点あり → [`docs/DATA_PIPELINE.md`](docs/DATA_PIPELINE.md)) | 不要。アプリ起動時に自動で追加される |
| **Worker (D1)** (タグ・投票などの集計系) | `imas-live-api/migrations/00xx_*.sql` を新規追加 | マージ後にオーナーが手動 (下記) |

### 守ること: **足すだけ**

CloudKit の Production は**列や型を消せず、型も変えられません**。一度流すと戻せないので、

- 列・型の**削除や改名はしない** (使わなくなった列は残したまま読まない)
- 型を変えたいときは**別名の列を足す**
- 新しい record type には `modifiedAt TIMESTAMP QUERYABLE SORTABLE` と `deletedAt TIMESTAMP QUERYABLE SORTABLE` を必ず持たせる
- 端末側も同じく**追加のみ**。`user_marks` (担当・お気に入り) は端末にしか無いデータなので、破壊的な移行は書かない

手元で確かめられます (鍵不要):

```bash
python3 tools/check_ckdb_schema.py --base origin/develop
# fork から作業しているなら、本家と比べる:
#   git remote add upstream https://github.com/fuga-if/idol-live-db.git && git fetch upstream develop
#   python3 tools/check_ckdb_schema.py --base upstream/develop
```

同じ検査が PR の CI (`schema-guard`) でも走り、追加される項目の一覧が job summary に出ます。
問題があれば PR の「Files changed」で該当行に注釈が付き、直し方も書いてあります。

`cloudkit_schema.ckdb` の型と列は **ASCII 順** (大文字が先。たとえば `Song` の `hasKamisabiCard` は `durationSec` と `isCollab` の間) に並んでいます。
追記するときはその位置に入れてください (ずれていても警告だけで、CI は落ちません)。

### PR に書くこと

PR テンプレートの「スキーマ変更」欄を埋めてください。特に**なぜその列が要るか**と、
**既存データをどう埋めるか** (空のままでよいか、`data/fixes/` で埋めるか) があるとレビューが速くなります。

### マージ後 (オーナー側・参考)

`develop` に `cloudkit_schema.ckdb` か D1 migration の変更が入ると、`schema-guard` が
**「本番スキーマ反映待ち」Issue を自動で起票**します。オーナーはそのチェックリストに沿って

1. CloudKit: `cktool import-schema` で Development へ → Dashboard の **Deploy Schema Changes** で Production へ
2. D1: `wrangler d1 migrations apply --remote` → Worker をデプロイ

を行い、Issue を close します。**マージ時の自動実行はしません** — Production の CloudKit スキーマは
`cktool` から昇格できない仕様であることと、戻せない操作をリリース前の `develop` マージで
確定させないためです。詳細は [`docs/DATA_PIPELINE.md`](docs/DATA_PIPELINE.md)。

## 6. 多言語対応 (i18n)

韓国語・英語などへの対応は大歓迎です。ただし**土台がまだ無い**ので、最初に進め方を Issue で相談させてください。

- **いまの状態**: iOS / Android / Web とも、画面の文字列はほぼコードに日本語で直接書かれています (iOS は String Catalog 未導入、Android の `res/values/strings.xml` もごく一部だけ)。
- **画面の文字列** (ボタン・メニュー・メッセージ): 翻訳ファイルへ切り出すだけなので、**スキーマ変更は不要**です。
  変更箇所が多くなるので、**「仕組みの導入」→「画面ごと」の小さい PR に分けて**ください。1 つの巨大な PR だと、`develop` の更新と衝突し続けてしまいます。
- **データ** (アイドル名・曲名・ライブ名などの翻訳表記): 列を足すことになるので [5. スキーマを変えたいとき](#5-スキーマ-db-の構造-を変えたいとき) の流れに乗ります。どの表にどんな列を足すかを先に Issue で合意してから進めるのがおすすめです。
- 翻訳でも [2. 非公式・版権の遵守](#2-非公式版権の遵守-絶対) は同じです (公式の表記・固有名称の扱いに注意)。

## 7. シークレットの取り扱い

- `.dev.vars` / `.env` / `*.p12` / 秘密鍵 / `google-services.json` 内の値などを**平文でコミットしない**。
- ローカル開発用シークレットは `.dev.vars.example` をコピーして `.dev.vars` に記入する (`.dev.vars` は `.gitignore` 済み)。
- 本番シークレットは `wrangler secret put` で Cloudflare 側に登録する。
- 誤って秘密をコミット・push した場合は、ただちにオーナーに連絡し、該当の鍵をローテーションする。
---

不明点はオーナー (リポジトリ管理者) に、Issue か PR のコメントで気軽に聞いてください。
