//  AppDatabase の Calendar Queries を切り出したもの。
//  分割の意図と分割線の引き方は docs/ARCHITECTURE.md を参照。
//  ここにあるのは移動してきたクエリだけで、ロジックは 1 行も変えていない。

import Foundation
import GRDB

extension AppDatabase {

    // MARK: - Calendar Queries

    /// (async) 指定期間のカレンダーエントリを取得。cooperative thread pool をブロックしない。
    func fetchCalendarEntriesAsync(in interval: DateInterval) async throws -> [CalendarEntry] {
        let startStr = Self.calendarDateFormatter.string(from: interval.start)
        let endStr = Self.calendarDateFormatter.string(from: interval.end)

        let shows = try await dbQueue.read { db in try Self.calendarShowsQuery(db, startStr: startStr, endStr: endStr) }
        let releases = try await dbQueue.read { db in try Self.calendarReleasesQuery(db, startStr: startStr, endStr: endStr) }
        let birthdayPairs = try await dbQueue.read { db in try Self.calendarBirthdayPairsQuery(db, interval: interval) }
        let staffBirthdayPairs = try await dbQueue.read { db in try Self.calendarStaffBirthdayPairsQuery(db, interval: interval) }
        let anniversaries = try await dbQueue.read { db in try Self.calendarAnniversariesQuery(db, interval: interval) }
        let tickets = try await dbQueue.read { db in try Self.calendarTicketsQuery(db, startStr: startStr, endStr: endStr) }

        return Self.assembleCalendarEntries(
            shows: shows, releases: releases,
            birthdayPairs: birthdayPairs, staffBirthdayPairs: staffBirthdayPairs,
            anniversaries: anniversaries, tickets: tickets
        )
    }

    private static func calendarShowsQuery(_ db: Database, startStr: String, endStr: String) throws -> [CalendarEntry] {
        let sql = """
            SELECT s.id, s.event_id, s.name, s.date, s.venue, s.venue_city,
                   s.start_time, s.sort_order, s.performer_type,
                   e.name AS event_name, e.brand_id, e.kind AS event_kind,
                   b.color AS brand_color
            FROM shows s
            JOIN events e ON s.event_id = e.id
            LEFT JOIN brands b ON e.brand_id = b.id
            WHERE s.date >= ? AND s.date <= ?
            ORDER BY s.date, s.sort_order
            """
        return try Row.fetchAll(db, sql: sql, arguments: [startStr, endStr]).map { row in
            CalendarEntry.show(CalendarShowRow(
                show: Show(
                    id: row["id"],
                    eventId: row["event_id"],
                    name: row["name"],
                    date: row["date"],
                    venue: row["venue"],
                    venueCity: row["venue_city"],
                    startTime: row["start_time"],
                    sortOrder: row["sort_order"],
                    performerType: row["performer_type"]
                ),
                eventName: row["event_name"],
                brandId: row["brand_id"],
                brandColor: row["brand_color"],
                eventKind: row["event_kind"]
            ))
        }
    }

    private static func calendarReleasesQuery(_ db: Database, startStr: String, endStr: String) throws -> [CalendarEntry] {
        let songs = try Song
            .filter(Column("release_date") >= startStr && Column("release_date") <= endStr)
            .filter(Column("parent_song_id") == nil)
            .order(Column("release_date"), Column("title_kana"))
            .fetchAll(db)
        var byDate: [String: [Song]] = [:]
        for song in songs {
            guard let date = song.releaseDate else { continue }
            byDate[date, default: []].append(song)
        }
        return byDate.map { date, songs in CalendarEntry.release(date: date, songs: songs) }
    }

    private static func calendarBirthdayPairsQuery(_ db: Database, interval: DateInterval) throws -> [(CalendarEntry, Date)] {
        let allIdols = try Idol.filter(Column("birthday") != nil).fetchAll(db)
        return allIdols.compactMap { idol -> (CalendarEntry, Date)? in
            guard let birthdayDate = Self.expandMonthDay(idol.birthday, in: interval) else { return nil }
            return (.birthday(idol), birthdayDate)
        }
    }

