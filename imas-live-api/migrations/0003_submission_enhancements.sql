-- 0003: submission enhancements (applied_at, retry_count, last_error, updated_at, rate_limits)

ALTER TABLE submissions ADD COLUMN applied_at TEXT;
ALTER TABLE submissions ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE submissions ADD COLUMN last_error TEXT;
ALTER TABLE submissions ADD COLUMN updated_at TEXT;

CREATE TABLE IF NOT EXISTS rate_limits (
  user_id TEXT NOT NULL,
  date    TEXT NOT NULL,
  action  TEXT NOT NULL,
  count   INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, date, action)
);

CREATE INDEX IF NOT EXISTS idx_submissions_status_applied  ON submissions(status, applied_at);
CREATE INDEX IF NOT EXISTS idx_submissions_author_status   ON submissions(author_id, status);
