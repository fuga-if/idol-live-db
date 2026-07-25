import XCTest
@testable import ImasLiveDB

/// `sortIdols` (純粋ロジック) の単体テスト。DB にも UI にも依存しない。
///
/// 固定する不変条件:
/// - 数値キー (年齢・身長・体重) は既定で降順 (年上から / 背が高い順)。
/// - **値が無いアイドルは並び方向に関わらず必ず末尾**。昇順で先頭に空欄が並ぶと
///   「若い順」を見に来た人の視界を潰すため。
/// - 同値は公式順 (sortOrder) で安定させる (再描画で順序が入れ替わらない)。
final class IdolListSortingTests: XCTestCase {

    private func makeIdol(
        _ id: String,
        sortOrder: Int = 0,
        nameKana: String? = nil,
        age: Int? = nil,
        height: Double? = nil,
        weight: Double? = nil,
        birthday: String? = nil,
        debutDate: String? = nil
    ) -> Idol {
        Idol(
            id: id, brandId: "cg", name: id, nameKana: nameKana,
            nameRomaji: nil, familyName: nil, givenName: nil, nickname: nil, color: nil,
            sortOrder: sortOrder, birthday: birthday, bloodType: nil, height: height, weight: weight,
            birthPlace: nil, age: age, bust: nil, waist: nil, hip: nil, constellation: nil,
            hobbies: nil, talents: nil, description: nil, gender: nil, handedness: nil,
            debutDate: debutDate, attribute: nil, aliases: nil, voiceActors: nil)
    }

    // MARK: - 年齢

    func testAgeDefaultsToOldestFirst() {
        let idols = [makeIdol("a", age: 15), makeIdol("b", age: 32), makeIdol("c", age: 21)]
        XCTAssertEqual(sortIdols(idols, by: .age).map(\.id), ["b", "c", "a"])
    }

    func testAgeAscendingIsYoungestFirst() {
        let idols = [makeIdol("a", age: 15), makeIdol("b", age: 32), makeIdol("c", age: 21)]
        XCTAssertEqual(sortIdols(idols, by: .age, ascending: true).map(\.id), ["a", "c", "b"])
    }

    func testAgeMissingValuesGoLastRegardlessOfDirection() {
        let idols = [makeIdol("none1"), makeIdol("young", age: 12), makeIdol("none2"), makeIdol("old", age: 30)]

        let desc = sortIdols(idols, by: .age, ascending: false).map(\.id)
        XCTAssertEqual(Array(desc.prefix(2)), ["old", "young"])
        XCTAssertEqual(Set(desc.suffix(2)), ["none1", "none2"])

        let asc = sortIdols(idols, by: .age, ascending: true).map(\.id)
        XCTAssertEqual(Array(asc.prefix(2)), ["young", "old"], "昇順でも値なしが先頭に来てはいけない")
        XCTAssertEqual(Set(asc.suffix(2)), ["none1", "none2"])
    }

    // MARK: - 身長 / 体重

    func testHeightDefaultsToTallestFirst() {
        let idols = [makeIdol("s", height: 140), makeIdol("t", height: 191), makeIdol("m", height: 158)]
        XCTAssertEqual(sortIdols(idols, by: .height).map(\.id), ["t", "m", "s"])
    }

    func testWeightAscendingIsLightestFirst() {
        let idols = [makeIdol("h", weight: 52), makeIdol("l", weight: 30), makeIdol("m", weight: 41)]
        XCTAssertEqual(sortIdols(idols, by: .weight, ascending: true).map(\.id), ["l", "m", "h"])
    }

    // MARK: - 文字列キー

    func testNameKanaAscending() {
        let idols = [
            makeIdol("c", nameKana: "うえの"),
            makeIdol("a", nameKana: "あまみ"),
            makeIdol("b", nameKana: "いおり"),
        ]
        XCTAssertEqual(sortIdols(idols, by: .nameKana).map(\.id), ["a", "b", "c"])
    }

    func testBirthdayAscendingStartsFromJanuary() {
        let idols = [
            makeIdol("dec", birthday: "--12-01"),
            makeIdol("jan", birthday: "--01-03"),
            makeIdol("jul", birthday: "--07-17"),
        ]
        XCTAssertEqual(sortIdols(idols, by: .birthday).map(\.id), ["jan", "jul", "dec"])
    }

    func testDebutDescendingIsNewestFirst() {
        let idols = [
            makeIdol("old", debutDate: "2011-11-28"),
            makeIdol("new", debutDate: "2019-01-10"),
            makeIdol("mid", debutDate: "2014-02-19"),
        ]
        XCTAssertEqual(sortIdols(idols, by: .debut, ascending: false).map(\.id), ["new", "mid", "old"])
    }

    func testBirthdayMissingValuesGoLast() {
        let idols = [makeIdol("none"), makeIdol("jan", birthday: "--01-03")]
        XCTAssertEqual(sortIdols(idols, by: .birthday).map(\.id), ["jan", "none"])
    }

    // MARK: - 安定性 / 公式順

    func testTiesFallBackToOfficialOrder() {
        let idols = [
            makeIdol("third", sortOrder: 30, age: 17),
            makeIdol("first", sortOrder: 10, age: 17),
            makeIdol("second", sortOrder: 20, age: 17),
        ]
        // 全員同い年 → 公式順で安定させる (再描画で入れ替わらない)
        XCTAssertEqual(sortIdols(idols, by: .age).map(\.id), ["first", "second", "third"])
    }

    func testOfficialOrderUsesSortOrder() {
        let idols = [makeIdol("b", sortOrder: 2), makeIdol("a", sortOrder: 1), makeIdol("c", sortOrder: 3)]
        XCTAssertEqual(sortIdols(idols, by: .official).map(\.id), ["a", "b", "c"])
    }

    // MARK: - グルーピング方針

    func testOnlyOfficialKeepsBrandGrouping() {
        XCTAssertTrue(IdolSortOrder.official.keepsBrandGrouping)
        for order in IdolSortOrder.allCases where order != .official {
            XCTAssertFalse(order.keepsBrandGrouping, "\(order.rawValue) は通し並びであるべき")
        }
    }

    // MARK: - 行に出す指標

    func testMetricLabelIsShownOnlyForSortableFields() {
        let idol = makeIdol("x", age: 17, height: 158, weight: 45)
        XCTAssertEqual(IdolSortOrder.age.metricLabel(for: idol), "17歳")
        XCTAssertEqual(IdolSortOrder.height.metricLabel(for: idol), "158cm")
        XCTAssertEqual(IdolSortOrder.weight.metricLabel(for: idol), "45kg")
        XCTAssertNil(IdolSortOrder.official.metricLabel(for: idol))
        XCTAssertNil(IdolSortOrder.nameKana.metricLabel(for: idol))
    }

    func testMetricLabelIsNilWhenValueMissing() {
        let idol = makeIdol("x")
        XCTAssertNil(IdolSortOrder.age.metricLabel(for: idol))
        XCTAssertNil(IdolSortOrder.height.metricLabel(for: idol))
    }
}