    private static func calendarStaffBirthdayPairsQuery(_ db: Database, interval: DateInterval) throws -> [(CalendarEntry, Date)] {
        let staffList = try Staff.filter(Column("birthday") != nil).fetchAll(db)
        return staffList.compactMap { staff -> (CalendarEntry, Date)? in
            guard let birthdayDate = Self.expandMonthDay(staff.birthday, in: interval) else { return nil }
            return (.staffBirthday(staff), birthdayDate)
        }
    }

    /// 記念日: 起点日 YYYY-MM-DD の MM-DD を interval 内の年に展開して当て、起点年以降だけ採用
    /// (起点より前の年は周年として意味を成さない)。
    private static func calendarAnniversariesQuery(_ db: Database, interval: DateInterval) throws -> [CalendarEntry] {
        let all = try Anniversary.fetchAll(db)
        var jst = Calendar(identifier: .gregorian)
        jst.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return all.compactMap { ann -> CalendarEntry? in
            guard let startDate = Self.parseDate(ann.date) else { return nil }
            let parts = ann.date.split(separator: "-")
            guard parts.count == 3,
                  let month = Int(parts[1]),
                  let day = Int(parts[2]) else { return nil }
            let intervalYear = jst.component(.year, from: interval.start)
            // 同 interval が年をまたぐ可能性は低いが念のため候補2年で試す。
            for y in [intervalYear, intervalYear + 1] {
                guard let recurring = jst.date(from: DateComponents(year: y, month: month, day: day)) else { continue }
                // 起点年より前 (= 0周年未満) は表示しない。起点年当日 (0周年=その日) も出す。
                guard recurring >= startDate else { continue }
                if recurring >= interval.start && recurring <= interval.end {
                    return .anniversary(ann)
                }
            }
            return nil
        }
    }

    /// チケット日程。受付開始 + 締切が揃えば「受付期間」を日跨ぎ帯 (.ticketPeriod) に、
    /// 開始が無ければ締切を単日点に。当落発表は常に単日点。
    /// ticket_deadline は自由記述もあり得るので YYYY-MM-DD にパースできた値だけ採用する。
    private static func calendarTicketsQuery(_ db: Database, startStr: String, endStr: String) throws -> [CalendarEntry] {
        let sql = """
            SELECT e.id, e.name, e.ticket_open_date, e.ticket_deadline, e.ticket_lottery_date, e.ticket_url,
                   b.color AS brand_color
            FROM events e
            LEFT JOIN brands b ON e.brand_id = b.id
            WHERE e.ticket_open_date IS NOT NULL
               OR e.ticket_deadline IS NOT NULL
               OR e.ticket_lottery_date IS NOT NULL
            """
        // YYYY-MM-DD としてパースできる文字列だけ返す (自由記述を弾く)。
        func validDate(_ value: String?) -> String? {
            guard let v = value, Self.calendarDateFormatter.date(from: v) != nil else { return nil }
            return v
        }
        var rows: [CalendarEntry] = []
        for row in try Row.fetchAll(db, sql: sql) {
            let eventId: String = row["id"]
            let name: String = row["name"]
            let brandColor: String? = row["brand_color"]
            let url: String? = row["ticket_url"]
            let open = validDate(row["ticket_open_date"])
            let deadline = validDate(row["ticket_deadline"])
            let lottery = validDate(row["ticket_lottery_date"])

            if let open, let deadline, open <= deadline {
                // 受付開始 + 締切が揃う → 受付期間スパン (表示レンジと重なる場合のみ)。
                if open <= endStr, deadline >= startStr {
                    rows.append(.ticketPeriod(TicketPeriodRow(
                        eventId: eventId, eventName: name, brandColor: brandColor,
                        start: open, end: deadline, url: url
                    )))
                }
            } else if let deadline, deadline >= startStr, deadline <= endStr {
                // 受付開始が無い場合は締切を単日点で。
                rows.append(.ticket(TicketCalendarRow(
                    eventId: eventId, eventName: name, brandColor: brandColor,
                    date: deadline, kind: .deadline, url: url
                )))
            }
            // 当落発表は常に単日点。
            if let lottery, lottery >= startStr, lottery <= endStr {
                rows.append(.ticket(TicketCalendarRow(
                    eventId: eventId, eventName: name, brandColor: brandColor,
                    date: lottery, kind: .lottery, url: url
                )))
            }
        }
        return rows
    }

