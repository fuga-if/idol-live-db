import Foundation
import GRDB

/// `EventReading` ポートの共有コア (imas-core インメモリスナップショット) アダプタ。
///
/// 呼び出し単位でスナップショットの有無を見て切り替える (スライス並走の原則):
/// - ロード済み → UniFFI 越しに `SnapshotStore` のクエリを呼ぶ
/// - 未ロード / ロード失敗 / メモリ警告で破棄後 → 従来の `GRDBEventRepository` に委ねる
///
/// FFI 形状の規約:
/// - user_marks (参加マーク) はスナップショットに**含まれない**。参加系のクエリには、
///   ここで GRDB から解決した参加 event/show id (と種別) を引数で渡す。
struct CoreEventRepository: EventReading {
    let snapshot: CoreSnapshotManager
    /// 未ロード時と未移送クエリの受け皿 (Strangler の旧経路)。
    let fallback: GRDBEventRepository

    private var database: AppDatabase { fallback.database }

    // MARK: - 一覧

    func events(brandId: String?) async throws -> [Event] {
        try await snapshot.withStore(fallbackTo: { try await fallback.events(brandId: brandId) }) { store in
            try store.eventRecords(brandId: brandId).map(CoreRecordMapping.event(from:))
        }
    }

    func event(id: String) async throws -> Event? {
        try await snapshot.withStore(fallbackTo: { try await fallback.event(id: id) }) { store in
            try store.eventRecord(id: id).map(CoreRecordMapping.event(from:))
        }
    }

    func eventsWithFirstDate(brandId: String?, includeEmpty: Bool, liveOnly: Bool, kinds: [EventKind]?) async throws -> [EventWithDate] {
        try await snapshot.withStore(fallbackTo: {
            try await fallback.eventsWithFirstDate(brandId: brandId, includeEmpty: includeEmpty, liveOnly: liveOnly, kinds: kinds)
        }) { store in
            try store.eventsWithFirstDate(
                brandId: brandId,
                includeEmpty: includeEmpty,
                liveOnly: liveOnly,
                // core は文字列で受ける (kind 列の生値)。nil = 指定なしはそのまま nil で渡す。
                kinds: kinds?.map(\.rawValue)
            ).map(CoreRecordMapping.eventWithDate(from:))
        }
    }

    func eventsWithDate(criterion: EventFilterCriterion, includeEmpty: Bool) async throws -> [EventWithDate] {
        switch criterion {
        case .brand(let id, _):
            // SQL 時代と同じく通常の一覧クエリに合流させる (kind 既定 = live + festival)。
            return try await eventsWithFirstDate(brandId: id, includeEmpty: includeEmpty, liveOnly: false, kinds: nil)
        case .year(let year):
            return try await snapshot.withStore(fallbackTo: {
                try await fallback.eventsWithDate(criterion: criterion, includeEmpty: includeEmpty)
            }) { store in
                try store.eventsWithDateByYear(year: Int32(year), includeEmpty: includeEmpty)
                    .map(CoreRecordMapping.eventWithDate(from:))
            }
        }
    }

    func eventNames() async throws -> [String] {
        try await snapshot.withStore(fallbackTo: { try await fallback.eventNames() }) { store in
            try store.eventNames()
        }
    }

    func eventsByIds(_ ids: [String]) async throws -> [EventWithDate] {
        guard !ids.isEmpty else { return [] }
        return try await snapshot.withStore(fallbackTo: { try await fallback.eventsByIds(ids) }) { store in
            try store.eventsWithDateByIds(ids: ids).map(CoreRecordMapping.eventWithDate(from:))
        }
    }

    /// ライブ名と会場名の両方に当てる検索 (検索スコープ「ライブ」)。
    ///
    /// `globalSearch` (イベント名のみ・各 20 件) とは別物なので、コアにも別の
    /// クエリとして持たせている。結果が id 昇順なのは元 SQL が DISTINCT のために
    /// PK 索引で走査していたからで、`limit` はその並びの先頭を取る。
    func searchEventsByNameOrVenue(query: String, limit: Int) async throws -> [Event] {
        try await snapshot.withStore(fallbackTo: { try await fallback.searchEventsByNameOrVenue(query: query, limit: limit) }) { store in
            try store.searchEventsByNameOrVenue(query: query, limit: UInt32(max(0, limit)))
                .map(CoreRecordMapping.event(from:))
        }
    }

