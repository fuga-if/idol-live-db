import SwiftUI

/// お気に入り一覧。曲・アイドル・イベントをセグメントで切替できる。
/// プロデュースタブの「お気に入り」タイルから飛ぶ。
struct FavoritesListView: View {
    @Environment(AppDatabase.self) private var database

    enum Tab: Int, CaseIterable {
        case song, idol, event
        var label: String {
            switch self {
            case .song:  return "曲"
            case .idol:  return "アイドル"
            case .event: return "ライブ"
            }
        }
    }

    @State private var section: Int = 0
    @State private var songs: [Song] = []
    @State private var idols: [Idol] = []
    @State private var events: [EventWithDate] = []
    @State private var loaded = false
    @State private var sheetDestination: DetailDestination?

    private var currentTab: Tab { Tab(rawValue: section) ?? .song }

    var body: some View {
        VStack(spacing: 0) {
            ImasTabs(labels: Tab.allCases.map(\.label), selection: $section)
                .padding(.horizontal, DS.Space.screen)
                .padding(.vertical, DS.Space.gap)

            content
        }
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle("お気に入り")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !loaded { await load() } }
        .sheet(item: $sheetDestination) { dest in
            DetailSheetView(destination: dest).environment(database)
        }
        .trackScreen("favorites_list")
    }

    @ViewBuilder
    private var content: some View {
        switch currentTab {
        case .song:
            if songs.isEmpty {
                emptyState(icon: "music.note", title: "お気に入りの曲がありません")
            } else {
                List {
                    ImasListSection("\(songs.count)曲") {
                        ForEach(songs) { song in
                            // Button でラップすると内側のジャケ写プレビュー再生タップが
                            // 吸われるため、行全体は onTapGesture で遷移を受ける。
                            ImasSongRow(song: song, density: .compact)
                                .contentShape(Rectangle())
                                .onTapGesture { sheetDestination = .song(song) }
                        }
                    }
                }
                .listStyle(.plain)
                .imasForm()
            }
        case .idol:
            if idols.isEmpty {
                emptyState(icon: "person.fill", title: "お気に入りのアイドルがいません")
            } else {
                List {
                    ImasListSection("\(idols.count)人") {
                        ForEach(idols) { idol in
                            Button {
                                sheetDestination = .idol(idol)
                            } label: {
                                ImasIdolRow(idol: idol, subtitle: VoiceActorDirectory.shared.current(for: idol.id).flatMap { $0.isEmpty ? nil : "CV: \($0)" })
                            }
                            .buttonStyle(.imasRow)
                        }
                    }
                }
                .listStyle(.plain)
                .imasForm()
            }
        case .event:
            if events.isEmpty {
                emptyState(icon: "music.mic", title: "お気に入りのライブがありません")
            } else {
                List {
                    ImasListSection("\(events.count)件") {
                        ForEach(events) { ew in
                            NavigationLink(value: ew.event) {
                                ImasEventRow(event: ew.event, date: ew.firstDate, subtitle: ew.dateRange)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .imasForm()
            }
        }
    }

    private func emptyState(icon: String, title: String) -> some View {
        VStack { Spacer(); ImasEmptyState(systemImage: icon, title: title); Spacer() }
    }

    private func load() async {
        loaded = true
        let mark = AppContainer.shared.markReading
        let songIds = (try? await mark.markedEntityIds(entity: .song, kind: .favorite)) ?? []
        let idolIds = (try? await mark.markedEntityIds(entity: .idol, kind: .favorite)) ?? []
        let eventIds = (try? await mark.markedEntityIds(entity: .event, kind: .favorite)) ?? []

        if !songIds.isEmpty {
            songs = (try? await AppContainer.shared.songReading.songs(ids: songIds)) ?? []
        }
        if !idolIds.isEmpty {
            idols = (try? await AppContainer.shared.idolReading.idols(ids: idolIds)) ?? []
        }
        if !eventIds.isEmpty {
            events = (try? await AppContainer.shared.eventReading.eventsByIds(eventIds)) ?? []
        }
    }
}
