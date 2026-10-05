import SwiftUI
import EventKit
import UIKit

/// 選択日の予定 1 行。スケジュール画面のインラインリストと、
/// 日詳細 sheet (`CalendarDayDetailView`) の双方で共有する。
/// 公演 / CDリリース / 誕生日 を `ImasRow` (記号/アバター + タイトル/サブ) で描画する。
struct DayEntryRow: View {
    @Environment(AppDatabase.self) private var database
    let entry: CalendarEntry
    /// タップ時に親へ詳細遷移先を通知する。親が sheet / nav で受ける。
    let onSelect: (DetailDestination) -> Void
    /// マイ予定タップ時に親へ通知する (DetailDestination を持たないため別経路)。
    /// 親は簡易詳細シート (PersonalEventDetailView) を出す。
    var onSelectPersonal: ((PersonalCalendarEvent) -> Void)? = nil
    /// この行が表示される暦日。記念日のN周年計算に使う (省略時は当日)。
    var displayDate: Date = Date()

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
        case .birthday(let idol, _):
            Button {
                onSelect(.idol(idol))
            } label: {
                birthdayRow(idol: idol)
            }
            .buttonStyle(.plain)
        case .staffBirthday(let staff, _):
            // 事務員は専用詳細画面が無いのでタップ無効 (View だけ)。
            staffBirthdayRow(staff: staff)
        case .anniversary(let ann, _):
            // 記念日も詳細導線無し。タップ無効。
            anniversaryRow(ann)
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
        }
    }

    // MARK: - Row variants

    /// 行の共通シェル。帯は敷かず、先頭の記号/アバター自体を実体の色で点ける
    /// (`ImasRowLeading.icon(seed:brand:)` / `.avatar`)。
    private func rowShell(leading: ImasRowLeading, title: String, subtitle: String?,
                          trailing: ImasRowTrailing = .chevron) -> some View {
        ImasRow(title: title, subtitle: subtitle, leading: leading, trailing: trailing, density: .compact)
    }

    private func showRow(_ row: CalendarShowRow) -> some View {
        let sub = [row.show.name, row.show.startTime, row.show.venue]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ・ ")
        return rowShell(
            leading: .icon("music.mic", tone: .themed, seed: row.brandColor),
            title: row.eventName,
            subtitle: sub.isEmpty ? nil : sub
        )
    }

    private func releaseRow(songs: [Song]) -> some View {
        let title = songs.count == 1
            ? songs[0].title
            : "\(songs.count)曲リリース: \(songs[0].title) 他"
        return rowShell(leading: .icon("opticaldisc.fill", tone: .attention), title: title, subtitle: "CDリリース")
    }

    private func birthdayRow(idol: Idol) -> some View {
        rowShell(
            leading: .avatar(label: idol.shortName, seed: idol.color,
                             imageURL: CustomImageService.shared.imageURL(for: idol.id)),
            title: "\(idol.name) 誕生日",
            subtitle: idol.birthdayDisplay,
            trailing: .custom(AnyView(ImasIconTile(systemImage: "gift.fill", size: .s28, tone: .themed, seed: idol.color)))
        )
    }

    /// 事務員 (音無小鳥・千川ちひろ 等) の誕生日行。アイドル詳細を持たないので非タップ。
    private func staffBirthdayRow(staff: Staff) -> some View {
        rowShell(
            leading: .icon("person.text.rectangle.fill", tone: .themed, seed: CalendarEntry.ThemeSeed.staffBirthday),
            title: "\(staff.name) 誕生日",
            subtitle: staff.role,
            trailing: .custom(AnyView(ImasIconTile(systemImage: "gift.fill", size: .s28, tone: .themed)))
        )
    }

    /// ブランド記念日 (N周年表示)。
    private func anniversaryRow(_ ann: Anniversary) -> some View {
        let kind = AnniversaryKind(rawValue: ann.kind)
        let icon = kind?.systemImage ?? "sparkles"
        var jst = Calendar(identifier: .gregorian)
        jst.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let thisYear = jst.component(.year, from: displayDate)
        let years = ann.anniversaryYears(in: thisYear)
        // 表示: 「21周年・アーケード版稼働」 (起点年=0周年は「初日」と表示)
        let title: String
        if let years {
            title = years == 0 ? "\(ann.label) (初日)" : "\(years)周年 ・ \(ann.label)"
        } else {
            title = ann.label
        }
        let subtitle = "\(ann.date.prefix(4)) 起点"
        return rowShell(
            leading: .icon(icon, tone: .themed, seed: CalendarEntry.ThemeSeed.anniversary),
            title: title,
            subtitle: subtitle,
            trailing: .none
        )
    }

    /// チケット日程行 (申込締切 / 当落発表 / 配信アーカイブ終了)。タップで親イベント詳細へ。
    /// 申込締切だけ朱 (緊急)。
    private func ticketRow(_ row: TicketCalendarRow) -> some View {
        let subtitle: String
        switch row.kind {
        case .deadline: subtitle = "\(row.saleName) ・ 申込締切"
        case .lottery: subtitle = "\(row.saleName) ・ 当落発表"
        case .archiveEnd: subtitle = row.saleName
        }
        let leading: ImasRowLeading = row.kind == .deadline
            ? .icon(row.kind.icon, tone: .negative)
            : .icon(row.kind.icon, tone: .themed, seed: CalendarEntry.ThemeSeed.ticket)
        return rowShell(leading: leading, title: "\(row.kind.label) ・ \(row.eventName)", subtitle: subtitle)
    }

    /// 端末カレンダー由来のマイ予定行。記号はカレンダーの色をそのまま点ける。
    private func personalRow(event: PersonalCalendarEvent) -> some View {
        let timeText = event.isAllDay
            ? "終日"
            : "\(event.start.formatted(date: .omitted, time: .shortened)) 〜 \(event.end.formatted(date: .omitted, time: .shortened))"
        return rowShell(
            leading: .icon("calendar", tone: .themed, seed: ColorMath.hexString(from: event.color)),
            title: event.title,
            subtitle: "\(timeText) ・ \(event.calendarTitle)"
        )
    }
}

