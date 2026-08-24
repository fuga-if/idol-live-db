import XCTest
@testable import ImasLiveDB

/// `SnapshotInvalidating*Writing` (ローカル upsert 成功後に共有コアスナップショットの
/// 再ロードを促すデコレータ) の単体テスト。DB / FFI に依存しない。
///
/// 回帰の背景: モデレーター編集の .applied 経路 (SongEditView) は GRDB へ直接 upsert する
/// だけで `.masterDataDidSync` が飛ばず、自分の編集が次の totalFetched>0 な sync か
/// アプリ再起動まで曲一覧/曲詳細 (core 経路) に映らなかった。
/// 「書き込み成功後に必ず invalidate (合成ルートでは snapshot.requestLoad()) を呼ぶ」
/// 契約をここで固定する。
final class SnapshotInvalidatingWritingTests: XCTestCase {

    /// invalidate 呼び出し回数の記録。テストは直列に await するので plain class で足りる。
    private final class Counter: @unchecked Sendable {
        private(set) var count = 0
        func bump() { count += 1 }
    }

    private enum StubError: Error { case fail }

    // MARK: - 基底 Writing のスタブ (何も書かない。shouldThrow で失敗経路を再現)

    private struct StubSongWriting: SongWriting {
        var shouldThrow = false
        func upsertSongs(_ songs: [Song]) async throws { if shouldThrow { throw StubError.fail } }
        func upsertSongArtists(_ songArtists: [SongArtist]) async throws { if shouldThrow { throw StubError.fail } }
        func upsertSongCalls(_ calls: [SongCall]) async throws {}
        func upsertSongVideos(_ videos: [SongVideo]) async throws {}
    }

    private struct StubEventWriting: EventWriting {
        func upsertEvents(_ events: [Event]) async throws {}
    }

    private struct StubShowWriting: ShowWriting {
        func upsertShows(_ shows: [Show]) async throws {}
        func upsertSetlistItems(_ items: [SetlistItem]) async throws {}
        func replaceSetlist(showId: String, items: [SetlistItem], performers: [SetlistPerformer]) async throws {}
    }

    private struct StubIdolWriting: IdolWriting {
        func upsertIdols(_ idols: [Idol]) async throws {}
    }

    // MARK: - Song (回帰の本丸: SongEditView .applied 経路)

    func testSongAndArtistUpsertTriggerReload() async throws {
        let counter = Counter()
        let sut = SnapshotInvalidatingSongWriting(base: StubSongWriting(), invalidate: { counter.bump() })

        try await sut.upsertSongs([])
        XCTAssertEqual(counter.count, 1, "曲の upsert 成功後は再ロードを促すこと (編集直後に自分の編集が見える)")

        try await sut.upsertSongArtists([])
        XCTAssertEqual(counter.count, 2, "song_artists はスナップショットが読む表なので同様に促すこと")
    }

    func testSongCallsAndVideosDoNotTriggerReload() async throws {
        // song_calls / song_videos はスナップショット対象外 (imas-core sqlite_loader が読まない)。
        // 無関係な編集で DB 全読みを走らせないこと。
        let counter = Counter()
        let sut = SnapshotInvalidatingSongWriting(base: StubSongWriting(), invalidate: { counter.bump() })

        try await sut.upsertSongCalls([])
        try await sut.upsertSongVideos([])
        XCTAssertEqual(counter.count, 0)
    }

    func testFailedUpsertDoesNotTriggerReload() async {
        // 書き込みが失敗したら DB は変わっていないので全読みしない
        // (0 件同期で post しない CloudKitSyncEngine と同じ精神)。
        let counter = Counter()
        let sut = SnapshotInvalidatingSongWriting(
            base: StubSongWriting(shouldThrow: true), invalidate: { counter.bump() }
        )

        do {
            try await sut.upsertSongs([])
            XCTFail("スタブは throw するはず")
        } catch {}
        XCTAssertEqual(counter.count, 0)
    }

    // MARK: - Event / Show / Idol (スナップショットが読むその他のマスタ表)

    func testEventShowIdolWritesTriggerReload() async throws {
        let counter = Counter()

        let events = SnapshotInvalidatingEventWriting(base: StubEventWriting(), invalidate: { counter.bump() })
        try await events.upsertEvents([])
        XCTAssertEqual(counter.count, 1)

        let shows = SnapshotInvalidatingShowWriting(base: StubShowWriting(), invalidate: { counter.bump() })
        try await shows.upsertShows([])
        try await shows.upsertSetlistItems([])
        try await shows.replaceSetlist(showId: "show1", items: [], performers: [])
        XCTAssertEqual(counter.count, 4, "shows / setlist_items / setlist_performers は披露回数・回収数の元データ")

        let idols = SnapshotInvalidatingIdolWriting(base: StubIdolWriting(), invalidate: { counter.bump() })
        try await idols.upsertIdols([])
        XCTAssertEqual(counter.count, 5)
    }
}
