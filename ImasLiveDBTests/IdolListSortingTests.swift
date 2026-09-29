import XCTest
@testable import ImasLiveDB

/// `sortIdols` (純粋ロジック) の単体テスト。DB にも UI にも依存しない。
///
/// 固定する不変条件:
/// - 数値キー (年齢・身長・体重) は既定で降順 (年上から / 背が高い順)。
/// - **値が無いアイドルは並び方向に関わらず必ず末尾**。昇順で先頭に空欄が並ぶと
///   「若い順」を見に来た人の視界を潰すため。
/// - 同値は公式順 (sortOrder) で安定させる (再描画で順序が入れ替わらない)。
///
/// 規則そのものはコア (imas-core) の Rust テストが持つ。ここに残すのは、Swift の包みが
/// コアに正しく渡し・受け取れていることを見る配線のスモークテストと、Swift にしか無い処理のテスト (Q-13)。
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
            debutDate: debutDate, attribute: nil, aliases: nil)
    }

    // MARK: - 配線のスモーク (並べ方と指標の文言はコアのテストが持つ)

    /// 並べ替えと一緒に受け取った指標が、並べた本人の id に配られていること。
    /// 値なしは並び方向にかかわらず末尾 (Optional → Int64 と ascending の受け渡し)。
    func testSortAndMetricLabelsGoThroughTheCore() {
        let idols = [makeIdol("none"), makeIdol("a", age: 17, height: 158), makeIdol("b", age: 12)]
        let byAge = sortIdolsWithMetrics(idols, by: .age, ascending: true)
        XCTAssertEqual(byAge.idols.map(\.id), ["b", "a", "none"])
        XCTAssertEqual(byAge.metricLabels, ["a": "17歳", "b": "12歳"])
        XCTAssertTrue(sortIdolsWithMetrics(idols, by: .official).metricLabels.isEmpty)
    }
}
