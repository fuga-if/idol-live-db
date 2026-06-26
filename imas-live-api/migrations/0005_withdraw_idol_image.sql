-- 0005: idol_image タイプの投稿を権利リスク回避のため取り下げ済みに移行
-- pending/flagged のものだけ withdrawn にする（approved/applied 等はそのまま保持）
UPDATE submissions
SET status = 'withdrawn'
WHERE type = 'idol_image'
  AND status IN ('pending', 'flagged');
