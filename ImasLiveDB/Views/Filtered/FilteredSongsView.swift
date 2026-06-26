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
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch criterion {
                case .creator:
                    if songsWithRoles.isEmpty {
                        ContentUnavailableView("楽曲が見つかりません", systemImage: "music.note.list")
                    } else {
                        creatorList
                    }
                default:
                    if songs.isEmpty {
                        ContentUnavailableView("楽曲が見つかりません", systemImage: "music.note.list")
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
            Section {
                ForEach(songs) { item in
                    Button {
                        navigate(.song(item.song))
                    } label: {
                        SongRowView(item: item)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("\(songs.count)曲")
                    .font(.imasCaption)
            }
        }
        .listStyle(.plain)
    }

    private var creatorList: some View {
        List {
            Section {
                ForEach(songsWithRoles) { item in
                    Button {
                        navigate(.song(item.song))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            SongRowView(item: SongWithArtists(song: item.song, artistNames: item.song.singerLabel ?? ""))
                            Text(item.rolesLabel)
                                .font(.imasScaled(11))
                                .foregroundStyle(.tint)
                                .padding(.leading, 62)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("\(songsWithRoles.count)曲")
                    .font(.imasCaption)
            }
        }
        .listStyle(.plain)
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
