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
        var diagnostics = SyncDiagnostics(
            eventsAt: 0, showsAt: 0, setlistItemsAt: 0, ml13thLiveExists: false,
            ml13thShowsCount: 0, ml13thSetlistItemsCount: 0,
            sc8thName: nil, sc8thKind: nil, sc8thShowsCount: 0)
        var shouldThrow = false

        func metaValue(forKey key: String) async throws -> String? {
            if shouldThrow { throw TestError.boom }
            return meta[key]
        }
        func databaseStats() async throws -> DatabaseStats {
            if shouldThrow { throw TestError.boom }
            return stats
        }
        func syncDiagnostics() async throws -> SyncDiagnostics {
            if shouldThrow { throw TestError.boom }
            return diagnostics
        }
    }

    private struct FakeBrandReading: BrandReading {
        var brandsToReturn: [Brand] = []
        func brands() async throws -> [Brand] { brandsToReturn }
    }

    private struct FakeMarkReading: MarkReading {
        var markedIds: [String] = []
        /// 「どの entity/kind で問い合わせたか」を検証するための記録。
        final class Recorder: @unchecked Sendable {
            var entity: UserMarkEntity?
            var kind: UserMarkKind?
        }
        var recorder = Recorder()

        func markedEntityIds(entity: UserMarkEntity, kind: UserMarkKind) async throws -> [String] {
            recorder.entity = entity
            recorder.kind = kind
            return markedIds
        }
        func autoCollectedSongIds() async throws -> Set<String> { [] }
    }

    private struct FakeIdolReading: IdolReading {
        var byIds: [Idol] = []
        var allIdols: [Idol] = []

        func idols(ids: [String]) async throws -> [Idol] { byIds }
        func idols(brandId: String?) async throws -> [Idol] { allIdols }

        func idol(id: String) async throws -> Idol? { nil }
        func idols(criterion: IdolFilterCriterion) async throws -> [Idol] { [] }
        func idolsByVoiceActor(name: String) async throws -> [Idol] { [] }
        func searchIdols(query: String, limit: Int) async throws -> [Idol] { [] }
        func idolCastNames() async throws -> [String: String] { [:] }
        func idolSongs(idolId: String, role: String?) async throws -> [Song] { [] }
        func idolPerformedSongs(idolId: String) async throws -> [IdolPerformedSong] { [] }
        func idolUnits(idolId: String) async throws -> [ImasLiveDB.Unit] { [] }
        func idolShows(idolId: String) async throws -> [CastShowRow] { [] }
        func allIdolsForPicker() async throws -> [Idol] { [] }
        func idolSongHistory(idolId: String, songId: String) async throws -> [CastShowRow] { [] }
    }

    private struct FakeUnitReading: UnitReading {
        var units: [ImasLiveDB.Unit] = []

        func unitIndex() async throws -> UnitIndex {
            UnitIndex(units: units, memberIds: [:], byIdol: [:], unitsWithSongs: [])
        }
        func unit(id: String) async throws -> ImasLiveDB.Unit? { nil }
        func unitMembers(unitId: String) async throws -> [Idol] { [] }
        func unitSongs(unitId: String) async throws -> [Song] { [] }
        func unitIdsWithSongs(unitIds: [String]) async throws -> Set<String> { [] }
        func performedUnitIds(eventId: String) async throws -> Set<String> { [] }
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
        XCTAssertNotNil(vm.syncDiagnostics)
    }

    /// meta が無いときは "不明" を出す (空文字や "nil" を画面に出さない)。
    func testLoadShowsUnknownWhenMetaMissing() async {
        let vm = makeVM(diagnostics: FakeDiagnosticsReading(meta: [:]))
        await vm.load()
        XCTAssertEqual(vm.schemaVersion, "不明")
        XCTAssertEqual(vm.dataVersion, "不明")
    }

    /// 担当は「idol / myPick」で引く。ここを取り違えるとテーマ色の候補が変わる。
    func testLoadQueriesMyPickIdols() async {
        let marks = FakeMarkReading(markedIds: ["i1", "i2"])
        let idols = FakeIdolReading(byIds: [makeIdol("i1"), makeIdol("i2")])
        let vm = makeVM(idols: idols, marks: marks)

        await vm.load()

        XCTAssertEqual(marks.recorder.entity, .idol)
        XCTAssertEqual(marks.recorder.kind, .myPick)
        XCTAssertEqual(vm.pickIdols.map(\.id), ["i1", "i2"])
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

    // MARK: - refreshSyncDiagnostics

    func testRefreshSyncDiagnosticsUpdatesOnly() async {
        let diag = FakeDiagnosticsReading(
            diagnostics: SyncDiagnostics(
                eventsAt: 7, showsAt: 0, setlistItemsAt: 0, ml13thLiveExists: false,
                ml13thShowsCount: 0, ml13thSetlistItemsCount: 0,
                sc8thName: nil, sc8thKind: nil, sc8thShowsCount: 0))
        let vm = makeVM(diagnostics: diag)

        await vm.refreshSyncDiagnostics()

        XCTAssertEqual(vm.syncDiagnostics?.eventsAt, 7)
        // load() を呼んでいないので他の値は初期値のまま
        XCTAssertEqual(vm.schemaVersion, "...")
    }

    /// 取得に失敗しても既存の診断値を壊さない (probe 直後に呼ばれるため)。
    func testRefreshSyncDiagnosticsSwallowsError() async {
        var diag = FakeDiagnosticsReading()
        diag.shouldThrow = true
        let vm = makeVM(diagnostics: diag)

        await vm.refreshSyncDiagnostics()

        XCTAssertNil(vm.syncDiagnostics)
    }
}
