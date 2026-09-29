-- 0032: コールガイドの一覧・履歴用メタデータ。
--
-- なぜ表を 2 つ増やすのか (lines_json から都度数える案を採らない理由):
--   1. **履歴は lines_json から作れない。** song_lyrics には「今の姿」しか無く、
--      誰がいつ何行ぶんのコールを書いたかはどこにも残っていない。
--      「最近の編集」を出す以上、書き込み時に記録する場所が要る。
--   2. **一覧の読みを曲数に対して O(1) で頭打ちにする。** 一覧のたびに lines_json を
--      舐めると読み取り行数が歌詞の登録曲数に比例して増え続ける。この表なら
--      「コールがある曲」だけが行になり、LIMIT で上限が決まる (0027 が
--      「歌詞 1 曲 = D1 1 行読み」を選んだ理由を一覧側でも守る)。
--
-- ⚠️ song_call_stats は派生データ。真実は song_lyrics.lines_json 側にしかない。
--    壊れたら下の backfill と同じ SQL で作り直せること (それ以上の復旧手段は要らない)。
--    call_edit_history だけは派生ではない (作り直せない一次データ)。
--
-- タイムスタンプは 0026 の規約どおり datetime('now') 形式 (UTC・空白区切り・ミリ秒なし)。
-- 読み出し時にのみ epoch 秒へ変換する (routes/lyrics.ts の sqliteTimestampToEpochSeconds)。

CREATE TABLE IF NOT EXISTS song_call_stats (
  song_id TEXT PRIMARY KEY,
  -- clap か calls が付いている行数 (= 注釈のある行数)。0 は「コールガイド無し」。
  -- 「コールは無いが手拍子だけ指定した曲」も整備済みなので、clap だけの行も数える。
  call_lines INTEGER NOT NULL DEFAULT 0,
  -- コール (calls[]) の総数。clap だけの行はここには入らない。
  call_count INTEGER NOT NULL DEFAULT 0,
  -- 最後に**人がコールを編集した**時刻。歌詞側の差し替えで数え直したときは更新しない
  -- (「誰がいつコールを書いたか」が歌詞の再投入で上書きされると履歴の意味が消えるため)。
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  -- 最後の編集者 (users.id または NULL)。**API 応答には出さない** (編集者匿名性: feed.ts の契約 §1)。
  -- 表示名は読み出し時に users を LEFT JOIN し、maskDisplayName を通して出す。
  -- NULL になるのは backfill 分・歌詞差し替えに伴う数え直し・運用者トークンによる一括投入
  -- (運用者の投入は「みんなの編集」ではないので編集者として記録しない)。
  -- ⚠️ 運用者トークンでの一括投入は、既にユーザーが書いていた曲の編集者参照も NULL で
  --    上書きする (最後に保存したのは実際に運用者なので、嘘は言っていない)。
  --    その曲の過去の編集者は call_edit_history 側に残る。
  updated_by_uid TEXT
);

-- 一覧は「最近整備された順」で出す。
CREATE INDEX IF NOT EXISTS idx_song_call_stats_updated ON song_call_stats(updated_at DESC);

CREATE TABLE IF NOT EXISTS call_edit_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  song_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  at TEXT NOT NULL DEFAULT (datetime('now')),
  -- 編集前後の件数だけを持つ。**コール本文もアンカー文字列も保存しない。**
  -- 履歴はメタデータであって、コール内容の第二の置き場所ではない
  -- (anchorText は歌詞の断片なので、増やせば増やすほど「歌詞の複製」に近づく)。
  -- revert 機能は作らない。現在値の正は常に lines_json 側。
  call_lines_before INTEGER NOT NULL,
  call_lines_after  INTEGER NOT NULL,
  call_count_before INTEGER NOT NULL,
  call_count_after  INTEGER NOT NULL
);

-- 「最近の編集」は at の新しい順。30 分以内の再保存は既存行を更新するので、
-- id 順ではなく at 順で並べる (id 順だとまとめた行が古い位置に沈む)。
CREATE INDEX IF NOT EXISTS idx_call_edit_history_at   ON call_edit_history(at DESC, id DESC);
-- 30 分以内の再保存を 1 行にまとめるときの直近行検索 (曲ごとの最新行を引く)。
CREATE INDEX IF NOT EXISTS idx_call_edit_history_song ON call_edit_history(song_id, id DESC);
-- 退会時の一括削除 (DELETE ... WHERE user_id = ?) 用。
CREATE INDEX IF NOT EXISTS idx_call_edit_history_user ON call_edit_history(user_id);

-- summary 列を置かない理由:
--   4 つの数から一意に決まる文字列なので、持つと二重管理になる。特に「30 分以内の
--   再保存を 1 行にまとめる」更新で、件数だけ動いて summary が古いまま残る事故が構造的に
--   起きる。要約は読み出し時に 4 つの数から組み立てる (call_stats.ts の buildCallEditSummary)。

-- ---------------------------------------------------------------------------
-- backfill: 既にコールが入っている曲 (2026-09 時点で 3 曲) を lines_json から数えて入れる。
--   json_valid で壊れた JSON を除外する (json_each は不正 JSON でエラーになり、
--   1 曲のせいで migration 全体が落ちる)。
--   updated_by_uid は NULL。履歴の無い時代に入った分なので「更新者不明」が正直な表現。
-- ---------------------------------------------------------------------------
INSERT INTO song_call_stats (song_id, call_lines, call_count, updated_at, updated_by_uid)
SELECT sl.song_id,
       (SELECT COUNT(*)
          FROM json_each(sl.lines_json) je
         WHERE COALESCE(json_array_length(je.value, '$.calls'), 0) > 0
            OR json_extract(je.value, '$.clap') IS NOT NULL),
       (SELECT COALESCE(SUM(COALESCE(json_array_length(je.value, '$.calls'), 0)), 0)
          FROM json_each(sl.lines_json) je),
       sl.updated_at,
       NULL
  FROM song_lyrics sl
 WHERE json_valid(sl.lines_json)
   AND EXISTS (SELECT 1
                 FROM json_each(sl.lines_json) je
                WHERE COALESCE(json_array_length(je.value, '$.calls'), 0) > 0
                   OR json_extract(je.value, '$.clap') IS NOT NULL);
