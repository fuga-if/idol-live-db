-- 0027: 歌詞の行を lyric_lines テーブルから song_lyrics.lines_json へ移す。
--
-- 動機は D1 の行読み取り上限。1曲 60 行を別テーブルに持つと、歌詞を1曲返すたびに
-- 60 行読む。D1 無料枠は 500万行/日、Worker は 10万リクエスト/日なので、
--   100,000 req × 60 行 = 600万行 > 500万行
-- となり、**リクエスト数より先に行読み取りが上限に当たる**。
-- JSON 1列にすれば 60 行 → 1 行になる。
--
-- 行をテーブルに分けていた本来の目的は「行に安定 ID を持たせ、歌詞を編集しても
-- コールの紐付けが壊れないようにする」ことだった。ID の安定性は JSON の中でも
-- 同じように担保できる (再 PUT 時に ord 順で既存 ID を引き継ぐ) ので、
-- テーブルである必要は無かった。
--
-- lines_json の形:
--   [{"id":"ll_<uuid>","ord":0,"kind":"lyric","text":"…","section":null,"startMs":null}, …]
--   kind は lyric / marker / blank。startMs は将来の再生連動用で現状は常に null。
--
-- SQL で行を個別に触れなくなるが、必要としている箇所は無い:
--   - コールは line_id を持つだけで、行の実体はアプリ側が JSON から解決する
--   - 歌詞検索は FTS の別テーブルを作るので lyric_lines を引くわけではない

ALTER TABLE song_lyrics ADD COLUMN lines_json TEXT NOT NULL DEFAULT '[]';

-- 既存データを JSON へ移す。json_group_array は挿入順を保証しないので、
-- ORDER BY を効かせるためにサブクエリで並べてから集約する。
UPDATE song_lyrics
   SET lines_json = COALESCE((
     SELECT json_group_array(
              json_object(
                'id', id, 'ord', ord, 'kind', kind,
                'text', text, 'section', section, 'startMs', start_ms
              )
            )
       FROM (SELECT * FROM lyric_lines WHERE song_id = song_lyrics.song_id
              ORDER BY ord, id)
   ), '[]');

DROP INDEX IF EXISTS idx_lyric_lines_song_ord;
DROP TABLE lyric_lines;
