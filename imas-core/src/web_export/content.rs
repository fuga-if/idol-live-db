//! 出面に出す固定文と外部 URL。
//!
//! 文言を 1 箇所に集めてあるのは、同じ断り書きがページごとに少しずつ違う、という
//! 事故を防ぐため。**Astro 側に日本語の固定文を書かない** (書くと出典が 2 つになる)。

use super::dto::{
    AboutLink, AboutSection, AppLinks, AppOpen, CallGuideClap, CallGuideEmphasis, CallGuideVocabulary,
    EmptyText,
};
use crate::domain::vocabulary;

/// サイトの起点。ホストを変えるときは以下も必ず揃える (docs/ARCHITECTURE-web.md O6 /
/// ~/dev/fugaapp/docs/subdomain-migration-plan.md §4-1 に詳細):
/// `astro.config.mjs` の `site`、`robots.txt` の `Sitemap:`、
/// `imas-live-api/wrangler.jsonc` の `ALLOWED_ORIGINS`、`web/wrangler.jsonc` の `routes`、
/// `web/tests/no-api-exposure.test.ts` の `ALLOWED_HOSTS`。
pub const SITE_ORIGIN: &str = "https://idollivedb.fugaapp.site";

pub const SITE_NAME: &str = "アイドルライブDB";
/// トップの大見出し。1 要素 = 1 行 (広い画面での改行位置)。
pub const HOME_HEADLINE: [&str; 2] = ["アイマスのライブを、", "セトリから引ける。"];
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

/// **アプリの** JASRAC 非商用配信の許諾番号。出面の断り書き (「アプリは … のもとで配信」) にだけ使う。
pub const APP_JASRAC_LICENSE_NUMBER: &str = "J260943703";

/// **この出面 (Web) の** JASRAC 許諾番号。Web の許諾はまだ無いので `None` (D-WEB-13)。
///
/// 出面で歌詞を出すときに掲示する番号 (フッタ・曲ページ) は必ずこれを使う。アプリの番号を
/// 使うと、許諾の無い出面にアプリの番号を掲示してしまう。許諾が下りたらここに番号を入れ、
/// それから [`LYRICS_ON_WEB`] を開ける (番号が無いまま開けるとコンパイルが通らない)。
pub const WEB_JASRAC_LICENSE_NUMBER: Option<&str> = None;

// 出面で歌詞を出すなら、出面の許諾番号の掲示が要る (掲示が許諾の条件)。
const _: () = assert!(!LYRICS_ON_WEB || WEB_JASRAC_LICENSE_NUMBER.is_some());

/// 出面に掲示する許諾番号。歌詞を出している間だけ `Some` (出面の番号)。
pub fn web_license_number() -> Option<&'static str> {
    if LYRICS_ON_WEB { WEB_JASRAC_LICENSE_NUMBER } else { None }
}

/// **この出面で歌詞を出すか。**
///
/// **2026-09-08 現在 `false`。Web に歌詞を出すには JASRAC の追加の許諾が要る**と分かったため。
/// (2026-09-06 に「この Web サイトも許諾 J260943703 の対象か」を確認して問題ないと回答を得たが、
/// その後、出面は別枠の申請が必要と判明した。)
///
/// **開けるときはこの 1 行を `true` にするだけ**。歌詞・コールガイド・案内文・API の呼び出し先は
/// すべてこの定数から出ているので、他に触る場所は無い (`lyrics_note` / `LyricsBlock` /
/// `call_guide_vocabulary` が全部ここを見る)。`false` の間は歌詞を 1 文字も配らない
/// (ページにも JSON にも出てこず、アプリへ案内する断り書きだけになる)。
///
/// 出す側の実装 (許諾番号とマークの掲示・コピー防止・1 リクエスト 1 曲・回数ログ) は
/// ここに揃っている。**本番で動く条件は API 側にもある** (docs/JASRAC.md §6.5):
/// 匿名 GET が本番に出ていること、CORS の許可 origin に出面があること、D1 の読み取り枠。
///
/// 歌詞 1 曲の取得は D1 の読み取り 1 回で、これは「リクエスト回数が数えられること」
/// という許諾の要件そのものなのでキャッシュできない。出面は押されたときだけ取りに行き、
/// 歌詞検索 (索引の全走査で最も枠を食う) は出面に持たない。
pub const LYRICS_ON_WEB: bool = false;

