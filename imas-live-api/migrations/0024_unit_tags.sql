-- ユニットタグ付け (idol_tags/idol_tag_master と同じ形の並走テーブル)。
CREATE TABLE unit_tags (
  unit_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  vote_count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (unit_id, tag_id)
);
CREATE INDEX idx_unit_tags_count ON unit_tags(tag_id, vote_count DESC);

-- 端末ごとの付与記録（重複防止）
CREATE TABLE device_unit_tag (
  device_id TEXT NOT NULL,
  unit_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (device_id, unit_id, tag_id)
);

CREATE TABLE unit_tag_master (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  category TEXT,
  color TEXT,
  created_by TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_by TEXT,
  updated_at INTEGER NOT NULL,
  is_official INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active'
);

-- idol_tag_description_history は description_before を後付け (0022) したが、
-- unit_tag_master は最初からこの列を持つ (idol 版と違い移行専用データが無いため)。
CREATE TABLE unit_tag_description_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tag_id TEXT NOT NULL,
  description TEXT,
  description_before TEXT,
  edited_by TEXT NOT NULL,
  edited_at INTEGER NOT NULL
);
CREATE INDEX idx_unit_tag_history_tag ON unit_tag_description_history(tag_id, edited_at DESC);

CREATE TABLE unit_tag_reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tag_id TEXT NOT NULL,
  reported_by TEXT NOT NULL,
  reason TEXT,
  reported_at INTEGER NOT NULL
);
CREATE INDEX idx_unit_tag_reports_tag ON unit_tag_reports(tag_id);
