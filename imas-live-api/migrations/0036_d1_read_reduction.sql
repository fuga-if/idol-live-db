-- 0036: D1 の rows_read 削減 (無料枠 500万行/日 を 96% 消費した事象への対応)
--
-- 0033〜0035 は欠番。この対応を最初 0032〜0035 として書いたが、同じ番号で
-- 0032_call_guide_stats が並行して入っていたため採番し直した。旧名は本番の
-- d1_migrations に記録が残っているので、番号を再利用せず後ろにずらしてある。
--
-- wrangler d1 insights で計測した上位クエリのうち、
-- 「インデックスが無いせいでフルスキャンしているもの」だけをここで潰す。
-- クエリ本体の書き換えは src 側 (polls.ts / apply.ts) と対で入る。

-- rate_limits の日次掃除 (DELETE ... WHERE date < ...) がフルスキャンだった。
-- 5分 cron × 283回/日 × 1006行 ≒ 285,000 行/日 を、削除対象だけの読み取りに落とす。
CREATE INDEX IF NOT EXISTS idx_rate_limits_date ON rate_limits(date);

-- GET /polls/achievements/:entityId は「終了お題の全エントリを RANK してから
-- entity_id で絞る」形だったため 1回 3,954 行読んでいた。
-- entity_id から先に引けるようにして、対象お題の中だけで順位を出す。
CREATE INDEX IF NOT EXISTS idx_poll_entries_entity ON poll_entries(entity_id, vote_count DESC);
