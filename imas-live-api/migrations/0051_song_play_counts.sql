-- 0051: 曲の再生回数 (試聴 / フル再生を別々に)。
--
-- 端末が 1 時間に 1 回まとめて送る (POST /plays/batch)。1 曲 1 行に数を足すだけ。
-- 急上昇のために「最後に数えた週 (JST の月曜)」とその週・前の週の数を同じ行に持ち、
-- 週が変わったら今週の数を前の週へ送る (行は増やさない)。
--
-- 順位は端末のコア (imas-core community_ranking.rs) が全曲の数から出すので、
-- 数の索引は張らない (D1 は索引の更新も書き込み行に数えるので、1 曲 1 行の書き込みに留める)。
CREATE TABLE IF NOT EXISTS song_play_counts (
  song_id TEXT PRIMARY KEY NOT NULL,
  preview_count INTEGER NOT NULL DEFAULT 0,
  full_count INTEGER NOT NULL DEFAULT 0,
  week TEXT NOT NULL,
  week_preview INTEGER NOT NULL DEFAULT 0,
  week_full INTEGER NOT NULL DEFAULT 0,
  prev_week_preview INTEGER NOT NULL DEFAULT 0,
  prev_week_full INTEGER NOT NULL DEFAULT 0
) WITHOUT ROWID;
