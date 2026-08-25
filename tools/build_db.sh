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
echo "✓ $DB を db/master.sql から再生成"
