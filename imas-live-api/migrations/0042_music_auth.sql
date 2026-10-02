-- 0042: Android で Apple Music にサインインするための受け渡し (routes/music_auth.ts)。
--
-- Android の MusicKit SDK の認証は、端末の Apple Music アプリにサインイン済みだと結果が返らない
-- 不具合がある (FB24754184)。ブラウザ (MusicKit JS) でサインインしてもらい、取れた
-- ミュージックユーザートークンをここへ一度だけ預け、始めた端末が一度だけ取りに来る。
-- 取りに来たら行ごと消す。取りに来なくても 10 分で cron が消す。
CREATE TABLE IF NOT EXISTS music_auth (
  code       TEXT PRIMARY KEY,
  device_id  TEXT NOT NULL,
  token      TEXT,
  created_at INTEGER NOT NULL
);
