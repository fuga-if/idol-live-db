import SwiftUI

/// イベントの「参加」を公演(show)単位で管理するシート。
/// 公演ごとに「現地 / 配信 / 不参加」を選ぶ (参加は show 単位の .attended に一本化)。
struct EventAttendanceSheet: View {
    let shows: [Show]
    /// 開催形態フォールバック元 (show に未設定の配信/LV 有無を event から継承)。
    var event: Event? = nil
    var seed: String? = nil
    var brand: String? = nil
    /// 変更後に呼ぶ (呼び出し側で派生状態を再計算するため)。
    var onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var attendance: [String: AttendanceType] = [:]

    private let markService = UserMarkService.shared

    private var allLive: Bool { !shows.isEmpty && shows.allSatisfy { attendance[$0.id] == .live } }

    var body: some View {
        NavigationStack {
            List {
                ImasListSection(footer: "公演ごとに参加形態を選べます（配信・ライブビューイングは開催があった公演のみ）。回収率には現地参加だけが数えられます。") {
                    ImasSelectableRow(
                        title: "全公演に現地参加",
                        trailing: .value("\(shows.count)公演"),
                        isSelected: allLive,
                        seed: seed, brand: brand
                    ) {
                        AppAnalytics.tap("event_attendance.toggle_all_live")
                        toggleAllLive()
                    }
                }

                ImasListSection("公演ごとに選ぶ") {
                    ForEach(shows) { show in
                        VStack(alignment: .leading, spacing: DS.Space.gap) {
                            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                                Text(show.name).imasText(.rowLabel).lineLimit(1)
                                Text([show.venue, show.date].compactMap { $0 }.joined(separator: " ・ "))
                                    .imasText(.meta).lineLimit(1)
                            }
                            HStack(spacing: DS.Space.gap) {
                                // そのライブに実在した形態だけ出す (show優先・eventフォールバック)。
                                ForEach(AttendanceAvailability.options(show: show, event: event), id: \.self) { type in
                                    let on = attendance[show.id] == type
                                    ImasFilterChip(text: type.label, systemImage: type.icon, isSelected: on,
                                                  seed: seed, brand: brand) {
                                        AppAnalytics.tap("event_attendance.set_\(type.label)")
                                        set(show: show, type: on ? nil : type)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .padding(.vertical, DS.Space.gapTight)
                        .listRowBackground(DS.surface)
                    }
                }
            }
            .imasForm()
            .navigationTitle("参加した公演")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.read(onClose: { dismiss() }))
            .onAppear(perform: reload)
            .trackScreen("event_attendance")
        }
    }

    private func reload() {
        var map: [String: AttendanceType] = [:]
        for show in shows {
            if let type = markService.attendance(entity: .show, id: show.id) {
                map[show.id] = type
            }
        }
        attendance = map
    }

    private func set(show: Show, type: AttendanceType?) {
        do {
            try markService.setAttendance(entity: .show, id: show.id, type: type)
        } catch {
            LocalWriteFailure.report(error, action: "参加の記録")
        }
        if let type { attendance[show.id] = type } else { attendance.removeValue(forKey: show.id) }
        onChange()
    }

    private func toggleAllLive() {
        let target: AttendanceType? = allLive ? nil : .live
        for show in shows {
            do {
                try markService.setAttendance(entity: .show, id: show.id, type: target)
            } catch {
                LocalWriteFailure.report(error, action: "参加の記録")
            }
        }
        reload()
        onChange()
    }
}
