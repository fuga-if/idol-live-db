import XCTest
@testable import ImasLiveDB

/// 年表のレイアウト計算 (`TimelineLayout`) の検査。
///
/// この層が壊れると症状が「なんとなく見た目が変」にしか出ず、目視では気づけない
/// (帯が 1 段深いだけ / 年が 1 日ずれるだけ)。純粋関数のうちに固めておく。
final class TimelineLayoutTests: XCTestCase {

    private let calendar = TimelineDateParser.calendar

    private func date(_ text: String) -> Date {
        guard let date = TimelineDateParser.date(text) else {
            XCTFail("日付をパースできない: \(text)")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    private func bar(
        _ id: String,
        _ start: String,
        _ end: String,
        lane: TimelineLane = .live
    ) -> TimelineBar {
        TimelineBar(
            id: id, lane: lane, title: id,
            start: date(start), end: date(end),
            marks: [], seedHex: nil, categoryKey: id, badge: nil, target: .none
        )
    }

    // MARK: - packRows

    func testPackRowsPutsNonOverlappingSpansOnTheSameRow() {
        let spans = [
            TimelineLayout.Span(start: 0, end: 10),
            TimelineLayout.Span(start: 30, end: 40),
            TimelineLayout.Span(start: 60, end: 70),
        ]
        XCTAssertEqual(TimelineLayout.packRows(spans, gap: 5), [0, 0, 0])
    }

    func testPackRowsPushesOverlappingSpansDown() {
        let spans = [
            TimelineLayout.Span(start: 0, end: 100),
            TimelineLayout.Span(start: 10, end: 50),
            TimelineLayout.Span(start: 20, end: 30),
        ]
        XCTAssertEqual(TimelineLayout.packRows(spans, gap: 0), [0, 1, 2])
    }

    /// gap の分だけ離れていない帯は同じ段に置かない (ラベルや点が隣とくっつくため)。
    func testPackRowsRespectsGap() {
        let spans = [
            TimelineLayout.Span(start: 0, end: 10),
            TimelineLayout.Span(start: 12, end: 20),
        ]
        XCTAssertEqual(TimelineLayout.packRows(spans, gap: 0), [0, 0])
        XCTAssertEqual(TimelineLayout.packRows(spans, gap: 8), [0, 1])
    }

    /// 空いた段があればそこを埋める (無駄に縦へ伸ばさない)。
    func testPackRowsReusesFreedRows() {
        let spans = [
            TimelineLayout.Span(start: 0, end: 100),   // row 0
            TimelineLayout.Span(start: 0, end: 10),    // row 1
            TimelineLayout.Span(start: 20, end: 30),   // row 1 に戻れる
        ]
        XCTAssertEqual(TimelineLayout.packRows(spans, gap: 0), [0, 1, 1])
    }

    /// 同時開始なら長い帯が上。参照デザインと同じく「長い流れが上、単発が下」に見える。
    func testPackRowsPutsLongerSpanOnTopWhenStartingTogether() {
        let spans = [
            TimelineLayout.Span(start: 0, end: 10),
            TimelineLayout.Span(start: 0, end: 100),
        ]
        XCTAssertEqual(TimelineLayout.packRows(spans, gap: 0), [1, 0])
    }

    func testPackRowsHandlesEmptyInput() {
        XCTAssertTrue(TimelineLayout.packRows([], gap: 4).isEmpty)
    }

    /// 入力順と戻り値の添字は必ず一致する (ここがずれると別の帯の位置に描かれる)。
    func testPackRowsKeepsInputOrder() {
        let spans = [
            TimelineLayout.Span(start: 90, end: 100),
            TimelineLayout.Span(start: 0, end: 10),
            TimelineLayout.Span(start: 95, end: 99),
        ]
        let rows = TimelineLayout.packRows(spans, gap: 0)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1], 0)       // 一番左は必ず 0 段目
        XCTAssertNotEqual(rows[0], rows[2])  // 重なる 2 本は別の段
    }

    /// start > end の壊れた入力でも段割りは破綻しない (DB 側の日付逆転に対する保険)。
    func testSpanNormalizesReversedRange() {
        let span = TimelineLayout.Span(start: 50, end: 10)
        XCTAssertEqual(span.start, 50)
        XCTAssertEqual(span.end, 50)
    }

