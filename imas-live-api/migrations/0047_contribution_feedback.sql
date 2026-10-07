-- 0047: データを入れた人に手応えを返す (Good の新着・公演の閲覧数) + 公演ページのクレジット
--
-- credit_opt_in: 公演ページの末尾 (奥付) に表示名を載せてよいか。本人が設定で選ぶ。既定は載せない (0)。
--   行が消えれば (退会) 一緒に消える。
-- show_views_weekly: 公演ページを見た端末の数を、JST の週 (月曜始まり、'YYYY-MM-DD') ごとに数える。
--   端末の重複は端末側で 1 週 1 公演 1 回に畳んでから送る (端末 ID の行は持たない = 個人データを積まない)。
--   「あなたが入れたセトリが先週何人に見られたか」に使うだけなので、古い週は日次 cron で消す。
-- 歌詞の投稿 (lyric_submissions) は edit_batch に入らないので、Good の新着にも閲覧数にもクレジットにも出ない。
ALTER TABLE users ADD COLUMN credit_opt_in INTEGER NOT NULL DEFAULT 0;

--   PK を (week, show_id) にして、先週の分の引き当て・古い週の削除をこの 1 本で賄う (副索引を持たず書き込みを軽く)。
CREATE TABLE IF NOT EXISTS show_views_weekly (
  week    TEXT NOT NULL,
  show_id TEXT NOT NULL,
  viewers INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (week, show_id)
);

-- batch ごとの「どの型の行があるか」(奥付の役割分け・自分のセトリの公演の引き当て) を、
-- setlist の batch の行を全部読まずに引くための索引。
CREATE INDEX IF NOT EXISTS idx_edit_history_batch_type ON edit_history(batch_id, record_type);
