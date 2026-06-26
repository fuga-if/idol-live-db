-- 0007_community_votes.sql
-- コミュニティ集計: お気に入り数 + ペンライト色セット投票

-- お気に入り集計
CREATE TABLE IF NOT EXISTS song_favorites (
  song_id TEXT PRIMARY KEY,
  count INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS device_song_favorite (
  device_id TEXT NOT NULL,
  song_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (device_id, song_id)
);
CREATE INDEX IF NOT EXISTS idx_song_favorites_count ON song_favorites(count DESC);

-- ペンラ色パレットマスタ
CREATE TABLE IF NOT EXISTS penlight_palette (
  color_hex TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  note TEXT
);

-- ペンラ色セット集計
CREATE TABLE IF NOT EXISTS penlight_color_set_votes (
  song_id TEXT NOT NULL,
  color_set_key TEXT NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (song_id, color_set_key)
);

-- 端末ごとの最新投票（差し替え用）
CREATE TABLE IF NOT EXISTS device_song_penlight (
  device_id TEXT NOT NULL,
  song_id TEXT NOT NULL,
  color_set_key TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (device_id, song_id)
);

-- 公式パレット初期データ
INSERT OR IGNORE INTO penlight_palette (color_hex, name, sort_order, note) VALUES
  ('#FFFFFF', '白',     1, '黒ペンライトの代用として使われることが多い'),
  ('#FF0000', '赤',     2, NULL),
  ('#FF69B4', 'ピンク', 3, NULL),
  ('#FF00FF', 'マゼンタ', 4, NULL),
  ('#FFA500', 'オレンジ', 5, NULL),
  ('#FFFF00', '黄',     6, '小鳥さん（本来グリーン）で振られることもある'),
  ('#ADFF2F', '黄緑',   7, NULL),
  ('#00FF00', '緑',     8, '星井美希（本来イエロー）で振られることもある'),
  ('#00FFFF', 'シアン', 9, NULL),
  ('#87CEEB', '水色',  10, NULL),
  ('#0000FF', '青',    11, NULL),
  ('#800080', '紫',    12, NULL),
  ('#A0522D', '茶',    13, NULL),
  ('#FFD700', '金',    14, NULL),
  ('#C0C0C0', '銀',    15, NULL);
