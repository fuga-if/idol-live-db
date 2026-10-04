-- みんなのプレイリスト (ユーザー投稿)。端末のプレイリストを「公開する」と 1 行できる。
-- 曲は id の並びだけ (曲名・歌詞は持たない。曲メタは端末のカタログが解決する)。
-- status は active / removed (作者の取り下げ・モデレーターの非表示)。行は消さない (Discord の通知と突き合わせるため)。
CREATE TABLE IF NOT EXISTS community_playlists (
  id TEXT PRIMARY KEY NOT NULL,
  created_by TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  song_ids_json TEXT NOT NULL,
  song_count INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_community_playlists_list ON community_playlists (status, updated_at DESC, id);
CREATE INDEX IF NOT EXISTS idx_community_playlists_owner ON community_playlists (created_by);
