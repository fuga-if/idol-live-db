-- 0043: 歌詞のタイミング (行・コールの再生位置) の整備状況と編集の記録。
--
-- song_timing_stats  … 曲ごとに時刻の入った行数・コール数。GET /calls/dashboard が
--                      「タイミングがある曲」を返すのに使う (歌詞本文は持たない)。
-- timing_edit_history … 保存 1 回 = 1 行。Discord の更新通知 (discord_digest.ts) が読む。
--                      件数だけで、時刻や歌詞は持たない。180 日で cron が消す。
CREATE TABLE IF NOT EXISTS song_timing_stats (
  song_id TEXT PRIMARY KEY,
  timed_lines INTEGER NOT NULL DEFAULT 0,
  timed_calls INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  -- 最後に保存した人 (users.id)。API 応答には出さない (表示名はマスクして JOIN で出す)。
  updated_by_uid TEXT
);
CREATE INDEX IF NOT EXISTS idx_song_timing_stats_updated ON song_timing_stats(updated_at DESC);

CREATE TABLE IF NOT EXISTS timing_edit_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  song_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  at TEXT NOT NULL DEFAULT (datetime('now')),
  timed_lines_before INTEGER NOT NULL DEFAULT 0,
  timed_lines_after INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_timing_edit_history_user ON timing_edit_history(user_id);
