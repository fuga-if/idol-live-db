import SwiftUI

/// 「マイ予想」: 自分がセトリ予想で投票した曲を公演別にまとめて表示する。
/// API はコミュニティデータ (show_id/song_id/vote_count) のみ返し、曲名・公演は local 解決。
struct MyPredictionsView: View {
    @Environment(AppDatabase.self) private var database

    @State private var groups: [ShowGroup] = []
    /// 読んだ票 (新しい順)。50 件ずつ読み足し、公演ごとのまとまりはここから組み直す。
    @State private var dtos: [MyPredictionDTO] = []
    @State private var hasMore = false
    @State private var isLoadingMore = false
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
                ImasLoadingState()
            } else if !isSignedIn {
                ImasEmptyState(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: "ログインが必要です",
                    message: "Apple Sign In すると、投票した予想がここにまとまります"
                )
            } else if groups.isEmpty {
                ImasEmptyState(
                    systemImage: "music.note.list",
                    title: "まだ予想していません",
                    message: "未来公演のセトリ予想で投票すると、ここに表示されます"
                )
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                // Button でラップすると内側のジャケ写プレビュー再生タップが
                                // 吸われるため、行全体は onTapGesture で遷移を受ける。
                                HStack(spacing: DS.Space.gap) {
                                    SongTitleRow(song: entry.song, showsChevron: false)
                                    ImasBadge(text: "\(entry.voteCount)", kind: .neutral, systemImage: "hand.thumbsup.fill")
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { sheetDestination = .song(entry.song) }
                            }
                        } header: {
                            Button { sheetDestination = .show(group.show) } label: {
                                HStack {
                                    Text(group.show.name).imasText(.sectionLabel).textCase(nil)
                                    Spacer()
                                    Text(group.show.date).imasText(.meta)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    // 末尾まで来たら古い予想を読み足す (一度に全件は読まない)。
                    if hasMore {
                        ImasInlineLoading()
                            .onAppear { Task { await loadMore() } }
                    }
                }
                .imasList()
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

    private static let pageSize = 50

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard isSignedIn else { groups = []; return }
        guard let page = try? await PredictionService.shared.myPredictions(limit: Self.pageSize) else {
            groups = []; return
        }
        dtos = page
        hasMore = page.count == Self.pageSize
        groups = await resolveGroups(dtos)
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore, let last = dtos.last else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let page = try? await PredictionService.shared.myPredictions(after: last, limit: Self.pageSize) else {
            return
        }
        dtos += page
        hasMore = page.count == Self.pageSize
        groups = await resolveGroups(dtos)
    }

    private func resolveGroups(_ dtos: [MyPredictionDTO]) async -> [ShowGroup] {
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
        return resolved
    }
}
