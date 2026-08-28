# データパイプライン (master データの鮮度と投入)

## 全体像

```
                ┌──────────────── source of truth ────────────────┐
   貢献者 PR ──▶ │  CloudKit Public DB  ◀── オーナーが apply/seed で書込 │
    (data/)      └───────┬──────────────────────────────────────────┘
                            │ 日次 cron (GitHub Actions, 鍵は environment)
                            ▼
                     db/master.sql  ──(git に載る・diff 可能)──▶ コントリビューターが pull して最新を取得
                            │ tools/build_db.sh / 各ツールが自動生成
                            ▼
              ImasLiveDB/Resources/master.sqlite (binary・gitignore・各自生成)
```

- **CloudKit が source of truth**。`db/master.sql` はその日次スナップショット (テキスト dump・git 管理)。
- binary `master.sqlite` は **gitignore**。`db/master.sql` から各自再生成 (`tools/build_db.sh`、または apply ツールが自動生成)。
- だから**コントリビューターは clone するだけで最新データに対して `--check` できる**。

## データ投入は `tools/apply_data.py` 一本

追加も修正も同じツールで扱う。`data/` 配下を読んで検証 → master.sqlite に反映 → CloudKit へ push する。

- **新規追加**: `data/<種類>/*.json` (`songs` / `setlists` / `events` / `idols` / `units`) … INSERT
- **既存レコード修正**: `data/fixes/*.json` … UPDATE (`idols` / `songs` / `events` / `shows` / `units` / `brands`)
- 形式は各 `data/<種類>/_template.json` / `data/fixes/_template.json` と [`data/README.md`](../data/README.md) 参照。全ファイルに `source` (出典 URL) 必須。

## コントリビューター

```bash
git pull                              # db/master.sql が日次で更新される
# 追加なら data/<種類>/ に、修正なら data/fixes/ に JSON を追加
python3 tools/apply_data.py --check    # 自己検証 (binary が無ければ db/master.sql から自動生成)
git add ... && PR
```

## オーナー (反映)

```bash
# PR をレビュー (出典確認) 後:
KID="<.claude/skills/sync-new-songs/SKILL.md に書いてある Production の key ID>"
python3 tools/apply_data.py --check  --only <ファイル名>.json                            # そのファイル単体で検証
python3 tools/apply_data.py --apply  --only <ファイル名>.json                            # ローカル master.sqlite に反映
CLOUDKIT_KEY_ID=$KID python3 tools/apply_data.py --apply --push --production --only <ファイル名>.json
# CloudKit に反映 → 翌日の cron が db/master.sql を更新 → 貢献が git にも反映される
```

**`--only` を付けること。** `--apply` は検証エラーが 1 件でもあると `sys.exit(1)` する。
`data/` には push 済みの INSERT 用 JSON が残ったままになりやすく、それが全部
「id は既に存在」で problem 判定になるため、絞らないと自分の変更が push まで到達しない
(2026-08-28 時点で 732 件が該当)。`--only` はパスではなくファイル名で照合する。

**鍵の在り処**: key ID は環境変数にも `~/.zshrc` にも無い。`.claude/skills/sync-new-songs/SKILL.md`
の冒頭に Production の値が書いてある (このディレクトリは `.git/info/exclude` で
リポジトリから除外済み)。秘密鍵は `tools/eckey.pem` で、スクリプトが自分で読む。

**スキーマを足した場合は push の前に**、`tools/cloudkit_schema.ckdb` を
Development へ `xcrun cktool import-schema` してから Dashboard で Production へ昇格する。
Production に列が無いうちに push すると弾かれる。

スキーマを変えた時 (列追加等) は、ローカル master.sqlite から `sqlite3 ... .dump > db/master.sql` で
dump を作り直してコミットする (cron はデータのみ更新し、スキーマは db/master.sql 由来のため)。

### `meta.data_version` (これが落ちるとユーザーに届かない)

アプリの reseed は **bundle 側 `data_version` > 端末側** のときだけ走る
(`AppDatabase.reseedMasterTablesIfNeeded`)。つまり:

- **`meta` が消えた dump を配ると reseed が二度と発火しない。** bundle 側が `0` と読まれ、
  既存ユーザーは無言で旧データのまま固定される。FK ゲートでは検知できない種類の事故。
  `meta` は CloudKit 側に実体が無いので、`export_cloudkit.py` の `PRESERVED_TABLES` で
  refresh 対象から外して既存 dump の値を引き継ぐ。
- **データを入れても `data_version` を上げなければ既存ユーザーには届かない。**
  cron は「マスタに実差分があった回だけ」+1 する (差分判定は `data_version` 行を除いて比較。
  バンプ自体が差分になる循環を避けるため)。手で `--apply --push` した分も、翌日の cron が
  差分を拾って上げるので通常は追加操作は不要。

