//! Web の年表 (`/timeline/`) の図の組み立て。
//!
//! アプリの年表 (帯を横に流すキャンバス) とは見せ方が違う: Web は 1 枚の SVG に
//! 「節目 / ライブ / 楽曲」の 3 段を置き、年の目盛りを共有する。素材はアプリと同じ
//! [`timeline_bars`] (節目とライブの帯) で、並べ方の部品も [`crate::domain::timeline_layout`]
//! (年境界・x 座標・段詰め) をそのまま使う。
//!
//! 座標は SVG の viewBox 単位 (幅 [`CHART_WIDTH`])。CSP で style 属性が使えないので、
//! 位置はすべてここで決めて属性として渡す。

use crate::domain::jst_day::jst;
use crate::domain::snapshot::Snapshot;
use crate::domain::timeline_layout::{pack_rows, year_boundaries, x_for, TimelineSpan};
use crate::domain::timeline_queries::{timeline_bars, TimelineBarLane, TimelineBarTarget};
use chrono::{DateTime, Datelike};
use std::collections::BTreeMap;

/// 図の幅 (viewBox 単位)。PC の本文幅でほぼ等倍になる。
pub const CHART_WIDTH: f64 = 1100.0;
/// 左の段名の欄。
const GUTTER: f64 = 76.0;
/// 年の目盛りの高さ。
const RULER_HEIGHT: f64 = 26.0;
/// 段の上下の余白。
const LANE_PAD: f64 = 12.0;
/// 節目 1 段の高さ (日付 + ラベルの 2 行)。
const MILESTONE_ROW: f64 = 36.0;
/// ライブの点の段の間隔。
const DOT_PITCH: f64 = 9.0;
const DOT_R: f64 = 3.5;
/// 周年ライブの点。
const DOT_R_FEATURED: f64 = 5.5;
/// 楽曲の棒の最大の高さ。
const MUSIC_BAR_MAX: f64 = 96.0;
/// 楽曲の棒の下に置く曲数の欄。
const MUSIC_LABEL: f64 = 16.0;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ChartLaneKind {
    Milestone,
    Live,
    Music,
}

