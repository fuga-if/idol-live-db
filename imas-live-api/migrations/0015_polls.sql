-- みんなの投票 (Community Theme Polls) v1
-- ユーザー投稿のお題
CREATE TABLE IF NOT EXISTS polls (
  id TEXT PRIMARY KEY NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  target_type TEXT NOT NULL,             -- 'song' | 'idol'
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  ends_at TEXT NOT NULL,                  -- 投票締切（ISO/datetime）
  status TEXT NOT NULL DEFAULT 'active'   -- 'active' | 'removed'
);
CREATE INDEX IF NOT EXISTS idx_polls_status_ends ON polls(status, ends_at);

-- お題ごとの候補(entity)集計
CREATE TABLE IF NOT EXISTS poll_entries (
  poll_id TEXT NOT NULL,
  entity_id TEXT NOT NULL,               -- song_id か idol_id（target_type依存・不透明キー）
  vote_count INTEGER NOT NULL DEFAULT 0,
  first_voted_by TEXT,
  first_voted_at TEXT,
  PRIMARY KEY (poll_id, entity_id)
);
CREATE INDEX IF NOT EXISTS idx_poll_entries ON poll_entries(poll_id, vote_count DESC);

-- 投票履歴（1ユーザー1お題で最大3票、entity重複不可）
CREATE TABLE IF NOT EXISTS poll_votes (
  poll_id TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  voted_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (poll_id, entity_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_poll_votes_user ON poll_votes(poll_id, user_id);
