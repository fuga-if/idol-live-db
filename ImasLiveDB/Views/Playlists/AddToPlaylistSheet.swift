import SwiftUI

/// 曲をプレイリストに足すシート (曲の詳細から)。既に入っているプレイリストには印を付ける。
struct AddToPlaylistSheet: View {
    let song: Song
    @Environment(\.dismiss) private var dismiss
    @State private var summaries: [PlaylistSummary] = []
    @State private var containing: Set<String> = []
    @State private var isNaming = false
    @State private var newName = ""

    private var store: any PlaylistStoring { AppContainer.shared.playlists }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { newName = ""; isNaming = true } label: {
                        ImasNavRow(title: "新しいプレイリスト", systemImage: "plus", showsChevron: false)
                    }
                    .buttonStyle(.imasRow)
                }
                if !summaries.isEmpty {
                    ImasListSection("プレイリスト") {
                        ForEach(summaries) { summary in
                            let added = containing.contains(summary.id)
                            ImasSelectableRow(title: summary.playlist.name, subtitle: "\(summary.songCount)曲",
                                              isSelected: added, isDisabled: added) {
                                Task { await add(to: summary.playlist) }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .imasForm()
            .navigationTitle("プレイリストに追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ImasIconButton(systemImage: "xmark", label: "閉じる", size: .small, style: .plain) { dismiss() }
                }
            }
            .alert("新しいプレイリスト", isPresented: $isNaming) {
                TextField("名前", text: $newName)
                Button("作って足す") { Task { await createAndAdd() } }
                Button("やめる", role: .cancel) {}
            }
        }
        .task { await load() }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        summaries = (try? await store.summaries()) ?? []
        var hits: Set<String> = []
        for summary in summaries {
            if (try? await store.songIds(playlistId: summary.id))?.contains(song.id) == true { hits.insert(summary.id) }
        }
        containing = hits
    }

    private func add(to playlist: Playlist) async {
        AppAnalytics.tap("playlist.add_song")
        do {
            try await store.append(playlistId: playlist.id, songIds: [song.id])
            dismiss()
        } catch {
            LocalWriteFailure.report(error, action: "プレイリストへの追加")
        }
    }

    private func createAndAdd() async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let playlist = try await store.create(name: name)
            await add(to: playlist)
        } catch {
            LocalWriteFailure.report(error, action: "プレイリストの作成")
        }
    }
}
