//! 出面に出す固定文と外部 URL。
//!
//! 文言を 1 箇所に集めてあるのは、同じ断り書きがページごとに少しずつ違う、という
//! 事故を防ぐため。**Astro 側に日本語の固定文を書かない** (書くと出典が 2 つになる)。

use super::dto::{AboutLink, AboutSection, AppLinks, AppOpen};

/// サイトの起点。独自ドメインを取るときに変えるのはここと `astro.config` の `site`、
/// robots.txt の 3 箇所だけで済むようにしてある。
pub const SITE_ORIGIN: &str = "https://idollivedb.fugalabs.uk";

pub const SITE_NAME: &str = "アイドルライブDB";
pub const SITE_TAGLINE: &str = "アイマスのライブ・公演・セットリスト・楽曲・アイドルを横断して調べられるデータベースです。";
pub const SITE_DISCLAIMER: &str =
    "非公式のファンメイドサイトです。株式会社バンダイナムコエンターテインメントおよび関連権利者とは一切関係ありません。";

pub const APP_STORE_URL: &str = "https://apps.apple.com/jp/app/id6763342297";
/// 共有文と同じハッシュタグ。**値の正は `domain::share_text`** で、アプリの共有シートと
/// 出面で別のタグを出さないよう再輸出にしてある。
pub use crate::domain::share_text::HASHTAG;
/// 公式 X アカウント (@idollivedb)。
pub const X_URL: &str = "https://x.com/idollivedb";
pub const PRIVACY_URL: &str = "https://fuga-if.github.io/imas-live-privacy/privacy.html";
pub const SUPPORT_URL: &str = "https://fuga-if.github.io/imas-live-privacy/support.html";
pub const TERMS_URL: &str = "https://fuga-if.github.io/imas-live-privacy/terms.html";
pub const REPOSITORY_URL: &str = "https://github.com/fuga-if/idol-live-db";

/// JASRAC 非商用配信の許諾番号。掲示が許諾の条件。
pub const JASRAC_LICENSE_NUMBER: &str = "J260943703";

/// **この出面で歌詞を出すか。**
///
/// `false` の間、歌詞は 1 文字も配らない (ページにも API 呼び出しにも出てこない)。
///
/// ⚠️ **`true` にしてよいのは、JASRAC に「この Web サイトも許諾の対象か」を
/// 確認してからだけ。** 許諾 (J260943703) はアプリの非商用配信に対して取ったもので、
/// 同じ許諾が別の出面 (この静的サイト) に及ぶかは許諾書だけでは決まらない。
/// 実装 (許諾番号の掲示・コピー防止・1 リクエスト 1 曲・回数ログ) は揃えてあるので、
/// 確認が取れたらここを `true` にするだけで出る。
///
/// もう 1 つの注意: 歌詞 1 曲の取得は D1 の読み取り 1 回で、これは
/// 「リクエスト回数が数えられること」という許諾の要件そのものなのでキャッシュできない。
/// D1 無料枠は 2026-09 時点で 96% 消費しているので、公開前に枠の状況も見ること。
pub const LYRICS_ON_WEB: bool = false;

/// 歌詞についての固定文。
///
/// **主語がアプリであることを崩さないこと。** JASRAC の許諾を受けて歌詞を
/// 配信しているのはアプリであって、本サイトではない。ここを「本サイトは
/// 許諾を受けています」と書くと事実に反する ([`LYRICS_ON_WEB`] が `true` に
/// なったら、そのときは主語を足すこと)。
pub const LYRICS_NOTE: &str = "歌詞はアプリ『アイドルライブDB』でご覧いただけます（アプリは JASRAC 許諾番号 J260943703 のもとで歌詞を配信しています）。本サイトでは歌詞を掲載していません。";

/// 出面で歌詞を出すときの文言。許諾番号を必ず添える (掲示が許諾の条件)。
pub const LYRICS_ON_WEB_NOTE: &str = "JASRAC 許諾番号 J260943703 のもとで掲載しています。1 曲ずつの表示のみで、まとめての取得はできません。";

/// 歌詞・コールガイドを取りに行く API の起点。
pub const API_ORIGIN: &str = "https://imas-live-api.tokata3011.workers.dev";

/// 「アプリで開く」の説明文 (詳細ページ共通)。
pub const APP_OPEN_NOTE: &str = "参加記録・投票・歌詞・コール・タグ付けはアプリでご利用いただけます。";

/// カスタムスキーム。`DeeplinkRouter` が受けるのは events / shows / polls の 3 種だけ。
pub const DEEPLINK_SCHEME: &str = "imaslivedb";