/// 歌詞を出していないときの状態の札。**「載せない」ではなく「まだ待っている」**と読める
/// 短い語にする (許諾が下りたら開ける、という状態を出すのがこの札の役目)。
/// `LYRICS_ON_WEB` を `true` にすると消える。
pub const LYRICS_PENDING_LABEL: &str = "JASRAC 許諾待ち";

/// 歌詞を出していないときの断り書き。
///
/// **主語がアプリであることを崩さないこと。** この文が出るのは出面が歌詞を配って
/// いないときで、そのとき JASRAC の許諾のもとで歌詞を配信しているのはアプリだけ。
/// 添える番号は [`APP_JASRAC_LICENSE_NUMBER`] (**アプリの**もので、この出面のものではない)。
fn lyrics_off_note() -> String {
    format!("本サイトでの歌詞の掲載には JASRAC の許諾が別に必要なため、いまは見合わせています。歌詞はアプリ『アイドルライブDB』でご覧いただけます（アプリは JASRAC 許諾番号 {APP_JASRAC_LICENSE_NUMBER} のもとで歌詞を配信しています）。")
}

/// 歌詞を取りに行くボタンの文言。使われ方はコールガイド目的が多いので、歌詞だけの
/// ボタンに見せない (About の説明文もこれを引く)。
pub const LYRICS_READ_LABEL: &str = "歌詞とコールガイドを読む";

/// 出面で歌詞を出すときの文言。出面の許諾番号を必ず添える (掲示が許諾の条件)。
pub fn lyrics_on_web_note(license_number: &str) -> String {
    format!("JASRAC 許諾番号 {license_number} のもとで掲載しています。1 曲ずつの表示のみで、まとめての取得はできません。")
}

/// 今の設定での歌詞の断り書き (曲ページ・About)。
pub fn lyrics_note() -> String {
    match web_license_number() {
        Some(number) => lyrics_on_web_note(number),
        None => lyrics_off_note(),
    }
}

/// 今の設定での状態の札。出しているときは状態を示す必要が無いので `None`。
pub fn lyrics_status_label() -> Option<String> {
    (!LYRICS_ON_WEB).then(|| LYRICS_PENDING_LABEL.to_string())
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
/// 歌詞が直されてアンカーがズレたコールの印。
pub const CALL_STALE_LABEL: &str = "ズレ";

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
        stale_label: CALL_STALE_LABEL.to_string(),
    }
}

