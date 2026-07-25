import os
import SwiftUI

struct FilteredShowsView: View {
    @Environment(AppDatabase.self) private var database
    let criterion: ShowFilterCriterion
    let navigate: (DetailDestination) -> Void

    @State private var shows: [Show] = []
    @State private var eventNames: [String: String] = [:]
    @State private var isLoading = true
    /// 会場 ID → 表示名。 criterion が持つのは ID なので、 タイトルに出す前に名前へ解決する
    /// (解決前は ID がそのまま "venue_京王アリーナtokyo での公演" と出てしまう)。
    @State private var venueName: String?
    @State private var venueDirectory: VenueDirectory = .empty

    /// 会場は名前を解決できたらそれを使う。 日付など他の criterion は既定のまま。
    private var resolvedTitle: String {
        if case .venue = criterion, let venueName {
            return "\(venueName)での公演"
        }
        return criterion.navigationTitle
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shows.isEmpty {
                ImasEmptyState(
                    systemImage: "ticket",
                    title: "公演が見つかりません"
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
        .navigationTitle(resolvedTitle)
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
                // 会場マスタがあれば公演日時点の名前を出す (改称前の公演は当時の名前)。
                // 無い公演は生の venue 文字列にフォールバックする。
                if let venue = venueDirectory.displayName(for: show) ?? show.venue {
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
            let directory = try await AppContainer.shared.showReading.venueDirectory()
            venueDirectory = directory
            if case .venue(let venueId) = criterion {
                // 会場は改称するので、 一覧の代表として最新の名前 (venues.name) を使う。
                // 各行の「当時の名前」は show 側で解決済み。
                venueName = directory.venue(id: venueId)?.name
            }
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
