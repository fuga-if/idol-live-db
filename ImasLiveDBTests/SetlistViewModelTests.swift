import XCTest
@testable import ImasLiveDB

/// セトリ画面の読み込み (`SetlistViewModel`) の単体テスト。
///
/// 以前は 1 つの do の中で 9 回 await していて、途中の 1 つが失敗すると、それより後ろ
/// (衣装・券種・ブランド色・イベント名・いいね) が読まれないまま中途半端な画面が残った。
/// ここでは、読み込みの単位ごとに失敗が閉じていることを見る。
@MainActor
final class SetlistViewModelTests: XCTestCase {

    private enum FakeError: Error { case boom, notUsed }

    // MARK: - Fakes

    private struct FakeShowReading: ShowReading {
        var rows: [SetlistRow] = []
        var failSetlist = false
        var failPerformers = false
        var ticketsToReturn: [ShowTicket] = []
        var rowMetaAnswers = RowMetaAnswers()

        func setlist(showId: String) async throws -> [SetlistRow] {
            if failSetlist { throw FakeError.boom }
            return rows
        }
        func allPerformers(showId: String) async throws -> [String: [PerformerRow]] {
            if failPerformers { throw FakeError.boom }
            return [:]
        }
        func originalArtistIds(songIds: [String]) async throws -> [String: Set<String>] { [:] }
        func eventCostumes(eventId: String) async throws -> EventCostumesRecord {
            EventCostumesRecord(shared: [], individual: [])
        }
        func costumeEvents(costumeId: String) async throws -> [CostumeEventRecord] { [] }
        func tickets(showId: String) async throws -> [ShowTicket] { ticketsToReturn }
        func venueDirectory() async throws -> VenueDirectory { .empty }

        // この読み込みでは呼ばれない。
        func shows(eventId: String) async throws -> [Show] { [] }
        func show(id: String) async throws -> Show? { nil }
        func latestShow() async throws -> Show? { nil }
        func setlistRowMeta(
            showId: String, nameMode: PerformerNameMode, displayMode: SetlistDisplayMode
        ) async throws -> SetlistRowMetaBundle {
            guard let bundle = rowMetaAnswers.next() else { throw FakeError.boom }
            return bundle
        }
        func showIdolIds(showId: String) async throws -> Set<String> { [] }
        func shows(criterion: ShowFilterCriterion) async throws -> [Show] { [] }
        func allShows(limit: Int) async throws -> [ShowWithEventName] { [] }
        func searchShows(query: String, limit: Int) async throws -> [ShowWithEventName] { [] }
        func showCastIdols(showId: String) async throws -> [Idol] { [] }
        func eventIdsAtVenue(_ venueId: String) async throws -> Set<String> { [] }
        func eventIds(forShows showIds: [String]) async throws -> Set<String> { [] }
        func venuesMatching(query: String, eventIds: [String]) async throws -> [String: String] { [:] }
    }

    private struct FakeIdolReading: IdolReading {
        func idols(ids: [String]) async throws -> [Idol] { [] }
        func similarIdols(from candidates: [SimilarIdolCandidate]) async throws -> [Idol] { [] }

        func idols(brandId: String?) async throws -> [Idol] { [] }
        func idol(id: String) async throws -> Idol? { nil }
        func idols(criterion: IdolFilterCriterion) async throws -> [Idol] { [] }
        func idolCastNames() async throws -> [String: String] { [:] }
        func idolsByVoiceActor(name: String) async throws -> [Idol] { [] }
        func searchIdols(query: String, limit: Int) async throws -> [Idol] { [] }
        func idolSongs(idolId: String, role: String?) async throws -> [Song] { [] }
        func idolOriginalSongSections(idolId: String) async throws -> [IdolSongSection] { [] }
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

    private struct FakeEventReading: EventReading {
        var eventToReturn: Event?
        func event(id: String) async throws -> Event? { eventToReturn }

        func events(brandId: String?) async throws -> [Event] { [] }
        func eventsWithFirstDate(brandId: String?, includeEmpty: Bool, liveOnly: Bool, kinds: [EventKind]?) async throws -> [EventWithDate] { [] }
        func searchEventsByNameOrVenue(query: String, limit: Int) async throws -> [Event] { [] }
        func eventStats(eventId: String) async throws -> EventStats { throw FakeError.notUsed }
        func eventAttendance(eventId: String) async throws -> EventAttendance? { nil }
        func eventHero(eventId: String, attendedShowIds: [String], eventMarked: Bool, today: String) async throws -> EventHeroRecord? { nil }
        func eventsWithDate(criterion: EventFilterCriterion, includeEmpty: Bool) async throws -> [EventWithDate] { [] }
        func eventNames() async throws -> [String] { [] }
        func attendedEventsWithDate() async throws -> [EventWithDate] { [] }
        func attendedEventTypeSets() async throws -> (live: Set<String>, stream: Set<String>, liveViewing: Set<String>) {
            ([], [], [])
        }
        func eventsByIds(_ ids: [String]) async throws -> [EventWithDate] { [] }
        func eventReleases(eventId: String) async throws -> [EventRelease] { [] }
        func ticketSales(eventId: String) async throws -> [TicketSale] { [] }
        func ticketSaleSpotlight(eventId: String) async throws -> TicketSale? { nil }
    }

    // MARK: - Fixtures

    private let show = Show(
        id: "sh1", eventId: "ev1", name: "DAY1", date: "2026-09-19", venue: nil, venueId: nil,
        hall: nil, streamPlatform: nil, venueCity: nil, startTime: nil, sortOrder: 0,
        performerType: nil, hasStreaming: nil, hasLiveViewing: nil)

