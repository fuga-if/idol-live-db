//! カレンダーの週表示の置き方: 時刻のある予定の列割り (最大 2 列 + `+n`)、
//! 受付期間の帯の列と段詰め (Q-08k / R-B-16)。
//!
//! 両 OS に写経されていた (iOS `WeekTimeGridView.layoutTimedBlocks` / `parseTimeMinutes` と
//! `CalendarPeriodBand.pack`、Android `WeekTimeGrid.kt` の `layoutTimedBlocks` / `parseTimeMinutes`
//! と帯の詰め方)。座標 (dp / pt) への換算と描画は各 OS。ここは列・段・数だけを決める。

use chrono::NaiveDate;

/// 公演は終了時刻を持たないので、この長さぶんの高さで置く。
pub const DEFAULT_SHOW_DURATION_MINUTES: u32 = 120;

/// 時刻のある予定を横に並べる最大の列数。3 列以上に割ると細すぎて読めない。
const MAX_TIMED_LANES: usize = 2;

/// `HH:MM` → 0:00 からの経過分。壊れた値・範囲外は `None` (終日の欄へ)。
pub fn parse_time_minutes(time: &str) -> Option<u32> {
    let (h, m) = time.split_once(':')?;
    let (h, m): (u32, u32) = (h.parse().ok()?, m.parse().ok()?);
    (h < 24 && m < 60).then_some(h * 60 + m)
}

/// 公演の (開始分, 終了分)。開始時刻が無ければ `None`。終了は 2 時間後 (24:00 で止める)。
pub fn show_minutes(start_time: Option<&str>) -> Option<TimedBlockInput> {
    let start = parse_time_minutes(start_time?)?;
    Some(TimedBlockInput { start_minutes: start, end_minutes: (start + DEFAULT_SHOW_DURATION_MINUTES).min(24 * 60) })
}

/// 時刻のある予定 1 つ。
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq, Eq)]
pub struct TimedBlockInput {
    pub start_minutes: u32,
    pub end_minutes: u32,
}

/// 置けた予定 1 つ。
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq, Eq)]
pub struct TimedPlacement {
    /// 入力の添字。
    pub index: u32,
    /// 0 か 1。
    pub lane: u32,
    /// 他の置けた予定と時間が重なるので半分の幅で置く (単独なら全幅)。
    pub half_width: bool,
}

/// 置けなかった予定の数 (`+n`)。同じ開始分ごと。
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq, Eq)]
pub struct OverflowBadgeRecord {
    pub start_minutes: u32,
    pub count: u32,
}

/// 1 日ぶんの時刻のある予定の置き方。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct TimedLayout {
    /// 開始 → 終了の早い順 (同じなら入力の順)。
    pub placements: Vec<TimedPlacement>,
    /// 開始分の早い順。
    pub overflow: Vec<OverflowBadgeRecord>,
}

/// 同じ時間帯の予定を最大 2 列に振り分け、入らない分を開始分ごとの `+n` にまとめる。
pub fn timed_layout(blocks: &[TimedBlockInput]) -> TimedLayout {
    let mut order: Vec<usize> = (0..blocks.len()).collect();
    order.sort_by_key(|&i| (blocks[i].start_minutes, blocks[i].end_minutes));
    let mut lane_ends: [Option<u32>; MAX_TIMED_LANES] = [None; MAX_TIMED_LANES];
    let mut visible: Vec<(usize, usize)> = Vec::new();
    let mut hidden: Vec<usize> = Vec::new();
    for i in order {
        let block = blocks[i];
        match lane_ends.iter().position(|end| end.is_none_or(|e| e <= block.start_minutes)) {
            Some(lane) => {
                lane_ends[lane] = Some(block.end_minutes);
                visible.push((i, lane));
            }
            None => hidden.push(i),
        }
    }
    let overlaps = |a: TimedBlockInput, b: TimedBlockInput| a.start_minutes < b.end_minutes && b.start_minutes < a.end_minutes;
    let placements = visible
        .iter()
        .map(|&(i, lane)| TimedPlacement {
            index: i as u32,
            lane: lane as u32,
            half_width: visible.iter().any(|&(j, _)| j != i && overlaps(blocks[i], blocks[j])),
        })
        .collect();
    let mut overflow: Vec<OverflowBadgeRecord> = Vec::new();
    let mut starts: Vec<u32> = hidden.iter().map(|&i| blocks[i].start_minutes).collect();
    starts.sort_unstable();
    for start in starts {
        match overflow.last_mut() {
            Some(last) if last.start_minutes == start => last.count += 1,
            _ => overflow.push(OverflowBadgeRecord { start_minutes: start, count: 1 }),
        }
    }
    TimedLayout { placements, overflow }
}

/// 受付期間 1 つ (`YYYY-MM-DD` の両端を含む)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct PeriodSpanInput {
    /// 帯の id (イベント id)。同じ id は最初の 1 つだけ置く。
    pub id: String,
    pub start: String,
    pub end: String,
}

