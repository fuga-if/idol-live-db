import XCTest
@testable import ImasLiveDB

/// 年表のレイアウト計算 (`TimelineLayout`) の検査。
///
/// この層が壊れると症状が「なんとなく見た目が変」にしか出ず、目視では気づけない
/// (帯が 1 段深いだけ / 年が 1 日ずれるだけ)。純粋関数のうちに固めておく。
///
/// 規則そのものはコア (imas-core) の Rust テストが持つ。ここに残すのは、Swift の包みが
/// コアに正しく渡し・受け取れていることを見る配線のスモークテストと、Swift にしか無い処理のテスト (Q-13)。
final class TimelineLayoutTests: XCTestCase {

    private let calendar = TimelineDateParser.calendar

    private func date(_ text: String) -> Date {
        guard let date = TimelineDateParser.date(text) else {
            XCTFail("日付をパースできない: \(text)")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    // MARK: - packRows

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

    func testHitIndexReturnsNilOnEmptyArea() {
        XCTAssertNil(TimelineLayout.hitIndex(x: 60, y: 15, boxes: sampleBoxes, slop: 6))
        XCTAssertNil(TimelineLayout.hitIndex(x: 10, y: 15, boxes: [], slop: 6))
    }

    // MARK: - yearRange / yearBoundaries

    /// 目盛りは「年数 + 1」本。最後の年にも右端の罫線が要る。
    func testYearBoundariesIncludeTheClosingEdge() {
        let boundaries = TimelineLayout.yearBoundaries(2024...2026)
        XCTAssertEqual(boundaries.map(\.year), [2024, 2025, 2026, 2027])
        XCTAssertEqual(boundaries.first?.date, date("2024-01-01"))
        XCTAssertEqual(boundaries.last?.date, date("2027-01-01"))
    }

    // MARK: - 座標変換

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
}
