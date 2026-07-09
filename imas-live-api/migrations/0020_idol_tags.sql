-- アイドルタグ付け (song_tags / device_song_tag と同じ形。tags マスタは曲と共有する)。
CREATE TABLE idol_tags (
  idol_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  vote_count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (idol_id, tag_id)
);
CREATE INDEX idx_idol_tags_count ON idol_tags(tag_id, vote_count DESC);

-- 端末ごとの付与記録（重複防止）
CREATE TABLE device_idol_tag (
  device_id TEXT NOT NULL,
  idol_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (device_id, idol_id, tag_id)
);
