-- 引き継ぎコード: ユーザー生成ローカルデータ (お気に入り/担当/投票履歴等) を
-- 別端末へ一時転送するためのワンタイムコード保管テーブル。
CREATE TABLE transfer_codes (
  code TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  payload TEXT NOT NULL,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);
CREATE INDEX idx_transfer_codes_expires ON transfer_codes(expires_at);