/// 見出しに使う書体。SIL Open Font License 1.1。
///
/// Google Fonts から読み込まず、latin サブセットを自己ホストしている
/// (第三者へのリクエストをゼロにするため)。OFL は**ライセンス文の同梱**を求めるので、
/// `web/public/fonts/OFL.txt` を配布物に入れ、About からそこへリンクする。
pub const FONT_NAME: &str = "Chakra Petch";
pub const FONT_LICENSE_NOTE: &str =
    "見出しの書体 Chakra Petch は SIL Open Font License 1.1 のもとで利用しています。";
pub const FONT_LICENSE_URL: &str = "/fonts/OFL.txt";

/// 既定の OGP 画像。
pub const DEFAULT_OG_IMAGE: &str = "/og/default.png";

pub fn app_links() -> AppLinks {
    AppLinks {
        app_store_url: APP_STORE_URL.to_string(),
        // Google Play (site.fugaapp.imaslivedb) は 2026-09-04 時点で 404。
        // 生きていないリンクを出面に置かない。
        play_store_url: None,
        x_url: Some(X_URL.to_string()),
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

/// 曲種別の日本語表記 (`songs.song_type` の語彙: solo / unit / all / cover / tie_in)。
/// 知らない値は捏造せず `None` (受け手は出さない)。
pub fn song_type_label(song_type: &str) -> Option<&'static str> {
    match song_type {
        "solo" => Some("ソロ曲"),
        "unit" => Some("ユニット曲"),
        "all" => Some("全体曲"),
        "cover" => Some("カバー"),
        "tie_in" => Some("タイアップ"),
        _ => None,
    }
}

/// 一覧に出す全種別。`event_list_queries` に渡す `kinds` はここを唯一の出典にする
/// (省略すると既定が効いて、一覧から静かに消える種別が出る)。
pub const ALL_EVENT_KINDS: [&str; 6] =
    ["live", "festival", "release_event", "other", "radio", "stream"];

/// About ページの固定文。
///
/// **出面の日本語はここが正。**Astro 側に文面を書くと、同じ断り書きがページごとに
/// 少しずつ違う、という壊れ方をする (直したつもりの箇所が 1 つ残る)。
pub fn about_sections() -> Vec<AboutSection> {
    vec![
        AboutSection {
            heading: "このサイトについて".to_string(),
            paragraphs: vec![SITE_DISCLAIMER.to_string(), SITE_TAGLINE.to_string()],
            links: vec![],
        },
        AboutSection {
            heading: "版権について".to_string(),
            paragraphs: vec![
                "キャラクター画像・公式ロゴ・歌詞は掲載していません。アイドルは名前の 1 文字を使ったモノグラムで表示しています。".to_string(),
                "ジャケット画像は Apple Music の配信情報 (songs.artwork_url) を参照しています。".to_string(),
            ],
            links: vec![],
        },
        AboutSection {
            heading: "歌詞について".to_string(),
            paragraphs: vec![LYRICS_NOTE.to_string()],
            links: vec![AboutLink {
                label: "App Store でアプリを見る".to_string(),
                href: APP_STORE_URL.to_string(),
                external: true,
            }],
        },
        AboutSection {
            heading: "アプリについて".to_string(),
            paragraphs: vec![
                "参加記録・投票・タグ付け・歌詞・コールはアプリでご利用いただけます。本サイトは閲覧専用です。".to_string(),
            ],
            links: vec![
                AboutLink { label: "X (@idollivedb)".to_string(), href: X_URL.to_string(), external: true },
                AboutLink { label: "プライバシーポリシー".to_string(), href: PRIVACY_URL.to_string(), external: true },
                AboutLink { label: "サポート".to_string(), href: SUPPORT_URL.to_string(), external: true },
                AboutLink { label: "利用規約".to_string(), href: TERMS_URL.to_string(), external: true },
            ],
        },
        AboutSection {
            heading: "書体".to_string(),
            paragraphs: vec![
                FONT_LICENSE_NOTE.to_string(),
                "本文は端末に入っている書体 (ヒラギノ角ゴ / Noto Sans JP 等) を使っています。"
                    .to_string(),
            ],
            links: vec![AboutLink {
                label: "SIL Open Font License 1.1 (全文)".to_string(),
                href: FONT_LICENSE_URL.to_string(),
                // 配布物に同梱しているので同一サイト内。
                external: false,
            }],
        },
        AboutSection {
            heading: "データの貢献".to_string(),
            paragraphs: vec![
                "セットリストや楽曲情報の誤りは GitHub からご指摘いただけます。データは公開リポジトリで管理しています。".to_string(),
            ],
            links: vec![AboutLink {
                label: "GitHub リポジトリ".to_string(),
                href: REPOSITORY_URL.to_string(),
                external: true,
            }],
        },
    ]
}
