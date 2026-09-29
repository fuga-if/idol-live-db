-- setlist_song_likes: ライブ後の「この曲良かった」トグル (GET /shows/:id/likes,
-- POST|DELETE /shows/:id/songs/:id/like, DELETE /users/me の連鎖削除で使う)。
--
-- ⚠️ このテーブルはコードから使われているのに CREATE TABLE がどの migration にも
--    無かった (0014 のコメントで名前が言及されているだけ)。本番 D1 には手で作られて
--    いた可能性が高く、その場合この migration は IF NOT EXISTS で no-op になる。
--    一方で migration だけから作った D1 (ローカル開発・新環境) では
--    「no such table」で 500 になっていた。
--
-- スキーマは src/index.ts の実際のクエリから決めている:
--   INSERT OR IGNORE INTO setlist_song_likes (show_id, song_id, user_id, liked_at)
--   DELETE ... WHERE show_id = ? AND song_id = ? AND user_id = ?   → 複合 PK で多重 like を物理排除
--   SELECT ... WHERE l.show_id = ? GROUP BY l.song_id              → PK 先頭が show_id なので追加索引不要
--   DELETE FROM setlist_song_likes WHERE user_id = ?               → 退会時の一括削除に user_id 索引
--
-- ⚠️ 本番へ適用する前に、既存テーブルの実スキーマ (PRAGMA table_info) が
--    これと一致するか確認すること。差があればこの定義ではなく本番に合わせる。
CREATE TABLE IF NOT EXISTS setlist_song_likes (
  show_id  TEXT NOT NULL,
  song_id  TEXT NOT NULL,
  user_id  TEXT NOT NULL,
  liked_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (show_id, song_id, user_id)
);

-- 退会 (DELETE /users/me) がユーザー単位で全 like を消すので、user_id 索引を張る。
CREATE INDEX IF NOT EXISTS idx_setlist_song_likes_user
  ON setlist_song_likes(user_id);
