//! カレンダー (`/calendar/` と `/calendar/<YYYY-MM>/`)。
//!
//! 何をどの日に出すかは `domain::calendar_queries` (アプリのカレンダーと同じ 1 本)。
//! ここは月の枠 (週 × 7 日) に流し込んだ形で、Astro は並べるだけ。

use super::common::{DateBadge, FilterAxis, NavLink, Ref, SeoBlock};

web_dto! {
    /// 月のカレンダー 1 枚。
    pub struct CalendarPage {
        pub schema_version: u32,
        pub path: String,
        /// `2026年9月`。
        pub title: String,
        /// この月の件数を 1 行に (`公演 10 ・ リリース曲 35 ・ 誕生日 32`)。0 のものは無く、全部 0 なら `None`。
        pub summary: Option<String>,
        /// 前の月・次の月。範囲の端では `None`。
        pub prev: Option<NavLink>,
        pub next: Option<NavLink>,
        /// 今月へ戻る導線。今月のページ自身には無い。
        pub today_link: Option<NavLink>,
        /// 年 (範囲内の年だけ、新しい順。押すとその年の最初の月) と、同じ年の月 (範囲外の月は無い) の切替。
        pub filters: Vec<FilterAxis>,
        /// 曜日の見出し (日曜始まり、アプリと同じ)。
        pub weekday_labels: Vec<String>,
        /// 週ごとの 7 日。月の外の日も枠を揃えるために入る (`in_month = false`)。
        pub weeks: Vec<CalendarWeek>,
        /// 予定のある日だけを日付順に (枠の下に並べる一覧)。
        pub days: Vec<CalendarDayGroup>,
        pub seo: SeoBlock,
    }
}

web_dto! {
    #[derive(Eq)]
    pub struct CalendarWeek {
        pub days: Vec<CalendarDay>,
    }
}

web_dto! {
    /// 枠の 1 日。
    #[derive(Eq)]
    pub struct CalendarDay {
        /// `2026-09-06`。下の一覧の見出しの id にもなる。
        pub date: String,
        pub day: u32,
        pub in_month: bool,
        pub is_today: bool,
        /// 枠に出す分 (先頭の数件)。全部は [`CalendarDayGroup::items`]。月の外の日は空。
        pub items: Vec<CalendarItem>,
        /// 枠に入り切らなかった件数の札 (`+2`)。
        pub overflow_label: Option<String>,
        /// 日を跨ぐ帯 (チケット受付期間)。
        pub bands: Vec<CalendarBand>,
    }
}

web_dto! {
    /// 予定 1 件。
    #[derive(Eq)]
    pub struct CalendarItem {
        pub kind: CalendarItemKind,
        /// 「公演」「リリース」「誕生日」「記念日」「申込締切」…。語は `content::CALENDAR_KIND_*`。
        pub kind_label: String,
        pub label: String,
        pub sub: Option<String>,
        /// 押し先 (公演・アイドル・ライブ・ブランド)。無いものは押せない。
        pub path: Option<String>,
        /// 色 (ブランド / アイドル / neutral)。
        pub theme_key: String,
        /// リリースの日だけ: その日に出た曲。
        pub refs: Vec<Ref>,
    }
}

impl CalendarItem {
    /// 押し先・副題・曲の無い素の 1 件。呼ぶ側が `..` で足す。
    pub fn new(kind: CalendarItemKind, kind_label: &str, label: impl Into<String>, theme_key: String) -> Self {
        Self {
            kind,
            kind_label: kind_label.to_string(),
            label: label.into(),
            sub: None,
            path: None,
            theme_key,
            refs: vec![],
        }
    }
}

web_dto! {
    #[derive(Copy, Eq)]
    pub enum CalendarItemKind {
        Show,
        Release,
        Birthday,
        Anniversary,
        Ticket,
    }
}

web_dto! {
    /// 日を跨ぐ帯の 1 日ぶん。
    #[derive(Eq)]
    pub struct CalendarBand {
        pub label: String,
        pub theme_key: String,
        /// この日が帯の始まり / 終わりか (角を丸める材料)。
        pub starts: bool,
        pub ends: bool,
        pub path: Option<String>,
    }
}

web_dto! {
    /// 予定のある 1 日 (枠の下の一覧)。
    #[derive(Eq)]
    pub struct CalendarDayGroup {
        pub date_badge: DateBadge,
        pub items: Vec<CalendarItem>,
    }
}
