-- 0013: オープン編集の監査基盤 (edit_batch + edit_history)
--
-- 全マスタ編集 (create/update/delete) を D1 に before/after スナップショットで記録し、
-- これを唯一の監査・revert 元とする。
-- 1 ユーザー操作 = 1 edit_batch。SetlistEditView の "items 一括置換 + 旧 item 削除" のような
-- 1 編集 = N レコード操作を batch でグルーピングし、batch 単位で all-or-nothing に revert する。
--
-- D1 は複数 statement の真トランザクションを持たないため、
--   (1) edit_batch + 全 edit_history 行を cloudkit_ok=0 で先に batch() INSERT
--   (2) CloudKit forceUpdate / softDelete 実行
--   (3) 成功時のみ cloudkit_ok=1 を UPDATE
-- とし、revert 対象は cloudkit_ok=1 のものだけに限定する (RedTeam High 対策)。

CREATE TABLE IF NOT EXISTS edit_batch (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  editor_id TEXT NOT NULL REFERENCES users(id), -- 編集者の users.id (sessionToken の uid)
  source TEXT NOT NULL DEFAULT 'app',           -- 'app' | 'revert' | 'admin' | 'seed'
  op TEXT NOT NULL,                             -- 'create' | 'update' | 'delete' | 'replace' | 'revert'
  summary TEXT,                                 -- 一覧表示用の機械生成要約 (サーバ生成。クライアント文字列は信頼しない)
  reverts_batch_id INTEGER REFERENCES edit_batch(id), -- op='revert' の時、打ち消した対象 batch
  cloudkit_ok INTEGER NOT NULL DEFAULT 0,       -- CloudKit forceUpdate/softDelete 成功フラグ
  created_at INTEGER NOT NULL,                  -- unixepoch ミリ秒 (modifiedAt と同単位で揃える)
  reverted_at INTEGER,                          -- この batch が後で revert された時刻 (ms)
  reverted_by TEXT REFERENCES users(id)         -- revert 実行者
);

CREATE INDEX IF NOT EXISTS idx_edit_batch_editor ON edit_batch(editor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_edit_batch_created ON edit_batch(created_at DESC);

CREATE TABLE IF NOT EXISTS edit_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  batch_id INTEGER NOT NULL REFERENCES edit_batch(id),
  record_type TEXT NOT NULL,        -- CloudKit recordType と一致 ('Event'|'Show'|'Song'|'Idol'|'SetlistItem'|...)
  record_name TEXT NOT NULL,        -- CloudKit recordName (= マスタ TEXT PK)
  op TEXT NOT NULL,                 -- 'create' | 'update' | 'delete'
  before_json TEXT,                 -- 編集前の全フィールド (camelCase CKフィールド名)。サーバが cloudKitLookup で権威取得。create 時 NULL
  after_json TEXT,                  -- 編集後に送ったフィールド。delete 時 NULL
  modified_at INTEGER NOT NULL,     -- CloudKit に注入した custom modifiedAt と同値 (差分同期との突合用, ms)
  created_at INTEGER NOT NULL,      -- レコード記録時刻 (ms)
  reverted INTEGER NOT NULL DEFAULT 0 -- このレコード行自体が打ち消し済みか (冪等性ガード)
);

CREATE INDEX IF NOT EXISTS idx_edit_history_record ON edit_history(record_type, record_name, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_edit_history_batch ON edit_history(batch_id);
