//! 出面に出す固定文と外部 URL。
//!
//! 文言を 1 箇所に集めてあるのは、同じ断り書きがページごとに少しずつ違う、という
//! 事故を防ぐため。**Astro 側に日本語の固定文を書かない** (書くと出典が 2 つになる)。

use super::dto::{
    AboutLink, AboutSection, AppLinks, AppOpen, CallGuideClap, CallGuideEmphasis, CallGuideVocabulary,
};

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
/// 2026-09-06、JASRAC に「この Web サイトも許諾 (J260943703) の対象か」を確認し、
/// 問題ないと回答を得たので `true`。`false` に戻すと歌詞は 1 文字も配らない
/// (ページにも API 呼び出しにも出てこず、案内文だけになる)。
///
/// 出す側の実装 (許諾番号とマークの掲示・コピー防止・1 リクエスト 1 曲・回数ログ) は
/// ここに揃っている。**本番で動く条件は API 側にもある** (docs/JASRAC.md §6.5):
/// 匿名 GET が本番に出ていること、CORS の許可 origin に出面があること、D1 の読み取り枠。
///
/// 歌詞 1 曲の取得は D1 の読み取り 1 回で、これは「リクエスト回数が数えられること」
/// という許諾の要件そのものなのでキャッシュできない。出面は押されたときだけ取りに行き、
/// 歌詞検索 (索引の全走査で最も枠を食う) は出面に持たない。
pub const LYRICS_ON_WEB: bool = true;

/// 歌詞を出していないときの断り書き。
///
/// **主語がアプリであることを崩さないこと。** この文が出るのは出面が歌詞を配って
/// いないときで、そのとき JASRAC の許諾のもとで歌詞を配信しているのはアプリだけ。
pub const LYRICS_OFF_NOTE: &str = "歌詞はアプリ『アイドルライブDB』でご覧いただけます（アプリは JASRAC 許諾番号 J260943703 のもとで歌詞を配信しています）。本サイトでは歌詞を掲載していません。";

/// 歌詞を取りに行くボタンの文言。使われ方はコールガイド目的が多いので、歌詞だけの
/// ボタンに見せない (About の説明文もこれを引く)。
pub const LYRICS_READ_LABEL: &str = "歌詞とコールガイドを読む";

/// 出面で歌詞を出すときの文言。許諾番号を必ず添える (掲示が許諾の条件)。
pub const LYRICS_ON_WEB_NOTE: &str = "JASRAC 許諾番号 J260943703 のもとで掲載しています。1 曲ずつの表示のみで、まとめての取得はできません。";

/// 今の設定での歌詞の断り書き (曲ページ・About)。
pub fn lyrics_note() -> &'static str {
    if LYRICS_ON_WEB {
        LYRICS_ON_WEB_NOTE
    } else {
        LYRICS_OFF_NOTE
    }
}

// ---- コールガイド (歌詞行につけるコール) の語彙 -------------------------------
// アプリ (`ImasLiveDB/Models/Lyrics.swift` / `CallGuideLineViews.swift`) と同じ語・記号。
// 出面はこれを置くだけで、意味 (どれが手拍子か・何番のアンカーか) は決めない。

