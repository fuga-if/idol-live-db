-- 0006_setlist_predictions.sql
-- 未来イベントの予想セトリ投票機能

-- イベントごとの曲予想集計
CREATE TABLE IF NOT EXISTS setlist_predictions (
  event_id TEXT NOT NULL,
  song_id TEXT NOT NULL,
  vote_count INTEGER NOT NULL DEFAULT 0,
  first_voted_by TEXT,
  first_voted_at TEXT,
  PRIMARY KEY (event_id, song_id)
);

CREATE INDEX IF NOT EXISTS idx_predictions_event
  ON setlist_predictions(event_id, vote_count DESC);

-- 投票履歴（ユーザー重複防止）
CREATE TABLE IF NOT EXISTS setlist_prediction_votes (
  event_id TEXT NOT NULL,
  song_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  voted_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (event_id, song_id, user_id)
);
