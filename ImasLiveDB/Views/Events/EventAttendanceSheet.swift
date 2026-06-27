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
    @Environment(\.colorScheme) private var scheme
    @State private var attendance: [String: AttendanceType] = [:]

    private let markService = UserMarkService.shared

    private var allLive: Bool { !shows.isEmpty && shows.allSatisfy { attendance[$0.id] == .live } }

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        NavigationStack {
            List {
                Section {
                    Button { AppAnalytics.tap("event_attendance.toggle_all_live"); toggleAllLive() } label: {
                        HStack(spacing: DS.sp3) {
                            Image(systemName: allLive ? "checkmark.circle.fill" : "circle")
                                .font(.imasScaled( 20))
                                .foregroundStyle(allLive ? t.accent : DS.ink3)
                            Text("全公演に現地参加")
                                .font(.imasSubhead.weight(.semibold))
                                .foregroundStyle(DS.ink)
                            Spacer()
                            Text("\(shows.count)公演")
                                .font(.imasCaption).foregroundStyle(DS.ink2)
                        }
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text("公演ごとに参加形態を選べます（配信・ライブビューイングは開催があった公演のみ）。回収率には現地参加だけが数えられます。")
                }
                .listRowBackground(DS.surface)

                Section {
                    ForEach(shows) { show in
                        VStack(alignment: .leading, spacing: DS.sp3) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(show.name)
                                    .font(.imasSubhead).foregroundStyle(DS.ink).lineLimit(1)
                                Text([show.venue, show.date].compactMap { $0 }.joined(separator: " ・ "))
                                    .font(.imasCaption).foregroundStyle(DS.ink2).lineLimit(1)
                            }
                            HStack(spacing: DS.sp2) {
                                // そのライブに実在した形態だけ出す (show優先・eventフォールバック)。
                                ForEach(AttendanceAvailability.options(show: show, event: event), id: \.self) { type in
                                    typePill(show: show, type: type, theme: t)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("公演ごとに選ぶ")
                }
                .listRowBackground(DS.surface)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DS.bg)
            .navigationTitle("参加した公演")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }.fontWeight(.semibold)
                }
            }
            .onAppear(perform: reload)
            .trackScreen("event_attendance")
        }
    }

    /// 現地/配信 選択ピル。選択中をもう一度押すと不参加に戻る。
    private func typePill(show: Show, type: AttendanceType, theme t: ImasTheme) -> some View {
        let on = attendance[show.id] == type
        return Button { AppAnalytics.tap("event_attendance.set_\(type.label)"); set(show: show, type: on ? nil : type) } label: {
            HStack(spacing: 5) {
                Image(systemName: type.icon).font(.imasScaled( 12, weight: .semibold))
                Text(type.label).font(.imasScaled( 13.5, weight: .semibold))
            }
            .padding(.horizontal, 13).padding(.vertical, 7)
            .foregroundStyle(on ? t.onAccent : DS.ink2)
            .background(on ? AnyShapeStyle(t.accent) : AnyShapeStyle(DS.fill), in: Capsule())
        }
        .buttonStyle(.plain)
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
        try? markService.setAttendance(entity: .show, id: show.id, type: type)
        if let type { attendance[show.id] = type } else { attendance.removeValue(forKey: show.id) }
        onChange()
    }

    private func toggleAllLive() {
        let target: AttendanceType? = allLive ? nil : .live
        for show in shows {
            try? markService.setAttendance(entity: .show, id: show.id, type: target)
        }
        reload()
        onChange()
    }
}
