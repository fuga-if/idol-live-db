import XCTest
@testable import ImasLiveDB

/// `MyPageViewModel` のオーケストレーション (ポート取得 → 表示値 / 型紙生成) の単体テスト。
/// JSON の組み立て自体は `MyPageRulesTests` 側で検証済み。ここでは
/// 「どのポートから何を取り、どう詰めるか」と、失敗時に画面を壊さないことを見る。
@MainActor
final class MyPageViewModelTests: XCTestCase {

    // MARK: - Fakes

    private struct FakeDiagnosticsReading: DiagnosticsReading {
        var meta: [String: String] = [:]
        var stats = DatabaseStats(songCount: 0, idolCount: 0, eventCount: 0, showCount: 0)
        var shouldThrow = false

        func metaValue(forKey key: String) async throws -> String? {
            if shouldThrow { throw TestError.boom }
            return meta[key]
        }
        func databaseStats() async throws -> DatabaseStats {
            if shouldThrow { throw TestError.boom }
            return stats
        }
    }

    private struct FakeBrandReading: BrandReading {
        var brandsToReturn: [Brand] = []
        func brands() async throws -> [Brand] { brandsToReturn }
    }

    private struct FakeMarkReading: MarkReading {
        var markedIds: [String] = []

        func markedEntityIds(entity: UserMarkEntity, kind: UserMarkKind) async throws -> [String] {
            markedIds
        }
        func autoCollectedSongIds() async throws -> Set<String> { [] }
    }

    private struct FakeIdolReading: IdolReading {
        var byIds: [Idol] = []
        var allIdols: [Idol] = []

        func idols(ids: [String]) async throws -> [Idol] { byIds }

        func similarIdols(from candidates: [SimilarIdolCandidate]) async throws -> [Idol] { [] }
        func idols(brandId: String?) async throws -> [Idol] { allIdols }

        func idol(id: String) async throws -> Idol? { nil }
        func idols(criterion: IdolFilterCriterion) async throws -> [Idol] { [] }
        func idolsByVoiceActor(name: String) async throws -> [Idol] { [] }
        func searchIdols(query: String, limit: Int) async throws -> [Idol] { [] }
        func idolCastNames() async throws -> [String: String] { [:] }
        func idolSongs(idolId: String, role: String?) async throws -> [Song] { [] }
        func idolOriginalSongSections(idolId: String) async throws -> [IdolSongSection] { [] }
        func idolPerformedSongs(idolId: String) async throws -> [IdolPerformedSong] { [] }
        func idolUnits(idolId: String) async throws -> [ImasLiveDB.Unit] { [] }
        func idolShows(idolId: String) async throws -> [CastShowRow] { [] }
        func allIdolsForPicker() async throws -> [Idol] { [] }
        func idolSongHistory(idolId: String, songId: String) async throws -> [CastShowRow] { [] }
    }

    private struct FakeUnitReading: UnitReading {
        var units: [ImasLiveDB.Unit] = []

        func unitIndex() async throws -> UnitIndex {
            UnitIndex(units: units, memberIds: [:], unitsWithSongs: [])
        }
        func unit(id: String) async throws -> ImasLiveDB.Unit? { nil }
        func unitMembers(unitId: String) async throws -> [Idol] { [] }
        func unitSongs(unitId: String) async throws -> [Song] { [] }
        func unitIdsWithSongs(unitIds: [String]) async throws -> Set<String> { [] }
        func allUnits() async throws -> [ImasLiveDB.Unit] { units }
    }

    private enum TestError: Error { case boom }

    // MARK: - Fixtures

    private func makeIdol(_ id: String, name: String? = nil) -> Idol {
        Idol(
            id: id, brandId: "cg", name: name ?? id, nameKana: nil,
            nameRomaji: nil, familyName: nil, givenName: nil, nickname: nil, color: nil,
            sortOrder: 0, birthday: nil, bloodType: nil, height: nil, weight: nil,
            birthPlace: nil, age: nil, bust: nil, waist: nil, hip: nil, constellation: nil,
            hobbies: nil, talents: nil, description: nil, gender: nil, handedness: nil,
            debutDate: nil, attribute: nil, aliases: nil)
    }

    private func makeUnit(_ id: String, name: String, isPermanent: Bool) -> ImasLiveDB.Unit {
        ImasLiveDB.Unit(id: id, brandId: "cg", name: name, isPermanent: isPermanent, nameAlt: nil)
    }

