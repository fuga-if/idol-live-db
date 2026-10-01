import os
import SwiftUI

struct FilteredSongsView: View {
    @Environment(AppDatabase.self) private var database
    let criterion: SongFilterCriterion
    let navigate: (DetailDestination) -> Void

    @State private var songs: [SongWithArtists] = []
    @State private var songsWithRoles: [SongWithRoles] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ImasLoadingState()
            } else {
                switch criterion {
                case .creator:
                    if songsWithRoles.isEmpty {
                        ImasEmptyState(systemImage: "music.note.list", title: "楽曲が見つかりません")
                    } else {
                        creatorList
                    }
                default:
                    if songs.isEmpty {
                        ImasEmptyState(systemImage: "music.note.list", title: "楽曲が見つかりません")
                    } else {
                        standardList
                    }
                }
            }
        }
        .navigationTitle(criterion.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSongs() }
        .trackScreen("filtered_songs")
    }

    private var standardList: some View {
        List {
            ImasListSummary<Int>(count: songs.count, unit: "曲")
                .listRowInsets(EdgeInsets())
                .listRowBackground(DS.bg)
                .listRowSeparator(.hidden)
            ForEach(songs) { item in
                Button {
                    navigate(.song(item.song))
                } label: {
                    SongRowView(item: item)
                }
                .buttonStyle(.plain)
            }
        }
        .imasList()
    }

    private var creatorList: some View {
        List {
            ImasListSummary<Int>(count: songsWithRoles.count, unit: "曲")
                .listRowInsets(EdgeInsets())
                .listRowBackground(DS.bg)
                .listRowSeparator(.hidden)
            ForEach(songsWithRoles) { item in
                Button {
                    navigate(.song(item.song))
                } label: {
                    VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                        SongRowView(item: SongWithArtists(song: item.song, artistNames: item.song.singerLabel ?? ""))
                        Text(item.rolesLabel)
                            .font(.imasCaption2)
                            .foregroundStyle(DS.ink2)
                            .padding(.leading, 62)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .imasList()
    }

    private func loadSongs() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if case .creator(let name) = criterion {
                songsWithRoles = try await AppContainer.shared.songReading.songsByCreator(name)
            } else {
                songs = try await AppContainer.shared.songReading.songs(criterion: criterion)
            }
        } catch {
            Logger.database.error("load_failed filtered_songs: \(error.localizedDescription)")
            songs = []
            songsWithRoles = []
        }
    }
}
