-- SideM Five-St@r Party!! (2018-05-20 昼/夜) の歌唱者と位置を直す (issue #145 #146 #147)
-- 出典: 公式の出演者 https://imas-sidem.com/special/event/fivestarparty/index.html (Beit は堀江瞬・高塚智人のみ。鷹城恭二は出演していない)
--       夏時間グラフィティの歌唱 = Beit, High×Joker, W (https://imas-db.jp/song/event/sidem5star.html)
BEGIN;
DELETE FROM setlist_performers WHERE setlist_item_id IN ('sh_L0440_4323','sh_L0441_4329') AND idol_id='sidem_鷹城恭二';
INSERT OR IGNORE INTO setlist_performers (setlist_item_id, idol_id) VALUES
 ('sh_L0440_4323','sidem_蒼井悠介'),('sh_L0440_4323','sidem_蒼井享介'),
 ('sh_L0441_4329','sidem_蒼井悠介'),('sh_L0441_4329','sidem_蒼井享介');
UPDATE setlist_items SET position = position - 4321 WHERE show_id='sh_L0440';
UPDATE setlist_items SET position = position - 4327 WHERE show_id='sh_L0441';
COMMIT;
