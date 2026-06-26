import os
import SwiftUI

struct FilteredShowsView: View {
    @Environment(AppDatabase.self) private var database
    let criterion: ShowFilterCriterion
    let navigate: (DetailDestination) -> Void

    @State private var shows: [Show] = []
    @State private var eventNames: [String: String] = [:]
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shows.isEmpty {
                ContentUnavailableView(
                    "公演が見つかりません",
                    systemImage: "ticket"
                )
            } else {
                List {
                    Section {
                        ForEach(shows) { show in
                            Button { navigate(.show(show)) } label: {
                                showRow(show)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(DS.surface)
                            .listRowSeparatorTint(DS.sep)
                        }
                    } header: {
                        Text("\(shows.count)公演")
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
        .task { await loadShows() }
        .trackScreen("filtered_shows")
    }

    @ViewBuilder
    private func showRow(_ show: Show) -> some View {
        let eventName = eventNames[show.eventId] ?? ""
        VStack(alignment: .leading, spacing: 4) {
            Text(eventName.isEmpty ? show.name : eventDisplayName(eventName))
                .font(.imasHeadline)
                .foregroundStyle(DS.ink)
                .lineLimit(1)
            HStack(spacing: 6) {
                if !eventName.isEmpty {
                    Text(show.name)
                        .font(.imasSubhead)
                        .foregroundStyle(DS.ink2)
                }
                if let venue = show.venue {
                    if !eventName.isEmpty {
                        Text("·").font(.imasCaption).foregroundStyle(DS.ink3)
                    }
                    Text(venue)
                        .font(.imasSubhead)
                        .foregroundStyle(DS.ink2)
                }
                Spacer()
                Text(show.date)
                    .font(.imasSubhead)
                    .foregroundStyle(DS.ink2)
            }
        }
        .padding(.vertical, 4)
    }

    private func loadShows() async {
        isLoading = true
        do {
            shows = try await AppContainer.shared.showReading.shows(criterion: criterion)
            let eventIds = Set(shows.map(\.eventId))
            var names: [String: String] = [:]
            for id in eventIds {
                if let event = try await AppContainer.shared.eventReading.event(id: id) {
                    names[id] = event.name
                }
            }
            eventNames = names
        } catch {
            Logger.database.error("load_failed filtered_shows: \(error.localizedDescription)")
            shows = []
            eventNames = [:]
        }
        isLoading = false
    }
}
