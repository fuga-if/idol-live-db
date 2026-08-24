//! 年表 (ブランド史) のレイアウト計算。
//!
//! 「どの帯を何行目に置くか」「日付をキャンバス上の何 pt に置くか」を View から剥がした
//! 純粋関数群。iOS `TimelineLayout` (TimelineLayout.swift) の一次実装。
//! UI フレームワークに依存しないので単体テストできる。この層が壊れると症状が
//! 「なんとなく見た目が変」にしか出ず目視では気づけない (帯が 1 段深いだけ /
//! 年が 1 日ずれるだけ) ため、ここで固めておく。
//!
//! 座標は pt を f64 で表す (iOS の CGFloat / Android の Dp への変換はラッパが担う)。
//! 日付は epoch 秒で受け取り、年の切り出しは JST (UTC+9 固定・夏時間なし) で行う。
//! 端末ローカルのタイムゾーンで年境界を切ると「1/1 のリリースが前年の帯に入る」
//! 表示崩れになるため、カレンダーは引数にせずコア側で JST に固定する。
//!
//! FFI 境界はエンティティ全体を渡さず射影 (占有区間・期間・当たり矩形) を渡し、
//! 結果は index / 座標の列で返す (1 ユーザー操作 = 1 呼び出し)。

use chrono::{DateTime, Datelike, FixedOffset, TimeZone};

/// JST は UTC+9 固定 (1951 年以降夏時間なし)。IANA tzdata に依存しない。
const JST_OFFSET_SECONDS: i32 = 9 * 3600;

/// 1 日 = 86,400 秒。年表の x 座標は「経過日数 × 倍率」で決まる。
const SECONDS_PER_DAY: f64 = 86_400.0;

fn jst() -> FixedOffset {
    FixedOffset::east_opt(JST_OFFSET_SECONDS).expect("JST offset は常に有効")
}

/// 行詰めに使う 1 本の占有区間 (キャンバス上の pt 座標)。
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq)]
pub struct TimelineSpan {
    pub start: f64,
    pub end: f64,
}

impl TimelineSpan {
    /// `start > end` の壊れた入力 (DB 側の日付逆転) を「start 位置の幅 0」に直す。
    ///
    /// Swift 原本は Span の init で正規化していたが、FFI の Record は素通しの
    /// データなので、消費側 ([`pack_rows`]) の入口で正規化する。
    /// 比較は Swift `max(start, end)` (`end >= start ? end : start`) の忠実な写し
    /// (NaN の end も start に倒れる)。
    pub fn normalized(self) -> Self {
        Self {
            start: self.start,
            end: if self.end >= self.start { self.end } else { self.start },
        }
    }
}

/// 帯が重ならないように行 (レーン内の段) を割り当てる。
///
/// 貪欲法。開始が早い順に見て、「まだ空いている一番上の段」へ置く。同じ開始位置なら
/// 長い帯を先に置き、長い帯ほど上に来るようにする (参照デザインと同じ見え方)。
///
/// - `spans`: 各帯の占有区間。**ラベル幅を含めた実効幅**を渡すこと (ラベルは帯より
///   長くなるので、帯の幅だけで詰めると文字が隣の帯に重なる)。
/// - `gap`: 隣り合う帯の間に最低限空ける余白 (pt)。
///
/// 返り値は `spans` と同じ添字順の行番号 (0 始まり)。ここがずれると別の帯の位置に
/// 描かれるため、入力順は必ず保つ。
pub fn pack_rows(spans: &[TimelineSpan], gap: f64) -> Vec<u32> {
    if spans.is_empty() {
        return Vec::new();
    }
    let spans: Vec<TimelineSpan> = spans.iter().map(|s| s.normalized()).collect();

    let mut order: Vec<usize> = (0..spans.len()).collect();
    order.sort_by(|&lhs, &rhs| {
        let (a, b) = (&spans[lhs], &spans[rhs]);
        // f64 の同値判定は partial_cmp で Swift の `!=` 分岐と同じ挙動にする
        // (0.0 と -0.0 は等しい)。区間は正規化済みで NaN は実質来ないが、
        // 来ても Equal に倒して添字順で決定的にする。
        a.start
            .partial_cmp(&b.start)
            .unwrap_or(std::cmp::Ordering::Equal)
            // 同時開始は長い方 (end が大きい方) を上に。
            .then(b.end.partial_cmp(&a.end).unwrap_or(std::cmp::Ordering::Equal))
            .then(lhs.cmp(&rhs))
    });

    let mut rows = vec![0u32; spans.len()];
    // 各行がどこまで埋まっているか (pt)。
    let mut row_ends: Vec<f64> = Vec::new();

    for index in order {
        let span = &spans[index];
        if let Some(free) = row_ends.iter().position(|&end| end + gap <= span.start) {
            rows[index] = free as u32;
            row_ends[free] = span.end;
        } else {
            rows[index] = row_ends.len() as u32;
            row_ends.push(span.end);
        }
    }
    rows
}

