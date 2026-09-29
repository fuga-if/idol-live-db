//! 年表 (`/timeline/` と `/timeline/brand/<id>/`) の DTO。
//!
//! 図は 1 枚の SVG。座標は viewBox 単位で Rust (`domain::timeline_chart`) が決め、
//! Astro は属性に置くだけ (CSP で style 属性が使えない)。

use super::common::{FilterAxis, Ref, SeoBlock};

web_dto! {
    pub struct TimelinePage {
        pub schema_version: u32,
        pub path: String,
        pub title: String,
        pub lede: String,
        /// すべて / ブランドごと の切替。
        pub scope: FilterAxis,
        pub chart: TimelineChartDto,
        /// 図の下の凡例 (段の読み方)。
        pub legend: Vec<TimelineLegend>,
        /// 今年のライブ (見出しと一覧)。
        pub year_lives_title: String,
        pub year_lives: Vec<TimelineLiveRow>,
        /// 今年の節目。
        pub year_milestones_title: String,
        pub year_milestones: Vec<TimelineMilestoneRow>,
        pub seo: SeoBlock,
    }
}

web_dto! {
    pub struct TimelineChartDto {
        pub width: f64,
        pub height: f64,
        /// 段名の欄の右端 (年の罫線はここから)。
        pub gutter: f64,
        pub ruler_height: f64,
        pub years: Vec<TimelineYearTick>,
        pub lanes: Vec<TimelineLaneBand>,
        pub milestones: Vec<TimelineMilestoneMark>,
        pub lives: Vec<TimelineLiveDot>,
        pub releases: Vec<TimelineReleaseBar>,
        /// 今日の縦線。範囲外なら None。
        pub today_x: Option<f64>,
    }
}

web_dto! {
    pub struct TimelineYearTick {
        pub year: i32,
        /// 目盛りの文字 (幅が狭い年は下 2 桁)。
        pub label: String,
        pub x: f64,
        pub width: f64,
        /// 文字の x (年の枠の中央)。
        pub label_x: f64,
    }
}

web_dto! {
    pub struct TimelineLaneBand {
        pub label: String,
        pub y: f64,
        pub height: f64,
        /// 段名の文字のベースライン。
        pub label_y: f64,
    }
}

web_dto! {
    pub struct TimelineMilestoneMark {
        pub x: f64,
        pub y: f64,
        pub date_display: String,
        pub label: String,
        pub theme_key: Option<String>,
        pub text_x: f64,
        /// 文字を点の左に右寄せで置くか (右端)。
        pub flip: bool,
        pub date_y: f64,
        pub label_y: f64,
    }
}

web_dto! {
    pub struct TimelineLiveDot {
        pub x: f64,
        pub y: f64,
        pub r: f64,
        pub path: String,
        /// ツールチップ (`<title>`) に出す名前と日付。
        pub title: String,
        pub featured: bool,
        pub theme_key: String,
    }
}

web_dto! {
    pub struct TimelineReleaseBar {
        pub year: i32,
        pub count: u32,
        pub x: f64,
        pub y: f64,
        pub width: f64,
        pub height: f64,
        pub label_x: f64,
        pub label_y: f64,
    }
}

web_dto! {
    pub struct TimelineLegend {
        pub label: String,
        pub note: String,
    }
}

web_dto! {
    /// 今年のライブ 1 行。
    pub struct TimelineLiveRow {
        /// `9.26`。
        pub date_display: String,
        pub event: Ref,
        /// 周年ライブの札。
        pub chip: Option<String>,
    }
}

web_dto! {
    pub struct TimelineMilestoneRow {
        pub date_display: String,
        pub label: String,
    }
}
