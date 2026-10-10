-- 0049: 歌詞を消したときに退避した注釈 (歌割・タイミング・コール・ここ好き)。
--
-- 2026-10-06 に歌詞本文を全削除したとき、利用者が付けた注釈だけを行 id/ord で手元に退避した。
-- 歌詞が投稿で入り直したら storeLyrics がここから付け直す (src/lyrics_annotation_archive.ts)。
-- 歌詞本文と anchorText は持たない。本文由来のコールは text を除いてある (戻せないので付け直さない)。
--
-- lines_json … 注釈のある行だけの配列 ({id, ord, kind, start_ms, clap, singers, partBreaks, calls})。
-- likes_json … {行 id: 人数} (ここ好き)。
-- restored_at … 付け直した時刻。NULL = まだ (行が合わない曲は NULL のまま残る)。
-- 中身は tools/lyrics/upload_annotation_archive.py が手元の退避ファイルから入れる。
CREATE TABLE IF NOT EXISTS lyric_annotation_archive (
  song_id TEXT PRIMARY KEY,
  lines_json TEXT NOT NULL,
  likes_json TEXT NOT NULL DEFAULT '{}',
  archived_at TEXT NOT NULL,
  restored_at TEXT
);
