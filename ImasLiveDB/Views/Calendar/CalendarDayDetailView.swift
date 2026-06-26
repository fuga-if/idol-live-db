import SwiftUI
import EventKit
import UIKit

/// 選択日の予定 1 行。スケジュール画面のインラインリストと、
/// 日詳細 sheet (`CalendarDayDetailView`) の双方で共有する。
/// 公演 / CDリリース / 誕生日 を ImasLeadBar + アイコン/アバター + タイトル/サブ で描画する。
struct DayEntryRow: View {
    @Environment(AppDatabase.self) private var database
    let entry: CalendarEntry
    /// タップ時に親へ詳細遷移先を通知する。親が sheet / nav で受ける。
    let onSelect: (DetailDestination) -> Void
    /// マイ予定タップ時に親へ通知する (DetailDestination を持たないため別経路)。
    /// 親は簡易詳細シート (PersonalEventDetailView) を出す。
    var onSelectPersonal: ((PersonalCalendarEvent) -> Void)? = nil

    var body: some View {
        switch entry {
        case .show(let row):
            // 主タップ: 親イベント詳細。スワイプ (セトリ) で公演 (Show) に直接飛べる。
            Button {
                Task {
                    if let event = try? await AppContainer.shared.eventReading.event(id: row.show.eventId) {
                        onSelect(.event(event))
                    }
                }
            } label: {
                showRow(row)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    Task {
                        if let show = try? await AppContainer.shared.showReading.show(id: row.show.id) {
                            onSelect(.show(show))
                        }
                    }
                } label: {
                    Label("セトリ", systemImage: "music.note.list")
                }
                .tint(DS.sys)
            }
        case .release(_, let songs):
            Button {
                guard let first = songs.first else { return }
                onSelect(.song(first))
            } label: {
                releaseRow(songs: songs)
            }
            .buttonStyle(.plain)
        case .birthday(let idol):
            Button {
                onSelect(.idol(idol))
            } label: {
                birthdayRow(idol: idol)
            }
            .buttonStyle(.plain)
        case .personal(let event):
            Button {
                onSelectPersonal?(event)
            } label: {
                personalRow(event: event)
            }
            .buttonStyle(.plain)
        case .ticket(let row):
            Button {
                Task {
                    if let event = try? await AppContainer.shared.eventReading.event(id: row.eventId) {
                        onSelect(.event(event))
                    }
                }
            } label: {
                ticketRow(row)
            }
            .buttonStyle(.plain)
        case .ticketPeriod(let row):
            Button {
                Task {
                    if let event = try? await AppContainer.shared.eventReading.event(id: row.eventId) {
                        onSelect(.event(event))
                    }
                }
            } label: {
                ticketPeriodRow(row)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Row variants

    /// 行の共通シェル: リードバー + リーディング (アイコン/アバター) + タイトル/サブ + 末尾。
    private func rowShell<Leading: View, Trailing: View>(
        seed: String?,
        title: String,
        subtitle: String?,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: DS.sp3) {
            ImasLeadBar(seed: seed)
                .frame(height: 36)
            leading()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.imasSubhead.weight(.semibold))
                    .foregroundStyle(DS.ink)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.imasFootnote)
                        .foregroundStyle(DS.ink2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.sp2)
            trailing()
        }
        .padding(.horizontal, DS.sp4)
        .padding(.vertical, DS.sp3)
        .contentShape(Rectangle())
    }

    private func showRow(_ row: CalendarShowRow) -> some View {
        let sub = [row.show.name, row.show.startTime, row.show.venue]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ・ ")
        return rowShell(
            seed: row.brandColor,
            title: row.eventName,
            subtitle: sub.isEmpty ? nil : sub,
            leading: { ShowIconAvatar(seed: row.brandColor) },
            trailing: { chevron }
        )
    }

    private func releaseRow(songs: [Song]) -> some View {
        let title = songs.count == 1
            ? songs[0].title
            : "\(songs.count)曲リリース: \(songs[0].title) 他"
        return rowShell(
            seed: nil,
            title: title,
            subtitle: "CDリリース",
            leading: { ReleaseIconAvatar() },
            trailing: { chevron }
        )
    }

    private func birthdayRow(idol: Idol) -> some View {
        rowShell(
            seed: idol.color,
            title: "\(idol.name) 誕生日",
            subtitle: idol.birthdayDisplay,
            leading: { IdolAvatarView(idol: idol, size: 36) },
            trailing: { BirthdayGiftChip(seed: idol.color) }
        )
    }

    /// チケット受付期間行 (受付開始〜申込締切)。タップで親イベント詳細へ。
    private func ticketPeriodRow(_ row: TicketPeriodRow) -> some View {
        let range = [Self.md(row.start), Self.md(row.end)].compactMap { $0 }.joined(separator: " 〜 ")
        return rowShell(
            seed: nil,
            title: "受付期間 ・ \(row.eventName)",
            subtitle: range.isEmpty ? "チケット受付期間" : "チケット受付  \(range)",
            leading: { TicketIconAvatar(systemImage: "calendar.badge.clock", color: .indigo) },
            trailing: { chevron }
        )
    }

    /// "2026-06-13" → "6/13"。
    private static func md(_ ymd: String) -> String? {
        let parts = ymd.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        return "\(m)/\(d)"
    }

    /// チケット日程行 (申込締切 / 当落発表)。タップで親イベント詳細へ。
    private func ticketRow(_ row: TicketCalendarRow) -> some View {
        let color: Color = row.kind == .deadline ? DS.danger : .indigo
        return rowShell(
            seed: nil,
            title: "\(row.kind.label) ・ \(row.eventName)",
            subtitle: row.kind == .deadline ? "チケット申込の締切" : "チケット当落発表",
            leading: { TicketIconAvatar(systemImage: row.kind.icon, color: color) },
            trailing: { chevron }
        )
    }

    /// 端末カレンダー由来のマイ予定行。リードバーはカレンダー色をそのまま使う。
    private func personalRow(event: PersonalCalendarEvent) -> some View {
        let timeText = event.isAllDay
            ? "終日"
            : "\(event.start.formatted(date: .omitted, time: .shortened)) 〜 \(event.end.formatted(date: .omitted, time: .shortened))"
        return HStack(spacing: DS.sp3) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(event.color)
                .frame(width: 3, height: 36)
            Image(systemName: "calendar")
                .font(.imasScaled( 16, weight: .semibold))
                .foregroundStyle(event.color)
                .frame(width: 36, height: 36)
                .background(event.color.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.imasSubhead.weight(.semibold))
                    .foregroundStyle(DS.ink)
                    .lineLimit(2)
                Text("\(timeText) ・ \(event.calendarTitle)")
                    .font(.imasFootnote)
                    .foregroundStyle(DS.ink2)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.sp2)
            chevron
        }
        .padding(.horizontal, DS.sp4)
        .padding(.vertical, DS.sp3)
        .contentShape(Rectangle())
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.imasScaled( 13, weight: .semibold))
            .foregroundStyle(DS.ink3)
    }
}

