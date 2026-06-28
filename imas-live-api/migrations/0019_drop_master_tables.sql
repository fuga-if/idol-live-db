-- D1 から曲・アイドル系マスタテーブルを削除。
--
-- 背景:
--   マスタの真実は iOS バンドルの master.sqlite (クライアント主導で更新)。
--   D1 側は集計系 (タグ/ペンライト/投票/予想/お気に入り) のみを担うため、
--   これらマスタテーブルは「使われていない/使う予定もない」二重管理になっていた。
--   集計系の各テーブルは entity_id を不透明文字列として保存しており、
--   表示時にクライアントが master.sqlite から解決する。
--
-- 残すもの:
--   - brands: 9 行で軽量、brand スコープ作成時の typo 検証に使う
--   - users / submissions / votes / meta / api_rate_limits: 別系統 (システム)
--
-- 削除順は外部参照ぽい子→親 (FK は無いが慣習として)。
DROP TABLE IF EXISTS setlist_performers;
DROP TABLE IF EXISTS setlist_items;
DROP TABLE IF EXISTS show_cast;
DROP TABLE IF EXISTS shows;
DROP TABLE IF EXISTS events;
DROP TABLE IF EXISTS unit_members;
DROP TABLE IF EXISTS units;
DROP TABLE IF EXISTS song_artists;
DROP TABLE IF EXISTS songs;
DROP TABLE IF EXISTS idol_cast;
DROP TABLE IF EXISTS cast;
DROP TABLE IF EXISTS idol_brands;
DROP TABLE IF EXISTS idols;
