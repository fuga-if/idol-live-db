-- brand スコープのお題作成で「その他」ブランドを選ぶと 400 (scope_brand_ids contains unknown id) で
-- 作れなかった。D1 の brands は brand_id の実在チェックだけに使う写しで、master の 'other' が抜けていた。
-- 写しなので名前・色は master.sqlite の brands に合わせる (表示には使っていない)。
INSERT OR IGNORE INTO brands (id, name, short_name, color, sort_order)
VALUES ('other', 'その他', 'Other', '#8E8E93', 99);
