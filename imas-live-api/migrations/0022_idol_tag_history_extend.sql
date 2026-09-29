-- idol_tag_description_history に description_before を追加 (tag_description_history の 0010 と同じ拡張)。
ALTER TABLE idol_tag_description_history ADD COLUMN description_before TEXT;
