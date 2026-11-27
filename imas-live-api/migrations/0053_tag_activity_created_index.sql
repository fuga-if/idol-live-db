-- 0053: GET /tags/activity (最近のタグ・伸びてるタグ・急上昇) の 6 本のクエリが
-- device_song_tag / device_idol_tag を created_at で引くのに索引が無く、キャッシュが外れるたびに
-- 両表を全件読んでいた (D1 の rows_read が票数に比例して増える)。新しい行と期間内の行だけを読ませる。
--
-- 10/19 の e7f09230 (0051 で出したが未マージ。0051 は別のマイグレーションが使った) の出し直し。
-- 追加だけ (列・既存の索引は変えない)。
CREATE INDEX IF NOT EXISTS idx_device_song_tag_created ON device_song_tag(created_at);
CREATE INDEX IF NOT EXISTS idx_device_idol_tag_created ON device_idol_tag(created_at);