/// ブラウザが自分以外に通信してよい origin (CSP の connect-src)。
/// 出面が通信するのは歌詞 (1 曲ずつ・検索) だけなので、歌詞を出す間だけ歌詞 API が入る。
pub fn connect_origins() -> Vec<String> {
    if LYRICS_ON_WEB { vec![API_ORIGIN.to_string()] } else { vec![] }
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
    web_license_number().map(|number| format!("JASRAC 許諾番号 {number}"))
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

// ---- タグ (曲に付いたコミュニティのタグ) の一覧 ----------------------------------
/// タグ一覧 (`/tags/`) の見出しと、楽曲一覧からの入口の文言。
pub const TAG_LIST_TITLE: &str = "タグ";
pub const TAG_LIST_LINK_LABEL: &str = "タグから探す";
pub const TAG_LIST_LEDE: &str =
    "アプリの利用者が曲に付けたタグです。付いている曲の多い順。タグ付けはアプリから。";
pub const TAG_LIST_DESCRIPTION: &str = "アイドルマスターの楽曲に付いたタグの一覧。タグから曲を探せます。";
/// 運営が用意したタグの札。
pub const TAG_OFFICIAL_LABEL: &str = "公式";
/// タグ 1 つの曲一覧 (`/tags/<tagId>/`) の見出し・説明。
pub fn tag_page_title(name: &str) -> String {
    format!("「{name}」の曲")
}
pub fn tag_page_lede(name: &str) -> String {
    format!("「{name}」のタグが付いた曲を、付けた人の多い順に並べています。")
}
pub fn tag_page_description(name: &str, count: u32) -> String {
    format!("アイドルマスターの楽曲のうち「{name}」のタグが付いた {count} 曲。")
}

/// シリーズ横断の合同曲に付ける札。ブランド別の一覧では、そのブランドの曲に混じって出るので
/// 「これは合同」と言っておく。
pub const SONG_COLLAB_LABEL: &str = "合同曲";

/// 音楽カードゲーム「KAMISABI」に収録されている曲に付ける札。
/// 語の正本は domain 側 (iOS / Android も同じ文字列を FFI で読む)。
pub const SONG_KAMISABI_LABEL: &str = crate::domain::kamisabi_cards::CARD_LABEL;

// ---- アイドル一覧の表 -----------------------------------------------------------
/// 表の見出し (名前の列の次から)。値の並びは `emit::lists::idol_list_item` が同じ順で作る。
pub const IDOL_COLUMN_BRAND: &str = "ブランド";
pub const IDOL_COLUMN_VOICE_ACTOR: &str = "CV";
pub const IDOL_COLUMN_BIRTHDAY: &str = "誕生日";
pub const IDOL_COLUMN_AGE: &str = "年齢";
pub const IDOL_COLUMN_HEIGHT: &str = "身長";
pub const IDOL_COLUMN_WEIGHT: &str = "体重";
pub const IDOL_COLUMN_BLOOD: &str = "血液型";
pub const IDOL_COLUMN_CONSTELLATION: &str = "星座";
pub const IDOL_COLUMN_BIRTHPLACE: &str = "出身";
pub const IDOL_COLUMN_ATTRIBUTE: &str = "属性";
pub const IDOL_COLUMN_DEBUT: &str = "デビュー日";
pub const IDOL_COLUMN_SONGS: &str = "持ち曲";
pub const IDOL_COLUMN_SHOWS: &str = "出演";
/// 名前の列の見出し。
pub const IDOL_COLUMN_NAME: &str = "名前";

/// デビュー日 (`YYYY-MM-DD`)。年まで出す (誕生日と違い、いつデビューしたかが読みどころ)。
pub fn idol_debut_display(debut: &str) -> String {
    match debut.split('-').collect::<Vec<_>>().as_slice() {
        [y, m, d] => match (m.parse::<i64>(), d.parse::<i64>()) {
            (Ok(m), Ok(d)) => format!("{y}年{m}月{d}日"),
            // 数字として読めない形はそのまま出す (原本も同じ)。
            _ => debut.to_string(),
        },
        _ => debut.to_string(),
    }
}

pub fn idol_age_display(age: i64) -> String {
    format!("{age}歳")
}

pub fn idol_weight_display(weight: f64) -> String {
    format!("{}kg", weight as i64)
}

pub fn idol_blood_display(blood_type: &str) -> String {
    format!("{blood_type}型")
}

/// ブランド内の属性。`cute` のような英字の分類は先頭だけ大文字にし、
/// `1年` のように既に日本語のものはそのまま出す (対応表を持つほどの規則性が無い)。
pub fn idol_attribute_label(attribute: &str) -> String {
    let mut chars = attribute.chars();
    match chars.next() {
        Some(first) if first.is_ascii_alphabetic() => {
            first.to_ascii_uppercase().to_string() + chars.as_str()
        }
        _ => attribute.to_string(),
    }
}

// ---- 一覧の頭の切替 -------------------------------------------------------------
/// 帯 (今後 / 開催済み / カレンダー) の名。読み上げにだけ使う。
pub const FILTER_SCOPE_EVENTS: &str = "今後 / 開催済み";
/// 畳んだメニューの軸名。閉じた札に「軸 いまの値」と出る。
pub const FILTER_AXIS_BRAND: &str = "ブランド";
pub const FILTER_AXIS_YEAR: &str = "年";
pub const FILTER_AXIS_BIRTH_MONTH: &str = "誕生月";
pub const FILTER_AXIS_PREFECTURE: &str = "都道府県";
pub const FILTER_AXIS_MONTH: &str = "月";

// ---- カレンダー -----------------------------------------------------------------
pub const CALENDAR_TITLE: &str = "カレンダー";
pub const CALENDAR_DESCRIPTION: &str = "アイドルマスターのライブ公演・楽曲リリース・誕生日・記念日のカレンダー。";
pub const CALENDAR_TODAY_LINK: &str = "今月へ";
/// 日曜始まり (アプリのカレンダーと同じ)。
pub const CALENDAR_WEEKDAYS: [&str; 7] = ["日", "月", "火", "水", "木", "金", "土"];
pub const CALENDAR_KIND_SHOW: &str = "公演";
pub const CALENDAR_KIND_RELEASE: &str = "リリース";
pub const CALENDAR_KIND_BIRTHDAY: &str = "誕生日";
pub const CALENDAR_KIND_ANNIVERSARY: &str = "記念日";
/// チケットの日程の札。語は `vocabulary::TICKET_DATES` にしか書かない (Q-08g)。
pub const CALENDAR_KIND_TICKET_OPEN: &str = vocabulary::TICKET_DATES[0].label;
pub const CALENDAR_KIND_TICKET_DEADLINE: &str = vocabulary::TICKET_DATES[1].label;
pub const CALENDAR_KIND_TICKET_LOTTERY: &str = vocabulary::TICKET_DATES[2].label;
/// 件数の 1 行での「リリース曲」(予定の札は「リリース」。公演・誕生日・記念日は札と同じ語)。
pub const CALENDAR_SUMMARY_RELEASES: &str = "リリース曲";

pub fn calendar_month_title(year: i32, month: u32) -> String {
    format!("{year}年{month}月")
}

pub fn calendar_month_description(year: i32, month: u32, shows: u32) -> String {
    format!("{year}年{month}月のアイドルマスターの公演 {shows} 件と、楽曲のリリース・誕生日・記念日の日程。")
}

/// 月の件数 (数え方は `emit::calendar::month_counts`)。説明文と `calendar_summary` の材料。
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct CalendarCounts {
    pub shows: u32,
    pub release_songs: u32,
    pub birthdays: u32,
    pub anniversaries: u32,
}

/// この月の件数を 1 行に (`公演 10 ・ リリース曲 35 ・ 誕生日 32 ・ 記念日 3`)。0 は言わない。
pub fn calendar_summary(c: &CalendarCounts) -> Option<String> {
    let part = |label: &str, n: u32| (n > 0).then(|| format!("{label} {n}"));
    crate::domain::display_join::join_parts([
        part(CALENDAR_KIND_SHOW, c.shows),
        part(CALENDAR_SUMMARY_RELEASES, c.release_songs),
        part(CALENDAR_KIND_BIRTHDAY, c.birthdays),
        part(CALENDAR_KIND_ANNIVERSARY, c.anniversaries),
    ])
}

/// 同じ日に出た曲をまとめた札。曲は一覧に全部並べる。
pub fn calendar_release_label(count: usize) -> String {
    format!("リリース {count} 曲")
}

/// 枠に入り切らなかった件数。
pub fn calendar_overflow_label(count: usize) -> String {
    format!("+{count}")
}

/// 記念日の表示 (`アーケード版稼働 21周年`)。当年 (0 周年) は年数を付けない。
pub fn anniversary_display(label: &str, years: i32) -> String {
    if years > 0 { format!("{label} {years}周年") } else { label.to_string() }
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

/// 「アプリで開く」の見出し。アプリの名前はサイト名と同じ。
fn app_open_title() -> String {
    format!("アプリ「{SITE_NAME}」")
}

/// deeplink を持たないページ (曲 / アイドル / ユニット / 会場) の導線。
pub fn app_open_plain() -> AppOpen {
    AppOpen {
        title: app_open_title(),
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
        title: app_open_title(),
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

/// ライブ種別の日本語表記。出面は正式な形 (「リリースイベント」)。語は `vocabulary` にしか
/// 書かない (Q-08f)。知らない値は「その他」(一覧から消さずに出す。Q-08l)。
pub fn kind_label(kind: &str) -> &'static str {
    vocabulary::event_kind(kind).label
}

/// 曲種別の日本語表記。出面は正式な形 (「ソロ曲」)。語は `vocabulary` にしか書かない (Q-08f)。
/// 知らない値は捏造せず `None` (受け手は出さない)。
pub fn song_type_label(song_type: &str) -> Option<&'static str> {
    vocabulary::song_type(song_type).map(|t| t.label)
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
                format!("{}アイドルは名前と、そのアイドルの色だけで表示しています。", not_hosted_note()),
                "ジャケット画像は Apple Music が配信しているものを参照しています。".to_string(),
            ],
            links: vec![],
        },
        AboutSection {
            heading: "歌詞について".to_string(),
            paragraphs: if LYRICS_ON_WEB {
                vec![
                    lyrics_note(),
                    format!("曲ページで「{LYRICS_READ_LABEL}」を押すと、その 1 曲の歌詞とコールガイドが表示されます。歌詞の中の言葉から曲を探すには、検索ページの「歌詞」を使ってください。コールガイドの編集はアプリでご利用いただけます。"),
                ]
            } else {
                vec![
                    lyrics_note(),
                    "歌詞の中の言葉から曲を探す検索も、同じ理由で止めています（一致した箇所の前後を返すため、歌詞の掲載と同じ扱いになります）。許諾が得られ次第、どちらも本サイトで開きます。".to_string(),
                ]
            },
            links: vec![AboutLink {
                label: "App Store でアプリを見る".to_string(),
                href: APP_STORE_URL.to_string(),
            }],
        },
        AboutSection {
            heading: "アプリについて".to_string(),
            paragraphs: vec![
                app_note(),
            ],
            links: vec![
                AboutLink { label: "X (@idollivedb)".to_string(), href: X_URL.to_string() },
                AboutLink { label: "プライバシーポリシー".to_string(), href: PRIVACY_URL.to_string() },
                AboutLink { label: "サポート".to_string(), href: SUPPORT_URL.to_string() },
                AboutLink { label: "利用規約".to_string(), href: TERMS_URL.to_string() },
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
            }],
        },
    ]
}

