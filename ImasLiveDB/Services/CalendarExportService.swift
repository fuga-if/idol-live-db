import EventKit
import Foundation
import os
import UIKit

// MARK: - CalendarExportService

/// デバイスカレンダーへのライブ予定エクスポートサービス。
/// EventKit を使用し、ユーザーが Google アカウントをデバイスに設定していれば
/// Google カレンダーへも自動同期される。
///
/// - 重複防止: 追加済みイベント ID を UserDefaults に記録し、ベストエフォートで防ぐ。
/// - 権限拒否時: 設定アプリへの誘導 URL を提供する。
/// - write-only モード: `store.defaultCalendarForNewEvents` に追加するシンプルな設計。
@MainActor
final class CalendarExportService: Sendable {

    static let shared = CalendarExportService()

    private let store = EKEventStore()

    // MARK: - UserDefaults keys

    private enum Defaults {
        static let addedIDs = "calendar_export_added_show_ids"
    }

    private var addedShowIDs: Set<String> {
        get {
            let arr = UserDefaults.standard.stringArray(forKey: Defaults.addedIDs) ?? []
            return Set(arr)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: Defaults.addedIDs)
        }
    }

    private init() {}

    // MARK: - Authorization

    /// 現在の EventKit 認証状態を返す。
    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// iOS 17 の write-only アクセス権限を要求する。
    /// - Returns: 権限が付与されていれば `true`。
    func requestAccess() async throws -> Bool {
        let status = authorizationStatus
        switch status {
        case .authorized, .writeOnly, .fullAccess:
            return true
        case .notDetermined:
            return try await store.requestWriteOnlyAccessToEvents()
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// 設定アプリを開くための URL。権限拒否時に誘導する。
    var settingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    // MARK: - Export

    /// Show と Event 情報からデバイスカレンダーにイベントを追加する。
    /// - Parameters:
    ///   - show: 追加する公演
    ///   - event: 親イベント（名前・ブランド情報用）
    ///   - forceAdd: true の場合は重複チェックをスキップして再追加する
    /// - Returns: 追加されたか、既存だったか
    func exportShow(_ show: Show, event: Event, forceAdd: Bool = false) async throws -> ExportResult {
        let granted = try await requestAccess()
        guard granted else {
            return .permissionDenied
        }

        // 重複チェック
        if !forceAdd && addedShowIDs.contains(show.id) {
            return .alreadyAdded
        }

        guard let calendar = store.defaultCalendarForNewEvents else {
            throw CalendarExportError.noDefaultCalendar
        }

        let ekEvent = EKEvent(eventStore: store)
        ekEvent.calendar = calendar
        ekEvent.title = buildTitle(show: show, event: event)
        ekEvent.location = show.venue

        let (startDate, endDate, isAllDay) = try buildDates(for: show)
        ekEvent.startDate = startDate
        ekEvent.endDate = endDate
        ekEvent.isAllDay = isAllDay

        ekEvent.notes = buildNotes(show: show, event: event)

        try store.save(ekEvent, span: .thisEvent)

        // 追加済みとして記録
        var ids = addedShowIDs
        ids.insert(show.id)
        addedShowIDs = ids

        return .added
    }

    /// UserDefaults から追加済み記録を削除する（「もう一度追加」用）。
    func removeAddedRecord(for showId: String) {
        var ids = addedShowIDs
        ids.remove(showId)
        addedShowIDs = ids
    }

    // MARK: - Private helpers

    private func buildTitle(show: Show, event: Event) -> String {
        show.name.isEmpty ? event.name : "\(event.name) \(show.name)"
    }

    private func buildNotes(show: Show, event: Event) -> String {
        var parts: [String] = []
        if let venue = show.venue, !venue.isEmpty { parts.append("会場: \(venue)") }
        if let city = show.venueCity, !city.isEmpty { parts.append("都市: \(city)") }
        return parts.joined(separator: "\n")
    }

    /// 公演日時を解析して (startDate, endDate, isAllDay) を返す。
    /// startTime がある場合は時刻付き 2 時間イベント、なければ終日イベント。
    /// 日付パース失敗時はエラーをスロー。
    private func buildDates(for show: Show) throws -> (start: Date, end: Date, isAllDay: Bool) {
        let dateStr = show.date
        let timeStr = show.startTime

        // JST で日付を解析
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        if let time = timeStr, !time.isEmpty {
            // 時刻付き: "YYYY-MM-DD" + "HH:MM"
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            if let start = formatter.date(from: "\(dateStr) \(time)") {
                let end = start.addingTimeInterval(7200) // 2 時間
                return (start, end, false)
            }
        }

        // 終日: EventKit では endDate = startDate（同日）が正しい all-day 表現
        formatter.dateFormat = "yyyy-MM-dd"
        if let start = formatter.date(from: dateStr) {
            return (start, start, true)
        }

        // 日付パース失敗はエラー
        throw CalendarExportError.invalidDate(dateStr)
    }
}

// MARK: - ExportResult

enum ExportResult: Sendable {
    /// 正常に追加された
    case added
    /// 既に追加済みだった
    case alreadyAdded
    /// 権限が拒否された
    case permissionDenied
}

// MARK: - CalendarExportError

enum CalendarExportError: LocalizedError, Sendable {
    case noDefaultCalendar
    case invalidDate(String)

    var errorDescription: String? {
        switch self {
        case .noDefaultCalendar:
            return "デフォルトカレンダーが見つかりませんでした。設定でカレンダーへのアクセスを許可してください。"
        case .invalidDate(let str):
            return "日付の解析に失敗しました: \(str)"
        }
    }
}