/// 年範囲の計算に使う帯の期間 (エンティティ全体でなく開始/終了だけの射影)。
/// 単日の出来事は `start == end`。値は epoch 秒 (JST 日付の 0 時)。
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq, Eq)]
pub struct TimelineBarPeriod {
    pub start_epoch_seconds: i64,
    pub end_epoch_seconds: i64,
}

/// 帯の集合が覆う年の範囲 (両端含む)。
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq, Eq)]
pub struct TimelineYearRange {
    pub first_year: i32,
    pub last_year: i32,
}

/// epoch 秒 → JST での年。表現不能な epoch は UNIX epoch (1970) に倒す
/// (jst_day と同じ保険。年表データでは到達しない)。
fn jst_year(epoch_seconds: i64) -> i32 {
    DateTime::from_timestamp(epoch_seconds, 0)
        .unwrap_or(DateTime::UNIX_EPOCH)
        .with_timezone(&jst())
        .year()
}

/// 帯の集合が覆う年の範囲。空なら `None`。
///
/// 端が中途半端な位置で切れないよう、年単位に丸めた `first..=last` を返す。
/// 開始年は各帯の start から、終了年は各帯の end から取る。全帯の期間が逆転して
/// `first > last` になる壊れたデータでも `None` に倒す (範囲として成立しないため)。
pub fn year_range(periods: &[TimelineBarPeriod]) -> Option<TimelineYearRange> {
    if periods.is_empty() {
        return None;
    }
    let mut min_year = i32::MAX;
    let mut max_year = i32::MIN;
    for period in periods {
        min_year = min_year.min(jst_year(period.start_epoch_seconds));
        max_year = max_year.max(jst_year(period.end_epoch_seconds));
    }
    (min_year <= max_year).then_some(TimelineYearRange {
        first_year: min_year,
        last_year: max_year,
    })
}

/// 年境界 1 本ぶん。`epoch_seconds` はその年の JST 1/1 00:00。
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq, Eq)]
pub struct TimelineYearBoundary {
    pub year: i32,
    pub epoch_seconds: i64,
}

/// 年境界 (その年の 1/1 00:00 JST) を作る。範囲の終端は「翌年の 1/1」まで含めて
/// 返すので、目盛りの本数は `年数 + 1` になる (最後の年にも右端の罫線が引かれる)。
///
/// `first_year > last_year` の壊れた範囲は空を返す。カレンダーで表現できない年
/// (i32 の端など) は Swift 原本の compactMap と同じく黙って落とす。
pub fn year_boundaries(first_year: i32, last_year: i32) -> Vec<TimelineYearBoundary> {
    if first_year > last_year {
        return Vec::new();
    }
    (first_year..=last_year.saturating_add(1))
        .filter_map(|year| {
            let date = jst().with_ymd_and_hms(year, 1, 1, 0, 0, 0).single()?;
            Some(TimelineYearBoundary {
                year,
                epoch_seconds: date.timestamp(),
            })
        })
        .collect()
}

/// 日付 (epoch 秒) → キャンバス X 座標 (pt)。経過日数に比例する。
pub fn x_for(epoch_seconds: i64, origin_epoch_seconds: i64, points_per_day: f64) -> f64 {
    (epoch_seconds - origin_epoch_seconds) as f64 / SECONDS_PER_DAY * points_per_day
}

/// [`x_for`] の一括版。帯や年境界の全 x を 1 回の呼び出しで出す
/// (要素ごとの FFI 呼び出しを避けるための形)。
pub fn x_positions(
    epoch_seconds: &[i64],
    origin_epoch_seconds: i64,
    points_per_day: f64,
) -> Vec<f64> {
    epoch_seconds
        .iter()
        .map(|&epoch| x_for(epoch, origin_epoch_seconds, points_per_day))
        .collect()
}

/// キャンバス X 座標 (pt) → 日付 (epoch 秒)。ズーム後にスクロール位置を保つときに使う。
///
/// 倍率 0 以下 (NaN 含む) では原点に倒す (ピンチで潰し切ったときのゼロ除算の保険)。
/// 秒の小数部を丸めないよう f64 で返す (往復変換で日付が滲まないように)。
pub fn epoch_at_x(x: f64, origin_epoch_seconds: i64, points_per_day: f64) -> f64 {
    if !(points_per_day > 0.0) {
        return origin_epoch_seconds as f64;
    }
    origin_epoch_seconds as f64 + x / points_per_day * SECONDS_PER_DAY
}

