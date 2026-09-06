//! コールガイドの進捗ページ (`/calls/`) の DTO。
//!
//! 中身は Worker の `GET /calls/dashboard` を日次で写した JSON (`db/calls_dashboard.json`)
//! を焼き込んだもの。閲覧のたびに API は呼ばない。載るのは曲・件数・日時・マスク済みの
//! 表示名だけで、歌詞もコール本文も含まない (Worker 側の応答がそもそも含まない)。

use super::common::{Ref, SeoBlock, StatTile};

web_dto! {
    pub struct CallGuidePage {
        pub schema_version: u32,
        pub path: String,
        pub title: String,
        /// 説明文 (iOS のダッシュボードと同じ)。
        pub intro: String,
        /// `2026-09-06 12:34 (JST) 時点の情報です…`。写しの時刻は Worker の `generatedAt`。
        pub snapshot_note: String,
        /// ガイドあり / 書き手募集中 / タグ付き の数。0 も出す (「未整備 0」は良い知らせ)。
        pub stat_tiles: Vec<StatTile>,
        /// コールガイドがある曲 (更新の新しい順)。
        pub with_calls: Vec<CallGuideSongRow>,
        /// 一覧が Worker の上限で打ち切られているときの断り。
        pub with_calls_note: Option<String>,
        /// 最近の編集 (新しい順)。
        pub recent_edits: Vec<CallGuideEditRow>,
        /// 「コール曲」タグが付いているのに未整備の曲 (票の多い順)。
        pub wanted: Vec<Ref>,
        /// 見出しに添える断り (歌詞が未登録で並べていない曲数)。
        pub wanted_note: Option<String>,
        pub seo: SeoBlock,
    }
}

web_dto! {
    /// コールガイドがある曲 1 行。
    #[derive(Eq)]
    pub struct CallGuideSongRow {
        pub song: Ref,
        /// `32 件・19 行`。
        pub detail: String,
        /// `2026-09-05 (金)`。
        pub updated_display: String,
        /// マスク済みの表示名 (無ければ `匿名`、Worker が決める)。
        pub updated_by: String,
    }
}

web_dto! {
    /// 最近の編集 1 件。
    #[derive(Eq)]
    pub struct CallGuideEditRow {
        pub song: Ref,
        /// `コールを付けた (32 件・19 行)` など。言い方は iOS と同じ規則。
        pub label: String,
        pub at_display: String,
        pub by: String,
    }
}
