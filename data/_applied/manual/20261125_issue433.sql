-- issue #433: 283 Production XXXX Performance XXX= S/N-GUL4R1TY // 0x03; overflow() (sh_L1249)
-- VOY@GER の歌唱者: 公式セトリ画像 (https://idolmaster-official.jp/news/01_18479.html) で「ストレイライト」→ 芹沢あさひ・和泉愛依を足す
-- 区分 (アンコール / ダブルアンコール): 公式画像に記載なし・他の出典も見つからず投稿内容で登録
BEGIN;
UPDATE setlist_items SET section='アンコール' WHERE id IN ('sh_L1249_13365','sh_L1249_13366','sh_L1249_13367');
UPDATE setlist_items SET section='ダブルアンコール' WHERE id='sh_L1249_13368';
INSERT OR IGNORE INTO setlist_performers(setlist_item_id,idol_id) VALUES ('sh_L1249_13364','sc_芹沢あさひ'),('sh_L1249_13364','sc_和泉愛依');
COMMIT;
