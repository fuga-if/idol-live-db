import Foundation

// =============================================================================
// 年表のレイアウト計算 — 本体は imas-core の domain/timeline_layout.rs。
//
// 行詰め・年範囲・座標変換・タップ判定の規則と設計意図はすべてそちらに記載。
// ここが担うのは境界の型合わせだけ:
// - Date <-> epoch 秒、CGFloat/Double <-> f64、Int <-> Int32/UInt32 の変換
// - エンティティ (TimelineBar) から必要フィールドだけの射影 Record を作る
// 年境界の切り出しはコア側で JST 固定なので、Calendar は受け取らない。
// 帯・年境界ごとの座標は一括版 xs() で 1 回の FFI 呼び出しにまとめる
// (要素ごとの FFI 呼び出しにしない)。
// =============================================================================

enum TimelineLayout {
    /// 行詰めに使う 1 本の占有区間 (キャンバス上の pt 座標)。
    ///
    /// `start > end` の逆転入力は init で「start 位置の幅 0」に直す (コア側の
    /// `TimelineSpan::normalized` と同じ規則。Record は素通しなので両側で揃えている)。
    struct Span: Sendable, Equatable {
        var start: Double
        var end: Double

        init(start: Double, end: Double) {
            self.start = start
            self.end = max(start, end)
        }
    }

    /// 帯が重ならないように行 (レーン内の段) を割り当てる。
    /// 返り値は `spans` と同じ添字順の行番号 (0 始まり)。
    static func packRows(_ spans: [Span], gap: Double) -> [Int] {
        timelinePackRows(
            spans: spans.map { TimelineSpan(start: $0.start, end: $0.end) },
            gap: gap
        ).map(Int.init)
    }

    /// 帯の集合が覆う年の範囲 (JST)。空なら nil。
    static func yearRange(of bars: [TimelineBar]) -> ClosedRange<Int>? {
        let range = timelineYearRange(periods: bars.map {
            TimelineBarPeriod(
                startEpochSeconds: Int64($0.start.timeIntervalSince1970),
                endEpochSeconds: Int64($0.end.timeIntervalSince1970)
            )
        })
        guard let range else { return nil }
        return Int(range.firstYear)...Int(range.lastYear)
    }

    /// 年境界 (各年の JST 1/1 00:00)。終端は翌年の 1/1 まで含む (目盛りは年数 + 1 本)。
    static func yearBoundaries(_ range: ClosedRange<Int>) -> [(year: Int, date: Date)] {
        timelineYearBoundaries(
            firstYear: Int32(range.lowerBound),
            lastYear: Int32(range.upperBound)
        ).map { (Int($0.year), Date(timeIntervalSince1970: Double($0.epochSeconds))) }
    }

    /// 日付 → キャンバス X 座標 (pt)。単発の変換 (今日線・ジャンプ先) 用。
    static func x(for date: Date, origin: Date, pointsPerDay: Double) -> Double {
        timelineX(
            epochSeconds: Int64(date.timeIntervalSince1970),
            originEpochSeconds: Int64(origin.timeIntervalSince1970),
            pointsPerDay: pointsPerDay
        )
    }

    /// `x(for:)` の一括版。帯・年境界の全 x をこの 1 呼び出しで出す。
    static func xs(for dates: [Date], origin: Date, pointsPerDay: Double) -> [Double] {
        timelineXPositions(
            epochSeconds: dates.map { Int64($0.timeIntervalSince1970) },
            originEpochSeconds: Int64(origin.timeIntervalSince1970),
            pointsPerDay: pointsPerDay
        )
    }

    /// キャンバス X 座標 (pt) → 日付。ズーム後にスクロール位置を保つときに使う。
    static func date(atX x: Double, origin: Date, pointsPerDay: Double) -> Date {
        Date(timeIntervalSince1970: timelineEpochAtX(
            x: x,
            originEpochSeconds: Int64(origin.timeIntervalSince1970),
            pointsPerDay: pointsPerDay
        ))
    }

    /// タップ判定用の当たり矩形 (キャンバス座標)。
    struct HitBox: Sendable, Equatable {
        var x: Double
        var width: Double
        var y: Double
        var height: Double
    }

    /// キャンバス座標 (x, y) にある帯の添字。無ければ nil。タップ 1 回につき 1 呼び出し。
    static func hitIndex(x: Double, y: Double, boxes: [HitBox], slop: Double) -> Int? {
        timelineHitIndex(
            x: x,
            y: y,
            boxes: boxes.map { TimelineHitBox(x: $0.x, width: $0.width, y: $0.y, height: $0.height) },
            slop: slop
        ).map(Int.init)
    }

    /// 表示幅に年表全体が収まる `pointsPerDay` を求める。壊れた入力は 1 に倒す。
    static func fitPointsPerDay(spanDays: Double, width: Double) -> Double {
        timelineFitPointsPerDay(spanDays: spanDays, width: width)
    }
}