    private func row(_ id: String, song: String) -> SetlistRow {
        SetlistRow(
            id: id, position: 1, section: nil, notes: nil, unitName: nil, songId: song,
            songTitle: song, appleMusicId: nil, artworkUrl: nil, previewUrl: nil, songBrandId: "ml")
    }

    private let brand = Brand(id: "ml", name: "ミリオンライブ", shortName: "ミリオン",
                              color: "FFC30B", sortOrder: 0, iconUrl: nil)

    private func event() -> Event {
        Event(
            id: "ev1", brandId: "ml", name: "14thLIVE", eventType: "",
            isStreaming: false, isSolo: false, kind: "live",
            ticketOpenDate: nil, ticketDeadline: nil, ticketLotteryDate: nil,
            ticketUrl: nil, jointBrandIds: nil)
    }

    private let ticket = ShowTicket(
        id: "t1", showId: "sh1", kind: .live, name: "全席指定", price: 14_000,
        isEstimate: false, note: nil, sortOrder: 0)

    private func makeVM(
        shows: FakeShowReading,
        likes: @escaping @Sendable (String) async throws -> [SetlistLikeService.LikeEntry] = { _ in [] }
    ) -> SetlistViewModel {
        SetlistViewModel(
            showReading: shows,
            idolReading: FakeIdolReading(),
            brandReading: FakeBrandReading(brandsToReturn: [brand]),
            eventReading: FakeEventReading(eventToReturn: event()),
            fetchLikes: likes)
    }

    // MARK: - Tests

    /// 出演者が読めなくても、セトリ・券種・ブランド色・イベント名は出る。
    func testOneFailedUnitDoesNotHideTheOthers() async {
        var shows = FakeShowReading(rows: [row("i1", song: "s1")], ticketsToReturn: [ticket])
        shows.failPerformers = true
        let vm = makeVM(shows: shows)

        await vm.load(show: show)

        XCTAssertEqual(vm.setlist.map(\.id), ["i1"])
        XCTAssertEqual(vm.tickets.map(\.id), ["t1"])
        XCTAssertEqual(vm.brandNameById["ml"], "ミリオン")
        XCTAssertEqual(vm.showBrandHex, "FFC30B")
        XCTAssertEqual(vm.event?.name, "14thLIVE")
    }

    /// セトリが読めないときも、公演の添え物 (券種・イベント名) は出す。
    /// いいねはセトリが無いと付けようがないので聞きに行かない。
    func testSetlistFailureStillLoadsShowExtrasButSkipsLikes() async {
        var shows = FakeShowReading(ticketsToReturn: [ticket])
        shows.failSetlist = true
        let likesAsked = LockedFlag()
        let vm = makeVM(shows: shows, likes: { _ in
            likesAsked.set()
            return []
        })

        await vm.load(show: show)

        XCTAssertTrue(vm.setlist.isEmpty)
        XCTAssertEqual(vm.tickets.map(\.id), ["t1"])
        XCTAssertEqual(vm.event?.name, "14thLIVE")
        XCTAssertFalse(likesAsked.value)
    }

    /// いいねの結果は曲 id で引ける。押した後の反映も同じ場所に入る。
    func testLikesAreIndexedBySongAndUpdatable() async {
        let vm = makeVM(
            shows: FakeShowReading(rows: [row("i1", song: "s1")]),
            likes: { _ in [SetlistLikeService.LikeEntry(songId: "s1", likeCount: 2, hasUserLiked: false)] })

        await vm.load(show: show)
        XCTAssertEqual(vm.likesBySongId["s1"]?.likeCount, 2)

        vm.setLike(songId: "s1", likeCount: 3, hasUserLiked: true)
        XCTAssertEqual(vm.likesBySongId["s1"]?.likeCount, 3)
        XCTAssertEqual(vm.likesBySongId["s1"]?.hasUserLiked, true)
    }

    /// 同じ公演の読み直しが落ちても、区切りの見出しは前の答えのまま残る。
    /// 別の公演に移って落ちたときは、前の公演の答えを持ち越さない。
    func testRowMetaReloadFailureKeepsTheSectionHeadings() async {
        let shows = FakeShowReading(rows: [row("i1", song: "s1")])
        shows.rowMetaAnswers.queue([SetlistRowMetaBundle(rows: [meta("i1", heading: "アンコール")], collection: nil)])
        let vm = makeVM(shows: shows)

        await vm.loadRowMeta(showId: "sh1", nameMode: .idolOnly, displayMode: .normal)
        await vm.loadRowMeta(showId: "sh1", nameMode: .castOnly, displayMode: .normal)
        XCTAssertEqual(vm.rowMetaByItemId["i1"]?.sectionHeading, "アンコール")

        await vm.loadRowMeta(showId: "sh2", nameMode: .idolOnly, displayMode: .normal)
        XCTAssertTrue(vm.rowMetaByItemId.isEmpty)
    }

    private func meta(_ itemId: String, heading: String) -> SetlistRowMetaRecord {
        SetlistRowMetaRecord(
            itemId: itemId, performerLabel: nil, unitNames: [], isFullCast: false, ordinal: 1,
            ordinalLabel: "", isFirstPerformance: false, previousDate: nil, sinceLabel: nil,
            noteGroups: [], sectionHeading: heading, startsSection: true, lineup: nil,
            performerNotes: [])
    }
}

/// 行の添え物の答えを順に返す。尽きたら失敗扱い。
private final class RowMetaAnswers: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [SetlistRowMetaBundle] = []
    func queue(_ bundles: [SetlistRowMetaBundle]) { lock.withLock { answers = bundles } }
    func next() -> SetlistRowMetaBundle? {
        lock.withLock { answers.isEmpty ? nil : answers.removeFirst() }
    }
}

/// 別スレッドから立てる真偽値 (いいねを聞きに行ったかの記録)。
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}
