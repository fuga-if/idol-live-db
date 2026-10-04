import SwiftUI

/// プレイリスト 1 つ。上から順に Apple Music で鳴らす。並べ替え・外すは編集で。
/// 曲は「曲を足す」で検索して足す。そのほかから「みんなのプレイリスト」に公開できる。
struct PlaylistDetailView: View {
    @Environment(AppDatabase.self) private var database
    @State var playlist: Playlist
    @State private var songs: [Song] = []
    @State private var loaded = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var playFailed = false
    @State private var sheetDestination: DetailDestination?
    @State private var showsPicker = false
    @State private var isPublishing = false
    @State private var publishTitle = ""
    @State private var publishDescription = ""
    @State private var showsLoginPrompt = false
    @State private var publishMessage: String?

    private var store: any PlaylistStoring { AppContainer.shared.playlists }

    var body: some View {
        Group {
            if loaded && songs.isEmpty {
                VStack(spacing: DS.sp5) {
                    Spacer()
                    ImasEmptyState(systemImage: "music.note", title: "曲がまだありません",
                                   message: "曲を検索して足しましょう。曲の詳細や曲一覧の左スワイプからも足せます。")
                    ImasButton(title: "曲を足す", systemImage: "plus", role: .primary) { showsPicker = true }
                    Spacer()
                }
                .padding(.horizontal, DS.Space.screen)
            } else {
                List {
                    Section {
                        header.listRowBackground(Color.clear).listRowSeparator(.hidden)
                    }
                    Section {
                        Button { showsPicker = true } label: {
                            ImasNavRow(title: "曲を足す", systemImage: "plus", showsChevron: false)
                        }
                        .buttonStyle(.imasRow)
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
                    if !songs.isEmpty {
                        Button(playlist.publishedId == nil ? "みんなに公開する" : "公開中の中身を更新する",
                               systemImage: "person.2") { beginPublish() }
                    }
                    if playlist.publishedId != nil {
                        Button("公開をやめる", systemImage: "eye.slash", role: .destructive) {
                            Task { await unpublish() }
                        }
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
        .alert(playlist.publishedId == nil ? "みんなに公開する" : "公開中の中身を更新する", isPresented: $isPublishing) {
            TextField("タイトル (40 文字まで)", text: $publishTitle)
            TextField("ひとこと (なくてもよい)", text: $publishDescription)
            Button(playlist.publishedId == nil ? "公開する" : "更新する") { Task { await publish() } }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("タイトル・ひとこと・曲の並びが「みんなのプレイリスト」に載ります。名前は出ません。")
        }
        .alert(publishMessage ?? "", isPresented: Binding(get: { publishMessage != nil },
                                                          set: { if !$0 { publishMessage = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .sheet(isPresented: $showsLoginPrompt) { LoginToEditSheet() }
        .sheet(isPresented: $showsPicker) {
            SongSearchPickerView { picked in
                Task { await add(picked) }
            }
            .environment(database)
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

    private func add(_ picked: [Song]) async {
        guard !picked.isEmpty else { return }
        AppAnalytics.tap("playlist.add_from_picker")
        do {
            try await store.append(playlistId: playlist.id, songIds: picked.map(\.id))
        } catch {
            LocalWriteFailure.report(error, action: "プレイリストへの追加")
        }
        await load()
    }

    private func beginPublish() {
        switch EditPermission.rules.outcomeOnEditTap {
        case .present:
            publishTitle = playlist.name
            publishDescription = ""
            isPublishing = true
        case .promptLogin: showsLoginPrompt = true
        case .ignore: break
        }
    }

    private var communityAPI: any CommunityPlaylistStoring { AppContainer.shared.communityPlaylists }

    private func publish() async {
        let title = publishTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let description = publishDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = CommunityPlaylistInput(title: String(title.prefix(40)),
                                           description: description.isEmpty ? nil : String(description.prefix(200)),
                                           songIds: songs.map(\.id))
        AppAnalytics.tap(playlist.publishedId == nil ? "playlist.publish" : "playlist.update_published")
        do {
            let published: CommunityPlaylist
            if let id = playlist.publishedId {
                published = try await communityAPI.update(id: id, input)
            } else {
                published = try await communityAPI.publish(input)
            }
            try await store.setPublishedId(playlistId: playlist.id, publishedId: published.id)
            playlist.publishedId = published.id
            publishMessage = "公開しました。みんなのプレイリストに数分で並びます。"
        } catch {
            publishMessage = "公開できませんでした。\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    private func unpublish() async {
        guard let id = playlist.publishedId else { return }
        do {
            try await communityAPI.remove(id: id)
            try await store.setPublishedId(playlistId: playlist.id, publishedId: nil)
            playlist.publishedId = nil
        } catch {
            publishMessage = "公開をやめられませんでした。\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
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