/// タップ判定用の当たり矩形 (キャンバス座標)。
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq)]
pub struct TimelineHitBox {
    pub x: f64,
    pub width: f64,
    pub y: f64,
    pub height: f64,
}

/// キャンバス座標 (x, y) にある帯の添字。無ければ `None`。
///
/// 細い帯 (単日イベントは数 pt) でも押せるように **横方向にだけ** `slop` の遊びを
/// 持たせる。縦に広げないのは、上下の段は別の出来事なので誤爆が致命的になるため。
/// 候補が複数あるときは左端がタップ位置に最も近いものを選ぶ
/// (同距離なら先勝ち = Swift `min(by:)` と同じ)。
pub fn hit_index(x: f64, y: f64, boxes: &[TimelineHitBox], slop: f64) -> Option<u32> {
    boxes
        .iter()
        .enumerate()
        .filter(|(_, b)| {
            y >= b.y && y <= b.y + b.height && x >= b.x - slop && x <= b.x + b.width + slop
        })
        .min_by(|(_, a), (_, b)| (a.x - x).abs().total_cmp(&(b.x - x).abs()))
        .map(|(index, _)| index as u32)
}

/// 表示幅に年表全体が収まる points_per_day を求める。
///
/// - `span_days`: 年表全体の日数。
/// - `width`: 収めたい表示幅 (pt)。
///
/// 壊れた入力 (0 以下・NaN) では 0 や NaN を返さず 1 に倒す
/// (キャンバス幅 0 でクラッシュさせないため)。
pub fn fit_points_per_day(span_days: f64, width: f64) -> f64 {
    if !(span_days > 0.0 && width > 0.0) {
        return 1.0;
    }
    width / span_days
}

#[cfg(test)]
mod tests {
    use super::*;

    /// JST の日付 0 時を epoch 秒に (テスト入力用。iOS テストの TimelineDateParser 相当)。
    fn jst_date(year: i32, month: u32, day: u32) -> i64 {
        jst()
            .with_ymd_and_hms(year, month, day, 0, 0, 0)
            .single()
            .expect("テスト日付は常に有効")
            .timestamp()
    }

    fn span(start: f64, end: f64) -> TimelineSpan {
        TimelineSpan { start, end }
    }

    // --- pack_rows ---

    #[test]
    fn pack_rows_puts_non_overlapping_spans_on_the_same_row() {
        let spans = [span(0.0, 10.0), span(30.0, 40.0), span(60.0, 70.0)];
        assert_eq!(pack_rows(&spans, 5.0), vec![0, 0, 0]);
    }

    #[test]
    fn pack_rows_pushes_overlapping_spans_down() {
        let spans = [span(0.0, 100.0), span(10.0, 50.0), span(20.0, 30.0)];
        assert_eq!(pack_rows(&spans, 0.0), vec![0, 1, 2]);
    }

    /// gap の分だけ離れていない帯は同じ段に置かない (ラベルや点が隣とくっつくため)。
    #[test]
    fn pack_rows_respects_gap() {
        let spans = [span(0.0, 10.0), span(12.0, 20.0)];
        assert_eq!(pack_rows(&spans, 0.0), vec![0, 0]);
        assert_eq!(pack_rows(&spans, 8.0), vec![0, 1]);
    }

    /// 空いた段があればそこを埋める (無駄に縦へ伸ばさない)。
    #[test]
    fn pack_rows_reuses_freed_rows() {
        let spans = [
            span(0.0, 100.0), // row 0
            span(0.0, 10.0),  // row 1
            span(20.0, 30.0), // row 1 に戻れる
        ];
        assert_eq!(pack_rows(&spans, 0.0), vec![0, 1, 1]);
    }

    /// 同時開始なら長い帯が上。参照デザインと同じく「長い流れが上、単発が下」に見える。
    #[test]
    fn pack_rows_puts_longer_span_on_top_when_starting_together() {
        let spans = [span(0.0, 10.0), span(0.0, 100.0)];
        assert_eq!(pack_rows(&spans, 0.0), vec![1, 0]);
    }

    #[test]
    fn pack_rows_handles_empty_input() {
        assert!(pack_rows(&[], 4.0).is_empty());
    }

