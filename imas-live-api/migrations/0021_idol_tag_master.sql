-- アイドルタグを曲タグと別プールに分離する。
-- 理由: 曲タグ (ムード/ジャンル等) とアイドルタグ (性格/属性等) は意味的に別カテゴリの語彙であり、
-- 同じマスタ (tags) を共有すると検索・人気ランキング・オートコンプリートが混ざって片方のノイズに
-- なる (例: 曲向けの「エモーショナル」がアイドルタグ候補にも出る)。song_tags/idol_tags と同じ
-- 「同じ形のテーブルをドメインごとに並走させる」既存パターンを、マスタ自体にも適用する。
CREATE TABLE idol_tag_master (
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

CREATE TABLE idol_tag_description_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tag_id TEXT NOT NULL,
  description TEXT,
  edited_by TEXT NOT NULL,
  edited_at INTEGER NOT NULL
);
CREATE INDEX idx_idol_tag_history_tag ON idol_tag_description_history(tag_id, edited_at DESC);

CREATE TABLE idol_tag_reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tag_id TEXT NOT NULL,
  reported_by TEXT NOT NULL,
  reason TEXT,
  reported_at INTEGER NOT NULL
);
CREATE INDEX idx_idol_tag_reports_tag ON idol_tag_reports(tag_id);

-- idol_tags.tag_id は今後 idol_tag_master.id を指す (0020 時点では tags.id を共有していた)。
-- この時点で idol_tags に入っている行は本セッションで追加された機能がリリース直後のため実データ無し
-- (device_idol_tag も同様)。安全のため明示的に空にしておく (旧 tags.id を指す孤立行を残さない)。
DELETE FROM device_idol_tag;
DELETE FROM idol_tags;