`tools/build_db.sh` は FK 整合性に加えて `data_version` の存在も検証し、欠けていれば
master.sqlite の生成を失敗させる。

## コミュニティデータ (D1) のバックアップ / スナップショット

マスタ (CloudKit) は日次 cron で `db/master.sql` に落ちるので失っても戻せる。
一方 **D1 は集計系コミュニティ (タグ・投票・お気に入り・予想・いいね) の唯一の正で、
バックアップの仕組みが無かった**。飛ばすとユーザーの投稿が丸ごと消える。

用途が違う 2 つを分けている。**混ぜないこと。**

| | 完全バックアップ | 公開スナップショット |
|---|---|---|
| ツール | `tools/backup_d1.sh` | `tools/export_community_snapshot.py --remote` |
| 出力 | `db_backups_local/d1_<日時>.sql` | `db/community.sql` |
| git | **載せない** (gitignore 済み) | 載せる (diff で履歴が追える) |
| 中身 | 全テーブル・全列 (Apple uid / device_id / 表示名 / 引き継ぎコードを含む) | 「誰が」を含まない集計のみ |
| 目的 | 災害復旧 | 「この時点でどんなタグがあり何が人気だったか」の記録 |

⚠️ **このリポジトリは public。** D1 の生ダンプを git に載せると Apple uid と device_id が
恒久的に公開される。だから完全バックアップは手元 (`db_backups_local/`) にだけ置き、
git に載せる方は識別子を含む列を一切出力しない。`export_community_snapshot.py` は
出力対象の列に `user_id` / `device_id` / `created_by` 等が混ざっていたら
実行前に落ちるようになっている。

```bash
# リリース前に (オーナー)
bash tools/backup_d1.sh                                  # 完全バックアップ → 手元
python3 tools/export_community_snapshot.py --remote      # 公開スナップショット → db/community.sql
git add db/community.sql && git commit -m "data(community): リリース時点のスナップショット"

# 動作確認 (誰でも・鍵不要)
python3 tools/export_community_snapshot.py --local

# 復元 (災害時)
npx wrangler d1 execute imas-live-db --remote --file db_backups_local/d1_<日時>.sql
```

> `wrangler d1 execute --json` は SQL の NULL を文字列 `"null"` として返し、本物の
> 文字列 `'null'` と区別できない。スナップショット生成は値の整形を Python でやらず
> SQLite の `quote()` に任せてこれを回避している (`export_community_snapshot.py` の注記)。

## 日次自動エクスポート (GitHub Actions)

`.github/workflows/refresh-data.yml` が毎日 CloudKit → `db/master.sql` を出力し、変化があれば自動コミット。
main / develop はどちらも保護ブランチ (PR + オーナー承認必須) なので、bot は**専用ブランチ `bot/data-refresh`**
に push する。**オーナーが `bot/data-refresh` → develop の PR でレビュー&マージ**して取り込む
(データ更新もレビューを通る)。develop → main は通常のリリースマージ。
鍵 (CloudKit S2S) を CI に置くので、**以下のセキュリティ設定が前提**。

### 必要な GitHub 設定 (一度だけ)

1. **Environment "cloudkit" を作成し、secret を登録 + main 限定にする**
   ```bash
   gh secret set CLOUDKIT_KEY_ID --env cloudkit --body "<CloudKit Key ID>"
   gh secret set CLOUDKIT_PRIVATE_KEY --env cloudkit < tools/eckey.pem
   ```
   GitHub UI → Settings → Environments → cloudkit → **Deployment branches: Selected → `main` のみ**。
   schedule は既定ブランチ(main)で走るため鍵を取得でき、feature ブランチ / PR で走る他ワークフローからは取得できない。

2. **main / develop の branch protection**: 両方とも PR 必須 + 承認必須 + **Code Owners レビュー必須**
   (`.github/CODEOWNERS` の `* @owner` で全 PR をオーナー承認必須に)。
   bot は保護ブランチへ直接 push せず `bot/data-refresh` へ出すので bypass 設定は不要。

3. **CODEOWNERS** (`.github/CODEOWNERS`): `* @owner` で全ファイル + `/.github/`・`/tools/` を明示。
   secret に触れるワークフロー・反映ツールの改ざんを防ぐ。

4. **`bot/data-refresh`** (保護外): bot が `db/master.sql` を push する専用ブランチ。
   オーナーが develop への PR でレビュー&マージして取り込む。

### この設定で守れること

| 攻撃 | 結果 |
|---|---|
| コントリビューターが別ワークフローで鍵を抜く | ❌ environment が main 限定なので feature ブランチでは鍵が出ない |
| ワークフロー/ツールを改ざんして鍵を抜く | ❌ CODEOWNERS + PR レビュー必須で main に入らない |
| 日次エクスポート | ✅ main の schedule なので鍵を使え、無人で回る |
