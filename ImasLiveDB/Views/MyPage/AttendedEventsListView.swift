import SwiftUI

/// マイページから「参加したライブ 全て見る」で開く一覧。
/// 参加マーク (event-level attended) が付いた event を公演日降順で表示する。
struct AttendedEventsListView: View {
    let events: [EventWithDate]

    var body: some View {
        List {
            Section {
                ForEach(events) { ew in
                    NavigationLink(value: ew.event) {
                        EventNameRow(event: ew.event, subtitle: ew.dateRange, showsChevron: false)
                    }
                    .listRowBackground(DS.surface)
                    .listRowSeparatorTint(DS.sep)
                }
            } header: {
                Text("\(events.count)件")
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.bg)
        .navigationTitle("参加したライブ")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("attended_events")
        // navigationDestination(for: Event.self) は親 (MyPageView の NavigationStack 直下)
        // に登録済み。ここで再登録すると同一スタックに同型 destination が二重になり、
        // 「一覧が再表示され、戻るで詳細に飛ぶ」遷移崩れを起こすため置かない。
    }
}
