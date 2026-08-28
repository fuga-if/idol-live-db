import XCTest
@testable import ImasLiveDB

/// `UnitListViewModel` の絞り込みが**コアの照合を通っている**ことの単体テスト。
///
/// 長らくここは `displayName.localizedCaseInsensitiveContains` を手書きしていて、
/// 曲・アイドル・ライブは「あるすとろめりあ」で当たるのにユニット一覧だけ当たらない、
/// という説明の付かない差になっていた。さらに `units.name_kana` が無かったので、
/// 漢字のユニット名は読みからも辿り着けなかった。両方を塞いだ後の回帰止め。
@MainActor
final class UnitListViewModelTests: XCTestCase {

    // MARK: - Fakes

    private struct FakeUnitReading: UnitReading {
        var unitsToReturn: [ImasLiveDB.Unit] = []

        /// 一覧は `unitsWithSongs()` を通る (= 曲ありユニットだけ)。
        /// 既定実装が `unitIndex()` から組むので、ここは全件を「曲あり」として返す。
        func unitIndex() async throws -> UnitIndex {
            UnitIndex(
                units: unitsToReturn,
                memberIds: [:],
                byIdol: [:],
                unitsWithSongs: Set(unitsToReturn.map(\.id))
            )
        }

        // 未使用メソッドは既定値で充足 (このテストでは呼ばれない)。
        func unit(id: String) async throws -> ImasLiveDB.Unit? { nil }
        func unitMembers(unitId: String) async throws -> [Idol] { [] }
        func unitSongs(unitId: String) async throws -> [Song] { [] }
        func unitIdsWithSongs(unitIds: [String]) async throws -> Set<String> { [] }
        func performedUnitIds(eventId: String) async throws -> Set<String> { [] }
        func allUnits() async throws -> [ImasLiveDB.Unit] { unitsToReturn }
    }

    private struct FakeBrandReading: BrandReading {
        var brandsToReturn: [Brand] = []
        func brands() async throws -> [Brand] { brandsToReturn }
    }

    // MARK: - Fixtures

    private func makeUnit(
        _ id: String, name: String, nameAlt: String? = nil, nameKana: String? = nil
    ) -> ImasLiveDB.Unit {
        ImasLiveDB.Unit(
            id: id, brandId: "cg", name: name,
            isPermanent: true, nameAlt: nameAlt, nameKana: nameKana
        )
    }

    private func loadedViewModel(_ units: [ImasLiveDB.Unit]) async -> UnitListViewModel {
        let vm = UnitListViewModel(
            unitReading: FakeUnitReading(unitsToReturn: units),
            brandReading: FakeBrandReading(brandsToReturn: [
                Brand(id: "cg", name: "シンデレラガールズ", shortName: "CG",
                      color: nil, sortOrder: 0)
            ])
        )
        await vm.loadData()
        return vm
    }

    private func names(_ vm: UnitListViewModel, _ query: String) -> [String] {
        vm.rebuild(searchText: query)
        return vm.filteredUnits.map(\.name)
    }

    // MARK: - Tests

    /// ひらがな↔カタカナを畳む。手書きの `contains` に戻したらここが落ちる。
    func testSearchFoldsKanaLikeEveryOtherList() async {
        let vm = await loadedViewModel([makeUnit("u1", name: "アルストロメリア")])

        XCTAssertEqual(names(vm, "アルストロメリア"), ["アルストロメリア"])
        XCTAssertEqual(names(vm, "あるすとろめりあ"), ["アルストロメリア"],
                       "ひらがなで打っても当たること")
        XCTAssertEqual(names(vm, "すとろ"), ["アルストロメリア"], "部分一致")
    }

    /// 漢字のユニット名を読みで引ける (`units.name_kana`)。
    ///
    /// 「あたらよづき」は表記から機械的には起こせない読みで、実際にこの列を足すまで
    /// 「可惜夜月」には辿り着けなかった。
    func testKanjiNameIsReachableThroughItsReading() async {
        let vm = await loadedViewModel([
            makeUnit("u1", name: "可惜夜月", nameKana: "あたらよづき"),
            makeUnit("u2", name: "凸レーション", nameKana: "でこれーしょん")
        ])

        XCTAssertEqual(names(vm, "あたらよづき"), ["可惜夜月"])
        XCTAssertEqual(names(vm, "でこれーしょん"), ["凸レーション"])
        // 読みもカタカナ入力で当たる (畳み込みは読み側にも効く)。
        XCTAssertEqual(names(vm, "デコレーション"), ["凸レーション"])
        // 漢字表記でも従来どおり引ける (読みを足して失われていない)。
        XCTAssertEqual(names(vm, "可惜"), ["可惜夜月"])
    }

    /// 別名でも引ける (「Cleasky」でも「クレスカイ」でも)。
    func testAlternateNameIsSearchable() async {
        let vm = await loadedViewModel([
            makeUnit("u1", name: "Cleasky", nameAlt: "クレスカイ")
        ])

        XCTAssertEqual(names(vm, "cleasky"), ["Cleasky"], "大文字小文字を畳む")
        XCTAssertEqual(names(vm, "くれすかい"), ["Cleasky"], "別名をひらがなで")
    }

    /// 読みが無い行は名前だけで引ける (読みは全件には入っていない)。
    func testUnitsWithoutReadingStillMatchByName() async {
        let vm = await loadedViewModel([makeUnit("u1", name: "星纏天女")])

        XCTAssertEqual(names(vm, "星纏"), ["星纏天女"])
        XCTAssertTrue(names(vm, "せいてん").isEmpty, "読みが無いので かなでは当たらない")
    }

    /// 空の検索語は絞り込まない。
    func testEmptyQueryKeepsEveryUnit() async {
        let vm = await loadedViewModel([
            makeUnit("u1", name: "可惜夜月", nameKana: "あたらよづき"),
            makeUnit("u2", name: "アルストロメリア")
        ])

        XCTAssertEqual(names(vm, ""), ["可惜夜月", "アルストロメリア"])
        XCTAssertEqual(names(vm, "   "), ["可惜夜月", "アルストロメリア"], "空白だけも同じ")
    }
}
