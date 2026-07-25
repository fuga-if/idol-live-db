import os
import SwiftUI

/// 「この会場での公演」「この日の公演」の一覧。
///
/// 会場での一覧は 20〜30 公演が数年にまたがるので、 イベント一覧と同じく **年で束ねる**。
/// 行の作りもイベント一覧 (ImasSectionHeader + ImasListContainer + ImasLeadBar) に揃える。
struct FilteredShowsView: View {
    @Environment(AppDatabase.self) private var database
    let criterion: ShowFilterCriterion
    let navigate: (DetailDestination) -> Void

    @State private var shows: [Show] = []
    @State private var events: [String: Event] = [:]
    @State private var isLoading = true
    /// criterion が持つのは会場 ID なので、 タイトルに出す前に名前へ解決する
    /// (解決前は ID がそのまま "venue_京王アリーナtokyo での公演" と出てしまう)。
    @State private var venueName: String?
    @State private var venueDirectory: VenueDirectory = .empty

    /// 会場での一覧では全行が同じ会場なので、 行に会場名を出すのは冗長。
    /// 日付での一覧は会場が行ごとに違うので出す。
    private var showsVenueInRow: Bool {
        if case .venue = criterion { return false }
        return true
    }

    private var resolvedTitle: String {
        if case .venue = criterion, let venueName { return "\(venueName)での公演" }
        return criterion.navigationTitle
    }

    /// 年 → その年の公演 (新しい年が先、 年内も新しい順)。
    private var groupedByYear: [(year: String, shows: [Show])] {
        let groups = Dictionary(grouping: shows) { String($0.date.prefix(4)) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shows.isEmpty {
                ImasEmptyState(systemImage: "ticket", title: "公演が見つかりません")
            } else {
                content
            }
        }
        .background(DS.bg)
        .navigationTitle(resolvedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadShows() }
        .trackScreen("filtered_shows")
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groupedByYear.enumerated()), id: \.element.year) { index, group in
                    VStack(alignment: .leading, spacing: 8) {
                        // tight は count を描画しないので渡さない (イベント一覧と同じ見出し)。
                        ImasSectionHeader(title: "\(group.year)年", tight: true)
                            .padding(.horizontal, 16)

                        ImasListContainer {
                            ForEach(Array(group.shows.enumerated()), id: \.element.id) { rowIndex, show in
                                if rowIndex > 0 {
                                    Divider().overlay(DS.sep).padding(.leading, 16)
                                }
                                Button { navigate(.show(show)) } label: { showRow(show) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, index == 0 ? 8 : 18)
                }
                Color.clear.frame(height: 24)
            }
        }
    }

    @ViewBuilder
    private func showRow(_ show: Show) -> some View {
        let event = events[show.eventId]
        ImasLeadRow(
            title: event.map { eventDisplayName($0.name) } ?? show.name,
            subtitle: subtitle(show),
            seed: BrandPalette.hex(for: event?.brandId),
            rainbow: !(event?.jointBrandIdList.isEmpty ?? true)
        )
        .imasCopyable([
            ("ライブ名をコピー", event?.name),
            ("公演名をコピー", show.name),
        ])
    }

    /// 「07/25 · DAY2 · メインアリーナ」。 年はセクション見出しにあるので月日だけ出す。
    private func subtitle(_ show: Show) -> String {
        var parts: [String] = []
        let md = show.date.split(separator: "-")
        parts.append(md.count >= 3 ? "\(md[1])/\(md[2])" : show.date)
        if !show.name.isEmpty { parts.append(show.name) }
        if showsVenueInRow, let venue = venueDirectory.displayName(for: show) ?? show.venue {
            parts.append(venue)
        } else if let hall = show.hall, !hall.isEmpty {
            // 同じ会場でもホールが違えば別物なので、 会場名を省く代わりにホールは出す。
            parts.append(hall)
        }
        return parts.joined(separator: " · ")
    }

    private func loadShows() async {
        isLoading = true
        do {
            shows = try await AppContainer.shared.showReading.shows(criterion: criterion)
            let directory = try await AppContainer.shared.showReading.venueDirectory()
            venueDirectory = directory
            if case .venue(let venueId) = criterion {
                // 一覧の代表は現在名。 各行の「当時の名前」は show ごとに解決する。
                venueName = directory.venue(id: venueId)?.name
            }
            var loaded: [String: Event] = [:]
            for id in Set(shows.map(\.eventId)) {
                if let event = try await AppContainer.shared.eventReading.event(id: id) {
                    loaded[id] = event
                }
            }
            events = loaded
        } catch {
            Logger.database.error("load_failed filtered_shows: \(error.localizedDescription)")
            shows = []
            events = [:]
        }
        isLoading = false
    }
}