// ---- 空の一覧・節の案内 -----------------------------------------------------------
// 見出しは「何が無いか」、本文は「次にどうすればよいか」(あるときだけ)。

/// 空のときだけ案内を出す。中身があれば `None` (受け手は「あれば出す」だけにする)。
pub fn empty_text(is_empty: bool, title: &str, body: Option<&str>) -> Option<EmptyText> {
    is_empty.then(|| EmptyText { title: title.to_string(), body: body.map(str::to_string) })
}

pub const EMPTY_UPCOMING_EVENTS: &str = "今後の開催予定はまだ登録されていません";
/// トップの「今後のライブ」が空のとき (一覧ページと違い、行き先を言い添える)。
pub const EMPTY_UPCOMING_EVENTS_HOME_BODY: &str =
    "発表され次第このページに載ります。過去の記録は「開催済み」からご覧ください。";
pub const EMPTY_EVENTS: &str = "該当するライブがありません";
pub const EMPTY_EVENTS_BODY: &str = "別の年やブランドに切り替えるか、検索からお探しください。";
pub const EMPTY_SONGS: &str = "該当する楽曲がありません";
pub const EMPTY_SONGS_BODY: &str = "別のブランドに切り替えるか、検索からお探しください。";
pub const EMPTY_IDOLS: &str = "該当するアイドルがいません";
pub const EMPTY_IDOLS_BODY: &str = "別のブランドや誕生月に切り替えてみてください。";
pub const EMPTY_UNITS: &str = "該当するユニットがありません";
pub const EMPTY_VENUES: &str = "該当する会場がありません";
pub const EMPTY_CALENDAR_MONTH: &str = "この月の予定はまだありません";
/// トップの「最近の公演」と会場の公演一覧。
pub const EMPTY_SHOW_RECORDS: &str = "公演の記録がありません";
pub const EMPTY_EVENT_SHOWS: &str = "公演がまだ登録されていません";
pub const EMPTY_SONG_HISTORY: &str = "ライブでの披露記録がありません";
pub const EMPTY_IDOL_SONGS: &str = "持ち曲がまだ登録されていません";
pub const EMPTY_SETLIST: &str = "セットリストがまだ登録されていません";
pub const EMPTY_SETLIST_BODY: &str = "GitHub のリポジトリからデータの追加にご協力いただけます。";
pub const EMPTY_BRAND_IDOLS: &str = "アイドルが登録されていません";
pub const EMPTY_UNIT_MEMBERS: &str = "メンバーがまだ登録されていません";
pub const EMPTY_UNIT_SONGS: &str = "ユニット曲がまだ登録されていません";
pub const EMPTY_CALL_GUIDES: &str = "まだコールガイドがありません";
pub const EMPTY_CALL_GUIDES_BODY: &str =
    "「コール曲」タグの付いた曲から書き始められます (アプリの歌詞タブから)。";
