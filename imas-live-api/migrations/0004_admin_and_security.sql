-- 0004: admin column + votes unique index

ALTER TABLE users ADD COLUMN is_admin INTEGER NOT NULL DEFAULT 0;

CREATE UNIQUE INDEX IF NOT EXISTS idx_votes_unique ON votes(submission_id, user_id);
