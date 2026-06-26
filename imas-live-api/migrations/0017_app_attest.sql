-- App Attest (iOS) の端末ごとの公開鍵と署名カウンタを保管。
-- assertion 検証でカウンタ単調増加をチェックしてリプレイを防ぐ。
CREATE TABLE IF NOT EXISTS app_attest_keys (
  key_id     TEXT PRIMARY KEY,   -- DCAppAttestService の keyId (base64)
  public_key TEXT NOT NULL,      -- credCert の SPKI (base64)
  counter    INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
