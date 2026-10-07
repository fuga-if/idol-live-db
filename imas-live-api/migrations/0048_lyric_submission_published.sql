-- 0048: 歌詞の投稿のうち、その投稿で公開された (song_lyrics に入った) ものの時刻。
--
-- 投稿した人への手応え (「歌詞が公開されました」・ここ好きの反響)、曲の歌詞の奥付 (歌詞入力 ○○)、
-- BAN した人の歌詞をまとめて非公開にするときの引き当てに使う。NULL = この投稿では公開していない
-- (既に歌詞があった曲への直しの提案など)。
ALTER TABLE lyric_submissions ADD COLUMN published_at TEXT;

-- これまでの分: 出典が「みんなの投稿」の曲は、その曲のいちばん早い投稿で公開された。
UPDATE lyric_submissions SET published_at = created_at
 WHERE id IN (
   SELECT s.id FROM lyric_submissions s
     JOIN song_lyrics l ON l.song_id = s.song_id
    WHERE l.source = 'みんなの投稿'
      AND s.created_at = (SELECT MIN(s2.created_at) FROM lyric_submissions s2 WHERE s2.song_id = s.song_id));

CREATE INDEX IF NOT EXISTS idx_lyric_submissions_published ON lyric_submissions (song_id, published_at);

-- 直しの投稿もすぐ公開する (2026-10-07 オーナー判断)。上書きされる前の版をここに残し、
-- モデレーターが POST /admin/lyrics/:song_id/restore で 1 つ前に戻せるようにする。
CREATE TABLE IF NOT EXISTS song_lyrics_versions (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  song_id     TEXT NOT NULL,
  source      TEXT,
  status      TEXT NOT NULL,
  lines_json  TEXT NOT NULL,
  replaced_at TEXT NOT NULL DEFAULT (datetime('now')),
  -- 上書きした投稿 (lyric_submissions.id)。
  replaced_by TEXT
);
CREATE INDEX IF NOT EXISTS idx_song_lyrics_versions_song ON song_lyrics_versions (song_id, id DESC);

-- 歌詞を出せない曲 (JASRAC 非委託で NexTone にも見つからない。tools/jasrac/works.tsv の note)。
-- 投稿は預かるが公開しない。見つかったらここに足す。
CREATE TABLE IF NOT EXISTS lyric_unlicensed_songs (
  song_id TEXT PRIMARY KEY NOT NULL,
  note    TEXT
);
INSERT OR IGNORE INTO lyric_unlicensed_songs (song_id, note) VALUES
  ('765as_binarystar', 'JASRAC 非委託・NexTone 未発見 (2026-09-16)'),
  ('765as_excavate', 'JASRAC 非委託・NexTone 未発見 (2026-09-16)'),
  ('765as_labyrinth', 'JASRAC 非委託・NexTone 未発見 (2026-09-16)'),
  ('765as_北極星をズラしちゃえ', 'JASRAC 非委託・NexTone 未発見 (2026-09-16)'),
  ('961_エクストリームオーバードライブ', 'JASRAC 非委託・NexTone 未発見 (2026-09-16)'),
  ('cg_大好きのブーケ', 'JASRAC 非委託・NexTone 未発見 (2026-09-16)');
