-- Discord のロール受け取り (routes/discord.ts)。
--
-- discord_oauth_states: OAuth の state。ワンタイム・10 分で失効 (5 分 cron で掃除)。
--   kind = 'discord' … アプリの「Discord でロールを受け取る」から。user_id がアプリのアカウント。
--   kind = 'github'  … Discord の /申請 から。discord_user_id が申請した人 (Discord が署名した値)。
-- discord_links: アプリのアカウントと Discord のユーザーの紐付け (最後に連携したもの)。
CREATE TABLE discord_oauth_states (
  state TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  user_id TEXT,
  discord_user_id TEXT,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);
CREATE INDEX idx_discord_oauth_states_expires ON discord_oauth_states(expires_at);

CREATE TABLE discord_links (
  user_id TEXT PRIMARY KEY,
  discord_user_id TEXT NOT NULL,
  linked_at TEXT NOT NULL
);

-- #更新通知 のまとめ投稿 (discord_digest.ts) の読み進め位置。source ごとに、最後に通知した rowid。
-- 行が無い source は、初回に「今の末尾」を入れるだけで投稿しない (過去の全件を流さないため)。
CREATE TABLE discord_digest_cursors (
  source TEXT PRIMARY KEY,
  last_rowid INTEGER NOT NULL
);
