import os
import SwiftUI

struct FilteredEventsView: View {
    @Environment(AppDatabase.self) private var database
    let criterion: EventFilterCriterion
    /// 共有 NavigationStack の path へ push するクロージャ (兄弟 Filtered*View と同様)。
    let navigate: (DetailDestination) -> Void

    @State private var eventsWithDate: [EventWithDate] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ImasLoadingState()
            } else if eventsWithDate.isEmpty {
                ImasEmptyState(
                    systemImage: "music.mic",
                    title: "ライブが見つかりません"
                )
            } else {
                List {
                    ImasListSummary<Int>(count: eventsWithDate.count, unit: "件")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(DS.bg)
                        .listRowSeparator(.hidden)
                    ForEach(eventsWithDate) { ew in
                        Button { navigate(.event(ew.event)) } label: {
                            // 種別は生の内部値ではなくラベルで出す。未分類なら何も出さない
                            // (日付は半券の日付欄が言うので、ここで重ねない)。
                            ImasEventRow(
                                event: ew.event,
                                date: ew.firstDate,
                                subtitle: EventType(rawValue: ew.event.eventType)?.displayLabel
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .imasList()
            }
        }
        .navigationTitle(criterion.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadEvents() }
        .trackScreen("filtered_events")
    }

    private func loadEvents() async {
        isLoading = true
        do {
            eventsWithDate = try await AppContainer.shared.eventReading.eventsWithDate(criterion: criterion, includeEmpty: true)
        } catch {
            Logger.database.error("load_failed filtered_events: \(error.localizedDescription)")
            eventsWithDate = []
        }
        isLoading = false
    }
}