    // MARK: - hitIndex (タップ判定)

    /// 行 0 に 2 本、行 1 に 1 本。座標系はキャンバス基準 (パン適用後)。
    private var sampleBoxes: [TimelineLayout.HitBox] {
        [
            .init(x: 0, width: 20, y: 0, height: 30),     // 0
            .init(x: 100, width: 20, y: 0, height: 30),   // 1
            .init(x: 0, width: 20, y: 30, height: 30),    // 2
        ]
    }

    func testHitIndexFindsBarUnderPoint() {
        XCTAssertEqual(TimelineLayout.hitIndex(x: 10, y: 15, boxes: sampleBoxes, slop: 6), 0)
        XCTAssertEqual(TimelineLayout.hitIndex(x: 110, y: 15, boxes: sampleBoxes, slop: 6), 1)
    }

    /// 段が違えば別の出来事。縦には遊びを持たせない。
    func testHitIndexDistinguishesRows() {
        XCTAssertEqual(TimelineLayout.hitIndex(x: 10, y: 45, boxes: sampleBoxes, slop: 6), 2)
    }

    /// 細い帯を押せるように横だけ slop ぶん広い。
    func testHitIndexAppliesHorizontalSlopOnly() {
        XCTAssertEqual(TimelineLayout.hitIndex(x: -5, y: 15, boxes: sampleBoxes, slop: 6), 0)
        XCTAssertEqual(TimelineLayout.hitIndex(x: 25, y: 15, boxes: sampleBoxes, slop: 6), 0)
        // slop を超えた先は何も無い (隣の帯を誤爆しない)
        XCTAssertNil(TimelineLayout.hitIndex(x: 40, y: 15, boxes: sampleBoxes, slop: 6))
        // 縦は広げない
        XCTAssertNil(TimelineLayout.hitIndex(x: 10, y: -5, boxes: sampleBoxes, slop: 6))
    }

    func testHitIndexReturnsNilOnEmptyArea() {
        XCTAssertNil(TimelineLayout.hitIndex(x: 60, y: 15, boxes: sampleBoxes, slop: 6))
        XCTAssertNil(TimelineLayout.hitIndex(x: 10, y: 15, boxes: [], slop: 6))
    }

    /// 重なった帯は左端がタップ位置に近い方を選ぶ。
    func testHitIndexPrefersNearestLeadingEdge() {
        let boxes: [TimelineLayout.HitBox] = [
            .init(x: 0, width: 200, y: 0, height: 30),
            .init(x: 90, width: 20, y: 0, height: 30),
        ]
        XCTAssertEqual(TimelineLayout.hitIndex(x: 95, y: 10, boxes: boxes, slop: 6), 1)
        XCTAssertEqual(TimelineLayout.hitIndex(x: 5, y: 10, boxes: boxes, slop: 6), 0)
    }

    // MARK: - yearRange / yearBoundaries

    func testYearRangeCoversAllBars() {
        let bars = [
            bar("a", "2013-05-29", "2014-04-30"),
            bar("b", "2026-08-01", "2027-07-25"),
        ]
        XCTAssertEqual(TimelineLayout.yearRange(of: bars, calendar: calendar), 2013...2027)
    }

    func testYearRangeIsNilForEmptyBars() {
        XCTAssertNil(TimelineLayout.yearRange(of: [], calendar: calendar))
    }

    /// 目盛りは「年数 + 1」本。最後の年にも右端の罫線が要る。
    func testYearBoundariesIncludeTheClosingEdge() {
        let boundaries = TimelineLayout.yearBoundaries(2024...2026, calendar: calendar)
        XCTAssertEqual(boundaries.map(\.year), [2024, 2025, 2026, 2027])
        XCTAssertEqual(boundaries.first?.date, date("2024-01-01"))
        XCTAssertEqual(boundaries.last?.date, date("2027-01-01"))
    }

    // MARK: - 座標変換

