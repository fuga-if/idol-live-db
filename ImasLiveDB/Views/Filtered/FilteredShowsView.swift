import os
import SwiftUI

/// 「この会場での公演」「この日の公演」の一覧。
///
/// 会場での一覧は 20〜30 公演が数年にまたがるので、 イベント一覧と同じく **年で束ねる**。
/// 行の作りもイベント一覧 (ImasSectionHeader + ImasCardList + ImasLeadBar) に揃える。
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

    /// 年ごとの塊 (新しい年が先・年が読めない公演は末尾の「日程未定」)。
    /// 見出し (`2026年`) と並びはコアの `group_indices_by_year_desc`。塊の中は渡した並び。
    private var groupedByYear: [(year: String, shows: [Show])] {
        groupIndicesByYearDesc(dates: shows.map(\.date)).map { group in
            (year: group.label, shows: group.indices.map { shows[Int($0)] })
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ImasLoadingState()
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

    // ⚠️ ここは **List でなければならない**。行をスワイプしての参加登録 (`attendanceSwipe`) は
    // List の行にしか効かず、ScrollView + LazyVStack に付けても無言で消える
    // (習熟度画面のスワイプが同じ理由で一度死んでいる)。
    //
    // 行を半券 (`ImasShowRow`) にしてからは、行どうしがカードへ入れ子にならず
    // それぞれ自分の形を持つので、グループの先頭/末尾で角丸を描き分ける計算は要らない
    // (イベント一覧 `EventListView` で突き当たった実機スクロールの不具合もこれで避けられる)。
    private var content: some View {
        List {
            ForEach(groupedByYear, id: \.year) { group in
                ImasDateHeader(big: group.year)
                    .padding(.horizontal, DS.Space.screen)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(DS.bg)
                    .listRowSeparator(.hidden)

                ForEach(group.shows) { show in
                    Button { navigate(.show(show)) } label: { showRow(show) }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: DS.Space.screen, bottom: 4, trailing: DS.Space.screen))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .attendanceSwipe(show: show, event: events[show.eventId])
                }
            }
            Color.clear.frame(height: DS.Space.section)
                .listRowInsets(EdgeInsets())
                .listRowBackground(DS.bg)
                .listRowSeparator(.hidden)
        }
        .imasList()
        .environment(\.defaultMinListRowHeight, 0)
    }

    @ViewBuilder
    private func showRow(_ show: Show) -> some View {
        let event = events[show.eventId]
        ImasShowRow(
            date: show.date,
            title: event.map { eventDisplayName($0.name) } ?? show.name,
            subtitle: subtitle(show),
            brandHex: BrandColors.hex(for: event?.brandId),
            rainbow: !(event?.jointBrandIdList.isEmpty ?? true),
            showsChevron: true
        )
        .imasCopyable([
            CopyItem("ライブ名をコピー", event?.name, key: "event_name"),
            CopyItem("公演名をコピー", show.name, key: "show_name"),
        ])
    }

    /// 「DAY2 · メインアリーナ」。 年は見出し、月日は半券の日付欄にあるので、ここは公演名と会場だけ。
    private func subtitle(_ show: Show) -> String? {
        var parts: [String] = []
        if !show.name.isEmpty { parts.append(show.name) }
        if showsVenueInRow, let venue = venueDirectory.displayName(for: show) ?? show.venue {
            parts.append(venue)
        } else if let hall = show.hall, !hall.isEmpty {
            // 同じ会場でもホールが違えば別物なので、 会場名を省く代わりにホールは出す。
            parts.append(hall)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
