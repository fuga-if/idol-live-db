import Foundation

/// 今年の P 活動報告の材料を引く。参加マーク・担当・帳簿は端末、集計はコア (`yearReport`)。
@MainActor
enum YearReportSource {
    /// 報告 1 年分と、色 (先頭の担当の色)。
    struct Loaded {
        let report: YearReport
        let years: [Int]
        let accentSeed: String?
        let accentBrand: String?
    }

    /// 入口に出す年 (12 月は今年・1 月は去年。その年に参加が無ければ出さない)。
    static func offerYear() async -> Int? {
        guard let year = yearReportOfferYear(today: JSTDay.today()) else { return nil }
        return await years().contains(Int(year)) ? Int(year) : nil
    }

    /// 参加した公演のある年 (新しい順)。
    static func years() async -> [Int] {
        let database = AppDatabase.shared
        let showMarks = (try? await CollectionAttendance.marks(entity: .show, database: database)) ?? []
        let eventMarks = (try? await CollectionAttendance.marks(entity: .event, database: database)) ?? []
        let years = try? await coreYears(AppContainer.shared.coreSnapshot, showMarks: showMarks,
                                         eventMarks: eventMarks, today: JSTDay.today())
        return (years ?? []).map(Int.init)
    }

    private nonisolated static func coreYears(
        _ snapshot: CoreSnapshotManager, showMarks: [AttendanceMarkRecord], eventMarks: [AttendanceMarkRecord],
        today: String
    ) async throws -> [UInt16] {
        try await snapshot.withStore { store in
            try store.yearReportYears(showMarks: showMarks, eventMarks: eventMarks, today: today)
        }
    }

    private nonisolated static func coreReport(_ snapshot: CoreSnapshotManager, input: YearReportInput) async throws
        -> YearReport {
        try await snapshot.withStore { try $0.yearReport(input: input) }
    }

    static func load(year: Int) async -> Loaded? {
        let c = AppContainer.shared
        let database = AppDatabase.shared
        let showMarks = (try? await CollectionAttendance.marks(entity: .show, database: database)) ?? []
        let eventMarks = (try? await CollectionAttendance.marks(entity: .event, database: database)) ?? []
        let oshiIds = (try? await c.markReading.markedEntityIds(entity: .idol, kind: .myPick)) ?? []
        let expenses = ((try? await c.ledgerReading.expenses()) ?? []).map {
            ExpenseEntry(id: $0.id, date: $0.date, category: $0.categoryValue, amount: $0.amount,
                         showId: $0.showId, eventId: $0.eventId, showLabel: nil, note: $0.note)
        }
        let name = (try? await c.producerCards.myCard())?.name ?? ""
        let input = YearReportInput(
            year: UInt16(clamping: year), name: name, showMarks: showMarks, eventMarks: eventMarks,
            oshiIdolIds: oshiIds, collectionIncludesStream: CollectionAttendance.includeStream,
            usesLedger: !expenses.isEmpty, expenses: expenses)
        guard let report = try? await coreReport(c.coreSnapshot, input: input) else { return nil }
        let lead = oshiIds.isEmpty ? nil : (try? await c.idolReading.idols(ids: [oshiIds[0]]))?.first
        let brands = lead == nil ? [] : ((try? await c.brandReading.brands()) ?? [])
        let brand = lead.flatMap { idol in brands.first { $0.id == idol.brandId }?.color }
        return Loaded(report: report, years: await years(), accentSeed: lead?.color, accentBrand: brand)
    }
}
