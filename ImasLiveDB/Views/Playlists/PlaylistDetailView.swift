import SwiftUI

/// プレイリスト 1 つ。上から順に Apple Music で鳴らす。並べ替え・外すは編集で。
struct PlaylistDetailView: View {
    @State var playlist: Playlist
    @State private var songs: [Song] = []
    @State private var loaded = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var playFailed = false
    @State private var sheetDestination: DetailDestination?

    private var store: any PlaylistStoring { AppContainer.shared.playlists }

    var body: some View {
        Group {
            if loaded && songs.isEmpty {
                VStack {
                    Spacer()
                    ImasEmptyState(systemImage: "music.note", title: "曲がまだありません",
                                   message: "曲の詳細の記号のボタンから足せます。")
                    Spacer()
                }
            } else {
                List {
                    Section {
                        header.listRowBackground(Color.clear).listRowSeparator(.hidden)
                    }
                    ImasListSection("\(songs.count)曲") {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            ImasSongRow(song: song, density: .compact)
                                .contentShape(Rectangle())
                                .onTapGesture { play(from: index) }
                                .swipeActions(edge: .leading) {
                                    Button("詳細") { sheetDestination = .song(song) }
                                }
                        }
                        .onMove(perform: move)
                        .onDelete(perform: remove)
                    }
                }
                .listStyle(.plain)
                .imasForm()
            }
        }
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !songs.isEmpty { EditButton() }
                Menu {
                    Button("名前を変える", systemImage: "pencil") {
                        renameText = playlist.name
                        isRenaming = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("そのほか")
            }
        }
        .alert("名前を変える", isPresented: $isRenaming) {
            TextField("名前", text: $renameText)
            Button("変える") { Task { await rename() } }
            Button("やめる", role: .cancel) {}
        }
        .sheet(item: $sheetDestination) { DetailSheetView(destination: $0) }
        .task { await load() }
        .trackScreen("playlist_detail")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasButton(title: "再生", systemImage: "play.fill", role: .primary, size: .large) {
                AppAnalytics.tap("playlist.play_all")
                play(from: 0)
            }
            if playFailed {
                ImasNote("プレイリストの再生には Apple Music の契約が要ります。", systemImage: "music.note")
            }
            let unplayable = PlaylistPlayback.unplayableCount(songs)
            if unplayable > 0 {
                ImasNote("Apple Music に無い \(unplayable) 曲は飛ばします。", systemImage: "forward.end")
            }
        }
    }

    private func play(from index: Int) {
        Task { playFailed = !(await PlaylistPlayback.play(songs, startAt: index)) }
    }

    private func load() async {
        let ids = (try? await store.songIds(playlistId: playlist.id)) ?? []
        let found = (try? await AppContainer.shared.songReading.songs(ids: ids)) ?? []
        let byId = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        songs = ids.compactMap { byId[$0] }
        loaded = true
    }

    private func move(_ from: IndexSet, _ to: Int) {
        guard let source = from.first else { return }
        // List の to は「抜く前の並びでの挿入位置」。抜いた後の位置に直してコアへ渡す。
        let destination = to > source ? to - 1 : to
        let ids = playlistMoveSong(ids: songs.map(\.id), from: UInt32(source), to: UInt32(destination))
        save(ids)
    }

    private func remove(_ offsets: IndexSet) {
        let removed = Set(offsets.map { songs[$0].id })
        save(songs.map(\.id).filter { !removed.contains($0) })
    }

    private func save(_ ids: [String]) {
        let byId = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        songs = ids.compactMap { byId[$0] }
        Task {
            do { try await store.setSongIds(playlistId: playlist.id, songIds: ids) } catch {
                LocalWriteFailure.report(error, action: "プレイリストの並び替え")
            }
        }
    }

    private func rename() async {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            try await store.rename(id: playlist.id, name: name)
            playlist.name = name
        } catch {
            LocalWriteFailure.report(error, action: "プレイリストの名前の変更")
        }
    }
}
