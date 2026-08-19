import Foundation

// =============================================================================
// 年表のレイアウト計算 (純粋関数)。
//
// 「どの帯を何行目に置くか」「日付をキャンバス上の何 pt に置くか」を View から剥がす。
// SwiftUI に依存しないので単体テストできる (ImasLiveDBTests/TimelineLayoutTests)。
// =============================================================================

enum TimelineLayout {
    /// 行詰めに使う 1 本の占有区間 (キャンバス上の pt 座標)。
    struct Span: Sendable, Equatable {
        var start: Double
        var end: Double

        init(start: Double, end: Double) {
            self.start = start
            self.end = max(start, end)
        }
    }

    /// 帯が重ならないように行 (レーン内の段) を割り当てる。
    ///
    /// 貪欲法。開始が早い順に見て、「まだ空いている一番上の段」へ置く。同じ開始位置なら
    /// 長い帯を先に置き、長い帯ほど上に来るようにする (参照デザインと同じ見え方)。
    ///
    /// - Parameters:
    ///   - spans: 各帯の占有区間。**ラベル幅を含めた実効幅**を渡すこと (ラベルは帯より
    ///     長くなるので、帯の幅だけで詰めると文字が隣の帯に重なる)。
    ///   - gap: 隣り合う帯の間に最低限空ける余白 (pt)。
    /// - Returns: `spans` と同じ添字順の行番号 (0 始まり)。
    static func packRows(_ spans: [Span], gap: Double) -> [Int] {
        guard !spans.isEmpty else { return [] }

        let order = spans.indices.sorted { lhs, rhs in
            let a = spans[lhs], b = spans[rhs]
            if a.start != b.start { return a.start < b.start }
            // 同時開始は長い方を上に。
            if a.end != b.end { return a.end > b.end }
            return lhs < rhs
        }

        var rows = [Int](repeating: 0, count: spans.count)
        /// 各行がどこまで埋まっているか (pt)。
        var rowEnds: [Double] = []

        for index in order {
            let span = spans[index]
            if let free = rowEnds.firstIndex(where: { $0 + gap <= span.start }) {
                rows[index] = free
                rowEnds[free] = span.end
            } else {
                rows[index] = rowEnds.count
                rowEnds.append(span.end)
            }
        }
        return rows
    }

    /// 帯の集合が覆う年の範囲。空なら nil。
    ///
    /// 端が中途半端な位置で切れないよう、年単位に丸めた `first...last` を返す。
    static func yearRange(of bars: [TimelineBar], calendar: Calendar) -> ClosedRange<Int>? {
        guard !bars.isEmpty else { return nil }
        var minYear = Int.max
        var maxYear = Int.min
        for bar in bars {
            minYear = min(minYear, calendar.component(.year, from: bar.start))
            maxYear = max(maxYear, calendar.component(.year, from: bar.end))
        }
        guard minYear <= maxYear else { return nil }
        return minYear...maxYear
    }

    /// 年境界 (その年の 1/1 00:00) を作る。範囲の終端は「翌年の 1/1」まで含めて返すので、
    /// 目盛りの本数は `年数 + 1` になる (最後の年にも右端の罫線が引かれる)。
    static func yearBoundaries(_ range: ClosedRange<Int>, calendar: Calendar) -> [(year: Int, date: Date)] {
        (range.lowerBound...(range.upperBound + 1)).compactMap { year in
            var components = DateComponents()
            components.year = year
            components.month = 1
            components.day = 1
            guard let date = calendar.date(from: components) else { return nil }
            return (year, date)
        }
    }

    /// 日付 → キャンバス X 座標 (pt)。
    static func x(for date: Date, origin: Date, pointsPerDay: Double) -> Double {
        date.timeIntervalSince(origin) / 86_400 * pointsPerDay
    }

    /// キャンバス X 座標 (pt) → 日付。ズーム後にスクロール位置を保つときに使う。
    static func date(atX x: Double, origin: Date, pointsPerDay: Double) -> Date {
        guard pointsPerDay > 0 else { return origin }
        return origin.addingTimeInterval(x / pointsPerDay * 86_400)
    }

    /// タップ判定用の当たり矩形 (キャンバス座標)。
    struct HitBox: Sendable, Equatable {
        var x: Double
        var width: Double
        var y: Double
        var height: Double
    }

    /// キャンバス座標 (x, y) にある帯の添字。無ければ nil。
    ///
    /// 細い帯 (単日イベントは数 pt) でも押せるように **横方向にだけ** `slop` の遊びを持たせる。
    /// 縦に広げないのは、上下の段は別の出来事なので誤爆が致命的になるため。
    /// 候補が複数あるときは左端がタップ位置に最も近いものを選ぶ。
    static func hitIndex(x: Double, y: Double, boxes: [HitBox], slop: Double) -> Int? {
        boxes.indices
            .filter { index in
                let box = boxes[index]
                return y >= box.y && y <= box.y + box.height
                    && x >= box.x - slop && x <= box.x + box.width + slop
            }
            .min { abs(boxes[$0].x - x) < abs(boxes[$1].x - x) }
    }

    /// 表示幅に年表全体が収まる `pointsPerDay` を求める。
    ///
    /// - Parameters:
    ///   - span: 年表全体の日数。
    ///   - width: 収めたい表示幅 (pt)。
    static func fitPointsPerDay(spanDays: Double, width: Double) -> Double {
        guard spanDays > 0, width > 0 else { return 1 }
        return width / spanDays
    }
}
