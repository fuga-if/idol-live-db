-- 0041: 歌詞の管理団体 (tools/jasrac/works.tsv の rights_org を写す)。
--
-- '' = JASRAC、'nextone' = NexTone。Android 版は当面 NexTone の許諾だけで歌詞を出すので、
-- Android からの取得はこの列が 'nextone' の曲に絞る (routes/lyrics.ts の lyricsAllowedForClient)。
-- 値は tools/jasrac/push_rights_org.py が works.tsv から入れる。
ALTER TABLE song_lyrics ADD COLUMN rights_org TEXT NOT NULL DEFAULT '';
