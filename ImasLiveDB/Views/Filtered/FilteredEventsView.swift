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
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if eventsWithDate.isEmpty {
                ContentUnavailableView(
                    "ライブが見つかりません",
                    systemImage: "music.mic"
                )
            } else {
                List {
                    Section {
                        ForEach(eventsWithDate) { ew in
                            Button { navigate(.event(ew.event)) } label: {
                                EventNameRow(
                                    event: ew.event,
                                    subtitle: [ew.event.eventType, ew.firstDate].compactMap { $0 }.joined(separator: "  ")
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(DS.surface)
                            .listRowSeparatorTint(DS.sep)
                        }
                    } header: {
                        Text("\(eventsWithDate.count)件")
                            .font(.imasCaption)
                            .foregroundStyle(DS.ink2)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(DS.bg)
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
