import Foundation
import os

/// `ShowReading` ポートの共有コア (imas-core インメモリスナップショット) アダプタ。
/// スナップショットがまだなら、ロードを待ってから答える (`CoreSnapshotManager.withStore`)。
struct CoreShowRepository: ShowReading {
    let snapshot: CoreSnapshotManager
    /// 参加マーク (`user_marks`) の引き先。ユーザーデータはスナップショットに載らない
    /// (書き込みが頻繁でプラットフォームが正) ので、DB から解決して渡す。
    let database: AppDatabase

    // MARK: - 公演

    func shows(eventId: String) async throws -> [Show] {
        try await snapshot.withStore { store in
            try store.showsByEvent(eventId: eventId).map(CoreRecordMapping.show(from:))
        }
    }

    func show(id: String) async throws -> Show? {
        try await snapshot.withStore { store in
            try store.showRecord(id: id).map(CoreRecordMapping.show(from:))
        }
    }

    func latestShow() async throws -> Show? {
        try await snapshot.withStore { store in
            try store.latestShow().map(CoreRecordMapping.show(from:))
        }
    }

    func shows(criterion: ShowFilterCriterion) async throws -> [Show] {
        try await snapshot.withStore { store in
            let records: [ShowRecord]
            switch criterion {
            case .venue(let venue):
                // core 側も「venue_id 一致 or 生の会場文字列一致」の OR を保っている
                // (会場 ID 未解決の古い公演を取りこぼさないため)。
                records = try store.showsAtVenue(venue: venue)
            case .date(let date):
                records = try store.showsOnDate(date: date)
            }
            return records.map(CoreRecordMapping.show(from:))
        }
    }

    func allShows(limit: Int) async throws -> [ShowWithEventName] {
        try await snapshot.withStore { store in
            try store.allShowsWithEventName(limit: UInt32(max(0, limit)))
                .map(CoreRecordMapping.showWithEventName(from:))
        }
    }

    func searchShows(query: String, limit: Int) async throws -> [ShowWithEventName] {
        try await snapshot.withStore { store in
            try store.searchShowsWithEventName(query: query, limit: UInt32(max(0, limit)))
                .map(CoreRecordMapping.showWithEventName(from:))
        }
    }

    // MARK: - セットリスト

    func setlist(showId: String) async throws -> [SetlistRow] {
        try await snapshot.withStore { store in
            try store.showSetlist(showId: showId).map(CoreRecordMapping.setlistRow(from:))
        }
    }

    func allPerformers(showId: String) async throws -> [String: [PerformerRow]] {
        try await snapshot.withStore { store in
            try store.showSetlistPerformers(showId: showId)
                .mapValues { $0.map(CoreRecordMapping.performerRow(from:)) }
        }
    }

    func setlistRowMeta(
        showId: String,
        nameMode: PerformerNameMode,
        displayMode: SetlistDisplayMode
    ) async throws -> SetlistRowMetaBundle {
        let attended = await attendedIds()
        return try await snapshot.withStore { store in
            try store.showSetlistRowMeta(
                showId: showId,
                mode: nameMode,
                displayMode: displayMode,
                attendedShowIds: attended.shows,
                attendedEventIds: attended.events
            )
        }
    }

    /// 券種はスナップショットに載らない (価格マスタは公演の表示に要らない) ので、DB から引く。
    func tickets(showId: String) async throws -> [ShowTicket] {
        try await database.showTicketsAsync(showId: showId).map(\.ticket)
    }

    /// 参加マーク (user_marks) はスナップショットに無いので、ここで解決して渡す。
    /// 何を回収と数えるかの規則は core (`CollectionAttendance` 参照)。
    ///
    /// 読めなかったときは「参加記録なし」と同じ見え方になる (回収の表示が丸ごと消える)。
    /// 黙って消えると原因が分からないので、必ず log を残す。
    private func attendedIds() async -> (shows: [String], events: [String]) {
        do {
            return (
                shows: try await CollectionAttendance.showIds(database: database),
                events: try await CollectionAttendance.eventIds(database: database)
            )
        } catch {
            Logger.database.error(
                "attendance_marks_failed setlistRowMeta: \(error.localizedDescription)"
            )
            return ([], [])
        }
    }

    func showIdolIds(showId: String) async throws -> Set<String> {
        try await snapshot.withStore { store in
            Set(try store.showCastIdolIds(showId: showId))
        }
    }

    func showCastIdols(showId: String) async throws -> [Idol] {
        try await snapshot.withStore { store in
            // core は sort_order 順の idol_id 列を返す (`showIdolIds` と同じ 1 本の API)。
            // 実体化はプラットフォーム側の規約なので、その並びを保って引き直す。
            try CoreRecordMapping.idols(store: store, orderedIds: store.showCastIdolIds(showId: showId))
        }
    }

    func eventCostumes(eventId: String) async throws -> EventCostumesRecord {
        try await snapshot.withStore { store in
            try store.eventCostumeRecords(eventId: eventId)
        }
    }

    func costumeEvents(costumeId: String) async throws -> [CostumeEventRecord] {
        try await snapshot.withStore { store in
            try store.costumeEventRecords(costumeId: costumeId)
        }
    }

    func originalArtistIds(songIds: [String]) async throws -> [String: Set<String>] {
        guard !songIds.isEmpty else { return [:] }
        return try await snapshot.withStore { store in
            try store.originalArtistIdsMap(songIds: songIds).mapValues { Set($0) }
        }
    }

    // MARK: - 会場

    func venueDirectory() async throws -> VenueDirectory {
        try await snapshot.withStore { store in
            let record = try store.venueDirectory()
            return CoreRecordMapping.venueDirectory(from: record)
        }
    }

    func eventIdsAtVenue(_ venueId: String) async throws -> Set<String> {
        try await snapshot.withStore { store in
            Set(try store.eventIdsAtVenue(venueId: venueId))
        }
    }

    func eventIds(forShows showIds: [String]) async throws -> Set<String> {
        guard !showIds.isEmpty else { return [] }
        return try await snapshot.withStore { store in
            Set(try store.eventIdsForShows(showIds: showIds))
        }
    }

    func venuesMatching(query: String, eventIds: [String]) async throws -> [String: String] {
        try await snapshot.withStore { store in
            try store.venuesMatching(query: query, eventIds: eventIds)
        }
    }
}
