-- 0038_setlist_predictions_show_id.sql
-- 予想セトリの 2 表を本番 D1 と同じ形にする (新しい環境・ローカル・テスト用)。
--
-- 0006 で作った表は event_id だったが、本番の表は show_id になっていて (rename の migration は
-- 無かった)、コードも show_id を使う。migrations だけから作った D1 では予想の API が
-- 「no such column: show_id」で 500 になっていた。本番の実スキーマ (sqlite_master) と
-- 突き合わせて、次を本番に合わせる。
--   setlist_predictions      : event_id → show_id、first_voted_at を NOT NULL DEFAULT (datetime('now'))
--                              索引は idx_predictions_event をやめ、idx_setlist_predictions_show
--   setlist_prediction_votes : event_id → show_id、索引 idx_setlist_prediction_votes_user
--   setlist_song_likes       : 索引 idx_setlist_song_likes_show (本番にある)
--
-- ⚠️ 本番ではこの migration を流さない (表はすでにこの形)。`wrangler d1 migrations apply --remote`
--    を使うときは、先に本番の d1_migrations にこのファイル名を適用済みとして入れておく
--    (SQL は README の「D1 migration 適用」)。
--    万一本番で流れても、列の位置で全行を写してから入れ替えるので、データは失われない
--    (両方の形の表で成り立つ書き方にしてある。表の全行を読み書きするので、流さないこと)。

CREATE TABLE setlist_predictions_new (
  show_id TEXT NOT NULL,
  song_id TEXT NOT NULL,
  vote_count INTEGER NOT NULL DEFAULT 0,
  first_voted_by TEXT,
  first_voted_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (show_id, song_id)
);
-- first_voted_at が NULL の古い行は、OR REPLACE で既定値 (今の時刻) になる。
INSERT OR REPLACE INTO setlist_predictions_new (show_id, song_id, vote_count, first_voted_by, first_voted_at)
  SELECT * FROM setlist_predictions;
DROP TABLE setlist_predictions;
ALTER TABLE setlist_predictions_new RENAME TO setlist_predictions;
CREATE INDEX idx_setlist_predictions_show ON setlist_predictions(show_id);

CREATE TABLE setlist_prediction_votes_new (
  show_id TEXT NOT NULL,
  song_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  voted_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (show_id, song_id, user_id)
);
INSERT INTO setlist_prediction_votes_new (show_id, song_id, user_id, voted_at)
  SELECT * FROM setlist_prediction_votes;
DROP TABLE setlist_prediction_votes;
ALTER TABLE setlist_prediction_votes_new RENAME TO setlist_prediction_votes;
CREATE INDEX idx_setlist_prediction_votes_user ON setlist_prediction_votes(user_id);

CREATE INDEX IF NOT EXISTS idx_setlist_song_likes_show ON setlist_song_likes(show_id);
