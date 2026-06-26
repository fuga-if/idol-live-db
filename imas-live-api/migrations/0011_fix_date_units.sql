-- Fix: timestamps were stored as milliseconds (Date.now()), convert to seconds
-- Condition: values > 9999999999 are clearly in milliseconds (> year 2286 in seconds)
UPDATE tags SET created_at = created_at/1000 WHERE created_at > 9999999999;
UPDATE tags SET updated_at = updated_at/1000 WHERE updated_at > 9999999999;
UPDATE tag_description_history SET edited_at = edited_at/1000 WHERE edited_at > 9999999999;
UPDATE device_song_favorite SET created_at = created_at/1000 WHERE created_at > 9999999999;
UPDATE device_song_penlight SET created_at = created_at/1000 WHERE created_at > 9999999999;
UPDATE device_song_tag SET created_at = created_at/1000 WHERE created_at > 9999999999;
UPDATE device_tag_create_quota SET count = count WHERE 1; -- no created_at column, no-op for safety
UPDATE tag_reports SET reported_at = reported_at/1000 WHERE reported_at > 9999999999;