    func testXIsProportionalToElapsedDays() {
        let origin = date("2026-01-01")
        XCTAssertEqual(TimelineLayout.x(for: origin, origin: origin, pointsPerDay: 2), 0, accuracy: 0.001)
        XCTAssertEqual(
            TimelineLayout.x(for: date("2026-01-11"), origin: origin, pointsPerDay: 2),
            20, accuracy: 0.001
        )
    }

    func testDateAtXRoundTrips() {
        let origin = date("2020-03-01")
        let target = date("2023-11-17")
        let x = TimelineLayout.x(for: target, origin: origin, pointsPerDay: 0.27)
        let back = TimelineLayout.date(atX: x, origin: origin, pointsPerDay: 0.27)
        XCTAssertEqual(back.timeIntervalSince1970, target.timeIntervalSince1970, accuracy: 1)
    }

    /// 倍率 0 でゼロ除算しない (ピンチで潰し切ったときの保険)。
    func testDateAtXWithZeroScaleReturnsOrigin() {
        let origin = date("2020-03-01")
        XCTAssertEqual(TimelineLayout.date(atX: 500, origin: origin, pointsPerDay: 0), origin)
    }

    /// うるう年をまたいでも年の幅は実日数どおり (366 日の年は 1 日ぶん広い)。
    func testLeapYearIsWiderThanCommonYear() {
        let origin = date("2023-01-01")
        let leapWidth = TimelineLayout.x(for: date("2025-01-01"), origin: origin, pointsPerDay: 1)
            - TimelineLayout.x(for: date("2024-01-01"), origin: origin, pointsPerDay: 1)
        let commonWidth = TimelineLayout.x(for: date("2024-01-01"), origin: origin, pointsPerDay: 1)
        XCTAssertEqual(commonWidth, 365, accuracy: 0.001)
        XCTAssertEqual(leapWidth, 366, accuracy: 0.001)
    }

    func testFitPointsPerDayFillsTheGivenWidth() {
        XCTAssertEqual(TimelineLayout.fitPointsPerDay(spanDays: 1000, width: 400), 0.4, accuracy: 0.0001)
        // 壊れた入力でも 0 や NaN を返さない (キャンバス幅 0 でクラッシュさせないため)。
        XCTAssertEqual(TimelineLayout.fitPointsPerDay(spanDays: 0, width: 400), 1)
        XCTAssertEqual(TimelineLayout.fitPointsPerDay(spanDays: 1000, width: 0), 1)
    }

    // MARK: - 日付パース

    func testDateParserAcceptsIsoPrefixAndRejectsGarbage() {
        XCTAssertEqual(TimelineDateParser.date("2026-08-04"), date("2026-08-04"))
        XCTAssertEqual(TimelineDateParser.date("2026-08-04T12:00:00Z"), date("2026-08-04"))
        XCTAssertNil(TimelineDateParser.date(""))
        XCTAssertNil(TimelineDateParser.date("2026-08"))
        XCTAssertNil(TimelineDateParser.date(nil))
    }

    /// `GROUP_CONCAT` 由来のカンマ区切りは重複を畳んで昇順に。
    func testDatesParsesGroupConcatAndSortsUniquely() {
        let dates = TimelineDateParser.dates("2026-03-02,2026-01-01,2026-03-02,bad")
        XCTAssertEqual(dates, [date("2026-01-01"), date("2026-03-02")])
        XCTAssertTrue(TimelineDateParser.dates(nil).isEmpty)
    }

    /// 端末のタイムゾーンに関係なく JST の日付境界で切る。
    /// (ここがローカル依存だと「1/1 のリリースが前年の帯に入る」表示崩れになる)
    func testCalendarIsPinnedToTokyo() {
        XCTAssertEqual(TimelineDateParser.calendar.timeZone.identifier, "Asia/Tokyo")
        XCTAssertEqual(calendar.component(.year, from: date("2026-01-01")), 2026)
        XCTAssertEqual(calendar.component(.year, from: date("2025-12-31")), 2025)
    }

    // MARK: - TimelineBar

    func testDurationDaysIsZeroForSingleDayBar() {
        XCTAssertEqual(bar("x", "2026-08-04", "2026-08-04").durationDays, 0, accuracy: 0.001)
        XCTAssertEqual(bar("y", "2026-08-04", "2026-08-06").durationDays, 2, accuracy: 0.001)
    }
}
