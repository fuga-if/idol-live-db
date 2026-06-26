import XCTest
@testable import ImasLiveDB

/// `filterIdols` (純粋ロジック) の単体テスト。DB に依存しない。
final class IdolListFilteringTests: XCTestCase {

    private func makeIdol(_ id: String, name: String = "", brandId: String = "cg",
                          nameKana: String? = nil, attribute: String? = nil) -> Idol {
        Idol(
            id: id, brandId: brandId, name: name.isEmpty ? id : name, nameKana: nameKana,
            nameRomaji: nil, familyName: nil, givenName: nil, nickname: nil, color: nil,
            sortOrder: 0, birthday: nil, bloodType: nil, height: nil, weight: nil,
            birthPlace: nil, age: nil, bust: nil, waist: nil, hip: nil, constellation: nil,
            hobbies: nil, talents: nil, description: nil, gender: nil, handedness: nil,
            debutDate: nil, attribute: attribute, aliases: nil, voiceActors: nil)
    }

    func testBrandFilter() {
        let idols = [makeIdol("a", brandId: "cg"), makeIdol("b", brandId: "ml")]
        var ctx = IdolFilterContext()
        ctx.selectedBrandIds = ["ml"]
        XCTAssertEqual(filterIdols(idols, ctx).map(\.id), ["b"])
    }

    func testAttributeFilter() {
        let idols = [makeIdol("a", attribute: "cute"), makeIdol("b", attribute: "cool")]
        var ctx = IdolFilterContext()
        ctx.selectedAttribute = "cool"
        XCTAssertEqual(filterIdols(idols, ctx).map(\.id), ["b"])
    }

    func testMarkFiltersAreAndConditions() {
        let idols = [makeIdol("a"), makeIdol("b"), makeIdol("c")]
        var ctx = IdolFilterContext()
        ctx.requireFavorite = true
        ctx.favoriteIds = ["a", "b"]
        ctx.requireMyPick = true
        ctx.myPickIds = ["b", "c"]
        XCTAssertEqual(filterIdols(idols, ctx).map(\.id), ["b"])
    }

    func testSearchMatchesCastName() {
        let idols = [makeIdol("a", name: "島村卯月"), makeIdol("b", name: "渋谷凛")]
        var ctx = IdolFilterContext()
        ctx.searchText = "おおぬま" // 名前には無いがキャスト名で一致
        ctx.castNames = ["a": "大橋彩香", "b": "福原綾香"]
        // どちらのキャストにも「おおぬま」は無い → 0件
        XCTAssertTrue(filterIdols(idols, ctx).isEmpty)

        ctx.castNames = ["a": "おおぬま某", "b": "福原綾香"]
        XCTAssertEqual(filterIdols(idols, ctx).map(\.id), ["a"])
    }
}