    /// 入力順と戻り値の添字は必ず一致する (ここがずれると別の帯の位置に描かれる)。
    #[test]
    fn pack_rows_keeps_input_order() {
        let spans = [span(90.0, 100.0), span(0.0, 10.0), span(95.0, 99.0)];
        let rows = pack_rows(&spans, 0.0);
        assert_eq!(rows.len(), 3);
        assert_eq!(rows[1], 0); // 一番左は必ず 0 段目
        assert_ne!(rows[0], rows[2]); // 重なる 2 本は別の段
    }

    /// start > end の壊れた入力でも段割りは破綻しない (DB 側の日付逆転に対する保険)。
    #[test]
    fn span_normalizes_reversed_range() {
        let normalized = span(50.0, 10.0).normalized();
        assert_eq!(normalized.start, 50.0);
        assert_eq!(normalized.end, 50.0);
    }

    /// 逆転区間は「start 位置の幅 0」として詰められる。end=-100 のまま扱うと
    /// gap 8 でも後続の帯が同じ段に入り、描画位置 (x=10) の帯と密着してしまう。
    #[test]
    fn pack_rows_treats_reversed_span_as_zero_width_at_start() {
        let spans = [span(10.0, -100.0), span(15.0, 30.0)];
        assert_eq!(pack_rows(&spans, 8.0), vec![0, 1]);
    }

    // --- hit_index (タップ判定) ---

    /// 行 0 に 2 本、行 1 に 1 本。座標系はキャンバス基準 (パン適用後)。
    fn sample_boxes() -> Vec<TimelineHitBox> {
        vec![
            TimelineHitBox { x: 0.0, width: 20.0, y: 0.0, height: 30.0 },   // 0
            TimelineHitBox { x: 100.0, width: 20.0, y: 0.0, height: 30.0 }, // 1
            TimelineHitBox { x: 0.0, width: 20.0, y: 30.0, height: 30.0 },  // 2
        ]
    }

    #[test]
    fn hit_index_finds_bar_under_point() {
        assert_eq!(hit_index(10.0, 15.0, &sample_boxes(), 6.0), Some(0));
        assert_eq!(hit_index(110.0, 15.0, &sample_boxes(), 6.0), Some(1));
    }

    /// 段が違えば別の出来事。縦には遊びを持たせない。
    #[test]
    fn hit_index_distinguishes_rows() {
        assert_eq!(hit_index(10.0, 45.0, &sample_boxes(), 6.0), Some(2));
    }

    /// 細い帯を押せるように横だけ slop ぶん広い。
    #[test]
    fn hit_index_applies_horizontal_slop_only() {
        assert_eq!(hit_index(-5.0, 15.0, &sample_boxes(), 6.0), Some(0));
        assert_eq!(hit_index(25.0, 15.0, &sample_boxes(), 6.0), Some(0));
        // slop を超えた先は何も無い (隣の帯を誤爆しない)
        assert_eq!(hit_index(40.0, 15.0, &sample_boxes(), 6.0), None);
        // 縦は広げない
        assert_eq!(hit_index(10.0, -5.0, &sample_boxes(), 6.0), None);
    }

    #[test]
    fn hit_index_returns_none_on_empty_area() {
        assert_eq!(hit_index(60.0, 15.0, &sample_boxes(), 6.0), None);
        assert_eq!(hit_index(10.0, 15.0, &[], 6.0), None);
    }

    /// 重なった帯は左端がタップ位置に近い方を選ぶ。
    #[test]
    fn hit_index_prefers_nearest_leading_edge() {
        let boxes = [
            TimelineHitBox { x: 0.0, width: 200.0, y: 0.0, height: 30.0 },
            TimelineHitBox { x: 90.0, width: 20.0, y: 0.0, height: 30.0 },
        ];
        assert_eq!(hit_index(95.0, 10.0, &boxes, 6.0), Some(1));
        assert_eq!(hit_index(5.0, 10.0, &boxes, 6.0), Some(0));
    }

    // --- year_range / year_boundaries ---

    fn period(start: i64, end: i64) -> TimelineBarPeriod {
        TimelineBarPeriod { start_epoch_seconds: start, end_epoch_seconds: end }
    }

    #[test]
    fn year_range_covers_all_bars() {
        let periods = [
            period(jst_date(2013, 5, 29), jst_date(2014, 4, 30)),
            period(jst_date(2026, 8, 1), jst_date(2027, 7, 25)),
        ];
        assert_eq!(
            year_range(&periods),
            Some(TimelineYearRange { first_year: 2013, last_year: 2027 })
        );
    }

    #[test]
    fn year_range_is_none_for_empty_bars() {
        assert_eq!(year_range(&[]), None);
    }

