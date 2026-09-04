-- 0033: tags.song_count (そのタグが何曲に付いているか) を非正規化して持つ。
--
-- GET /songs/:id/similar が D1 の読み取りの最大消費源 (1,902,000 行/日 = 全体の 40%) で、
-- 1 回あたり 5,497 行 ≒ song_tags 全 4,717 行を実質フルスキャンしていた。
-- 原因は「候補の作り方」で、タグ 90 件のうち 1 件が 479 曲に付いており、
-- そのありふれたタグ経由で候補が爆発していた。
--
-- 対策として「その曲に付いた希少なタグだけで候補を作り、珍しい共有タグほど高く見る」
-- (IDF 重み付け) に変えるが、そのためにはタグごとの曲数が要る。
-- 毎回 GROUP BY で数えると結局フルスキャンになる (実測: それだけで 4,717 行) ので、
-- 90 行しかない tags 側に持たせる。
--
-- これは推薦の重み付けにしか使わない近似値で、厳密である必要はない。
-- 日次 cron (refreshTagSongCounts) が唯一の更新経路で、タグ付けのたびの
-- 増減はしない (ドリフトしても翌日には揃うし、順位が僅かに動くだけ)。
ALTER TABLE tags ADD COLUMN song_count INTEGER NOT NULL DEFAULT 0;

UPDATE tags SET song_count = (
  SELECT COUNT(*) FROM song_tags st WHERE st.tag_id = tags.id
);
