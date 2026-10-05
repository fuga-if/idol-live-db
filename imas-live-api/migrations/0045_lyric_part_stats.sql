-- 0045: パート分け (誰が歌うか) の整備状況。曲一覧の「パート分けがある曲のみ」(GET /lyrics/annotations) が読む。
--
-- song_part_stats … 曲ごとに歌う人の付いた行数 (行の頭か、行の途中の区切りに誰かがいる行)。
--                   PUT /songs/:id/parts が書く。歌詞本文・誰が歌うかは持たない (数だけ)。
CREATE TABLE IF NOT EXISTS song_part_stats (
  song_id TEXT PRIMARY KEY,
  part_lines INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 今あるパートを数えて入れておく (一度きり)。
INSERT OR REPLACE INTO song_part_stats (song_id, part_lines)
SELECT s.song_id, COUNT(*)
FROM song_lyrics s, json_each(s.lines_json) j
WHERE json_array_length(json_extract(j.value, '$.singers')) > 0
   OR json_array_length(json_extract(j.value, '$.partBreaks')) > 0
GROUP BY s.song_id;