/// 手拍子の指示 (Worker の `clap` の値, 記号, 名前)。行頭に記号、凡例に名前。
pub const CALL_GUIDE_CLAPS: [(&str, &str, &str); 4] = [
    ("back_beat", "★", "裏拍"),
    ("four_on_floor", "■", "4つ打ち"),
    ("ppph", "♠", "PPPH"),
    ("none", "♥", "コールなし"),
];
/// コールの強調度 (Worker の `emphasis` の値, 名前)。`normal` は既定なので凡例に出さない。
pub const CALL_GUIDE_EMPHASES: [(&str, &str); 3] = [
    ("normal", "通常"),
    ("optional", "おこのみで"),
    ("performer_request", "演者要望"),
];
/// 行内の 1 箇所に掛かるコールの印 / 掛かる範囲が無い (行末) コールの印。
pub const CALL_MARKER_SINGLE: &str = "↳";
pub const CALL_MARKER_END: &str = "»";
/// 同じ行に複数のアンカーがあるときの対応付け。超えたら受け手が素の数字に落とす。
pub const CALL_ANCHOR_MARKERS: [&str; 10] = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩"];
/// 歌に被せるコールの札 / 範囲付きと混ざった行での行末コールの札 / ズレたコールの印。
pub const CALL_TIMING_OVER_LABEL: &str = "同時";
pub const CALL_END_LABEL: &str = "行末";
pub const CALL_STALE_LABEL: &str = "ズレ";
/// 凡例で「同時」に添える説明。
pub const CALL_LEGEND_OVER_LABEL: &str = "歌に被せる";

/// 出面に配るコールガイドの語彙 (上の定数を 1 つに束ねる)。
pub fn call_guide_vocabulary() -> CallGuideVocabulary {
    CallGuideVocabulary {
        claps: CALL_GUIDE_CLAPS
            .iter()
            .map(|(kind, symbol, label)| CallGuideClap {
                kind: kind.to_string(),
                symbol: symbol.to_string(),
                label: label.to_string(),
            })
            .collect(),
        emphases: CALL_GUIDE_EMPHASES
            .iter()
            .map(|(kind, label)| CallGuideEmphasis { kind: kind.to_string(), label: label.to_string() })
            .collect(),
        marker_single: CALL_MARKER_SINGLE.to_string(),
        marker_end: CALL_MARKER_END.to_string(),
        anchor_markers: CALL_ANCHOR_MARKERS.iter().map(|m| m.to_string()).collect(),
        timing_over_label: CALL_TIMING_OVER_LABEL.to_string(),
        end_label: CALL_END_LABEL.to_string(),
        stale_label: CALL_STALE_LABEL.to_string(),
        legend_over_label: CALL_LEGEND_OVER_LABEL.to_string(),
    }
}

/// 歌詞の中の言葉で曲を探す API (検索ページの「歌詞」)。出面で歌詞を出すときだけ。
/// 応答は曲 id と一致箇所の窓だけで、本文は 1 曲ずつの GET と同じ経路。
pub fn lyrics_search_url() -> Option<String> {
    LYRICS_ON_WEB.then(|| format!("{API_ORIGIN}/lyrics/search"))
}

/// フッタに載せる許諾の表示 (マークの隣の文字)。歌詞を出しているときだけ。
/// 「お申込みいただいたサイトのトップページ等の見やすい位置に表示」が許諾の条件で、
/// 全ページ共通のフッタに置けばトップにも載る。
pub fn lyrics_license_notice() -> Option<String> {
    LYRICS_ON_WEB.then(|| format!("JASRAC 許諾番号 {JASRAC_LICENSE_NUMBER}"))
}

/// 載せていないものの断り。歌詞を出しているときは歌詞を含めない。
fn not_hosted_note() -> &'static str {
    if LYRICS_ON_WEB {
        "キャラクター画像・公式ロゴは掲載していません。"
    } else {
        "キャラクター画像・公式ロゴ・歌詞は掲載していません。"
    }
}

/// フッタの断り書き (全ページ)。**出面の日本語はここが正** — Astro に文面を書かない。
pub fn footer_notes() -> Vec<String> {
    vec![
        SITE_DISCLAIMER.to_string(),
        format!("{}ジャケット画像は Apple Music の提供によるものです。", not_hosted_note()),
    ]
}

/// コールガイドの進捗ページ (`/calls/`) の説明。iOS のダッシュボードと同じ文。
pub const CALL_GUIDE_INTRO: &str = if LYRICS_ON_WEB {
    // 出面で読める間は、読み手が得るものを先に言う (進捗表そのものが目的の人は少ない)。
    "曲ページの「歌詞とコールガイドを読む」を押すと、歌詞の行ごとに「ここでこう叫ぶ」が読めます。それがコールガイドです。書き込みはアプリの歌詞タブから。ここでは進み具合を見られます。"
} else {
    "歌詞の行ごとに「ここでこう叫ぶ」を書き込むのがコールガイドです。読み書きはアプリの歌詞タブから。ここでは進み具合だけを見られます。"
};

