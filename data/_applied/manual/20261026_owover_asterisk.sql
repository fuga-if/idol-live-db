-- ØωØver!! と -Heart Beat Version- の歌唱者が「デレパジ」(渋谷凛・島村卯月・城ヶ崎美嘉・多田李衣菜・本田未央) になっていた。
-- 正しくは ＊(Asterisk) (前川みく・多田李衣菜)。セトリの表記も全公演 ＊(Asterisk)。
-- song_units は CloudKit に型が無く db/master.sql だけが正。原唱者の 8 行は CloudKit から
-- owover_asterisk_cloudkit_delete_20261026.tsv で物理削除する。
-- 2 公演 (AP06&07 発売記念イベント、MOIW2015 Day2) は出演者が空だったので、出演表にいる 2 人を入れる。
BEGIN;
UPDATE songs SET singer_label = '＊(Asterisk)', unit_name = '＊(Asterisk)', unit_id = 'unit_444a9693'
  WHERE id IN ('cg_øωøver', 'cg_øωøver_-heart_beat_version-');
DELETE FROM song_artists WHERE song_id IN ('cg_øωøver', 'cg_øωøver_-heart_beat_version-') AND role = 'original'
  AND idol_id IN ('cg_渋谷凛', 'cg_島村卯月', 'cg_城ヶ崎美嘉', 'cg_本田未央');
INSERT OR IGNORE INTO song_artists VALUES ('cg_øωøver', 'cg_前川みく', 'original');
INSERT OR IGNORE INTO song_artists VALUES ('cg_øωøver_-heart_beat_version-', 'cg_前川みく', 'original');
DELETE FROM song_units WHERE song_id IN ('cg_øωøver', 'cg_øωøver_-heart_beat_version-') AND unit_id = 'デレパジ';
INSERT OR IGNORE INTO setlist_performers VALUES ('sh_L0247_2081', 'cg_前川みく'), ('sh_L0247_2081', 'cg_多田李衣菜'),
  ('sh_L0260_2201', 'cg_前川みく'), ('sh_L0260_2201', 'cg_多田李衣菜');
COMMIT;
