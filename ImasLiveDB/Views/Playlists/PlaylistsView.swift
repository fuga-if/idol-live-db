import SwiftUI

/// プレイリストの一覧。プロデュースタブから開く。プレイリストは端末にだけ保存する。
struct PlaylistsView: View {
    @State private var summaries: [PlaylistSummary] = []
    @State private var loaded = false
    @State private var isNaming = false
    @State private var newName = ""

    private var store: any PlaylistStoring { AppContainer.shared.playlists }

    var body: some View {
        Group {
            if loaded && summaries.isEmpty {
                VStack(spacing: DS.sp5) {
                    Spacer()
                    ImasEmptyState(systemImage: "music.note.list", title: "プレイリストがありません",
                                   message: "曲の詳細の記号のボタンから、曲を足せます。")
                    ImasButton(title: "新しいプレイリスト", systemImage: "plus", role: .primary) { beginNaming() }
                    Spacer()
                }
                .padding(.horizontal, DS.Space.screen)
            } else {
                List {
                    ImasListSection("\(summaries.count)件") {
                        ForEach(summaries) { summary in
                            NavigationLink(value: summary.playlist) {
                                ImasNavRow(title: summary.playlist.name, subtitle: "\(summary.songCount)曲",
                                           systemImage: "music.note.list", showsChevron: false)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
                .listStyle(.plain)
                .imasForm()
            }
        }
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle("プレイリスト")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ImasIconButton(systemImage: "plus", label: "新しいプレイリスト", size: .small, style: .plain) {
                    beginNaming()
                }
            }
        }
        .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
        .alert("新しいプレイリスト", isPresented: $isNaming) {
            TextField("名前", text: $newName)
            Button("作る") { Task { await create() } }
            Button("やめる", role: .cancel) {}
        }
        .task { await load() }
        .trackScreen("playlists")
    }

    private func beginNaming() {
        newName = ""
        isNaming = true
    }

    private func load() async {
        summaries = (try? await store.summaries()) ?? []
        loaded = true
    }

    private func create() async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        AppAnalytics.tap("playlists.create")
        do {
            _ = try await store.create(name: name)
        } catch {
            LocalWriteFailure.report(error, action: "プレイリストの作成")
        }
        await load()
    }

    private func delete(_ offsets: IndexSet) {
        let ids = offsets.map { summaries[$0].id }
        Task {
            for id in ids {
                do { try await store.delete(id: id) } catch {
                    LocalWriteFailure.report(error, action: "プレイリストの削除")
                }
            }
            await load()
        }
    }
}
