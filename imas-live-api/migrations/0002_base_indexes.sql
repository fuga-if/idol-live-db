-- 0002: 基本インデックス（クリーンDB プロビジョニング用）

CREATE INDEX IF NOT EXISTS idx_submissions_status ON submissions(status);
CREATE INDEX IF NOT EXISTS idx_submissions_author ON submissions(author_id);
CREATE INDEX IF NOT EXISTS idx_votes_submission ON votes(submission_id);
CREATE INDEX IF NOT EXISTS idx_shows_event ON shows(event_id);
CREATE INDEX IF NOT EXISTS idx_shows_date ON shows(date);
CREATE INDEX IF NOT EXISTS idx_setlist_items_show ON setlist_items(show_id);
CREATE INDEX IF NOT EXISTS idx_setlist_items_song ON setlist_items(song_id);
CREATE INDEX IF NOT EXISTS idx_setlist_performers_item ON setlist_performers(setlist_item_id);
CREATE INDEX IF NOT EXISTS idx_setlist_performers_cast ON setlist_performers(cast_id);
CREATE INDEX IF NOT EXISTS idx_songs_brand ON songs(brand_id);
CREATE INDEX IF NOT EXISTS idx_songs_composer ON songs(composer);
CREATE INDEX IF NOT EXISTS idx_api_rate_limits_bucket ON api_rate_limits(minute_bucket);
