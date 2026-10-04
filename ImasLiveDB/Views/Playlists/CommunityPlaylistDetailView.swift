import SwiftUI

/// みんなのプレイリスト 1 つ。そのまま再生するか、自分のプレイリストとして保存する。
/// 自分が公開したもの・モデレーターは取り下げられる。
struct CommunityPlaylistDetailView: View {
    /// 一覧で取った分 (曲は先頭だけ)。開いたら全曲を取り直す。
    let summary: CommunityPlaylist
    @Environment(\.dismiss) private var dismiss
    @State private var playlist: CommunityPlaylist?
    @State private var songs: [Song] = []
    @State private var loaded = false
    @State private var playFailed = false
    @State private var message: String?
    @State private var sheetDestination: DetailDestination?
    @State private var isOwn = false

    private var api: any CommunityPlaylistStoring { AppContainer.shared.communityPlaylists }
    private var current: CommunityPlaylist { playlist ?? summary }

    var body: some View {
        List {
            Section {
                header.listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            if loaded {
                ImasListSection("\(songs.count)曲") {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        ImasSongRow(song: song, density: .compact)
                            .contentShape(Rectangle())
                            .onTapGesture { play(from: index) }
                            .swipeActions(edge: .leading) {
                                Button("詳細") { sheetDestination = .song(song) }
                            }
                    }
                }
            }
        }
        .listStyle(.plain)
        .imasForm()
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("自分のプレイリストに保存", systemImage: "square.and.arrow.down") {
                        Task { await saveCopy() }
                    }
                    if isOwn || AuthService.shared.isAdmin {
                        Button(isOwn ? "公開をやめる" : "非表示にする (モデレーター)", systemImage: "eye.slash",
                               role: .destructive) { Task { await remove() } }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("そのほか")
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .sheet(item: $sheetDestination) { DetailSheetView(destination: $0) }
        .task { await load() }
        .trackScreen("community_playlist_detail")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            if let description = current.description, !description.isEmpty {
                Text(description).imasText(.body).fixedSize(horizontal: false, vertical: true)
            }
            ImasButton(title: "再生", systemImage: "play.fill", role: .primary, size: .large) {
                AppAnalytics.tap("community_playlist.play_all")
                play(from: 0)
            }
            .disabled(songs.isEmpty)
            if playFailed {
                ImasNote("プレイリストの再生には Apple Music の契約が要ります。", systemImage: "music.note")
            }
            let unplayable = PlaylistPlayback.unplayableCount(songs)
            if unplayable > 0 {
                ImasNote("Apple Music に無い \(unplayable) 曲は飛ばします。", systemImage: "forward.end")
            }
            let unknown = current.songCount - songs.count
            if loaded && unknown > 0 {
                // 端末のカタログにまだ無い曲 (新曲の取り込み待ち) は出せない。
                ImasNote("この端末にまだ無い \(unknown) 曲は表示していません。", systemImage: "arrow.down.circle")
            }
        }
    }

    private func load() async {
        let full = (try? await api.playlist(id: summary.id)) ?? summary
        playlist = full
        let found = (try? await AppContainer.shared.songReading.songs(ids: full.songIds)) ?? []
        let byId = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        songs = full.songIds.compactMap { byId[$0] }
        loaded = true
        if AuthService.shared.isSignedIn, let mine = try? await api.mine() {
            isOwn = mine.contains { $0.id == summary.id }
        }
    }

    private func play(from index: Int) {
        Task { playFailed = !(await PlaylistPlayback.play(songs, startAt: index)) }
    }

    private func saveCopy() async {
        AppAnalytics.tap("community_playlist.save_copy")
        do {
            _ = try await AppContainer.shared.playlists.saveCopy(of: current)
            message = "自分のプレイリストに保存しました。"
        } catch {
            LocalWriteFailure.report(error, action: "プレイリストの保存")
        }
    }

    private func remove() async {
        do {
            try await api.remove(id: summary.id)
            dismiss()
        } catch {
            message = "取り下げられませんでした。\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }
}
