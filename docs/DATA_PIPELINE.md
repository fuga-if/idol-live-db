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
鍵 (CloudKit S2S) を CI に置くので、**以下のセキュリティ設定が前提**。

### 必要な GitHub 設定 (一度だけ)

1. **Environment "cloudkit" を作成し、secret を登録 + main 限定にする**
   ```bash
   # 鍵 ID
   gh secret set CLOUDKIT_KEY_ID --env cloudkit --body "<CloudKit Key ID>"
   # 秘密鍵 (PEM)
   gh secret set CLOUDKIT_PRIVATE_KEY --env cloudkit < tools/eckey.pem
   ```
   GitHub UI → Settings → Environments → cloudkit → **Deployment branches: Selected → `main` のみ**。
   これで feature ブランチ / PR で走る他ワークフローからは鍵を取得できない。

2. **main の branch protection**
   - Require a pull request before merging (Require review)
   - Require review from Code Owners (← `.github/CODEOWNERS` を効かせる)
   - **Allow specified actors to bypass**: `github-actions[bot]` を追加
     (cron が `db/master.sql` を直接 push できるように。人間は PR 必須のまま)

3. **CODEOWNERS** (`.github/CODEOWNERS`) で `/.github/` と `/tools/` をオーナー承認必須にする
   → secret に触れるワークフローや反映ツールを勝手に書き換えられない。

### この設定で守れること

| 攻撃 | 結果 |
|---|---|
| コントリビューターが別ワークフローで鍵を抜く | ❌ environment が main 限定なので feature ブランチでは鍵が出ない |
| ワークフロー/ツールを改ざんして鍵を抜く | ❌ CODEOWNERS + PR レビュー必須で main に入らない |
| 日次エクスポート | ✅ main の schedule なので鍵を使え、無人で回る |
