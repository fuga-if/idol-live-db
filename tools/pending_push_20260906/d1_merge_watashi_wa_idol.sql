-- 私はアイドル♥ (765as_私はアイドル_2) → 私はアイドル♡ (765as_私はアイドル) のコミュニティデータ統合。
-- マスタ側は tools/merge_duplicate_songs.py で統合済み。D1 (imas-live-db) の song_id も付け替える。
--
--   cd imas-live-api && npx wrangler d1 execute imas-live-db --remote \
--     --file ../tools/pending_push_20260906/d1_merge_watashi_wa_idol.sql
--
-- 方針: 集計表は足し合わせる。端末/ユーザーごとの表は付け替え、主キーが衝突する行
-- (同じ人が両方に投票していた) は残す側を優先して消す (UPDATE OR IGNORE → DELETE)。
-- 2026-09-06 の community.sql では song_tags 3 件 / song_favorites 1 件 / poll_entries 1 件が対象。

-- 事前確認 (歌詞があれば付け替え後に lyrics_gram_index の作り直しが要る)
SELECT 'song_lyrics(_2)' AS what, count(*) AS n FROM song_lyrics WHERE song_id = '765as_私はアイドル_2';

-- タグ
INSERT INTO song_tags (song_id, tag_id, vote_count)
  SELECT '765as_私はアイドル', tag_id, vote_count FROM song_tags WHERE song_id = '765as_私はアイドル_2'
  ON CONFLICT(song_id, tag_id) DO UPDATE SET vote_count = vote_count + excluded.vote_count;
DELETE FROM song_tags WHERE song_id = '765as_私はアイドル_2';
UPDATE OR IGNORE device_song_tag SET song_id = '765as_私はアイドル' WHERE song_id = '765as_私はアイドル_2';
DELETE FROM device_song_tag WHERE song_id = '765as_私はアイドル_2';
INSERT OR REPLACE INTO song_tag_counts (song_id, tag_count)
  SELECT s.song_id, COUNT(*) FROM song_tags s JOIN tags t ON t.id = s.tag_id AND t.status != 'removed'
  WHERE s.song_id = '765as_私はアイドル' GROUP BY s.song_id;
DELETE FROM song_tag_counts WHERE song_id = '765as_私はアイドル_2';

-- お気に入り
INSERT INTO song_favorites (song_id, count)
  SELECT '765as_私はアイドル', count FROM song_favorites WHERE song_id = '765as_私はアイドル_2'
  ON CONFLICT(song_id) DO UPDATE SET count = count + excluded.count;
DELETE FROM song_favorites WHERE song_id = '765as_私はアイドル_2';
UPDATE OR IGNORE device_song_favorite SET song_id = '765as_私はアイドル' WHERE song_id = '765as_私はアイドル_2';
DELETE FROM device_song_favorite WHERE song_id = '765as_私はアイドル_2';

-- ペンライト色
INSERT INTO penlight_color_set_votes (song_id, color_set_key, count)
  SELECT '765as_私はアイドル', color_set_key, count FROM penlight_color_set_votes WHERE song_id = '765as_私はアイドル_2'
  ON CONFLICT(song_id, color_set_key) DO UPDATE SET count = count + excluded.count;
DELETE FROM penlight_color_set_votes WHERE song_id = '765as_私はアイドル_2';
UPDATE OR IGNORE device_song_penlight SET song_id = '765as_私はアイドル' WHERE song_id = '765as_私はアイドル_2';
DELETE FROM device_song_penlight WHERE song_id = '765as_私はアイドル_2';

-- セトリ予想 / 出演者予想 / セトリのいいね
INSERT INTO setlist_predictions (event_id, song_id, vote_count, first_voted_by, first_voted_at)
  SELECT event_id, '765as_私はアイドル', vote_count, first_voted_by, first_voted_at
  FROM setlist_predictions WHERE song_id = '765as_私はアイドル_2'
  ON CONFLICT(event_id, song_id) DO UPDATE SET vote_count = vote_count + excluded.vote_count;
DELETE FROM setlist_predictions WHERE song_id = '765as_私はアイドル_2';
UPDATE OR IGNORE setlist_prediction_votes SET song_id = '765as_私はアイドル' WHERE song_id = '765as_私はアイドル_2';
DELETE FROM setlist_prediction_votes WHERE song_id = '765as_私はアイドル_2';
INSERT INTO setlist_performer_predictions (show_id, song_id, idol_id, vote_count, first_voted_by, first_voted_at)
  SELECT show_id, '765as_私はアイドル', idol_id, vote_count, first_voted_by, first_voted_at
  FROM setlist_performer_predictions WHERE song_id = '765as_私はアイドル_2'
  ON CONFLICT(show_id, song_id, idol_id) DO UPDATE SET vote_count = vote_count + excluded.vote_count;
DELETE FROM setlist_performer_predictions WHERE song_id = '765as_私はアイドル_2';
UPDATE OR IGNORE setlist_performer_prediction_votes SET song_id = '765as_私はアイドル' WHERE song_id = '765as_私はアイドル_2';
DELETE FROM setlist_performer_prediction_votes WHERE song_id = '765as_私はアイドル_2';
UPDATE OR IGNORE setlist_song_likes SET song_id = '765as_私はアイドル' WHERE song_id = '765as_私はアイドル_2';
DELETE FROM setlist_song_likes WHERE song_id = '765as_私はアイドル_2';

-- お題投票 (entity_id が song_id のもの)
INSERT INTO poll_entries (poll_id, entity_id, vote_count, first_voted_by, first_voted_at)
  SELECT poll_id, '765as_私はアイドル', vote_count, first_voted_by, first_voted_at
  FROM poll_entries WHERE entity_id = '765as_私はアイドル_2'
  ON CONFLICT(poll_id, entity_id) DO UPDATE SET vote_count = vote_count + excluded.vote_count;
DELETE FROM poll_entries WHERE entity_id = '765as_私はアイドル_2';
UPDATE OR IGNORE poll_votes SET entity_id = '765as_私はアイドル' WHERE entity_id = '765as_私はアイドル_2';
DELETE FROM poll_votes WHERE entity_id = '765as_私はアイドル_2';

-- 歌詞・コールガイド (残す側に既にあれば消す側を捨てる)
UPDATE OR IGNORE song_lyrics SET song_id = '765as_私はアイドル' WHERE song_id = '765as_私はアイドル_2';
UPDATE lyric_lines SET song_id = '765as_私はアイドル'
  WHERE song_id = '765as_私はアイドル_2' AND EXISTS (SELECT 1 FROM song_lyrics WHERE song_id = '765as_私はアイドル');
DELETE FROM song_lyrics WHERE song_id = '765as_私はアイドル_2';
DELETE FROM lyric_lines WHERE song_id = '765as_私はアイドル_2';
UPDATE OR IGNORE song_call_stats SET song_id = '765as_私はアイドル' WHERE song_id = '765as_私はアイドル_2';
DELETE FROM song_call_stats WHERE song_id = '765as_私はアイドル_2';
UPDATE call_edit_history SET song_id = '765as_私はアイドル' WHERE song_id = '765as_私はアイドル_2';

-- 事後確認 (0 になっていること)
SELECT 'left(_2)' AS what,
  (SELECT count(*) FROM song_tags WHERE song_id = '765as_私はアイドル_2')
  + (SELECT count(*) FROM song_favorites WHERE song_id = '765as_私はアイドル_2')
  + (SELECT count(*) FROM poll_entries WHERE entity_id = '765as_私はアイドル_2') AS n;
