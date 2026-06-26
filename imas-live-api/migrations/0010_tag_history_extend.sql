ALTER TABLE tag_description_history ADD COLUMN description_before TEXT;
-- description カラムは変更後の値 (after) を意味する形に統一