/// 週の中に置く帯 1 本。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct PeriodBandPlacement {
    pub id: String,
    /// 週の中の列 (0〜6)。週より前に始まる帯は 0、後に終わる帯は 6。
    pub start_col: u32,
    pub end_col: u32,
    /// この週で始まる (左端を丸める)。
    pub round_leading: bool,
    /// この週で終わる (右端を丸める)。
    pub round_trailing: bool,
    /// 段 (0 から)。前の帯と列が重ならなければ同じ段に詰める。
    pub lane: u32,
}

/// 週 (`week_start` から 7 日) にかかる受付期間の帯を、列と段に置く。
/// 週にかからない帯・日付の読めない帯は置かない。段は始まりの早い順に貪欲に詰める。
pub fn period_bands(week_start: &str, periods: &[PeriodSpanInput]) -> Vec<PeriodBandPlacement> {
    let parse = |d: &str| NaiveDate::parse_from_str(d, "%Y-%m-%d").ok();
    let Some(week) = parse(week_start) else { return Vec::new() };
    let mut seen = std::collections::HashSet::new();
    let mut bands: Vec<PeriodBandPlacement> = periods
        .iter()
        .filter(|p| seen.insert(p.id.as_str()))
        .filter_map(|p| {
            let start = (parse(&p.start)? - week).num_days();
            let end = (parse(&p.end)? - week).num_days();
            if end < 0 || start > 6 || end < start {
                return None;
            }
            Some(PeriodBandPlacement {
                id: p.id.clone(),
                start_col: start.clamp(0, 6) as u32,
                end_col: end.clamp(0, 6) as u32,
                round_leading: start >= 0,
                round_trailing: end <= 6,
                lane: 0,
            })
        })
        .collect();
    bands.sort_by_key(|b| b.start_col);
    let mut lane_ends: Vec<u32> = Vec::new();
    for band in &mut bands {
        match lane_ends.iter().position(|&end| end < band.start_col) {
            Some(lane) => {
                band.lane = lane as u32;
                lane_ends[lane] = band.end_col;
            }
            None => {
                band.lane = lane_ends.len() as u32;
                lane_ends.push(band.end_col);
            }
        }
    }
    bands
}

#[cfg(test)]
mod tests {
    use super::*;

    fn b(start: u32, end: u32) -> TimedBlockInput {
        TimedBlockInput { start_minutes: start, end_minutes: end }
    }

    #[test]
    fn times_parse_only_valid_clock_values() {
        assert_eq!(parse_time_minutes("18:30"), Some(18 * 60 + 30));
        assert_eq!(parse_time_minutes("0:05"), Some(5));
        for bad in ["24:00", "12:60", "1830", "", "ab:cd", "1:2:3"] {
            assert_eq!(parse_time_minutes(bad), None, "{bad}");
        }
        assert_eq!(show_minutes(Some("23:00")), Some(b(23 * 60, 24 * 60)), "24:00 で止める");
        assert_eq!(show_minutes(None), None);
    }

    #[test]
    fn overlapping_blocks_share_two_lanes_and_the_rest_become_plus_n() {
        let blocks = [b(600, 720), b(600, 720), b(600, 700), b(660, 720), b(900, 1000)];
        let layout = timed_layout(&blocks);
        let lanes: Vec<(u32, u32, bool)> = layout.placements.iter().map(|p| (p.index, p.lane, p.half_width)).collect();
        // (600,700) が先頭 (終了が早い)、次に (600,720) の最初のもの。残りは入らない。
        assert_eq!(lanes, vec![(2, 0, true), (0, 1, true), (4, 0, false)]);
        assert_eq!(
            layout.overflow,
            vec![OverflowBadgeRecord { start_minutes: 600, count: 1 }, OverflowBadgeRecord { start_minutes: 660, count: 1 }]
        );
    }

    #[test]
    fn a_lane_frees_up_when_the_previous_block_ends() {
        let layout = timed_layout(&[b(600, 660), b(660, 720)]);
        assert!(layout.placements.iter().all(|p| p.lane == 0 && !p.half_width));
        assert!(layout.overflow.is_empty());
    }

    fn p(id: &str, start: &str, end: &str) -> PeriodSpanInput {
        PeriodSpanInput { id: id.into(), start: start.into(), end: end.into() }
    }

    #[test]
    fn bands_are_clipped_to_the_week_and_packed_into_lanes() {
        // 2026-09-20 (日) から 7 日。
        let bands = period_bands(
            "2026-09-20",
            &[
                p("a", "2026-09-10", "2026-09-22"),
                p("b", "2026-09-23", "2026-10-05"),
                p("c", "2026-09-21", "2026-09-24"),
                p("a", "2026-09-20", "2026-09-20"),
                p("out", "2026-10-01", "2026-10-02"),
                p("bad", "未定", "2026-09-21"),
            ],
        );
        let got: Vec<(&str, u32, u32, bool, bool, u32)> = bands
            .iter()
            .map(|b| (b.id.as_str(), b.start_col, b.end_col, b.round_leading, b.round_trailing, b.lane))
            .collect();
        assert_eq!(
            got,
            vec![
                ("a", 0, 2, false, true, 0),
                ("c", 1, 4, true, true, 1),
                ("b", 3, 6, true, false, 0),
            ]
        );
    }
}
