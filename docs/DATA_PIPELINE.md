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
python3 tools/apply_data.py --apply                                      # ローカル master.sqlite に反映
CLOUDKIT_KEY_ID=$KID python3 tools/apply_data.py --apply --push --production  # CloudKit へ push
# CloudKit に反映 → 翌日の cron が db/master.sql を更新 → 貢献が git にも反映される
```

スキーマを変えた時 (列追加等) は、ローカル master.sqlite から `sqlite3 ... .dump > db/master.sql` で
dump を作り直してコミットする (cron はデータのみ更新し、スキーマは db/master.sql 由来のため)。

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
