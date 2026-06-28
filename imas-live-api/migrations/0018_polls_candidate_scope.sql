-- みんなの投票: 候補スコープ拡張
-- candidate_scope:
--   'all'    : 既存挙動。scope_brand_ids / scope_entity_ids は無視
--   'brand'  : scope_brand_ids = JSON配列 (例: ["961","876"]). 1件以上必須
--   'manual' : scope_entity_ids = JSON配列 (例: ["song_xxx","song_yyy"]). 2件以上 / 500件以下
ALTER TABLE polls ADD COLUMN candidate_scope TEXT NOT NULL DEFAULT 'all'
  CHECK (candidate_scope IN ('all','brand','manual'));
ALTER TABLE polls ADD COLUMN scope_brand_ids TEXT;
ALTER TABLE polls ADD COLUMN scope_entity_ids TEXT;
