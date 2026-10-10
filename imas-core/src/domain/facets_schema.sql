-- アイドルの項目 (ファセット) の表。**master_schema.sql にはまだ入れていない。**
--
-- master_schema.sql は db/master.sql (CloudKit の日次写し) のスキーマと一致することをテスト
-- (ddl_reproduces_the_bundled_schema) が固定している。ここの 2 表は CloudKit の本番スキーマに
-- IdolFacet / IdolHairstyle を昇格し、日次 export が db/master.sql に出すようになってから
-- master_schema.sql へ移す (そのとき schema_registry.rs の Auxiliary を Master にする)。
-- それまでは tools/apply_data.py (ensure_facet_tables) がこのファイルから表を作る。
-- 定義は src/domain/idol_facets.rs、運用は docs/ARCHITECTURE-facets.md。

-- 髪以外の項目の値。1 値 1 行 (複数値の項目は行が複数)。
-- id = 'if_' + sha1(idol_id|facet|[value 複数値のみ]) の先頭 20 桁 (idol_facets.rs の facet_row_key)。
-- origin: official (公式) / promoted (タグから昇格)。
CREATE TABLE idol_facets (
            id TEXT PRIMARY KEY NOT NULL,
            idol_id TEXT NOT NULL,
            facet TEXT NOT NULL,
            value TEXT NOT NULL,
            origin TEXT NOT NULL DEFAULT 'official',
            source_note TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (idol_id) REFERENCES idols(id) ON DELETE CASCADE
        );
CREATE INDEX idx_idol_facets_idol ON idol_facets(idol_id, facet);

-- 髪型 1 つぶんのまとまり。1 人に複数 (基本 / セカンドヘア / 覚醒後 …) 持てて、
-- is_main = 1 は髪型が 1 つ以上ある人につきちょうど 1 つ (部分一意索引 + apply_data --check + テスト)。
-- styles / accessories は複数値で、'、' 区切りの 1 文字列 (語彙に '、' は無い)。
-- id = 'ih_' + sha1(idol_id|label) の先頭 20 桁。
CREATE TABLE idol_hairstyles (
            id TEXT PRIMARY KEY NOT NULL,
            idol_id TEXT NOT NULL,
            label TEXT NOT NULL,
            is_main INTEGER NOT NULL DEFAULT 0,
            hair_color TEXT,
            hair_color_secondary TEXT,
            hair_length TEXT,
            styles TEXT,
            bangs TEXT,
            accessories TEXT,
            origin TEXT NOT NULL DEFAULT 'official',
            source_note TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (idol_id) REFERENCES idols(id) ON DELETE CASCADE
        );
CREATE INDEX idx_idol_hairstyles_idol ON idol_hairstyles(idol_id, sort_order);
CREATE UNIQUE INDEX idx_idol_hairstyles_main ON idol_hairstyles(idol_id) WHERE is_main = 1;
CREATE UNIQUE INDEX idx_idol_hairstyles_label ON idol_hairstyles(idol_id, label);
