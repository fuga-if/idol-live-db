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
            ImasSegmented(labels: Tab.allCases.map(\.label), selection: $section)
                .padding(.horizontal, DS.sp5)
                .padding(.vertical, DS.sp3)

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
                    Section {
                        ForEach(songs) { song in
                            // Button でラップすると内側のジャケ写プレビュー再生タップが
                            // 吸われるため、行全体は onTapGesture で遷移を受ける。
                            SongTitleRow(song: song, showsChevron: false)
                                .contentShape(Rectangle())
                                .onTapGesture { sheetDestination = .song(song) }
                                .listRowBackground(DS.surface)
                                .listRowSeparatorTint(DS.sep)
                        }
                    } header: {
                        Text("\(songs.count)曲").font(.imasCaption).foregroundStyle(DS.ink2)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        case .idol:
            if idols.isEmpty {
                emptyState(icon: "person.fill", title: "お気に入りのアイドルがいません")
            } else {
                List {
                    Section {
                        ForEach(idols) { idol in
                            Button { sheetDestination = .idol(idol) } label: {
                                HStack(spacing: DS.sp3) {
                                    IdolAvatarView(idol: idol, size: 36)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(idol.name).font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                                        if let cv = idol.currentVoiceActor, !cv.isEmpty {
                                            Text("CV: \(cv)").font(.imasCaption).foregroundStyle(DS.ink3)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(DS.surface)
                            .listRowSeparatorTint(DS.sep)
                        }
                    } header: {
                        Text("\(idols.count)人").font(.imasCaption).foregroundStyle(DS.ink2)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        case .event:
            if events.isEmpty {
                emptyState(icon: "music.mic", title: "お気に入りのライブがありません")
            } else {
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
                        Text("\(events.count)件").font(.imasCaption).foregroundStyle(DS.ink2)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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
