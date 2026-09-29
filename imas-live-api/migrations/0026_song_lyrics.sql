-- 歌詞配信 (最小構成)。
--
-- ⚠️ 歌詞本文は D1 にしか置かない。db/master.sql / ImasLiveDB/Resources/master.sqlite /
--    CloudKit のいずれにも入れてはいけない。JASRAC 許諾の条件が「ユーザが一括
--    ダウンロードできない形式での配信」であり、bundle SQLite や CloudKit の
--    レコード同期はまさに一括ダウンロードに当たる。配信経路は
--    GET /songs/:song_id/lyrics (セッション JWT 必須・1リクエスト1曲) だけ。
--
-- タイムスタンプの形式について (このリポジトリの既存の混在をここで断ち切る):
--   本リポジトリには SQLite の datetime('now') = "2026-08-05 12:00:00" (空白区切り) と
--   JS の toISOString() = "2026-08-05T12:00:00.000Z" (T区切り) が混在していて、
--   同じ列に両方が入ると文字列比較 (BETWEEN / < / >) が壊れる。
--   ("T" > " " なので T 区切りの行は常に空白区切りより大きく並ぶ。
--    routes/polls.ts:314 はこれを避けるため toISOString() を空白区切りに潰している。)
--   → **このテーブル群は datetime('now') 形式 (UTC・空白区切り・ミリ秒なし) に統一する。**
--     既存テーブル (users.updated_at, setlist_song_likes.liked_at 等) の既定値が
--     datetime('now') であり、多数派に寄せた方が将来の JOIN/比較で事故らないため。
--   → routes/lyrics.ts は JS 側で日時文字列を組み立てず、必ず SQL の datetime('now') で書く。
--     読み出し時のみ " " を "T" に、末尾に "Z" を足して epoch 秒に変換して返す。

CREATE TABLE song_lyrics (
  song_id TEXT PRIMARY KEY,
  -- 出典 (CD ブックレット等)。表示には使わないが、権利者からの申し入れ時に
  -- 「そのテキストがどこから来たか」を示す唯一の記録になる。
  source TEXT,
  -- draft は投入・校正中で配信しない。GET が返すのは published だけ。
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published')),
  -- status が初めて published になった時刻。JASRAC 年次利用曲目報告の
  -- 母集団を「その期間に掲載していた曲」で切るための基準。
  -- 一度セットしたら published→draft→published と往復しても更新しない。
  first_published_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 報告対象期間の絞り込み (first_published_at <= 期末) に使う。
CREATE INDEX idx_song_lyrics_first_published ON song_lyrics(first_published_at);

CREATE TABLE lyric_lines (
  -- 'll_<uuid>' のサーバ採番。**発行後は不変**。
  -- 将来コールガイドが「この行にこのコール」と行 ID で紐づけるため、
  -- 本文を直すたびに ID が変わると紐付けが全部切れる。
  -- → PUT /admin/lyrics/:song_id は全消し全入れをせず、ord 順に既存 id を再利用する。
  id TEXT PRIMARY KEY,
  song_id TEXT NOT NULL,
  ord INTEGER NOT NULL,
  -- lyric = 歌詞本文 / marker = イントロ・間奏等の構造マーカー / blank = 意図的な余白。
  -- marker はコールを置く受け皿になるので歌詞行と同じテーブルに並べる。
  kind TEXT NOT NULL DEFAULT 'lyric' CHECK (kind IN ('lyric', 'marker', 'blank')),
  text TEXT NOT NULL DEFAULT '',
  section TEXT,
  -- 将来の再生連動 (曲頭からの経過ミリ秒)。今は常に NULL で、書き込み経路も作らない。
  start_ms INTEGER
);

-- GET は必ず「1曲ぶんを ord 順」で読むので、この複合索引だけで足りる。
-- UNIQUE にはしない: PUT の行数増減で ord を振り直す途中に一時的な重複が起きうるため。
CREATE INDEX idx_lyric_lines_song_ord ON lyric_lines(song_id, ord);