    private func makeVM(
        diagnostics: FakeDiagnosticsReading = FakeDiagnosticsReading(),
        brands: FakeBrandReading = FakeBrandReading(),
        idols: FakeIdolReading = FakeIdolReading(),
        marks: FakeMarkReading = FakeMarkReading(),
        units: FakeUnitReading = FakeUnitReading()
    ) -> MyPageViewModel {
        MyPageViewModel(
            diagnosticsReading: diagnostics, brandReading: brands,
            idolReading: idols, markReading: marks, unitReading: units)
    }

    // MARK: - load

    func testLoadFillsVersionsAndStats() async {
        let diag = FakeDiagnosticsReading(
            meta: ["schema_version": "27", "data_version": "61"],
            stats: DatabaseStats(songCount: 10, idolCount: 20, eventCount: 3, showCount: 5))
        let vm = makeVM(diagnostics: diag)

        await vm.load()

        XCTAssertEqual(vm.schemaVersion, "27")
        XCTAssertEqual(vm.dataVersion, "61")
        XCTAssertEqual(vm.dbStats?.idolCount, 20)
    }

    /// DB が転んでも画面は開ける (設定画面が真っ白になる方が困る)。
    func testLoadKeepsGoingWhenDiagnosticsThrow() async {
        var diag = FakeDiagnosticsReading()
        diag.shouldThrow = true
        let vm = makeVM(diagnostics: diag, brands: FakeBrandReading(brandsToReturn: []))

        await vm.load()

        // 初期値のまま。クラッシュしない。
        XCTAssertEqual(vm.schemaVersion, "...")
        XCTAssertNil(vm.dbStats)
    }

    /// 診断 (版と件数) を読み損ねても、ブランドと担当は読む。
    /// 以前は同じ do の中にあり、診断の失敗でテーマ色の選択肢 (担当) まで消えていた。
    func testBrandsAndPicksLoadEvenWhenDiagnosticsThrow() async {
        var diag = FakeDiagnosticsReading()
        diag.shouldThrow = true
        let brand = Brand(id: "cg", name: "シンデレラガールズ", shortName: "CG",
                          color: nil, sortOrder: 0, iconUrl: nil)
        let vm = makeVM(
            diagnostics: diag,
            brands: FakeBrandReading(brandsToReturn: [brand]),
            idols: FakeIdolReading(byIds: [makeIdol("i1")]),
            marks: FakeMarkReading(markedIds: ["i1"]))

        await vm.load()

        XCTAssertNil(vm.dbStats)
        XCTAssertEqual(vm.brands.map(\.id), ["cg"])
        XCTAssertEqual(vm.pickIdols.map(\.id), ["i1"])
    }

    // MARK: - 画像インポート用の型紙

    func testTemplatesAreGeneratedForIdolsBrandsAndUnits() async throws {
        let vm = makeVM(
            brands: FakeBrandReading(brandsToReturn: [
                Brand(id: "cg", name: "シンデレラガールズ", shortName: "CG",
                      color: nil, sortOrder: 0, iconUrl: nil)
            ]),
            idols: FakeIdolReading(allIdols: [makeIdol("i1", name: "あ"), makeIdol("i2", name: "い")]),
            units: FakeUnitReading(units: [
                makeUnit("u1", name: "常設ユニット", isPermanent: true),
                makeUnit("u2", name: "臨時ユニット", isPermanent: false),
            ]))

        await vm.load()

        let idolURL = try XCTUnwrap(vm.idolTemplateURL)
        let idolJSON = try String(contentsOf: idolURL, encoding: .utf8)
        XCTAssertTrue(idolJSON.contains("\"あ\""))
        XCTAssertTrue(idolJSON.contains("\"い\""))

        let brandURL = try XCTUnwrap(vm.brandTemplateURL)
        XCTAssertTrue(try String(contentsOf: brandURL, encoding: .utf8).contains("\"CG\""))

        // 臨時ユニットは型紙に載せない (数百行になって常設が埋もれるため)。
        let unitURL = try XCTUnwrap(vm.unitTemplateURL)
        let unitJSON = try String(contentsOf: unitURL, encoding: .utf8)
        XCTAssertTrue(unitJSON.contains("\"常設ユニット\""))
        XCTAssertFalse(unitJSON.contains("\"臨時ユニット\""))
    }
}
