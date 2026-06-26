CREATE TABLE IF NOT EXISTS api_rate_limits (
  ip TEXT NOT NULL,
  minute_bucket INTEGER NOT NULL,  -- floor(unix_seconds / 60)
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (ip, minute_bucket)
);
CREATE INDEX IF NOT EXISTS idx_api_rate_limits_bucket ON api_rate_limits(minute_bucket);
