-- 歌詞の投稿 (利用者が CD の歌詞カードなどの一次ソースを見て入力した歌詞)。
-- 2026-10-06 に取り込み元の問題で歌詞を全削除した。再開は投稿だけで行い、公開はモデレーターの確認後。
-- 本文はここに置いたまま song_lyrics には入れない (公開の手順は別に作る)。
-- source_kind は booklet / official / listening (imas-core domain/lyric_submission.rs と同じ)。
-- status は pending (確認待ち) / accepted / rejected / withdrawn。行は消さない (誰が何を出したかの記録)。
CREATE TABLE IF NOT EXISTS lyric_submissions (
  id TEXT PRIMARY KEY NOT NULL,
  song_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  source_kind TEXT NOT NULL,
  source_note TEXT,
  body TEXT NOT NULL,
  line_count INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  reviewed_at TEXT,
  reviewed_by TEXT
);
CREATE INDEX IF NOT EXISTS idx_lyric_submissions_queue ON lyric_submissions (status, created_at);
CREATE INDEX IF NOT EXISTS idx_lyric_submissions_song ON lyric_submissions (song_id);
CREATE INDEX IF NOT EXISTS idx_lyric_submissions_user ON lyric_submissions (user_id, created_at);