// MARK: - 日詳細 sheet (detent プレゼン用に保持。共有行 DayEntryRow を再利用)

struct CalendarDayDetailView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.colorScheme) private var scheme
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
        Group {
            if case .show(let row) = entry {
                // 公演行だけ参加登録のスワイプを付ける (右)。カレンダー追加 (左) と規則を共有。
                DayEntryRow(entry: entry, onSelect: onSelect, onSelectPersonal: onSelectPersonal, displayDate: selectedDate)
                    .environment(database)
                    .attendanceSwipe(show: row.show)
            } else {
                DayEntryRow(entry: entry, onSelect: onSelect, onSelectPersonal: onSelectPersonal, displayDate: selectedDate)
                    .environment(database)
            }
        }
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
                .tint(DS.success)
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
            VStack(alignment: .leading, spacing: DS.sp1) {
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
        // アイドル誕生日と事務員誕生日は同じ「gift」アイコンでまとめて集計。
        let birthdayCount = entries.filter {
            if case .birthday = $0 { return true }
            if case .staffBirthday = $0 { return true }
            return false
        }.count
        let anniversaryCount = entries.filter { if case .anniversary = $0 { true } else { false } }.count
        let ticketCount = entries.filter { if case .ticket = $0 { true } else { false } }.count
        let personalCount = entries.filter { if case .personal = $0 { true } else { false } }.count
        return HStack(spacing: DS.sp3) {
            if showCount > 0 {
                summaryBadge(count: showCount, systemImage: "music.mic", color: DS.sys)
            }
            if releaseCount > 0 {
                summaryBadge(count: releaseCount, systemImage: "opticaldisc", color: DS.warning)
            }
            if birthdayCount > 0 {
                summaryBadge(count: birthdayCount, systemImage: "gift", color: ImasTheme.derive(seed: CalendarEntry.ThemeSeed.staffBirthday, scheme: scheme).accent)
            }
            if anniversaryCount > 0 {
                summaryBadge(count: anniversaryCount, systemImage: "sparkles", color: ImasTheme.derive(seed: CalendarEntry.ThemeSeed.anniversary, scheme: scheme).accent)
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
        HStack(spacing: DS.Space.gapTight) {
            Image(systemName: systemImage).imasText(.badge, color: color)
            Text("\(count)").font(.imasDisplay(13, weight: .semibold)).foregroundStyle(color)
        }
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

// 記号の装飾 (旧 ShowIconAvatar / ReleaseIconAvatar / TicketIconAvatar / BirthdayGiftChip) は
// `ImasRowLeading.icon(seed:brand:)` / `ImasIconTile` に置き換えて `DayEntryRow` に統合した
// (地を敷いた色付き丸は「記号を淡い色の四角に入れない」原則に反するため)。
