import Foundation

/// `ShowReading` ポートの共有コア (imas-core インメモリスナップショット) アダプタ。
///
/// 呼び出し単位でスナップショットの有無を見て切り替える (スライス並走の原則):
/// - ロード済み → UniFFI 越しに `SnapshotStore` のクエリを呼ぶ
/// - 未ロード / ロード失敗 / メモリ警告で破棄後 → 従来の `GRDBShowRepository` に委ねる
///
/// ポートの全メソッドに対応する core API があるため、未ロード時以外は全て core 経路。
struct CoreShowRepository: ShowReading {
    let snapshot: CoreSnapshotManager
    /// 未ロード時の受け皿 (Strangler の旧経路)。
    let fallback: GRDBShowRepository

    // MARK: - 公演

    func shows(eventId: String) async throws -> [Show] {
        try await snapshot.withStore(fallbackTo: { try await fallback.shows(eventId: eventId) }) { store in
            try store.showsByEvent(eventId: eventId).map(CoreRecordMapping.show(from:))
        }
    }

    func show(id: String) async throws -> Show? {
        try await snapshot.withStore(fallbackTo: { try await fallback.show(id: id) }) { store in
            try store.showRecord(id: id).map(CoreRecordMapping.show(from:))
        }
    }

    func latestShow() async throws -> Show? {
        try await snapshot.withStore(fallbackTo: { try await fallback.latestShow() }) { store in
            try store.latestShow().map(CoreRecordMapping.show(from:))
        }
    }

    func shows(criterion: ShowFilterCriterion) async throws -> [Show] {
        try await snapshot.withStore(fallbackTo: { try await fallback.shows(criterion: criterion) }) { store in
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
        try await snapshot.withStore(fallbackTo: { try await fallback.allShows(limit: limit) }) { store in
            try store.allShowsWithEventName(limit: UInt32(max(0, limit)))
                .map(CoreRecordMapping.showWithEventName(from:))
        }
    }

    func searchShows(query: String, limit: Int) async throws -> [ShowWithEventName] {
        try await snapshot.withStore(fallbackTo: { try await fallback.searchShows(query: query, limit: limit) }) { store in
            try store.searchShowsWithEventName(query: query, limit: UInt32(max(0, limit)))
                .map(CoreRecordMapping.showWithEventName(from:))
        }
    }

    // MARK: - セットリスト

    func setlist(showId: String) async throws -> [SetlistRow] {
        try await snapshot.withStore(fallbackTo: { try await fallback.setlist(showId: showId) }) { store in
            try store.showSetlist(showId: showId).map(CoreRecordMapping.setlistRow(from:))
        }
    }

    func allPerformers(showId: String) async throws -> [String: [PerformerRow]] {
        try await snapshot.withStore(fallbackTo: { try await fallback.allPerformers(showId: showId) }) { store in
            try store.showSetlistPerformers(showId: showId)
                .mapValues { $0.map(CoreRecordMapping.performerRow(from:)) }
        }
    }

    func showIdolIds(showId: String) async throws -> Set<String> {
        try await snapshot.withStore(fallbackTo: { try await fallback.showIdolIds(showId: showId) }) { store in
            Set(try store.showCastIdolIds(showId: showId))
        }
    }

    func showCastIdols(showId: String) async throws -> [Idol] {
        try await snapshot.withStore(fallbackTo: { try await fallback.showCastIdols(showId: showId) }) { store in
            // core は sort_order 順の idol_id 列を返す (`showIdolIds` と同じ 1 本の API)。
            // 実体化はプラットフォーム側の規約なので、その並びを保って引き直す。
            try CoreRecordMapping.idols(store: store, orderedIds: store.showCastIdolIds(showId: showId))
        }
    }

    func originalArtistIds(songIds: [String]) async throws -> [String: Set<String>] {
        guard !songIds.isEmpty else { return [:] }
        return try await snapshot.withStore(fallbackTo: { try await fallback.originalArtistIds(songIds: songIds) }) { store in
            try store.originalArtistIdsMap(songIds: songIds).mapValues { Set($0) }
        }
    }

    // MARK: - 会場

    func venueDirectory() async throws -> VenueDirectory {
        try await snapshot.withStore(fallbackTo: { try await fallback.venueDirectory() }) { store in
            let record = try store.venueDirectory()
            return CoreRecordMapping.venueDirectory(from: record)
        }
    }

    func eventIdsAtVenue(_ venueId: String) async throws -> Set<String> {
        try await snapshot.withStore(fallbackTo: { try await fallback.eventIdsAtVenue(venueId) }) { store in
            Set(try store.eventIdsAtVenue(venueId: venueId))
        }
    }

    func venuesMatching(query: String, eventIds: [String]) async throws -> [String: String] {
        try await snapshot.withStore(fallbackTo: { try await fallback.venuesMatching(query: query, eventIds: eventIds) }) { store in
            try store.venuesMatching(query: query, eventIds: eventIds)
        }
    }
}
