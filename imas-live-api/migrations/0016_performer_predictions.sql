-- 0016_performer_predictions.sql
-- 出演者予想「この曲を誰が歌う？」投票機能

-- 公演×曲×アイドルの予想集計
CREATE TABLE IF NOT EXISTS setlist_performer_predictions (
  show_id TEXT NOT NULL,
  song_id TEXT NOT NULL,
  idol_id TEXT NOT NULL,
  vote_count INTEGER NOT NULL DEFAULT 0,
  first_voted_by TEXT,
  first_voted_at TEXT,
  PRIMARY KEY (show_id, song_id, idol_id)
);

CREATE INDEX IF NOT EXISTS idx_spp_show_song
  ON setlist_performer_predictions(show_id, song_id, vote_count DESC);

-- 投票履歴（ユーザー重複防止）
CREATE TABLE IF NOT EXISTS setlist_performer_prediction_votes (
  show_id TEXT NOT NULL,
  song_id TEXT NOT NULL,
  idol_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  voted_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (show_id, song_id, idol_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_sppv_user
  ON setlist_performer_prediction_votes(user_id);
