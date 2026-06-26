import XCTest
@testable import ImasLiveDB

/// `IdolDetailViewModel` のオーケストレーションの単体テスト。
/// 特に VM 固有の「所属ユニットを曲あり/曲なしに分割する」ロジックと、
/// ブランド引き当てを fake ポート越しに検証する。
@MainActor
final class IdolDetailViewModelTests: XCTestCase {

    private enum FakeError: Error { case notUsed }

    // MARK: - Fakes

    private struct FakeIdolReading: IdolReading {
        var unitsToReturn: [ImasLiveDB.Unit] = []

        func idolUnits(idolId: String) async throws -> [ImasLiveDB.Unit] { unitsToReturn }
        // 詳細ロードで呼ばれるが本テストでは空で十分。
        func idolSongs(idolId: String, role: String?) async throws -> [Song] { [] }
        func idolPerformedSongs(idolId: String) async throws -> [IdolPerformedSong] { [] }
        func idolShows(idolId: String) async throws -> [CastShowRow] { [] }

        // 未使用。
        func idols(brandId: String?) async throws -> [Idol] { [] }
        func idol(id: String) async throws -> Idol? { nil }
        func idols(ids: [String]) async throws -> [Idol] { [] }
        func idols(criterion: IdolFilterCriterion) async throws -> [Idol] { [] }
        func idolCastNames() async throws -> [String: String] { [:] }
        func idolsByVoiceActor(name: String) async throws -> [Idol] { [] }
        func searchIdols(query: String, limit: Int) async throws -> [Idol] { [] }
        func allIdolsForPicker() async throws -> [Idol] { [] }
        func idolSongHistory(idolId: String, songId: String) async throws -> [CastShowRow] { [] }
    }

    private struct FakeBrandReading: BrandReading {
        var brandsToReturn: [Brand] = []
        func brands() async throws -> [Brand] { brandsToReturn }
    }

    private struct FakeUnitReading: UnitReading {
        var unitIdsWithSongsToReturn: Set<String> = []

        func unitIdsWithSongs(unitIds: [String]) async throws -> Set<String> { unitIdsWithSongsToReturn }

        // 未使用。
        func unitIndex() async throws -> UnitIndex { throw FakeError.notUsed }
        func unit(id: String) async throws -> ImasLiveDB.Unit? { nil }
        func unitMembers(unitId: String) async throws -> [Idol] { [] }
        func unitSongs(unitId: String) async throws -> [Song] { [] }
        func performedUnitIds(eventId: String) async throws -> Set<String> { [] }
        func allUnits() async throws -> [ImasLiveDB.Unit] { [] }
    }

    // MARK: - Fixtures

    private func makeUnit(_ id: String, brandId: String = "cg") -> ImasLiveDB.Unit {
        ImasLiveDB.Unit(id: id, brandId: brandId, name: id, isPermanent: true, nameAlt: nil)
    }

    private func makeBrand(_ id: String) -> Brand {
        Brand(id: id, name: id, shortName: id, color: nil, sortOrder: 0, iconUrl: nil)
    }

    private func makeIdol(_ id: String, brandId: String) -> Idol {
        Idol(
            id: id, brandId: brandId, name: id, nameKana: nil,
            nameRomaji: nil, familyName: nil, givenName: nil, nickname: nil, color: nil,
            sortOrder: 0, birthday: nil, bloodType: nil, height: nil, weight: nil,
            birthPlace: nil, age: nil, bust: nil, waist: nil, hip: nil, constellation: nil,
            hobbies: nil, talents: nil, description: nil, gender: nil, handedness: nil,
            debutDate: nil, attribute: nil, aliases: nil, voiceActors: nil)
    }

    // MARK: - Tests

    func testLoadSplitsUnitsBySongPresencePreservingOrder() async {
        let units = [makeUnit("u1"), makeUnit("u2"), makeUnit("u3")]
        let vm = IdolDetailViewModel(
            idolReading: FakeIdolReading(unitsToReturn: units),
            brandReading: FakeBrandReading(brandsToReturn: [makeBrand("cg")]),
            unitReading: FakeUnitReading(unitIdsWithSongsToReturn: ["u1", "u3"]))

        await vm.loadDetails(idol: makeIdol("i", brandId: "cg"))

        // u1/u3 は曲あり、u2 は曲なし。元の name 順を保つ。
        XCTAssertEqual(vm.units.map(\.id), ["u1", "u2", "u3"])
        XCTAssertEqual(vm.unitsWithSongs.map(\.id), ["u1", "u3"])
        XCTAssertEqual(vm.unitsWithoutSongs.map(\.id), ["u2"])
    }

    func testLoadResolvesBrandByIdolBrandId() async {
        let vm = IdolDetailViewModel(
            idolReading: FakeIdolReading(),
            brandReading: FakeBrandReading(brandsToReturn: [makeBrand("cg"), makeBrand("ml")]),
            unitReading: FakeUnitReading())

        await vm.loadDetails(idol: makeIdol("i", brandId: "ml"))

        XCTAssertEqual(vm.brand?.id, "ml")
    }
}
