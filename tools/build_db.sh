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
echo "✓ $DB を db/master.sql から再生成"
