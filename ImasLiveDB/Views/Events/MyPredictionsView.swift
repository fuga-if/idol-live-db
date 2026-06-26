import SwiftUI

/// 「マイ予想」: 自分がセトリ予想で投票した曲を公演別にまとめて表示する。
/// API はコミュニティデータ (show_id/song_id/vote_count) のみ返し、曲名・公演は local 解決。
struct MyPredictionsView: View {
    @Environment(AppDatabase.self) private var database

    @State private var groups: [ShowGroup] = []
    @State private var isLoading = true
    @State private var sheetDestination: DetailDestination?

    private var isSignedIn: Bool { AuthService.shared.isSignedIn }

    private struct Entry: Identifiable {
        let song: Song
        let voteCount: Int
        var id: String { song.id }
    }
    private struct ShowGroup: Identifiable {
        let show: Show
        let entries: [Entry]
        var id: String { show.id }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !isSignedIn {
                ContentUnavailableView(
                    "ログインが必要です",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Apple Sign In すると、投票した予想がここにまとまります")
                )
            } else if groups.isEmpty {
                ContentUnavailableView(
                    "まだ予想していません",
                    systemImage: "music.note.list",
                    description: Text("未来公演のセトリ予想で投票すると、ここに表示されます")
                )
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                Button { sheetDestination = .song(entry.song) } label: {
                                    HStack(spacing: DS.sp2) {
                                        SongTitleRow(song: entry.song, showsChevron: false)
                                        Label("\(entry.voteCount)", systemImage: "hand.thumbsup.fill")
                                            .font(.imasCaption)
                                            .foregroundStyle(DS.ink2)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Button { sheetDestination = .show(group.show) } label: {
                                HStack {
                                    Text(group.show.name).textCase(nil)
                                    Spacer()
                                    Text(group.show.date).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("マイ予想")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheetDestination) { dest in
            DetailSheetView(destination: dest).environment(database)
        }
        .task { await load() }
        .trackScreen("my_predictions")
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard isSignedIn else { groups = []; return }
        guard let dtos = try? await PredictionService.shared.myPredictions() else { groups = []; return }

        // 曲を local カタログから一括解決。
        let songs = (try? await AppContainer.shared.songReading.songs(ids: dtos.map(\.songId))) ?? []
        let songsById = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })

        // 公演ごとにグルーピング (dtos は votedAt 降順なので出現順を維持)。
        var order: [String] = []
        var byShow: [String: [Entry]] = [:]
        for dto in dtos {
            guard let song = songsById[dto.songId] else { continue }
            if byShow[dto.showId] == nil { order.append(dto.showId) }
            byShow[dto.showId, default: []].append(Entry(song: song, voteCount: dto.voteCount))
        }

        var resolved: [ShowGroup] = []
        for showId in order {
            guard let show = try? await AppContainer.shared.showReading.show(id: showId),
                  let entries = byShow[showId] else { continue }
            resolved.append(ShowGroup(show: show, entries: entries))
        }
        groups = resolved
    }
}