// MARK: - 日詳細 sheet (detent プレゼン用に保持。共有行 DayEntryRow を再利用)

struct CalendarDayDetailView: View {
    @Environment(AppDatabase.self) private var database
    let entries: [CalendarEntry]
    let selectedDate: Date
    /// 親に「この sheet を閉じてから詳細 sheet を開いてほしい」と通知するコールバック。
    /// 二重 sheet 表示できない SwiftUI 制約への対応。
    let onSelect: (DetailDestination) -> Void
    /// マイ予定行タップ → 親が簡易詳細シートを開く (こちらも閉じてから開く流儀は親に任せる)。
    var onSelectPersonal: ((PersonalCalendarEvent) -> Void)? = nil

    // MARK: - カレンダー連携 state
    @State private var exportTarget: CalendarShowEntry? = nil
    @State private var exportResult: ExportResultAlert? = nil
    @State private var showPermissionAlert = false

    var body: some View {
        VStack(spacing: 0) {
            dayHeader

            if entries.isEmpty {
                ImasEmptyState(
                    systemImage: "calendar",
                    title: "イベントなし",
                    message: "この日はライブ・リリース・誕生日の記録がありません"
                )
                Spacer(minLength: 0)
            } else {
                List {
                    ForEach(entries) { entry in
                        entryRow(for: entry)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(DS.bg)
                .environment(\.defaultMinListRowHeight, 0)
            }
        }
        .background(DS.bg)
        .trackScreen("calendar_day")
        // カレンダーに追加 確認シート（presenting オーバーロードでレース回避）
        .confirmationDialog(
            "カレンダーに追加",
            isPresented: Binding(
                get: { exportTarget != nil },
                set: { if !$0 { exportTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: exportTarget
        ) { target in
            Button("「\(target.showRow.eventName)」を追加する") {
                exportTarget = nil
                Task { await performExport(target) }
            }
            Button("キャンセル", role: .cancel) {
                exportTarget = nil
            }
        } message: { target in
            Text("「\(target.showRow.eventName)」をデバイスのカレンダーに追加します。")
        }
        // 追加結果アラート
        .alert(item: $exportResult) { result in
            if result.kind == .alreadyAdded, let target = result.target {
                return Alert(
                    title: Text(result.title),
                    message: Text(result.message),
                    primaryButton: .default(Text("もう一度追加")) {
                        CalendarExportService.shared.removeAddedRecord(for: target.showRow.show.id)
                        Task { await performExport(target) }
                    },
                    secondaryButton: .cancel(Text("閉じる"))
                )
            }
            return Alert(
                title: Text(result.title),
                message: Text(result.message),
                dismissButton: .default(Text("OK"))
            )
        }
        // 権限拒否 → 設定アプリへ誘導
        .alert("カレンダーへのアクセスが拒否されています", isPresented: $showPermissionAlert) {
            Button("設定を開く") {
                if let url = CalendarExportService.shared.settingsURL {
                    UIApplication.shared.open(url)
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("ライブの予定をカレンダーに追加するには、設定アプリでカレンダーへのアクセスを許可してください。")
        }
    }

    // MARK: - 行の描画

    @ViewBuilder
    private func entryRow(for entry: CalendarEntry) -> some View {
        DayEntryRow(entry: entry, onSelect: onSelect, onSelectPersonal: onSelectPersonal)
            .environment(database)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(DS.surface)
            .listRowSeparatorTint(DS.sep)
            // 公演行だけ「カレンダーに追加」スワイプアクションを付ける
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if case .show(let row) = entry {
                    Button {
                        AppAnalytics.tap("calendar_day.calendar_add")
                        exportTarget = CalendarShowEntry(showRow: row)
                    } label: {
                        Label("カレンダー", systemImage: "calendar.badge.plus")
                    }
                    .tint(.green)
                }
            }
    }

    // MARK: - カレンダーエクスポート実行

    private func performExport(_ target: CalendarShowEntry) async {
        do {
            guard let event = try await AppContainer.shared.eventReading.event(id: target.showRow.show.eventId) else {
                exportResult = ExportResultAlert(
                    kind: .error,
                    title: "エラー",
                    message: "イベント情報の取得に失敗しました。",
                    target: target
                )
                return
            }

            let result = try await CalendarExportService.shared.exportShow(target.showRow.show, event: event)
            switch result {
            case .added:
                exportResult = ExportResultAlert(
                    kind: .added,
                    title: "追加しました",
                    message: "「\(target.showRow.eventName)」をカレンダーに追加しました。",
                    target: target
                )
            case .alreadyAdded:
                exportResult = ExportResultAlert(
                    kind: .alreadyAdded,
                    title: "追加済み",
                    message: "「\(target.showRow.eventName)」はすでにカレンダーに追加されています。",
                    target: target
                )
            case .permissionDenied:
                showPermissionAlert = true
            }
        } catch {
            exportResult = ExportResultAlert(
                kind: .error,
                title: "エラー",
                message: error.localizedDescription,
                target: target
            )
        }
    }

    // MARK: - ヘッダー

    private var dayHeader: some View {
        HStack(alignment: .center, spacing: DS.sp4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedDate.formatted(.dateTime.year().month(.wide).day()))
                    .font(.imasTitle3.weight(.bold))
                    .foregroundStyle(DS.ink)
                if !entries.isEmpty {
                    Text("\(entries.count)件のイベント")
                        .font(.imasFootnote)
                        .foregroundStyle(DS.ink2)
                }
            }
            Spacer()
            entryTypeSummary
        }
        .padding(.horizontal, DS.sp6)
        .padding(.vertical, DS.sp4)
        .background(DS.surface)
    }

    private var entryTypeSummary: some View {
        let showCount = entries.filter { if case .show = $0 { true } else { false } }.count
        let releaseCount = entries.filter { if case .release = $0 { true } else { false } }.count
        let birthdayCount = entries.filter { if case .birthday = $0 { true } else { false } }.count
        let ticketCount = entries.filter {
            if case .ticket = $0 { return true }
            if case .ticketPeriod = $0 { return true }
            return false
        }.count
        let personalCount = entries.filter { if case .personal = $0 { true } else { false } }.count
        return HStack(spacing: DS.sp3) {
            if showCount > 0 {
                summaryBadge(count: showCount, systemImage: "music.mic", color: DS.sys)
            }
            if releaseCount > 0 {
                summaryBadge(count: releaseCount, systemImage: "opticaldisc", color: DS.warning)
            }
            if birthdayCount > 0 {
                summaryBadge(count: birthdayCount, systemImage: "gift", color: .pink)
            }
            if ticketCount > 0 {
                summaryBadge(count: ticketCount, systemImage: "ticket", color: DS.danger)
            }
            if personalCount > 0 {
                summaryBadge(count: personalCount, systemImage: "calendar", color: DS.sys2)
            }
        }
    }

    private func summaryBadge(count: Int, systemImage: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).font(.imasScaled( 12, weight: .semibold))
            Text("\(count)").font(.imasDisplay(13, weight: .semibold))
        }
        .foregroundStyle(color)
    }
}

// MARK: - Supporting types

private struct CalendarShowEntry: Identifiable {
    let id = UUID()
    let showRow: CalendarShowRow
}

private enum ExportResultKind: Equatable {
    case added, alreadyAdded, error
}

private struct ExportResultAlert: Identifiable {
    let id = UUID()
    let kind: ExportResultKind
    let title: String
    let message: String
    let target: CalendarShowEntry?
}

// MARK: - Row leading / trailing accents

/// 公演アイコン (テーマ chip 面 + mic)。
private struct ShowIconAvatar: View {
    var seed: String?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = ImasTheme.derive(seed: seed, scheme: scheme)
        Image(systemName: "music.mic")
            .font(.imasScaled( 16, weight: .semibold))
            .foregroundStyle(t.chipText)
            .frame(width: 36, height: 36)
            .background(t.chipBg, in: Circle())
    }
}

/// リリースアイコン (橙基調)。
private struct ReleaseIconAvatar: View {
    var body: some View {
        Image(systemName: "opticaldisc.fill")
            .font(.imasScaled( 16, weight: .semibold))
            .foregroundStyle(DS.warning)
            .frame(width: 36, height: 36)
            .background(DS.warning.opacity(0.16), in: Circle())
    }
}

/// チケットアイコン (締切=赤 / 当落=藍)。
private struct TicketIconAvatar: View {
    let systemImage: String
    let color: Color
    var body: some View {
        Image(systemName: systemImage)
            .font(.imasScaled( 15, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 36, height: 36)
            .background(color.opacity(0.16), in: Circle())
    }
}

/// 誕生日末尾のギフトチップ (アイドル色テーマ)。
private struct BirthdayGiftChip: View {
    var seed: String?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let t = ImasTheme.derive(seed: seed, scheme: scheme)
        Image(systemName: "gift.fill")
            .font(.imasScaled( 12, weight: .semibold))
            .foregroundStyle(t.chipText)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(t.chipBg, in: Capsule())
    }
}