pub const EMPTY_CALL_EDITS: &str = "まだ編集がありません";
pub const EMPTY_CALL_EDITS_BODY: &str = "誰かがコールを書き込むと、ここに残ります。";
pub const EMPTY_CALL_WANTED: &str =
    "未整備の曲はありません。タグの付いた曲は、いまのところ全部書かれています。";

// ---- ページごとの固定文 -------------------------------------------------------------

/// コールガイドの「書き手募集中」の説明。並びは `emit::calls` の `wanted` と同じ (票の多い順)。
pub const CALL_GUIDE_WANTED_LEDE: &str =
    "「コール曲」タグが付いているのに、まだコールガイドが書かれていない曲 (票の多い順)。";

/// お題の一覧の説明。
/// セトリ予想の見出し。
pub const FORECAST_TITLE: &str = "過去のセトリから推定";
/// セトリ予想の説明。学習した公演の数を添える。
pub fn forecast_lede(training_shows: u32) -> String {
    format!(
        "これまでの{training_shows}公演のセトリと出演者から、歌われそうな曲を機械的に並べた目安です。アプリの「セトリ予想」と同じ推定です。"
    )
}
/// 年表の見出しの下。
pub const TIMELINE_LEDE: &str = "節目・ライブ・楽曲を 1 本の時間軸に並べました。点を押すとそのライブへ。";
/// 年表の一覧で、周年ライブに付ける札。
pub const TIMELINE_FEATURED_CHIP: &str = "周年ライブ";
/// ランキングの見出しの下。アプリの「調べる」と同じ数え方だと言っておく。
pub const RANKING_LEDE: &str = "記録されたセットリストと出演者から数えています。自分の回収率や、まだ生で聴けていない曲はアプリの「調べる」で。";
/// 年ごとの公演数の注記 (今年以降は、発表済みの予定を含む)。
pub fn ranking_years_note(year: &str) -> String {
    format!("{year}年以降は発表済みの予定を含みます。")
}
pub const POLL_LIST_LEDE: &str = "アプリの利用者が出し合ったお題と、記録した時点の得票です。投票はアプリから。";
/// お題の締切の日付に添える語。締切前か過ぎたかで言い分ける。
pub fn poll_ends_label(is_open: bool) -> &'static str {
    if is_open { "締切" } else { "終了" }
}

