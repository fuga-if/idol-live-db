-- タグマスタ（誰でも作成可能）
CREATE TABLE tags (
  id TEXT PRIMARY KEY,                 -- slug: ASCII小文字+数字+ハイフンに正規化、日本語は tag_ + base64url(name)
  name TEXT NOT NULL UNIQUE,           -- 表示名（日本語OK）"蒼い", "vo力団"
  description TEXT,                    -- 説明文（プレーンテキスト、改行可）
  category TEXT,                       -- mood/scene/special/free のいずれか、null可
  color TEXT,                          -- HEX任意
  created_by TEXT NOT NULL,            -- device_id
  created_at INTEGER NOT NULL,
  updated_by TEXT,
  updated_at INTEGER NOT NULL,
  is_official INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active'  -- active/under_review/removed
);

-- 曲↔タグ集計
CREATE TABLE song_tags (
  song_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  vote_count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (song_id, tag_id)
);
CREATE INDEX idx_song_tags_count ON song_tags(tag_id, vote_count DESC);

-- 端末ごとの付与記録（重複防止）
CREATE TABLE device_song_tag (
  device_id TEXT NOT NULL,
  song_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (device_id, song_id, tag_id)
);

-- 説明文編集履歴（過去版閲覧用 (rollback未実装)）
CREATE TABLE tag_description_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tag_id TEXT NOT NULL,
  description TEXT,
  edited_by TEXT NOT NULL,
  edited_at INTEGER NOT NULL
);
CREATE INDEX idx_tag_history_tag ON tag_description_history(tag_id, edited_at DESC);

-- タグ作成レート制限カウンタ
CREATE TABLE device_tag_create_quota (
  device_id TEXT NOT NULL,
  date_ymd TEXT NOT NULL,    -- "YYYY-MM-DD"
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (device_id, date_ymd)
);

-- タグ通報
CREATE TABLE tag_reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tag_id TEXT NOT NULL,
  reported_by TEXT NOT NULL,
  reason TEXT,
  reported_at INTEGER NOT NULL
);
CREATE INDEX idx_tag_reports_tag ON tag_reports(tag_id);
