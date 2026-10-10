-- アイドルのタグに「容姿」(category = 'appearance') の公式タグを足す。
--
-- 容姿は idols の列ではなくタグで持つ (利用者が投票で育てられるように)。語は
-- data/fixes/idol_appearance_review_20261010.csv の「入れるタグ」列とそろえてある
-- (オーナーはこの表を見て確認している)。description は画面でまとまりを見分けるための
-- 小分類 (髪色 / 髪の長さ / 髪型 / 髪の飾り)。目のタグは今は足さない。既存の「メガネ」
-- 「和装」は今の分類 (charm) のまま。
--
-- 公式のタグを作る API は無い (POST は is_official = 0 固定) ので、0007 の penlight_palette と
-- 同じく migration で入れる。created_by は端末 ID ではなく 'official'。
--
-- 同じ名前のタグを利用者が先に作っていた場合 (name は UNIQUE) は INSERT を飛ばし、
-- そのタグを公式・容姿にする (同じ語は同じ意味なので、票を分けない)。
-- 初期値 (票) はここでは入れない。入れ方はオーナーの承認待ち。

WITH official(id, name, description) AS (VALUES
  ('official_appearance_hair_black', '黒髪', '髪色'),
  ('official_appearance_hair_brown', '茶髪', '髪色'),
  ('official_appearance_hair_blonde', '金髪', '髪色'),
  ('official_appearance_hair_silver', '銀髪', '髪色'),
  ('official_appearance_hair_red', '赤髪', '髪色'),
  ('official_appearance_hair_orange', 'オレンジ髪', '髪色'),
  ('official_appearance_hair_pink', 'ピンク髪', '髪色'),
  ('official_appearance_hair_green', '緑髪', '髪色'),
  ('official_appearance_hair_blue', '青髪', '髪色'),
  ('official_appearance_hair_lightblue', '水色の髪', '髪色'),
  ('official_appearance_hair_purple', '紫髪', '髪色'),
  ('official_appearance_length_long', 'ロングヘア', '髪の長さ'),
  ('official_appearance_length_medium', 'ミディアムヘア', '髪の長さ'),
  ('official_appearance_length_short', 'ショートヘア', '髪の長さ'),
  ('official_appearance_style_twintails', 'ツインテール', '髪型'),
  ('official_appearance_style_ponytail', 'ポニーテール', '髪型'),
  ('official_appearance_style_sidetail', 'サイドテール', '髪型'),
  ('official_appearance_style_two_side_up', 'ツーサイドアップ', '髪型'),
  ('official_appearance_style_half_up', 'ハーフアップ', '髪型'),
  ('official_appearance_style_braid', '三つ編み', '髪型'),
  ('official_appearance_style_braided_in', '編み込み', '髪型'),
  ('official_appearance_style_bun', 'お団子', '髪型'),
  ('official_appearance_style_bob', 'ボブ', '髪型'),
  ('official_appearance_style_wavy', 'ウェーブ', '髪型'),
  ('official_appearance_style_drill', '縦ロール', '髪型'),
  ('official_appearance_style_straight', 'ストレートヘア', '髪型'),
  ('official_appearance_style_blunt_bangs', 'ぱっつん前髪', '髪型'),
  ('official_appearance_style_center_part', 'センター分け', '髪型'),
  ('official_appearance_style_slicked_back', 'オールバック', '髪型'),
  ('official_appearance_style_ahoge', 'アホ毛', '髪型'),
  ('official_appearance_style_flipped', '跳ね毛', '髪型'),
  ('official_appearance_style_spiky', '逆立てた髪', '髪型'),
  ('official_appearance_style_one_eye_hidden', '片目隠れ', '髪型'),
  ('official_appearance_style_streaks', 'メッシュ', '髪型'),
  ('official_appearance_style_two_tone', 'ツートンカラー', '髪型'),
  ('official_appearance_style_forehead', 'おでこ出し', '髪型'),
  ('official_appearance_accessory_ribbon', 'リボン', '髪の飾り'),
  ('official_appearance_accessory_hairband', 'ヘアバンド', '髪の飾り'),
  ('official_appearance_accessory_hairpin', 'ヘアピン', '髪の飾り'),
  ('official_appearance_accessory_hair_ornament', '髪飾り', '髪の飾り')
)
INSERT OR IGNORE INTO idol_tag_master
  (id, name, description, category, color, created_by, created_at, updated_at, is_official, status)
SELECT id, name, description, 'appearance', NULL, 'official',
       CAST(strftime('%s', 'now') AS INTEGER), CAST(strftime('%s', 'now') AS INTEGER), 1, 'active'
  FROM official;

UPDATE idol_tag_master
   SET is_official = 1, category = 'appearance', status = 'active'
 WHERE name IN ('黒髪', '茶髪', '金髪', '銀髪', '赤髪', 'オレンジ髪', 'ピンク髪', '緑髪', '青髪', '水色の髪', '紫髪', 'ロングヘア', 'ミディアムヘア', 'ショートヘア', 'ツインテール', 'ポニーテール', 'サイドテール', 'ツーサイドアップ', 'ハーフアップ', '三つ編み', '編み込み', 'お団子', 'ボブ', 'ウェーブ', '縦ロール', 'ストレートヘア', 'ぱっつん前髪', 'センター分け', 'オールバック', 'アホ毛', '跳ね毛', '逆立てた髪', '片目隠れ', 'メッシュ', 'ツートンカラー', 'おでこ出し', 'リボン', 'ヘアバンド', 'ヘアピン', '髪飾り')
   AND (is_official = 0 OR category IS NOT 'appearance' OR status != 'active');