    // MARK: - イベント詳細

    func eventStats(eventId: String) async throws -> EventStats {
        try await snapshot.withStore(fallbackTo: { try await fallback.eventStats(eventId: eventId) }) { store in
            let record = try store.eventStats(eventId: eventId)
            return CoreRecordMapping.eventStats(from: record)
        }
    }

    func eventAttendance(eventId: String) async throws -> EventAttendance? {
        try await snapshot.withStore(fallbackTo: { try await fallback.eventAttendance(eventId: eventId) }) { store in
            guard let record = try store.eventAttendance(eventId: eventId) else { return nil }
            // 母集団は sort_order 順の idol_id 列で返る。EventAttendance の grouped() は
            // brandIdols の並びを表示順としてそのまま使うので、順序を保って実体化する。
            let brandIdols = try CoreRecordMapping.idols(store: store, orderedIds: record.brandIdolIds)
            return EventAttendance(
                brandIdols: brandIdols,
                shows: record.shows.map(CoreRecordMapping.show(from:)),
                presenceByShow: record.presenceByShow.mapValues { Set($0) },
                leadByShow: record.leadByShow.mapValues { Set($0) },
                guestByShow: record.guestByShow.mapValues { Set($0) }
            )
        }
    }

    func eventReleases(eventId: String) async throws -> [EventRelease] {
        try await snapshot.withStore(fallbackTo: { try await fallback.eventReleases(eventId: eventId) }) { store in
            try store.eventReleases(eventId: eventId).map(CoreRecordMapping.eventRelease(from:))
        }
    }

    // MARK: - 参加マーク由来 (user_marks はスナップショットに無い)

    func attendedEventsWithDate() async throws -> [EventWithDate] {
        try await snapshot.withStore(fallbackTo: { try await fallback.attendedEventsWithDate() }) { store in
            let eventIds = try await database.fetchMarkedEntityIdsAsync(entity: .event, kind: .attended)
            let showIds = try await database.fetchMarkedEntityIdsAsync(entity: .show, kind: .attended)
            return try store.attendedEventsWithDate(attendedEventIds: eventIds, attendedShowIds: showIds)
                .map(CoreRecordMapping.eventWithDate(from:))
        }
    }

    func attendedEventTypeSets() async throws -> (live: Set<String>, stream: Set<String>, liveViewing: Set<String>) {
        try await snapshot.withStore(fallbackTo: { try await fallback.attendedEventTypeSets() }) { store in
            // 種別 (text_value) つきで渡す必要があるので id だけの取得 API では足りない。
            // 「種別なし = 現地扱い」の解釈は core 側が持つ (SQL 時代の default 分岐と同じ)。
            let eventMarks = try await attendanceMarks(entity: .event)
            let showMarks = try await attendanceMarks(entity: .show)
            let record = try store.attendedEventTypeSets(eventMarks: eventMarks, showMarks: showMarks)
            return (Set(record.live), Set(record.stream), Set(record.liveViewing))
        }
    }

    /// attended マークを (entity_id, text_value) の射影で取り出す。
    /// `fetchMarkedEntityIdsAsync` は id しか返さないため、種別が要る経路だけここで直接引く。
    private func attendanceMarks(entity: UserMarkEntity) async throws -> [AttendanceMarkRecord] {
        let marks = try await database.dbQueue.read { db in
            try UserMark.filter(
                UserMark.Columns.entityType == entity.rawValue &&
                UserMark.Columns.kind == UserMarkKind.attended.rawValue &&
                UserMark.Columns.boolValue == true
            ).fetchAll(db)
        }
        return marks.map { AttendanceMarkRecord(entityId: $0.entityId, attendanceType: $0.textValue) }
    }
}
