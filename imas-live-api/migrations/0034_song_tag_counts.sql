-- 0034: song_tag_counts (その曲に付いている有効タグの本数) を非正規化して持つ。
--
-- GET /songs/:id/similar が D1 の最大消費源 (1,902,000 行/日 = 全体の 40%)。
-- スコアは減衰つき Jaccard で、分母に「相手の曲のタグ総数」が要る。
-- これを候補 1 件ごとの相関副問い合わせで数えていたため、候補が数百件出る曲では
-- 1 回 16,800 行 (平均 5,497 行 ≒ song_tags 全 4,717 行) を読んでいた。
--
-- 数えるのをやめて引くだけにする。スコア式は一切変えないので、
-- 返る類似曲とその並び順は今までと完全に同一。
--
-- 更新は日次 cron (apply.ts の refreshTagCounts) の 1 か所のみ。
-- 推薦の重み付けにしか使わない近似値なので、タグ付けのたびに増減させて
-- ドリフトの原因を作るより、日次で数え直すほうが壊れにくい。
CREATE TABLE IF NOT EXISTS song_tag_counts (
  song_id   TEXT PRIMARY KEY,
  tag_count INTEGER NOT NULL DEFAULT 0
);

INSERT OR REPLACE INTO song_tag_counts (song_id, tag_count)
SELECT s.song_id, COUNT(*)
  FROM song_tags s
  JOIN tags t ON t.id = s.tag_id AND t.status != 'removed'
 GROUP BY s.song_id;
