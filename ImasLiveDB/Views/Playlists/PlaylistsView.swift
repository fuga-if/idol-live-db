import SwiftUI

/// プレイリストの入口。「自分」(端末にだけ保存) と「みんな」(ユーザーが公開したもの) を切り替える。
/// プロデュースタブから開く。
struct PlaylistsView: View {
    @State private var tab = 0
    @State private var summaries: [PlaylistSummary] = []
    @State private var loaded = false
    @State private var isNaming = false
    @State private var newName = ""
    @State private var openPlaylist: Playlist?

    private var store: any PlaylistStoring { AppContainer.shared.playlists }

    var body: some View {
        VStack(spacing: 0) {
            ImasTabs(labels: ["自分", "みんな"], selection: $tab)
                .padding(.horizontal, DS.Space.screen)
                .padding(.vertical, DS.Space.gap)
            if tab == 0 { mine } else { CommunityPlaylistsList() }
        }
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle("プレイリスト")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
        .navigationDestination(item: $openPlaylist) { PlaylistDetailView(playlist: $0) }
        .navigationDestination(for: CommunityPlaylist.self) { CommunityPlaylistDetailView(summary: $0) }
        .alert("新しいプレイリスト", isPresented: $isNaming) {
            TextField("名前", text: $newName)
            Button("作る") { Task { await create() } }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("作ったら、曲を検索して足せます。")
        }
        .task { await load() }
        .trackScreen("playlists")
    }

    /// 自分のプレイリスト。作る入口はいつも一番上に出す (空のときだけでなく)。
    private var mine: some View {
        List {
            Section {
                Button {
                    newName = ""
                    isNaming = true
                } label: {
                    ImasNavRow(title: "新しいプレイリスト", subtitle: "名前を付けて作り、曲を検索して足す",
                               systemImage: "plus", showsChevron: false)
                }
                .buttonStyle(.imasRow)
            } footer: {
                if loaded && summaries.isEmpty {
                    ImasNote("曲の詳細・曲一覧の左スワイプ・歌詞プレイヤーからも足せます。", systemImage: "text.badge.plus")
                }
            }
            if !summaries.isEmpty {
                ImasListSection("\(summaries.count)件") {
                    ForEach(summaries) { summary in
                        NavigationLink(value: summary.playlist) {
                            ImasNavRow(title: summary.playlist.name, subtitle: subtitle(summary),
                                       systemImage: "music.note.list", showsChevron: false)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .listStyle(.plain)
        .imasForm()
        .refreshable { await load() }
    }

    private func subtitle(_ summary: PlaylistSummary) -> String {
        summary.playlist.publishedId == nil ? "\(summary.songCount)曲" : "\(summary.songCount)曲 · 公開中"
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
            let playlist = try await store.create(name: name)
            await load()
            // 作ったらそのまま中へ入れて、曲を足すところから始めてもらう。
            openPlaylist = playlist
        } catch {
            LocalWriteFailure.report(error, action: "プレイリストの作成")
        }
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

/// みんなのプレイリストの一覧 (新しく更新された順)。下まで来たら続きを取る。
private struct CommunityPlaylistsList: View {
    @State private var playlists: [CommunityPlaylist] = []
    @State private var next: String?
    @State private var loaded = false
    @State private var failed = false
    @State private var songsById: [String: Song] = [:]

    private var api: any CommunityPlaylistStoring { AppContainer.shared.communityPlaylists }

    var body: some View {
        Group {
            if failed && playlists.isEmpty {
                VStack { Spacer(); ImasEmptyState(systemImage: "wifi.slash", title: "読み込めませんでした"); Spacer() }
            } else if loaded && playlists.isEmpty {
                VStack {
                    Spacer()
                    ImasEmptyState(systemImage: "music.note.list", title: "まだ公開されたプレイリストがありません",
                                   message: "自分のプレイリストを開いて、そのほかから公開できます。")
                    Spacer()
                }
                .padding(.horizontal, DS.Space.screen)
            } else {
                List {
                    ForEach(playlists) { playlist in
                        NavigationLink(value: playlist) { row(playlist) }
                            .onAppear { if playlist.id == playlists.last?.id { Task { await loadMore() } } }
                    }
                }
                .listStyle(.plain)
                .imasForm()
                .refreshable { await reload() }
            }
        }
        .task { if !loaded { await reload() } }
    }

    private func row(_ playlist: CommunityPlaylist) -> some View {
        let first = playlist.songIds.first.flatMap { songsById[$0] }
        let subtitle = [String(playlist.songCount) + "曲", playlist.description].compactMap { $0 }.joined(separator: " · ")
        return ImasRow(title: playlist.title, subtitle: subtitle,
                       leading: .artwork(title: first?.title ?? playlist.title, seed: BrandColors.hex(for: first?.brandId),
                                         imageURL: first?.artworkUrl.flatMap(URL.init(string:))),
                       density: .compact)
    }

    private func reload() async {
        do {
            let page = try await api.page(before: nil)
            playlists = page.playlists
            next = page.next
            failed = false
            await resolveSongs(page.playlists)
        } catch {
            failed = true
        }
        loaded = true
    }

    private func loadMore() async {
        guard let cursor = next else { return }
        next = nil
        guard let page = try? await api.page(before: cursor) else { next = cursor; return }
        playlists += page.playlists.filter { p in !playlists.contains { $0.id == p.id } }
        next = page.next
        await resolveSongs(page.playlists)
    }

    /// 一覧のジャケに使う先頭の曲を端末のカタログから引く。
    private func resolveSongs(_ page: [CommunityPlaylist]) async {
        let ids = page.compactMap(\.songIds.first).filter { songsById[$0] == nil }
        guard !ids.isEmpty, let songs = try? await AppContainer.shared.songReading.songs(ids: ids) else { return }
        for song in songs { songsById[song.id] = song }
    }
}
