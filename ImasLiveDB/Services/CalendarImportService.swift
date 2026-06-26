import EventKit
import Foundation
import SwiftUI
import UIKit

// MARK: - PersonalCalendarEvent

/// 端末カレンダーから取り込んだ「マイ予定」1 件の軽量スナップショット。
/// EKEvent をそのまま View へ流さず、表示に必要な値だけを Sendable な形で保持する。
/// アプリ内表示専用であり、DB / CloudKit には一切保存しない。
struct PersonalCalendarEvent: Identifiable, Hashable, Sendable {
    /// eventIdentifier + 開始時刻。繰り返しイベントの各回を区別する。
    let id: String
    let title: String
    /// 所属カレンダー名 (例: "仕事", "家族")
    let calendarTitle: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    /// EKEvent.location (未設定・空文字なら nil)
    let location: String?
    /// EKCalendar の色。前景は ColorMath.onColor で自動選択する。
    let color: Color
}

// MARK: - CalendarImportService

/// 端末カレンダー (iCloud / Google / CalDAV 等) の読み取りサービス。
/// EventKit のフルアクセス読み取り権限で表示範囲の EKEvent を取得し、
/// `PersonalCalendarEvent` へマップする。
/// 書き込み専用の `CalendarExportService` (write-only 権限) とは独立。
@MainActor
final class CalendarImportService {

    static let shared = CalendarImportService()

    private let store = EKEventStore()

    private init() {}

    // MARK: - Authorization

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// 読み取りに使えるフルアクセスを既に持っているか。
    /// write-only (エクスポート用) では読み取れないため false。
    var hasReadAccess: Bool {
        authorizationStatus == .fullAccess
    }

    /// フルアクセスを保証する。未決定 (または write-only のみ) なら権限ダイアログを出す。
    /// - Returns: 読み取り可能になれば true。拒否済みなら false (設定誘導は呼び出し側)。
    func ensureFullAccess() async throws -> Bool {
        switch authorizationStatus {
        case .fullAccess:
            return true
        case .notDetermined, .writeOnly:
            // write-only → full への昇格リクエストもここで行う
            return try await store.requestFullAccessToEvents()
        case .denied, .restricted, .authorized:
            return false
        @unknown default:
            return false
        }
    }

    /// 権限拒否時に誘導する設定アプリの URL。
    var settingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    // MARK: - Fetch

    /// 表示範囲内の全カレンダーのイベントを取得して軽量 struct にマップする。
    /// フルアクセスが無い場合は空配列 (権限確認は `ensureFullAccess()` で先に行う)。
    func events(in interval: DateInterval) -> [PersonalCalendarEvent] {
        guard hasReadAccess else { return [] }
        let predicate = store.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: nil
        )
        return store.events(matching: predicate).map(Self.map)
    }

    // MARK: - Mapping

    private static func map(_ event: EKEvent) -> PersonalCalendarEvent {
        let start = event.startDate ?? Date()
        let identifier = event.eventIdentifier ?? event.title ?? "unknown"
        let cgColor = event.calendar?.cgColor
        return PersonalCalendarEvent(
            id: "\(identifier)_\(start.timeIntervalSince1970)",
            title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "(タイトルなし)",
            calendarTitle: event.calendar?.title ?? "カレンダー",
            start: start,
            end: event.endDate ?? start,
            isAllDay: event.isAllDay,
            location: trimmedOrNil(event.location),
            color: cgColor.map { Color(cgColor: $0) } ?? DS.sys
        )
    }

    /// 前後空白を除去し、空文字なら nil を返す。
    private static func trimmedOrNil(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
