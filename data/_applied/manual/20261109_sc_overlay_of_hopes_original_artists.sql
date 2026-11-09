-- OVERLAY OF HOPES (sc_overlay_of_hopes, 全体曲) の原唱者 28 人を既存の全体曲 (sc_borderline 等) と同じ形で入れる
-- 根拠: https://x.com/imassc_prism/status/2113593234899554476 (全 28 名による歌唱)
BEGIN;
INSERT OR IGNORE INTO song_artists (song_id, idol_id, role)
  SELECT 'sc_overlay_of_hopes', idol_id, 'original' FROM unit_members WHERE unit_id='unit_シャイニーカラーズ';
COMMIT;
