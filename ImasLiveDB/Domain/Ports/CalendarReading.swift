import Foundation

/// カレンダー表示用エントリの読み取りポート (driven port)。
///
/// 実装は `Adapters/Persistence/CoreCalendarRepository` (共有コアのスナップショット)。
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol CalendarReading: Sendable {
    /// 指定期間に該当する公演/リリース/チケット等のカレンダーエントリ。
    func calendarEntries(in interval: DateInterval) async throws -> [CalendarEntry]
    /// その日と同じ月日の、過去の記念日・ライブ・リリースと誕生日 (「今日は何の日？」)。
    func onThisDay(_ date: Date) async throws -> OnThisDayDigest
}

/// 「今日は何の日？」の中身。何を拾うか・何年前か・共有文はコア (`on_this_day.rs`) が決め、
/// ここでは行に出す曲とアイドルを実体にしたものを添えるだけ。
struct OnThisDayDigest: @unchecked Sendable {
    let day: OnThisDay
    /// リリースの曲 (id → 曲)。
    let songs: [String: Song]
    /// 誕生日のアイドル (id → アイドル)。
    let idols: [String: Idol]
}