/// CV の履歴の行の見出し。
pub fn voice_actor_label(is_current: bool) -> &'static str {
    if is_current { "現任" } else { "歴代" }
}

/// 派生曲の親を言う 1 文の前後 (`この曲は <親> の派生曲です。`)。
pub const PARENT_SONG_NOTE_BEFORE: &str = "この曲は ";
pub const PARENT_SONG_NOTE_AFTER: &str = " の派生曲です。";

/// 円盤 1 枚の 1 行の表記 (`タイトル (発売日)`)。発売日が無ければタイトルだけ。
pub fn release_display(title: &str, release_date: Option<&str>) -> String {
    match release_date {
        Some(date) => format!("{title} ({date})"),
        None => title.to_string(),
    }
}

/// ホールの収容人数 (`9000人`)。人数が無い・0 のときは出さない。
pub fn capacity_display(capacity: Option<i32>) -> Option<String> {
    capacity.filter(|&c| c != 0).map(|c| format!("{c}人"))
}

/// 同じライブの公演を、ヒーローの帯に並べる上限の本数。これを超えると前後への送りにする。
/// 純粋に幅の話 (`DAY1 / DAY2 …` の帯が 1 行に収まる本数)。
pub const SIBLING_SHOWS_IN_SEGMENTS: usize = 8;

