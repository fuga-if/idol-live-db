-- 0028: 歌詞検索用の平文カラム (song_lyrics.body)。
--
-- なぜ lines_json を直接 LIKE しないか:
--   lines_json は {"kind":"lyric","text":"..."} の配列で、本文は JSON エスケープ済み。
--   検索語に " や \ が混ざると一致が壊れ、スニペットを切り出せば
--   `","kind":"lyric","text":"` のような構文まで混ざる。検索は平文に対して掛ける。
--
-- なぜ FTS5 を使わないか:
--   FTS5 の既定トークナイザは日本語を分割しない。trigram なら部分一致できるが
--   2文字のクエリが引けなくなる (「夢は」等が探せない)。曲数が 2,300 程度で
--   全走査しても D1 の行読み取りは 1 クエリ 2,300 行 ≒ 無料枠 (500万行/日) の 0.05%
--   なので、素直な LIKE の方が制約が少なく安い。曲数が桁で増えたら再考する。
--
-- kind='lyric' の行だけを改行で連結する。marker (イントロ/間奏) や blank は
-- 歌詞本文ではないので検索対象にしない (「間奏」で全曲ヒットしても意味がない)。

ALTER TABLE song_lyrics ADD COLUMN body TEXT NOT NULL DEFAULT '';

-- 既存行の backfill。以降は PUT /admin/lyrics/:song_id が lines_json と同時に書く。
UPDATE song_lyrics
SET body = COALESCE(
  (SELECT group_concat(json_extract(value, '$.text'), char(10))
     FROM json_each(song_lyrics.lines_json)
    WHERE json_extract(value, '$.kind') = 'lyric'),
  ''
);
