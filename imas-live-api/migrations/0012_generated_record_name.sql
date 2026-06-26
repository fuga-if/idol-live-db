-- 0012: new_song type の retry 時に recordName が変わらないよう永続化
ALTER TABLE submissions ADD COLUMN generated_record_name TEXT;