impl ChartLaneKind {
    pub fn label(self) -> &'static str {
        match self {
            Self::Milestone => "節目",
            Self::Live => "ライブ",
            Self::Music => "楽曲",
        }
    }

    /// 段の読み方 (図の下の凡例)。
    pub fn note(self) -> &'static str {
        match self {
            Self::Milestone => "ゲーム・アニメの始まりや、シリーズの大きな出来事。",
            Self::Live => "1 つの点が 1 つのライブ。大きい点は周年ライブ。",
            Self::Music => "その年に出た曲の数 (派生曲は数えない)。",
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct ChartLane {
    pub kind: ChartLaneKind,
    pub y: f64,
    pub height: f64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ChartYear {
    pub year: i32,
    pub x: f64,
    pub width: f64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ChartMilestone {
    pub brand_id: String,
    pub label: String,
    /// `YYYY-MM-DD`。
    pub date: String,
    pub x: f64,
    /// 点の中心の y。文字はこの右に 2 行で置く。
    pub y: f64,
    /// 右端で文字がはみ出すので、点の左に右寄せで置く。
    pub flip: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ChartLive {
    pub event_id: String,
    pub title: String,
    /// 最初の公演日 `YYYY-MM-DD`。
    pub date: String,
    pub featured: bool,
    pub x: f64,
    pub y: f64,
    pub r: f64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ChartRelease {
    pub year: i32,
    pub count: u32,
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct TimelineChart {
    pub width: f64,
    pub height: f64,
    pub gutter: f64,
    pub ruler_height: f64,
    pub years: Vec<ChartYear>,
    pub lanes: Vec<ChartLane>,
    pub milestones: Vec<ChartMilestone>,
    pub lives: Vec<ChartLive>,
    pub releases: Vec<ChartRelease>,
    /// 今日の縦線の x (範囲外なら None)。
    pub today_x: Option<f64>,
}

impl TimelineChart {
    /// その年のライブ (図の下の一覧)。日付順。
    pub fn lives_in(&self, year: &str) -> Vec<&ChartLive> {
        self.lives.iter().filter(|l| l.date.starts_with(year)).collect()
    }

    /// その年の節目。日付順。
    pub fn milestones_in(&self, year: &str) -> Vec<&ChartMilestone> {
        self.milestones.iter().filter(|m| m.date.starts_with(year)).collect()
    }
}

/// 年ごとの新曲数 (派生曲を除く)。ブランドは主ブランドで絞る。
pub fn yearly_release_counts(snap: &Snapshot, brand_id: Option<&str>) -> BTreeMap<i32, u32> {
    let mut out = BTreeMap::new();
    for song in &snap.songs {
        if song.parent_song_id.is_some() {
            continue;
        }
        if brand_id.is_some_and(|b| song.brand_id.as_deref() != Some(b)) {
            continue;
        }
        let Some(year) = song.release_date.as_deref().and_then(year_of) else { continue };
        *out.entry(year).or_insert(0) += 1;
    }
    out
}

fn year_of(date: &str) -> Option<i32> {
    let b = date.as_bytes();
    if b.len() < 10 || b[4] != b'-' {
        return None;
    }
    date[..4].parse().ok()
}

fn date_of(epoch: i64) -> String {
    DateTime::from_timestamp(epoch, 0)
        .unwrap_or(DateTime::UNIX_EPOCH)
        .with_timezone(&jst())
        .format("%Y-%m-%d")
        .to_string()
}

/// 文字列の幅のあらい見積もり (全角 1 字 = 1、半角 0.55 字)。段詰めで文字が
/// 隣に重ならないための値で、ぴったりである必要は無い。
fn text_width(text: &str, font_size: f64) -> f64 {
    text.chars().map(|c| if c.is_ascii() { 0.55 } else { 1.0 }).sum::<f64>() * font_size
}

/// 節目に添える日付 (`2013.2.27`)。
pub fn milestone_date_display(date: &str) -> String {
    let parts: Vec<&str> = date.splitn(3, '-').collect();
    match parts[..] {
        [y, m, d] => format!(
            "{}.{}.{}",
            y,
            m.trim_start_matches('0'),
            d.get(..2).unwrap_or(d).trim_start_matches('0')
        ),
        _ => date.to_string(),
    }
}

/// 年表の図。ライブも節目も曲も無ければ None。
pub fn timeline_chart(snap: &Snapshot, brand_id: Option<&str>, today: &str) -> Option<TimelineChart> {
    let bars = timeline_bars(snap, brand_id);
    let milestones_src: Vec<_> = bars.iter().filter(|b| b.lane == TimelineBarLane::Milestone).collect();
    let lives_src: Vec<_> = bars
        .iter()
        .filter(|b| b.lane == TimelineBarLane::Live)
        .filter_map(|b| match &b.target {
            TimelineBarTarget::Event { id } => Some((b, id.as_str())),
            _ => None,
        })
        .collect();
    let releases = yearly_release_counts(snap, brand_id);

    let this_year = year_of(today);
    let years_seen = milestones_src
        .iter()
        .chain(lives_src.iter().map(|(b, _)| b))
        .filter_map(|b| year_of(&date_of(b.start_epoch_seconds)))
        .chain(releases.keys().copied());
    let (mut first, mut last) = (i32::MAX, i32::MIN);
    for y in years_seen {
        first = first.min(y);
        last = last.max(y);
    }
    if first > last {
        return None;
    }
    if let Some(t) = this_year {
        last = last.max(t);
    }

    let bounds = year_boundaries(first, last);
    let origin = bounds.first()?.epoch_seconds;
    let end = bounds.last()?.epoch_seconds;
    let span_days = (end - origin) as f64 / 86_400.0;
    let ppd = (CHART_WIDTH - GUTTER) / span_days;
    let x = |epoch: i64| GUTTER + x_for(epoch, origin, ppd);

    let years: Vec<ChartYear> = bounds
        .windows(2)
        .map(|w| ChartYear { year: w[0].year, x: x(w[0].epoch_seconds), width: x(w[1].epoch_seconds) - x(w[0].epoch_seconds) })
        .collect();

    let mut lanes = Vec::new();
    let mut y = RULER_HEIGHT;

    // 節目: 点の右に日付とラベル。文字の幅ぶん占有させて段を詰める。
    let ms_spans: Vec<TimelineSpan> = milestones_src
        .iter()
        .map(|b| {
            let x0 = x(b.start_epoch_seconds);
            let date = milestone_date_display(&date_of(b.start_epoch_seconds));
            let w = text_width(&b.title, 12.0).max(text_width(&date, 11.0));
            if x0 + 8.0 + w > CHART_WIDTH {
                TimelineSpan { start: x0 - 8.0 - w, end: x0 + 4.0 }
            } else {
                TimelineSpan { start: x0 - 4.0, end: x0 + 8.0 + w }
            }
        })
        .collect();
    let ms_rows = pack_rows(&ms_spans, 10.0);
    let ms_row_count = ms_rows.iter().max().map(|m| m + 1).unwrap_or(0);
    let mut milestones = Vec::new();
    if ms_row_count > 0 {
        let height = LANE_PAD * 2.0 + f64::from(ms_row_count) * MILESTONE_ROW;
        for ((b, row), span) in milestones_src.iter().zip(&ms_rows).zip(&ms_spans) {
            let brand = snap
                .anniversaries
                .iter()
                .find(|a| format!("ms_{}", a.id) == b.id)
                .map(|a| a.brand_id.clone())
                .unwrap_or_default();
            milestones.push(ChartMilestone {
                brand_id: brand,
                label: b.title.clone(),
                date: date_of(b.start_epoch_seconds),
                x: x(b.start_epoch_seconds),
                y: y + LANE_PAD + f64::from(*row) * MILESTONE_ROW + 6.0,
                flip: span.end < x(b.start_epoch_seconds) + 5.0,
            });
        }
        lanes.push(ChartLane { kind: ChartLaneKind::Milestone, y, height });
        y += height;
    }

    // ライブ: 最初の公演日に点。重なる点は上へ積む。
    let live_items: Vec<(f64, bool, &str, &str, i64)> = lives_src
        .iter()
        .map(|(b, id)| {
            let featured = snap.event(id).is_some_and(|e| e.event_type == "anniversary");
            (x(b.start_epoch_seconds), featured, *id, b.title.as_str(), b.start_epoch_seconds)
        })
        .collect();
    let live_spans: Vec<TimelineSpan> = live_items
        .iter()
        .map(|&(x0, featured, ..)| {
            let r = if featured { DOT_R_FEATURED } else { DOT_R };
            TimelineSpan { start: x0 - r, end: x0 + r }
        })
        .collect();
    let live_rows = pack_rows(&live_spans, 1.0);
    let live_row_count = live_rows.iter().max().map(|m| m + 1).unwrap_or(0);
    let mut lives = Vec::new();
    if live_row_count > 0 {
        let height = LANE_PAD * 2.0 + f64::from(live_row_count) * DOT_PITCH + DOT_R_FEATURED;
        let base = y + height - LANE_PAD - DOT_R_FEATURED;
        for (&(x0, featured, id, title, epoch), row) in live_items.iter().zip(&live_rows) {
            lives.push(ChartLive {
                event_id: id.to_string(),
                title: title.to_string(),
                date: date_of(epoch),
                featured,
                x: x0,
                y: base - f64::from(*row) * DOT_PITCH,
                r: if featured { DOT_R_FEATURED } else { DOT_R },
            });
        }
        lives.sort_by(|a, b| a.date.cmp(&b.date).then(a.event_id.cmp(&b.event_id)));
        lanes.push(ChartLane { kind: ChartLaneKind::Live, y, height });
        y += height;
    }

    // 楽曲: 年ごとの新曲数の棒。
    let mut release_bars = Vec::new();
    if let Some(&max) = releases.values().max() {
        let height = LANE_PAD * 2.0 + MUSIC_BAR_MAX + MUSIC_LABEL;
        let floor = y + LANE_PAD + MUSIC_BAR_MAX;
        for (&year, &count) in &releases {
            let Some(col) = years.iter().find(|c| c.year == year) else { continue };
            let inset = (col.width * 0.18).min(10.0);
            let h = (f64::from(count) / f64::from(max) * MUSIC_BAR_MAX).max(1.0);
            release_bars.push(ChartRelease {
                year,
                count,
                x: col.x + inset,
                y: floor - h,
                width: col.width - inset * 2.0,
                height: h,
            });
        }
        lanes.push(ChartLane { kind: ChartLaneKind::Music, y, height });
        y += height;
    }

    let today_x = crate::domain::timeline_queries::epoch_of_date(today)
        .map(x)
        .filter(|tx| *tx >= GUTTER && *tx <= CHART_WIDTH);

    Some(TimelineChart {
        width: CHART_WIDTH,
        height: y,
        gutter: GUTTER,
        ruler_height: RULER_HEIGHT,
        years,
        lanes,
        milestones,
        lives,
        releases: release_bars,
        today_x,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn milestone_dates_drop_leading_zeros() {
        assert_eq!(milestone_date_display("2013-02-07"), "2013.2.7");
        assert_eq!(milestone_date_display("2026-12-24"), "2026.12.24");
    }
}
