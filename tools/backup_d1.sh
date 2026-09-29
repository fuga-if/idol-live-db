#!/usr/bin/env bash
# D1 (集計系コミュニティの唯一の正) の完全バックアップを手元に取る。
#
# なぜ必要か:
#   マスタは CloudKit が正で、日次 cron が db/master.sql に落としている (復旧可能)。
#   一方 D1 はタグ・投票・お気に入り・予想・いいねの**唯一の正**で、バックアップが
#   1 つも無い。飛んだらユーザーの投稿が全部消える。
#
# なぜ git に入れないか:
#   このリポジトリは public。D1 には Apple uid (users.id, *_votes.user_id)、
#   device_id、表示名、引き継ぎコードが入っており、公開すると個人情報が恒久的に漏れる。
#   → 完全ダンプは gitignore 済みの db_backups_local/ にだけ置く。
#   git に載せる公開用スナップショットは tools/export_community_snapshot.py (別物)。
#
# 使い方 (リリース前に実行):
#   bash tools/backup_d1.sh
#
# 復元 (災害時):
#   npx wrangler d1 execute imas-live-db --remote --file db_backups_local/d1_<日時>.sql
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_DIR="$ROOT/imas-live-api"
OUT_DIR="$ROOT/db_backups_local"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="$OUT_DIR/d1_${STAMP}.sql"

mkdir -p "$OUT_DIR"

# db_backups_local/ が本当に gitignore されているか確認する (public repo なので必須)。
if ! git -C "$ROOT" check-ignore -q "$OUT_DIR"; then
  echo "✗ db_backups_local/ が gitignore されていない。中断する (個人情報の公開を防ぐため)。" >&2
  exit 1
fi

echo "D1 (本番) をエクスポート中… 数分かかることがある"
(cd "$API_DIR" && npx wrangler d1 export imas-live-db --remote --output "$OUT")

if [ ! -s "$OUT" ]; then
  echo "✗ 出力が空。エクスポートに失敗している" >&2
  rm -f "$OUT"
  exit 1
fi

echo "✓ $OUT ($(du -h "$OUT" | cut -f1))"
echo
echo "行数の目安:"
for t in users tags idol_tag_master unit_tag_master song_tags idol_tags unit_tags \
         song_favorites penlight_color_set_votes polls poll_votes \
         setlist_predictions setlist_song_likes; do
  n=$(grep -c "INSERT INTO \"\?${t}\"\? " "$OUT" || true)
  printf '  %-28s %s\n' "$t" "$n"
done
echo
echo "⚠️ このファイルには Apple uid / device_id / 表示名 / 引き継ぎコードが含まれる。"
echo "   git に add しないこと (db_backups_local/ は gitignore 済み)。"