    /// DB から取得した6系統のエントリを統合してソートする (純 Swift、DB アクセスなし)。
    private static func assembleCalendarEntries(
        shows: [CalendarEntry], releases: [CalendarEntry],
        birthdayPairs: [(CalendarEntry, Date)], staffBirthdayPairs: [(CalendarEntry, Date)],
        anniversaries: [CalendarEntry], tickets: [CalendarEntry]
    ) -> [CalendarEntry] {
        // 誕生日は解決した実際の Date も一緒に持ち回る (birthday/staffBirthday は CalendarEntry に
        // 年を持たせていないため、ソート時に「実際に出現する年」を引けるよう id をキーに退避する)。
        var resolvedOccurrence: [String: Date] = [:]
        let birthdays: [CalendarEntry] = birthdayPairs.map { entry, date in
            resolvedOccurrence[entry.id] = date
            return entry
        }
        let staffBirthdays: [CalendarEntry] = staffBirthdayPairs.map { entry, date in
            resolvedOccurrence[entry.id] = date
            return entry
        }

        // 誕生日系は dateString が "--MM-DD" (実年を持たない) で文字列比較すると常に月内先頭に
        // 固まってしまうため、resolvedOccurrence にある実際の出現年で "YYYY-MM-DD" 化してから比較する。
        func sortDateString(_ entry: CalendarEntry) -> String {
            if let resolved = resolvedOccurrence[entry.id] {
                return Self.calendarDateFormatter.string(from: resolved)
            }
            return entry.dateString
        }

        return (shows + releases + birthdays + staffBirthdays + anniversaries + tickets).sorted { lhs, rhs in
            let l = sortDateString(lhs)
            let r = sortDateString(rhs)
            if l != r { return l < r }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    /// "--MM-DD" 形式の月日を interval 内の年に展開して Date を返す
    /// 2月29日など非閏年に存在しない日付は 2月28日にフォールバック。Idol/Staff の誕生日共用。
    ///
    /// WHY 候補2年: interval.start の年だけで解決すると、月グリッドが前年12月から
    /// 始まる月 (特に1月) で誕生日の年がずれて interval 範囲外に落ち、その月の誕生日が
    /// 全て消える。記念日ロジック (anniversaries ブロック) と同様に intervalYear /
    /// intervalYear+1 の両方を候補にして interval に収まる方を採用する。
    private static func expandMonthDay(_ monthDay: String?, in interval: DateInterval) -> Date? {
        guard let monthDay, monthDay.hasPrefix("--") else { return nil }
        let parts = monthDay.dropFirst(2).split(separator: "-")
        guard parts.count == 2, let month = Int(parts[0]), let day = Int(parts[1]) else { return nil }

        var jstCalendar = Calendar(identifier: .gregorian)
        jstCalendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let intervalYear = jstCalendar.component(.year, from: interval.start)

        for year in [intervalYear, intervalYear + 1] {
            let comps = DateComponents(year: year, month: month, day: day)
            if let date = jstCalendar.date(from: comps), date >= interval.start, date <= interval.end {
                return date
            }
            // 非閏年の 2/29 → 2/28 にフォールバック
            if month == 2 && day == 29,
               let fallback = jstCalendar.date(from: DateComponents(year: year, month: 2, day: 28)),
               fallback >= interval.start, fallback <= interval.end {
                return fallback
            }
        }
        return nil
    }

    private static let calendarDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        // JST 固定: 海外渡航中でも日付がズレないようにする
        fmt.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return fmt
    }()

    static func parseDate(_ string: String) -> Date? {
        calendarDateFormatter.date(from: string)
    }

}
