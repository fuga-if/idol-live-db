//! 出面に出す固定文と外部 URL。
//!
//! 文言を 1 箇所に集めてあるのは、同じ断り書きがページごとに少しずつ違う、という
//! 事故を防ぐため。**Astro 側に日本語の固定文を書かない** (書くと出典が 2 つになる)。

use super::dto::{AppLinks, AppOpen};

/// サイトの起点。独自ドメインを取るときに変えるのはここと `astro.config` の `site`、
/// robots.txt の 3 箇所だけで済むようにしてある。
pub const SITE_ORIGIN: &str = "https://imas-live-web.tokata3011.workers.dev";

pub const SITE_NAME: &str = "アイドルライブDB";
pub const SITE_TAGLINE: &str = "アイマスのライブ・公演・セットリスト・楽曲・アイドルを横断して調べられるデータベースです。";
pub const SITE_DISCLAIMER: &str =
    "非公式のファンメイドサイトです。株式会社バンダイナムコエンターテインメントおよび関連権利者とは一切関係ありません。";

pub const APP_STORE_URL: &str = "https://apps.apple.com/jp/app/id6763342297";
pub const HASHTAG: &str = "#アイドルライブDB";
pub const PRIVACY_URL: &str = "https://fuga-if.github.io/imas-live-privacy/privacy.html";
pub const SUPPORT_URL: &str = "https://fuga-if.github.io/imas-live-privacy/support.html";
pub const TERMS_URL: &str = "https://fuga-if.github.io/imas-live-privacy/terms.html";
pub const REPOSITORY_URL: &str = "https://github.com/fuga-if/idol-live-db";

/// 歌詞についての固定文。
///
/// **主語がアプリであることを崩さないこと。** JASRAC の許諾 (J260943703) を受けて
/// 歌詞を配信しているのはアプリであって、本サイトではない。ここを「本サイトは
/// 許諾を受けています」と書くと事実に反する。
pub const LYRICS_NOTE: &str = "歌詞はアプリ『アイドルライブDB』でご覧いただけます（アプリは JASRAC 許諾番号 J260943703 のもとで歌詞を配信しています）。本サイトでは歌詞を掲載していません。";

/// 「アプリで開く」の説明文 (詳細ページ共通)。
pub const APP_OPEN_NOTE: &str = "参加記録・投票・歌詞・コール・タグ付けはアプリでご利用いただけます。";

/// カスタムスキーム。`DeeplinkRouter` が受けるのは events / shows / polls の 3 種だけ。
pub const DEEPLINK_SCHEME: &str = "imaslivedb";

/// 既定の OGP 画像。
pub const DEFAULT_OG_IMAGE: &str = "/og/default.png";

pub fn app_links() -> AppLinks {
    AppLinks {
        app_store_url: APP_STORE_URL.to_string(),
        // Google Play (site.fugaapp.imaslivedb) は 2026-09-04 時点で 404。
        // 生きていないリンクを出面に置かない。
        play_store_url: None,
        hashtag: HASHTAG.to_string(),
        privacy_url: PRIVACY_URL.to_string(),
        support_url: SUPPORT_URL.to_string(),
        terms_url: TERMS_URL.to_string(),
        repository_url: REPOSITORY_URL.to_string(),
    }
}

/// deeplink を持たないページ (曲 / アイドル / ユニット / 会場) の導線。
pub fn app_open_plain() -> AppOpen {
    AppOpen {
        app_store_url: APP_STORE_URL.to_string(),
        deeplink: None,
        deeplink_kind: None,
        note: APP_OPEN_NOTE.to_string(),
    }
}

/// deeplink を持つページ (ライブ / 公演) の導線。
/// `kind` は `"event"` / `"show"`、`segment` は percent-encode 済みの id。
pub fn app_open_deeplink(kind: &str, segment: &str) -> AppOpen {
    let collection = match kind {
        "event" => "events",
        "show" => "shows",
        other => other,
    };
    AppOpen {
        app_store_url: APP_STORE_URL.to_string(),
        deeplink: Some(format!("{DEEPLINK_SCHEME}://{collection}/{segment}")),
        deeplink_kind: Some(kind.to_string()),
        note: APP_OPEN_NOTE.to_string(),
    }
}

/// 絶対 URL (canonical / OGP 用)。
pub fn absolute(path: &str) -> String {
    format!("{SITE_ORIGIN}{path}")
}

/// ライブ種別の日本語表記。一覧を全種別で出すので、行に付ける見分けが要る。
pub fn kind_label(kind: &str) -> &'static str {
    match kind {
        "live" => "ライブ",
        "festival" => "フェス",
        "release_event" => "リリースイベント",
        "radio" => "ラジオ",
        "stream" => "配信",
        _ => "その他",
    }
}

/// 一覧に出す全種別。`event_list_queries` に渡す `kinds` はここを唯一の出典にする
/// (省略すると既定が効いて、一覧から静かに消える種別が出る)。
pub const ALL_EVENT_KINDS: [&str; 6] =
    ["live", "festival", "release_event", "other", "radio", "stream"];
