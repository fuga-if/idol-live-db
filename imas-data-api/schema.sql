-- imas-data-api の D1 スキーマ。**これが唯一の定義**。
--   * Rust の web-export (`--api-sql`) は、この内容を先頭に付けて INSERT を書き足した SQL を出す
--     (`imas-core/src/web_export/data_api.rs`)。同期の SQL は表を作り直すので、何度流しても同じ結果になる。
--   * Worker のテスト (`test/queries.test.ts`) もこれを読み、クエリの実行計画を固定する。
--
-- 歌詞本文・歌詞の在り処・試聴音源の在り処に当たる列はこの DB に置かない。文書 (docs.body) は
-- `agent::tools` のツール面から組んだもので、その出力にも無い (Rust のテストが固定)。
--
-- 引く単位はすべて主キー / 索引。一覧は `ord` (公式順などの通し番号) を鍵にした
-- キーセット方式で、OFFSET は使わない (読み取り行数が読み飛ばしぶん増えるため)。

DROP TABLE IF EXISTS docs;
DROP TABLE IF EXISTS idols;
DROP TABLE IF EXISTS songs;
DROP TABLE IF EXISTS units;
DROP TABLE IF EXISTS song_idols;
DROP TABLE IF EXISTS terms;
DROP TABLE IF EXISTS meta;

-- 1 件ぶんの完成した文書 (JSON)。詳細 API はこの 1 行を返すだけ。kind: idol | song | unit | brands
CREATE TABLE docs (
  kind TEXT NOT NULL,
  id   TEXT NOT NULL,
  body TEXT NOT NULL,
  PRIMARY KEY (kind, id)
) WITHOUT ROWID;

-- 一覧の索引行。文書の中身は持たない (名前と絞り込みの鍵だけ)。
CREATE TABLE idols (
  ord         INTEGER PRIMARY KEY,
  id          TEXT NOT NULL,
  brand_id    TEXT,
  name        TEXT NOT NULL,
  name_kana   TEXT,
  is_external INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idols_brand ON idols (brand_id, ord);

CREATE TABLE songs (
  ord          INTEGER PRIMARY KEY,
  id           TEXT NOT NULL,
  brand_id     TEXT,
  title        TEXT NOT NULL,
  title_kana   TEXT,
  release_date TEXT
);
CREATE INDEX songs_brand ON songs (brand_id, ord);

CREATE TABLE units (
  ord          INTEGER PRIMARY KEY,
  id           TEXT NOT NULL,
  brand_id     TEXT,
  name         TEXT NOT NULL,
  name_kana    TEXT,
  is_permanent INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX units_brand ON units (brand_id, ord);

-- アイドルの持ち歌 (原唱 + ユニット名義)。`GET /v1/songs?idol=` の引き先。
CREATE TABLE song_idols (
  idol_id  TEXT NOT NULL,
  song_ord INTEGER NOT NULL,
  PRIMARY KEY (idol_id, song_ord)
) WITHOUT ROWID;

-- 前方一致の検索語。term は imas-text-fold で畳んだもの (検索語側も同じ wasm で畳む)。
-- kind: idol | song | unit。ord は idols / songs / units の ord。
CREATE TABLE terms (
  kind TEXT NOT NULL,
  term TEXT NOT NULL,
  ord  INTEGER NOT NULL,
  PRIMARY KEY (kind, term, ord)
) WITHOUT ROWID;

-- 同期の版と日時など。version が変わるとエッジのキャッシュが新しいキーになる。
CREATE TABLE meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
) WITHOUT ROWID;
