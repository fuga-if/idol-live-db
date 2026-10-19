-- GET /tags/activity が device_song_tag / device_idol_tag を毎回フルスキャンしていた。
--
-- 「最近つけられたタグ」(ORDER BY created_at DESC LIMIT 40) と「伸びてる / 急上昇」
-- (WHERE created_at >= 期間の頭) の 6 本とも created_at で引くのに索引が無く、
-- 1 回のキャッシュ外れで両表の全行 × 3 を読んでいた。表は票が増えるほど伸びるので、
-- rows_read が利用者数に比例して膨らむ形 (0036 と同じ種類の事象)。
-- created_at の索引で、新しい 40 行と期間内の行だけを読む形にする。
CREATE INDEX IF NOT EXISTS idx_device_song_tag_created ON device_song_tag(created_at);
CREATE INDEX IF NOT EXISTS idx_device_idol_tag_created ON device_idol_tag(created_at);