// ---- 検索ページ -------------------------------------------------------------------
pub const SEARCH_TITLE: &str = "検索";
/// 検索ページの説明。歌詞検索を出しているときだけ、その使い方を言い添える。
pub fn search_lede() -> String {
    let base = "楽曲・アイドル・ライブ・会場を名前でまとめて探します。ひらがな / カタカナ / 英字の大小の違いはアプリと同じ規則で吸収します。";
    if LYRICS_ON_WEB {
        format!("{base} 「歌詞」に切り替えると、歌詞の中の言葉から曲を探せます (2 文字以上)。")
    } else {
        base.to_string()
    }
}
/// 検索ページの `<meta name="description">`。**歌詞検索を閉じている間は歌詞に触れない**
/// (閉じているのに「歌詞の中の言葉で検索します」と書いていた)。
pub fn search_description() -> &'static str {
    if LYRICS_ON_WEB {
        "アイマスの楽曲・アイドル・ライブ・会場を名前で、または歌詞の中の言葉で検索します。ひらがな / カタカナ / 英字の違いは自動で吸収します。"
    } else {
        "アイマスの楽曲・アイドル・ライブ・会場を名前で検索します。ひらがな / カタカナ / 英字の違いは自動で吸収します。"
    }
}

// ---- 見つからないページ (404) --------------------------------------------------------
pub const NOT_FOUND_EYEBROW: &str = "404";
pub const NOT_FOUND_TITLE: &str = "ページが見つかりません";
pub const NOT_FOUND_LEDE: &str =
    "URL が変わったか、そのデータがまだ登録されていない可能性があります。 検索するか、下の入口からお探しください。";
pub const NOT_FOUND_DESCRIPTION: &str = "お探しのページは見つかりませんでした。検索か一覧からお探しください。";
/// 404 の入口に添えるひとこと。どの一覧を出すか・記号・名前・行き先は `emit::lists::SiteList`。
pub const NOT_FOUND_PREVIEW_EVENTS: &str = "今後の予定と開催済みの記録";
pub const NOT_FOUND_PREVIEW_SONGS: &str = "クレジット・歌唱アイドル・披露履歴";
pub const NOT_FOUND_PREVIEW_IDOLS: &str = "プロフィール・持ち曲・出演履歴";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn poll_end_and_voice_actor_rows_are_worded_by_state() {
        assert_eq!(poll_ends_label(true), "締切");
        assert_eq!(poll_ends_label(false), "終了");
        assert_eq!(voice_actor_label(true), "現任");
        assert_eq!(voice_actor_label(false), "歴代");
    }

    #[test]
    fn release_and_capacity_are_written_the_way_the_pages_showed_them() {
        assert_eq!(release_display("Blu-ray BOX", Some("2026-10-01")), "Blu-ray BOX (2026-10-01)");
        assert_eq!(release_display("Blu-ray BOX", None), "Blu-ray BOX");
        assert_eq!(capacity_display(Some(9000)), Some("9000人".to_string()));
        // 人数の分からないホール (0 / 無し) には添えない。
        assert_eq!(capacity_display(Some(0)), None);
        assert_eq!(capacity_display(None), None);
    }

    #[test]
    fn the_web_never_displays_the_app_licence_as_its_own() {
        // 閉じている間の断り書きの主語はアプリで、番号もアプリのもの。
        assert!(lyrics_off_note().contains(&format!("アプリは JASRAC 許諾番号 {APP_JASRAC_LICENSE_NUMBER}")));
        // 出面の掲示 (フッタ・曲ページ) は出面の番号だけ。今は許諾が無いので何も掲示しない。
        assert_eq!(web_license_number(), if LYRICS_ON_WEB { WEB_JASRAC_LICENSE_NUMBER } else { None });
        assert_eq!(lyrics_license_notice().is_some(), web_license_number().is_some());
        if let Some(number) = WEB_JASRAC_LICENSE_NUMBER {
            assert_ne!(number, APP_JASRAC_LICENSE_NUMBER, "Web の許諾はアプリとは別の番号");
        }
    }

    #[test]
    fn the_browser_may_call_the_lyrics_api_only_while_lyrics_are_on_the_web() {
        assert_eq!(connect_origins().is_empty(), !LYRICS_ON_WEB);
        assert_eq!(connect_origins().is_empty(), lyrics_search_url().is_none());
    }

    #[test]
    fn search_page_mentions_lyrics_only_when_lyrics_search_is_open() {
        assert_eq!(search_lede().contains("歌詞"), LYRICS_ON_WEB);
        assert_eq!(search_description().contains("歌詞"), LYRICS_ON_WEB);
    }
}
