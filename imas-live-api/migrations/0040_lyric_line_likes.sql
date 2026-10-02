-- 0040: 歌詞行の「ここ好き」を集める。
--
-- lyric_line_likes … 誰がどの行を好きと言ったか (1 人 1 行 1 回、PK で重複を物理排除)。
-- song_lyrics.likes_json … 行ごとの人数 {行ID: 人数}。歌詞の取得と同じ 1 行に載せるので、
--   人数を返すための D1 の追加読み取りは 0 回 (migration 0027 と同じ理由)。
--   付け外しのたびに lyric_line_likes から数え直して書く (加減算にしないのでずれない)。
CREATE TABLE IF NOT EXISTS lyric_line_likes (
  song_id  TEXT NOT NULL,
  line_id  TEXT NOT NULL,
  user_id  TEXT NOT NULL,
  liked_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (song_id, line_id, user_id)
);

-- 退会 (DELETE /users/me) で本人の分を消して数え直すのに使う。
CREATE INDEX IF NOT EXISTS idx_lyric_line_likes_user ON lyric_line_likes(user_id);

ALTER TABLE song_lyrics ADD COLUMN likes_json TEXT NOT NULL DEFAULT '{}';
