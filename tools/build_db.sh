#!/usr/bin/env bash
# db/master.sql から binary master.sqlite を再生成する (binary は gitignore・各自生成)。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUMP="$ROOT/db/master.sql"
DB="$ROOT/ImasLiveDB/Resources/master.sqlite"
[ -f "$DUMP" ] || { echo "db/master.sql が無い"; exit 1; }
rm -f "$DB"
mkdir -p "$(dirname "$DB")"
sqlite3 "$DB" < "$DUMP"

# FK 整合性ゲート (必須): バンドルされる master.sqlite に外部キー違反が 1 件でもあると、
# アプリ初回起動の reseed が単一トランザクションで全ロールバックし、ユーザーには無言で
# 旧データのまま継続してしまう (docs/DATA_PIPELINE.md / AppDatabase.reseedMasterTablesIfNeeded)。
# ここで検知して生成を失敗させ、壊れた DB が同梱されるのを防ぐ。
python3 "$ROOT/tools/check_fk_integrity.py" "$DB" || {
  echo "✗ 外部キー違反を検出。master.sqlite の同梱を中止 (db/master.sql を修正して再生成)。" >&2
  rm -f "$DB"
  exit 1
}

# data_version ゲート (必須): reseed は bundle 側 data_version > 端末側 のときだけ走る。
# meta が欠けた master.sqlite を同梱すると bundle=0 と読まれ、既存ユーザーでは reseed が
# 二度と発火せず、無言で旧データのまま固定される (FK ゲートでは検知できない)。
python3 - "$DB" <<'PY' || { rm -f "$DB"; exit 1; }
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
row = conn.execute("SELECT value FROM meta WHERE key = 'data_version'").fetchone()
version = int(row[0]) if row and str(row[0]).isdigit() else 0
if version <= 0:
    print("✗ meta.data_version が無い/不正。master.sqlite の同梱を中止 "
          "(このまま配ると既存ユーザーの reseed が止まる)。", file=sys.stderr)
    sys.exit(1)
print(f"✅ meta.data_version: {version}")
PY
# 内容の指紋 (必須): reseed の判定はこの値の一致/不一致で行う。
#
# 版番号 (data_version) は内容とは別に人が管理する数字なので、内容とズレる。実際にズレた:
# 読み仮名を入れる前のビルドが 70 を積んで出てしまい、端末が 70 を記録した結果、
# 70 のまま読み仮名入りを配っても「70 > 70」が偽になり永久に届かなくなった
# (imas-core domain/sync_planning.rs reseed_needed)。
#
# 指紋は正本 db/master.sql から機械的に作る。内容が変われば必ず変わり、変わらなければ
# 必ず同じになるので、人が上げ忘れることも上げ過ぎることもない。
CONTENT_HASH="$(shasum -a 256 "$DUMP" | cut -d' ' -f1)"
sqlite3 "$DB" "INSERT INTO meta (key, value) VALUES ('content_hash', '$CONTENT_HASH')
               ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
echo "✅ meta.content_hash: ${CONTENT_HASH:0:12}…"

echo "✓ $DB を db/master.sql から再生成"