    /// 年境界は JST で切る。端末ローカルで切ると「1/1 のリリースが前年の帯に入る」
    /// 表示崩れになる (iOS テスト testCalendarIsPinnedToTokyo に対応する性質)。
    #[test]
    fn year_is_cut_at_jst_boundary() {
        // 2026-01-01 00:00 JST の直前 1 秒は 2025 年。
        let new_year = jst_date(2026, 1, 1);
        assert_eq!(jst_year(new_year), 2026);
        assert_eq!(jst_year(new_year - 1), 2025);
        // UTC ではまだ 2025-12-31 15:00 だが、JST では既に 2026 年。
        assert_eq!(
            year_range(&[period(new_year, new_year)]),
            Some(TimelineYearRange { first_year: 2026, last_year: 2026 })
        );
    }

    /// 目盛りは「年数 + 1」本。最後の年にも右端の罫線が要る。
    #[test]
    fn year_boundaries_include_the_closing_edge() {
        let boundaries = year_boundaries(2024, 2026);
        assert_eq!(
            boundaries.iter().map(|b| b.year).collect::<Vec<_>>(),
            vec![2024, 2025, 2026, 2027]
        );
        assert_eq!(boundaries.first().map(|b| b.epoch_seconds), Some(jst_date(2024, 1, 1)));
        assert_eq!(boundaries.last().map(|b| b.epoch_seconds), Some(jst_date(2027, 1, 1)));
    }

    /// 逆転した範囲では空を返す (ClosedRange を作れない Swift 側と違いクラッシュさせない)。
    #[test]
    fn year_boundaries_reject_reversed_range() {
        assert!(year_boundaries(2027, 2024).is_empty());
    }

    // --- 座標変換 ---

    #[test]
    fn x_is_proportional_to_elapsed_days() {
        let origin = jst_date(2026, 1, 1);
        assert!((x_for(origin, origin, 2.0) - 0.0).abs() < 0.001);
        assert!((x_for(jst_date(2026, 1, 11), origin, 2.0) - 20.0).abs() < 0.001);
    }

    /// 一括版は 1 件ずつの計算と一致する (View は帯・年境界の全 x をこれ 1 回で引く)。
    #[test]
    fn x_positions_match_scalar_results() {
        let origin = jst_date(2026, 1, 1);
        let dates = [origin, jst_date(2026, 1, 11), jst_date(2027, 1, 1)];
        let batch = x_positions(&dates, origin, 2.0);
        assert_eq!(batch.len(), dates.len());
        for (i, &date) in dates.iter().enumerate() {
            assert_eq!(batch[i], x_for(date, origin, 2.0));
        }
        assert!(x_positions(&[], origin, 2.0).is_empty());
    }

    #[test]
    fn epoch_at_x_round_trips() {
        let origin = jst_date(2020, 3, 1);
        let target = jst_date(2023, 11, 17);
        let x = x_for(target, origin, 0.27);
        let back = epoch_at_x(x, origin, 0.27);
        assert!((back - target as f64).abs() < 1.0);
    }

    /// 倍率 0 でゼロ除算しない (ピンチで潰し切ったときの保険)。
    #[test]
    fn epoch_at_x_with_zero_scale_returns_origin() {
        let origin = jst_date(2020, 3, 1);
        assert_eq!(epoch_at_x(500.0, origin, 0.0), origin as f64);
        // NaN 倍率も原点に倒す (0 と同じ「成立しない倍率」扱い)。
        assert_eq!(epoch_at_x(500.0, origin, f64::NAN), origin as f64);
    }

    /// うるう年をまたいでも年の幅は実日数どおり (366 日の年は 1 日ぶん広い)。
    #[test]
    fn leap_year_is_wider_than_common_year() {
        let origin = jst_date(2023, 1, 1);
        let leap_width =
            x_for(jst_date(2025, 1, 1), origin, 1.0) - x_for(jst_date(2024, 1, 1), origin, 1.0);
        let common_width = x_for(jst_date(2024, 1, 1), origin, 1.0);
        assert!((common_width - 365.0).abs() < 0.001);
        assert!((leap_width - 366.0).abs() < 0.001);
    }

    #[test]
    fn fit_points_per_day_fills_the_given_width() {
        assert!((fit_points_per_day(1000.0, 400.0) - 0.4).abs() < 0.0001);
        // 壊れた入力でも 0 や NaN を返さない (キャンバス幅 0 でクラッシュさせないため)。
        assert_eq!(fit_points_per_day(0.0, 400.0), 1.0);
        assert_eq!(fit_points_per_day(1000.0, 0.0), 1.0);
        assert_eq!(fit_points_per_day(f64::NAN, 400.0), 1.0);
        assert_eq!(fit_points_per_day(1000.0, f64::NAN), 1.0);
    }
}
