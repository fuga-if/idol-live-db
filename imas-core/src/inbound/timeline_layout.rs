//! 年表レイアウト計算の FFI 面。ロジックは domain::timeline_layout。
//!
//! エンティティ全体は渡さず、占有区間 (TimelineSpan)・期間 (TimelineBarPeriod)・
//! 当たり矩形 (TimelineHitBox) の射影を渡して index / 座標の列で返す。
//! 帯や年境界ごとの座標は一括版 ([`timeline_x_positions`]) で 1 回の呼び出しに
//! まとめる (1 ユーザー操作 = 1 呼び出し。要素ごとの FFI 呼び出しにしない)。
//!
//! 日付は epoch 秒。年の切り出しは JST 固定 (理由は domain 側のドキュメント参照)。
//! pt 座標は f64 (CGFloat / Dp への変換はラッパが担う)。

use crate::domain::timeline_layout::{
    TimelineBarPeriod, TimelineHitBox, TimelineSpan, TimelineYearBoundary, TimelineYearRange,
};

/// 帯が重ならないように行 (レーン内の段) を割り当てる。
/// 返り値は `spans` と同じ添字順の行番号 (0 始まり)。詰め方の規則は domain 側参照。
#[uniffi::export]
pub fn timeline_pack_rows(spans: Vec<TimelineSpan>, gap: f64) -> Vec<u32> {
    crate::domain::timeline_layout::pack_rows(&spans, gap)
}

/// 帯の集合が覆う年の範囲 (JST)。空なら `None`。
#[uniffi::export]
pub fn timeline_year_range(periods: Vec<TimelineBarPeriod>) -> Option<TimelineYearRange> {
    crate::domain::timeline_layout::year_range(&periods)
}

/// 年境界 (各年の JST 1/1 00:00)。終端は翌年の 1/1 まで含む (目盛りは年数 + 1 本)。
#[uniffi::export]
pub fn timeline_year_boundaries(first_year: i32, last_year: i32) -> Vec<TimelineYearBoundary> {
    crate::domain::timeline_layout::year_boundaries(first_year, last_year)
}

/// 日付 (epoch 秒) → キャンバス X 座標 (pt)。単発の変換 (今日線・ジャンプ先) 用。
#[uniffi::export]
pub fn timeline_x(epoch_seconds: i64, origin_epoch_seconds: i64, points_per_day: f64) -> f64 {
    crate::domain::timeline_layout::x_for(epoch_seconds, origin_epoch_seconds, points_per_day)
}

/// [`timeline_x`] の一括版。帯・年境界の全 x をこの 1 呼び出しで出す。
#[uniffi::export]
pub fn timeline_x_positions(
    epoch_seconds: Vec<i64>,
    origin_epoch_seconds: i64,
    points_per_day: f64,
) -> Vec<f64> {
    crate::domain::timeline_layout::x_positions(
        &epoch_seconds,
        origin_epoch_seconds,
        points_per_day,
    )
}

/// キャンバス X 座標 → 日付 (epoch 秒、小数含む)。倍率 0 以下では原点に倒す。
#[uniffi::export]
pub fn timeline_epoch_at_x(x: f64, origin_epoch_seconds: i64, points_per_day: f64) -> f64 {
    crate::domain::timeline_layout::epoch_at_x(x, origin_epoch_seconds, points_per_day)
}

/// キャンバス座標 (x, y) にある帯の添字。無ければ `None`。タップ 1 回につき 1 呼び出し。
#[uniffi::export]
pub fn timeline_hit_index(x: f64, y: f64, boxes: Vec<TimelineHitBox>, slop: f64) -> Option<u32> {
    crate::domain::timeline_layout::hit_index(x, y, &boxes, slop)
}

/// 表示幅に年表全体が収まる points_per_day。壊れた入力は 1 に倒す。
#[uniffi::export]
pub fn timeline_fit_points_per_day(span_days: f64, width: f64) -> f64 {
    crate::domain::timeline_layout::fit_points_per_day(span_days, width)
}
