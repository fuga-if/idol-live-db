-- アイドルのタグに「容姿」(category = 'appearance') の公式タグをそろえる。
--
-- 容姿は idols の列ではなくタグで持つ (利用者が投票で育てられるように)。語は確認表
-- (data/research/appearance_20261010/idol_appearance_review_20261010.csv の「入れるタグ」列)
-- とそろえてある。目のタグは今は扱わない。「メガネ」「和装」「タレ目」「ほくろ」などは触らない。
--
-- **本番には利用者が作った髪のタグが既にある** (ロングヘア・黒髪・ツインテール・
-- 白髪・銀髪 など。category は主に charm)。それらは作り直さず、**名前で照合して**その行を
-- 公式・容姿にする (id は本番の行のまま。票も付いたまま)。新しく作るのは本番に同名が
-- 無い語だけ。下の 2 文はどちらも名前だけを見るので、どの環境に流しても同じ結果になる:
--   1. 同名の行が無い語だけを INSERT する (name は UNIQUE。id は新しく作る行にだけ使う)
--   2. 一覧の名前の行を、全部 公式・容姿・公開中 にする (description は書き換えない)
-- 初期値 (運営の票) はここでは入れない。tools/apply_data.py の --d1-sql が名前から引いて入れる。
--
-- 公式タグを作る API は無い (POST は is_official = 0 固定) ので、0007 の penlight_palette と
-- 同じく migration で入れる。created_by は端末 ID ではなく 'official'。

WITH official(id, name, description) AS (VALUES
  ('official_appearance_hair_black', '黒髪', '髪色'),
  ('official_appearance_hair_brown', '茶髪', '髪色'),
  ('official_appearance_hair_blonde', '金髪', '髪色'),
  ('official_appearance_hair_silver', '白髪・銀髪', '髪色'),
  ('official_appearance_hair_red', '赤髪', '髪色'),
  ('official_appearance_hair_orange', 'オレンジ髪', '髪色'),
  ('official_appearance_hair_pink', 'ピンク髪', '髪色'),
  ('official_appearance_hair_green', '緑髪', '髪色'),
  ('official_appearance_hair_blue', '青髪', '髪色'),
  ('official_appearance_hair_lightblue', '水色の髪', '髪色'),
  ('official_appearance_hair_purple', '紫髪', '髪色'),
  ('official_appearance_hair_multicolor', '髪色2色以上', '髪色'),
  ('official_appearance_length_long', 'ロングヘア', '髪の長さ'),
  ('official_appearance_length_bob_medium', 'ボブ〜ミディアムヘア', '髪の長さ'),
  ('official_appearance_length_short', 'ショートヘア', '髪の長さ'),
  ('official_appearance_style_twintails', 'ツインテール', '髪型'),
  ('official_appearance_style_low_twintails', 'ローツインテール', '髪型'),
  ('official_appearance_style_ponytail', 'ポニーテール', '髪型'),
  ('official_appearance_style_sidetail', 'サイドテール', '髪型'),
  ('official_appearance_style_half_sidetail', 'ハーフサイドテール', '髪型'),
  ('official_appearance_style_two_side_up', 'ツーサイドアップ', '髪型'),
  ('official_appearance_style_half_up', 'ハーフアップ', '髪型'),
  ('official_appearance_style_half_up_twin', 'ハーフアップツイン', '髪型'),
  ('official_appearance_style_braid', '三つ編み・編み込み', '髪型'),
  ('official_appearance_style_bun', 'お団子ヘア', '髪型'),
  ('official_appearance_style_single_tie', 'ひとつ縛り', '髪型'),
  ('official_appearance_style_updo', 'まとめ髪', '髪型'),
  ('official_appearance_style_wavy', 'ウェーブ', '髪型'),
  ('official_appearance_style_drill', '縦ロール', '髪型'),
  ('official_appearance_style_straight', 'ストレートヘア', '髪型'),
  ('official_appearance_style_blunt_bangs', 'ぱっつん前髪', '髪型'),
  ('official_appearance_style_hime_cut', '姫カット', '髪型'),
  ('official_appearance_style_center_part', 'センター分け', '髪型'),
  ('official_appearance_style_slicked_back', 'オールバック', '髪型'),
  ('official_appearance_style_pompadour', 'リーゼント', '髪型'),
  ('official_appearance_style_forehead', 'おでこ', '髪型'),
  ('official_appearance_style_ahoge', 'アホ毛', '髪型'),
  ('official_appearance_style_messy', '跳ね毛', '髪型'),
  ('official_appearance_style_flipped_out', '外はね', '髪型'),
  ('official_appearance_style_spiky', '逆立てた髪', '髪型'),
  ('official_appearance_style_one_eye_hidden', '片目隠れ', '髪型'),
  ('official_appearance_accessory_ribbon', 'リボン', '髪の飾り'),
  ('official_appearance_accessory_hairband', 'ヘアバンド', '髪の飾り'),
  ('official_appearance_accessory_hairpin', 'ヘアピン', '髪の飾り'),
  ('official_appearance_accessory_hair_ornament', '髪飾り', '髪の飾り')
)
INSERT INTO idol_tag_master
  (id, name, description, category, color, created_by, created_at, updated_at, is_official, status)
SELECT o.id, o.name, o.description, 'appearance', NULL, 'official',
       CAST(strftime('%s', 'now') AS INTEGER), CAST(strftime('%s', 'now') AS INTEGER), 1, 'active'
  FROM official o
 WHERE NOT EXISTS (SELECT 1 FROM idol_tag_master t WHERE t.name = o.name);

UPDATE idol_tag_master
   SET is_official = 1, category = 'appearance', status = 'active'
 WHERE name IN (
       '黒髪', '茶髪', '金髪', '白髪・銀髪', '赤髪', 'オレンジ髪', 'ピンク髪', '緑髪', '青髪', '水色の髪', '紫髪', '髪色2色以上',
       'ロングヘア', 'ボブ〜ミディアムヘア', 'ショートヘア',
       'ツインテール', 'ローツインテール', 'ポニーテール', 'サイドテール', 'ハーフサイドテール', 'ツーサイドアップ', 'ハーフアップ', 'ハーフアップツイン', '三つ編み・編み込み', 'お団子ヘア', 'ひとつ縛り', 'まとめ髪', 'ウェーブ', '縦ロール', 'ストレートヘア', 'ぱっつん前髪', '姫カット', 'センター分け', 'オールバック', 'リーゼント', 'おでこ', 'アホ毛', '跳ね毛', '外はね', '逆立てた髪', '片目隠れ',
       'リボン', 'ヘアバンド', 'ヘアピン', '髪飾り'
       );
