import Foundation
import GRDB

/// `CalendarReading` ポートの共有コア (imas-core インメモリスナップショット) アダプタ。
///
/// 呼び出し単位でスナップショットの有無を見て切り替える (スライス並走の原則)。
///
/// core が担うのは「表示範囲の絞り込み + 誕生日/記念日の年展開 + 並び替え」まで。
/// 返るのは公演やチケットの素の値と、曲/アイドル/スタッフ/記念日の **id** だけなので、
/// 実体化はここで行う (プラットフォーム側の規約)。
/// - 曲とアイドルはスナップショットから引く。
/// - スタッフと記念日はスナップショットが持たない (core にレコード取得 API が無い) ため
///   GRDB から引く。どちらも数十件の小さなマスタなので全件読みで足りる。
struct CoreCalendarRepository: CalendarReading {
    let snapshot: CoreSnapshotManager
    /// 未ロード時の受け皿 (Strangler の旧経路)。
    let fallback: GRDBCalendarRepository

    private var database: AppDatabase { fallback.database }

    func calendarEntries(in interval: DateInterval) async throws -> [CalendarEntry] {
        try await snapshot.withStore(fallbackTo: { try await fallback.calendarEntries(in: interval) }) { store in
            let records = try store.calendarEntries(
                startDay: Self.dayFormatter.string(from: interval.start),
                endDay: Self.dayFormatter.string(from: interval.end)
            )
            guard !records.isEmpty else { return [] }

            let songs = try songsById(store: store, records: records)
            let idols = try idolsById(store: store, records: records)
            let staff = try await staffById(records: records)
            let anniversaries = try await anniversariesById(records: records)

            // core が返す並び (ソート日付, カテゴリ順位) が表示順なので、そのまま保って実体化する。
            // 実体が引けなかった行は落とす (id だけ残ったマスタ不整合の行を出さない)。
            return records.compactMap { record in
                entry(from: record, songs: songs, idols: idols, staff: staff, anniversaries: anniversaries)
            }
        }
    }

    // MARK: - 1 レコードの実体化

    private func entry(
        from record: CalendarEntryRecord,
        songs: [String: Song],
        idols: [String: Idol],
        staff: [String: Staff],
        anniversaries: [String: Anniversary]
    ) -> CalendarEntry? {
        switch record {
        case let .show(showId, eventId, name, date, venue, venueCity, startTime, sortOrder, performerType,
                       eventName, brandId, brandColor, eventKind):
            return .show(CalendarShowRow(
                // SQL 時代と同じく、カレンダー行の Show は表示に要る列だけを持つ
                // (venue_id / hall / 配信フラグは引いていない)。
                show: Show(
                    id: showId,
                    eventId: eventId,
                    name: name,
                    date: date,
                    venue: venue,
                    venueCity: venueCity,
                    startTime: startTime,
                    sortOrder: Int(sortOrder),
                    performerType: performerType
                ),
                eventName: eventName,
                brandId: brandId,
                brandColor: brandColor,
                eventKind: eventKind
            ))

        case let .release(date, songIds):
            let resolved = songIds.compactMap { songs[$0] }
            // 曲が 1 曲も引けない日は行ごと出さない (空のリリース行は意味がない)。
            return resolved.isEmpty ? nil : .release(date: date, songs: resolved)

        case let .birthday(idolId, _):
            // occursOn (展開後の実出現日) は CalendarEntry.birthday が年を持たないため使わない。
            // 並びは core が解決済みで、ここでは順序を保つだけで足りる。
            return idols[idolId].map { .birthday($0) }

        case let .staffBirthday(staffId, _):
            return staff[staffId].map { .staffBirthday($0) }

        case let .anniversary(anniversaryId, _):
            return anniversaries[anniversaryId].map { .anniversary($0) }

        case let .ticket(eventId, eventName, brandColor, date, kind, url):
            return .ticket(TicketCalendarRow(
                eventId: eventId,
                eventName: eventName,
                brandColor: brandColor,
                date: date,
                kind: Self.ticketKind(from: kind),
                url: url
            ))

        case let .ticketPeriod(eventId, eventName, brandColor, start, end, url):
            return .ticketPeriod(TicketPeriodRow(
                eventId: eventId,
                eventName: eventName,
                brandColor: brandColor,
                start: start,
                end: end,
                url: url
            ))
        }
    }

    private static func ticketKind(from kind: CalendarTicketKind) -> TicketDateKind {
        switch kind {
        case .deadline: return .deadline
        case .lottery: return .lottery
        }
    }

    // MARK: - id → 実体の一括解決

    private func songsById(store: SnapshotStore, records: [CalendarEntryRecord]) throws -> [String: Song] {
        var ids: [String] = []
        for record in records {
            if case let .release(_, songIds) = record { ids.append(contentsOf: songIds) }
        }
        guard !ids.isEmpty else { return [:] }
        let songs = try CoreRecordMapping.songs(store: store, orderedIds: ids)
        return Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func idolsById(store: SnapshotStore, records: [CalendarEntryRecord]) throws -> [String: Idol] {
        var ids: [String] = []
        for record in records {
            if case let .birthday(idolId, _) = record { ids.append(idolId) }
        }
        guard !ids.isEmpty else { return [:] }
        let idols = try CoreRecordMapping.idols(store: store, orderedIds: ids)
        return Dictionary(idols.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// スタッフはスナップショット対象外なので GRDB から引く。数十件なので全件読みで足りる。
    /// 表示範囲にスタッフ誕生日が 1 件も無い月が大半なので、その場合は DB を触らない。
    private func staffById(records: [CalendarEntryRecord]) async throws -> [String: Staff] {
        guard records.contains(where: { if case .staffBirthday = $0 { return true } else { return false } }) else { return [:] }
        let rows = try await database.dbQueue.read { db in try Staff.fetchAll(db) }
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// 記念日も同様にスナップショット対象外。該当が無ければ DB を触らない。
    private func anniversariesById(records: [CalendarEntryRecord]) async throws -> [String: Anniversary] {
        guard records.contains(where: { if case .anniversary = $0 { return true } else { return false } }) else { return [:] }
        let rows = try await database.dbQueue.read { db in try Anniversary.fetchAll(db) }
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// core に渡す表示範囲の日付文字列。JST 固定なのは海外渡航中に日付がずれないため
    /// (`AppDatabase` の同名フォーマッタと同じ規則。原本が private なのでここに複製している。
    /// 変更時は両方を揃えること)。
    private static let dayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return fmt
    }()
}
