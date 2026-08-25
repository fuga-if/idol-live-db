-- 0030: lyrics_gram_index の posting を複数行に分割できるようにする。
--
-- 0029 は gram を PRIMARY KEY にしていたので、1つの gram の posting が必ず 1 行に
-- 収まる必要があった。ところが「い」は 2,287 曲に当たり、song_id を並べるだけで
-- 60KB になる。D1 は 1 SQL 文の長さに上限 (100KB 程度) があるため、この 1 行を
-- INSERT するだけで上限に近づき、曲が増えれば確実に超える。
--
-- gram + part を PK にして、長い posting は part を増やして分割できるようにする。
-- 読む側 (routes/lyrics.ts) は gram ごとに全 part を連結してから交差を取る。
--
-- 0029 で作った表は空 (索引未投入) なので、作り直しでデータは失われない。

DROP TABLE IF EXISTS lyrics_gram_index;

CREATE TABLE lyrics_gram_index (
  -- 1文字 または 2文字。歌詞本文から取った素の部分文字列 (正規化しない)。
  gram TEXT NOT NULL,
  -- 同じ gram の posting を分割した通し番号。分割不要なら 0 だけ。
  part INTEGER NOT NULL DEFAULT 0,
  -- その gram を含む song_id を "\n" 区切りで並べたもの。
  song_ids TEXT NOT NULL,
  PRIMARY KEY (gram, part)
) WITHOUT ROWID;
