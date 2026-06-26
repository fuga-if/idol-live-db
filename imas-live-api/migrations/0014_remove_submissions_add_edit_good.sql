-- 0014: submission/votes を即時撤去 + Good (編集への感謝) を新設
--
-- 即時オープン編集 (Phase 1-3) へ完全移行したため、承認投票 (OK/NG) を前提とした
-- submissions / votes システムは存在意義を失った。レガシーを温存せず物理 DROP する。
--
-- Good は「承認」とは切り離し、編集 (貢献) 1 batch への感謝/拍手・人気指標とする。
-- 1 ユーザー操作 = 1 edit_batch (Phase 1) なので Good も batch 単位で付ける
-- (POST /edits/:batchId/good)。複合 PK (batch_id, user_id) で 1 アカウント 1 Good を物理排除。
--
-- 貢献度は 2 指標を個別集計し合成しない:
--   - 編集件数      = users.contribution_count (1 batch finalize で +1。既存カラム流用)
--   - 受け取った Good = edit_good を editor 単位で COUNT (都度算出。低トラフィック前提)
--
-- 注意: 外部キー制約 ON のため、参照元 (votes → submissions) を先に DROP する。

-- 旧投票テーブル (submissions を参照) を先に削除
DROP INDEX IF EXISTS idx_votes_unique;
DROP TABLE IF EXISTS votes;

-- 旧投稿テーブルと関連 index を削除
DROP INDEX IF EXISTS idx_submissions_status_applied;
DROP INDEX IF EXISTS idx_submissions_author_status;
DROP INDEX IF EXISTS idx_submissions_generated_record_name;
DROP TABLE IF EXISTS submissions;

-- Good: 編集 batch への感謝 (toggle 型)。
--   - 複合 PK で多重 Good を物理排除 (votes / setlist_song_likes と同方針)
--   - 誰が押したか行を残すのは「自分が Good 済みか」判定 + BAN 時の濫用巻き戻しに必要
--   - 集計は COUNT(*) で都度算出
CREATE TABLE IF NOT EXISTS edit_good (
  batch_id   INTEGER NOT NULL REFERENCES edit_batch(id),
  user_id    TEXT    NOT NULL REFERENCES users(id),
  created_at INTEGER NOT NULL,  -- unixepoch ミリ秒 (edit_batch.created_at と同単位)
  PRIMARY KEY (batch_id, user_id)
);

-- batch_id 集計 (フィードの good_count) / user_id 集計 (BAN 時の巻き戻し・濫用検知) 両方向の index
CREATE INDEX IF NOT EXISTS idx_edit_good_batch ON edit_good(batch_id);
CREATE INDEX IF NOT EXISTS idx_edit_good_user  ON edit_good(user_id);
