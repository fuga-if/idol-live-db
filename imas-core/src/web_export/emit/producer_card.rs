//! P名刺ページ (`/p/`) 用の台帳 (`p/catalog.json`)。
//!
//! 名刺そのものはブラウザが wasm 経由で読み解くので、ここが書くのは
//! id → 名前・色・URL の台帳と、「アプリで開く」の固定文字列だけ。

use super::context::{page_title, Ctx};
use crate::domain::event_detail_queries::upcoming_shows;
use crate::domain::producer_card::CARD_PATH;
use crate::web_export::content;
use crate::web_export::dto::SCHEMA_VERSION;
use crate::web_export::dto::{CardCatalog, Robots, SeoBlock};

pub fn card_catalog(ctx: &Ctx) -> CardCatalog {
    let idols = ctx
        .snap
        .idols
        .iter()
        .filter_map(|idol| ctx.idol_ref(&idol.id))
        .collect();

    let upcoming_show_shows = upcoming_shows(ctx.snap, &ctx.today);
    let upcoming_shows_refs = upcoming_show_shows
        .iter()
        .filter_map(|show| ctx.show_ref(&show.id))
        .collect();

    let app = content::app_open_plain();

    CardCatalog {
        schema_version: SCHEMA_VERSION,
        idols,
        upcoming_shows: upcoming_shows_refs,
        app_store_url: app.app_store_url,
        deeplink_prefix: format!("{}://p#", content::DEEPLINK_SCHEME),
        app_open_title: app.title,
        app_open_note: app.note,
        unreadable_text: "この名刺は読み取れませんでした".to_string(),
        seo: SeoBlock {
            title: page_title("P名刺"),
            description: "QR で受け取った P名刺を表示します。".to_string(),
            canonical: content::absolute(CARD_PATH),
            og_image: content::absolute(content::DEFAULT_OG_IMAGE),
            // 個人の名刺なので検索に載せない。どこにも位置しないページ (404 と同じ扱い)
            // なのでパンくず・JSON-LD も持たない。
            robots: Robots::NoindexFollow,
            json_ld: serde_json::json!({}),
            breadcrumbs: vec![],
        },
    }
}