/// 「アプリで、もっと」(トップ) と About の説明。機能の並びは [`APP_FEATURES_NOTE`] と同じ 1 箇所。
pub fn app_note() -> String {
    format!("{APP_FEATURES_NOTE}このサイトは閲覧と共有に専念しています。")
}

/// ユニットの種類の言い方。一覧の札 (例外の「公演限定」だけ) と詳細ページで同じ語。
pub const UNIT_PERMANENT_LABEL: &str = "常設ユニット";
pub const UNIT_LIMITED_LABEL: &str = "公演限定";

pub fn unit_kind_label(is_permanent: bool) -> &'static str {
    if is_permanent { UNIT_PERMANENT_LABEL } else { UNIT_LIMITED_LABEL }
}

/// 歌詞・コールガイドを取りに行く API の起点。
pub const API_ORIGIN: &str = "https://imas-live-api.tokata3011.workers.dev";

/// 「アプリで開く」の説明文 (詳細ページ共通)。
pub const APP_OPEN_NOTE: &str = APP_FEATURES_NOTE;

/// アプリでしかできないことの並び。歌詞を出面で出すときは「歌詞」を「歌詞検索」に
/// 言い換える (歌詞そのものは出面にもある)。
pub const APP_FEATURES_NOTE: &str = if LYRICS_ON_WEB {
    "参加記録・投票・コールの編集・タグ付けはアプリでご利用いただけます。"
} else {
    "参加記録・投票・歌詞・コール・タグ付けはアプリでご利用いただけます。"
};

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

/// 既定の種別 (ライブ)。一覧の行で札にしないのはこれだけ (例外の種別だけを言う)。
pub const DEFAULT_EVENT_KIND: &str = "live";

/// 一覧の行に出す種別の札。既定の種別 (ライブ) には付けない — ほぼ全行に同じ札が並んでも
/// 見分けにならず、フェス・リリースイベントのような例外だけを言えばよい。
pub fn kind_chip(kind: &str) -> Option<&'static str> {
    (kind != DEFAULT_EVENT_KIND).then(|| kind_label(kind))
}

/// ライブ種別の日本語表記。
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

/// 楽曲一覧の行に添える作家の記載。「作曲」の語はここだけ (受け手は置くだけ)。
pub fn composer_credit(name: &str) -> String {
    format!("作曲 {name}")
}

/// 楽曲一覧の行に添える収録盤の記載。「収録」の語はここだけ。
pub fn cd_credit(title: &str) -> String {
    format!("収録 {title}")
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
                format!("{}アイドルは名前の 1 文字を使ったモノグラムで表示しています。", not_hosted_note()),
                "ジャケット画像は Apple Music が配信しているものを参照しています。".to_string(),
            ],
            links: vec![],
        },
        AboutSection {
            heading: "歌詞について".to_string(),
            paragraphs: if LYRICS_ON_WEB {
                vec![
                    lyrics_note().to_string(),
                    format!("曲ページで「{LYRICS_READ_LABEL}」を押すと、その 1 曲の歌詞とコールガイドが表示されます。歌詞の中の言葉から曲を探すには、検索ページの「歌詞」を使ってください。コールガイドの編集はアプリでご利用いただけます。"),
                ]
            } else {
                vec![lyrics_note().to_string()]
            },
            links: vec![AboutLink {
                label: "App Store でアプリを見る".to_string(),
                href: APP_STORE_URL.to_string(),
                external: true,
            }],
        },
        AboutSection {
            heading: "アプリについて".to_string(),
            paragraphs: vec![
                app_note(),
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
