-- マイ予想 (GET /me/predictions) をページで読むための index。
-- 自分の票を voted_at の新しい順に、ページの行数だけ読めるようにする
-- (今の idx_setlist_prediction_votes_user は user_id だけなので、並べ替えに自分の票を全部読む)。
CREATE INDEX IF NOT EXISTS idx_setlist_prediction_votes_user_voted
  ON setlist_prediction_votes(user_id, voted_at DESC, show_id DESC, song_id DESC);
