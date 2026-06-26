import XCTest
@testable import ImasLiveDB

/// `IdolListViewModel` のオーケストレーション (ポート取得 → グループ化) の単体テスト。
/// 絞り込み自体は `filterIdols` 側でテスト済み。ここでは VM 固有の
/// ブランド別グループ化・visibleBrands 導出・castNames 補完を検証する。
@MainActor
final class IdolListViewModelTests: XCTestCase {

    // MARK: - Fakes

    private struct FakeIdolReading: IdolReading {
        var idolsToReturn: [Idol] = []
        var castNamesToReturn: [String: String] = [:]

        func idols(brandId: String?) async throws -> [Idol] { idolsToReturn }
        func idolCastNames() async throws -> [String: String] { castNamesToReturn }

        // 未使用メソッドは既定値で充足 (このテストでは呼ばれない)。
        func idol(id: String) async throws -> Idol? { nil }
        func idols(ids: [String]) async throws -> [Idol] { [] }
        func idols(criterion: IdolFilterCriterion) async throws -> [Idol] { [] }
        func idolsByVoiceActor(name: String) async throws -> [Idol] { [] }
        func searchIdols(query: String, limit: Int) async throws -> [Idol] { [] }
        func idolSongs(idolId: String, role: String?) async throws -> [Song] { [] }
        func idolPerformedSongs(idolId: String) async throws -> [IdolPerformedSong] { [] }
        func idolUnits(idolId: String) async throws -> [ImasLiveDB.Unit] { [] }
        func idolShows(idolId: String) async throws -> [CastShowRow] { [] }
        func allIdolsForPicker() async throws -> [Idol] { [] }
        func idolSongHistory(idolId: String, songId: String) async throws -> [CastShowRow] { [] }
    }

    private struct FakeBrandReading: BrandReading {
        var brandsToReturn: [Brand] = []
        func brands() async throws -> [Brand] { brandsToReturn }
    }

    // MARK: - Fixtures

    private func makeIdol(_ id: String, brandId: String) -> Idol {
        Idol(
            id: id, brandId: brandId, name: id, nameKana: nil,
            nameRomaji: nil, familyName: nil, givenName: nil, nickname: nil, color: nil,
            sortOrder: 0, birthday: nil, bloodType: nil, height: nil, weight: nil,
            birthPlace: nil, age: nil, bust: nil, waist: nil, hip: nil, constellation: nil,
            hobbies: nil, talents: nil, description: nil, gender: nil, handedness: nil,
            debutDate: nil, attribute: nil, aliases: nil, voiceActors: nil)
    }

    private func makeBrand(_ id: String) -> Brand {
        Brand(id: id, name: id, shortName: id, color: nil, sortOrder: 0, iconUrl: nil)
    }

    private func makeVM(idols: [Idol], brands: [Brand], castNames: [String: String] = [:]) -> IdolListViewModel {
        IdolListViewModel(
            idolReading: FakeIdolReading(idolsToReturn: idols, castNamesToReturn: castNames),
            brandReading: FakeBrandReading(brandsToReturn: brands))
    }

    // MARK: - Tests

    func testLoadGroupsByBrandAndDerivesVisibleBrands() async {
        // cg に 2 件、ml に 1 件。空の op ブランドは visibleBrands に出ない。
        let idols = [makeIdol("a", brandId: "cg"), makeIdol("b", brandId: "ml"), makeIdol("c", brandId: "cg")]
        let brands = [makeBrand("cg"), makeBrand("ml"), makeBrand("op")]
        let vm = makeVM(idols: idols, brands: brands)

        await vm.loadData(filter: IdolFilterContext())

        XCTAssertEqual(vm.filteredIdols.count, 3)
        XCTAssertEqual(Set(vm.groupedByBrand["cg"]?.map(\.id) ?? []), ["a", "c"])
        XCTAssertEqual(vm.groupedByBrand["ml"]?.map(\.id), ["b"])
        XCTAssertNil(vm.groupedByBrand["op"])
        // visibleBrands は brands の並び順を保ち、空ブランドを除外する。
        XCTAssertEqual(vm.visibleBrands.map(\.id), ["cg", "ml"])
    }

    func testRebuildAppliesBrandFilter() async {
        let idols = [makeIdol("a", brandId: "cg"), makeIdol("b", brandId: "ml")]
        let brands = [makeBrand("cg"), makeBrand("ml")]
        let vm = makeVM(idols: idols, brands: brands)
        await vm.loadData(filter: IdolFilterContext())

        var ctx = IdolFilterContext()
        ctx.selectedBrandIds = ["ml"]
        vm.rebuild(filter: ctx)

        XCTAssertEqual(vm.filteredIdols.map(\.id), ["b"])
        XCTAssertEqual(vm.visibleBrands.map(\.id), ["ml"])
    }

    func testRebuildSuppliesCastNamesForSearch() async {
        // castNames は VM 保持の値が rebuild 時に補完され、検索対象に入る。
        let idols = [makeIdol("a", brandId: "cg"), makeIdol("b", brandId: "cg")]
        let brands = [makeBrand("cg")]
        let vm = makeVM(idols: idols, brands: brands, castNames: ["a": "大橋彩香", "b": "福原綾香"])
        await vm.loadData(filter: IdolFilterContext())

        var ctx = IdolFilterContext()
        ctx.searchText = "大橋" // 呼び出し側は castNames を詰めない
        vm.rebuild(filter: ctx)

        XCTAssertEqual(vm.filteredIdols.map(\.id), ["a"])
    }
}
