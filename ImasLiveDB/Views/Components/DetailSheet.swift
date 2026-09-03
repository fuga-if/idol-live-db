import os
import NukeUI
import SwiftUI

/// 詳細表示用のモーダルシート（アプリ全体で共通利用）
enum DetailDestination: Identifiable, Hashable {
    case song(Song)
    /// 楽曲詳細を「披露履歴」タブで開く (一覧の披露/回収バッジから直接ジャンプ)。
    case songHistory(Song)
    /// 楽曲詳細を「歌詞」タブで開く (歌詞検索の結果から直接ジャンプ)。
    /// 歌詞タブが載っていないビルドでは `SongDetailTab.resolved` が情報タブに倒す。
    case songLyrics(Song)
    case idol(Idol)
    case event(Event)
    case show(Show)
    case unit(Unit)
    case idolSongHistory(Idol, Song)
    case filteredSongs(SongFilterCriterion)
    case filteredIdols(IdolFilterCriterion)
    case filteredEvents(EventFilterCriterion)
    case filteredShows(ShowFilterCriterion)
    case tagDetail(SongTagEntry)
    /// アイドルタグ (idol_tag_master) 詳細。曲タグとは別プールなので tagDetail とは別ケース。
    case idolTagDetail(SongTagEntry)
    /// ユニットタグ (unit_tag_master) 詳細。曲/アイドルタグとも別プールなので別ケース。
    case unitTagDetail(SongTagEntry)
    /// みんなの投票のお題詳細。実体はサーバ側なので id だけ持ち、画面側で取得する。
    case poll(id: String)

    var id: String {
        switch self {
        case .song(let s): return "song_\(s.id)"
        case .songHistory(let s): return "songHistory_\(s.id)"
        case .songLyrics(let s): return "songLyrics_\(s.id)"
        case .idol(let i): return "idol_\(i.id)"
        case .event(let e): return "event_\(e.id)"
        case .show(let s): return "show_\(s.id)"
        case .unit(let u): return "unit_\(u.id)"
        case .idolSongHistory(let i, let s): return "idolSongHistory_\(i.id)_\(s.id)"
        case .filteredSongs(let c): return "filteredSongs_\(c.navigationTitle)"
        case .filteredIdols(let c): return "filteredIdols_\(c.navigationTitle)"
        case .filteredEvents(let c): return "filteredEvents_\(c.navigationTitle)"
        case .filteredShows(let c): return "filteredShows_\(c.navigationTitle)"
        case .tagDetail(let t): return "tagDetail_\(t.id)"
        case .idolTagDetail(let t): return "idolTagDetail_\(t.id)"
        case .unitTagDetail(let t): return "unitTagDetail_\(t.id)"
        case .poll(let id): return "poll_\(id)"
        }
    }

    // NavigationStack(path:) で push する用の Hashable 実装。
    // 各 case の id (上記) は一意の文字列なので、 id ベースで等価判定 + ハッシュ化する。
    static func == (lhs: DetailDestination, rhs: DetailDestination) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct DetailSheetView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss
    let destination: DetailDestination
    /// 詳細画面間の遷移は同一シート内の NavigationStack push で行う。
    /// 旧実装は sheet on sheet で重ねていたため画面が迷路化していた。
    @State private var path: [DetailDestination] = []

    var body: some View {
        NavigationStack(path: $path) {
            DetailContentView(destination: destination) { path.append($0) }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        dismissButton
                    }
                }
                .navigationDestination(for: DetailDestination.self) { dest in
                    DetailContentView(destination: dest) { path.append($0) }
                }
        }
    }

    private var dismissButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(DS.ink3)
        }
    }
}

/// `DetailDestination` 1 件を実際の詳細画面に解決する唯一の場所。
///
/// シート表示 (`DetailSheetView`) と検索結果からの push (`UnifiedSearchView`) の
/// 両方から使う。ここに集約しておかないと「シートから開いた詳細」と「push で開いた詳細」で
/// 到達できる画面がズレる。子への遷移は呼び出し元の path に委ねる (`navigate`)。
struct DetailContentView: View {
    let destination: DetailDestination
    let navigate: (DetailDestination) -> Void

    var body: some View {
        content(for: destination)
    }

    @ViewBuilder
    private func content(for dest: DetailDestination) -> some View {
        switch dest {
        case .song(let song):
            SongSheetContent(song: song, navigate: { navigate($0) })
                .onAppear { RecentsService.shared.record(kind: .song, id: song.id, name: song.title) }
        case .songHistory(let song):
            SongSheetContent(song: song, initialTab: .history, navigate: { navigate($0) })
                .onAppear { RecentsService.shared.record(kind: .song, id: song.id, name: song.title) }
        case .songLyrics(let song):
            SongSheetContent(song: song, initialTab: .lyrics, navigate: { navigate($0) })
                .onAppear { RecentsService.shared.record(kind: .song, id: song.id, name: song.title) }
        case .idol(let idol):
            // 共通のアイドル詳細 (一覧と同一コンポーネント)。子遷移は共有 path に push。
            IdolDetailView(idol: idol, navigate: { navigate($0) })
                .onAppear { RecentsService.shared.record(kind: .idol, id: idol.id, name: idol.name) }
        case .event(let event):
            EventDetailView(event: event, navigate: { navigate($0) })
        case .show(let show):
            SetlistView(show: show, navigate: { navigate($0) })
        case .unit(let unit):
            UnitDetailView(unit: unit, navigate: { navigate($0) })
        case .idolSongHistory(let idol, let song):
            IdolSongHistoryView(idol: idol, song: song, navigate: { navigate($0) })
        case .filteredSongs(let criterion):
            FilteredSongsView(criterion: criterion, navigate: { navigate($0) })
        case .filteredIdols(let criterion):
            FilteredIdolsView(criterion: criterion, navigate: { navigate($0) })
        case .filteredEvents(let criterion):
            FilteredEventsView(criterion: criterion, navigate: { navigate($0) })
        case .filteredShows(let criterion):
            FilteredShowsView(criterion: criterion, navigate: { navigate($0) })
        case .tagDetail(let tag):
            TagDetailView(tagId: tag.id, tagName: tag.name)
        case .idolTagDetail(let tag):
            IdolTagDetailView(tagId: tag.id, tagName: tag.name)
        case .unitTagDetail(let tag):
            UnitTagDetailView(tagId: tag.id, tagName: tag.name)
        case .poll(let id):
            PollDetailView(pollId: id)
        }
    }

}


// MARK: - Song Sheet Content

/// 楽曲詳細のタブ。
///
/// 表示順は「曲そのものの情報 → 歌詞 → 現場 (履歴) → みんな (コミュニティ)」。
/// 数値インデックスで持つと差し込みのたびに呼び出し側がズレるので列挙で持つ。
enum SongDetailTab: Int, CaseIterable, Hashable {
    case info
    case lyrics
    case history
    case community

    var label: String {
        switch self {
        case .info: return "情報・歌唱"
        case .lyrics: return "歌詞"
        case .history: return "披露履歴"
        case .community: return "コミュニティ"
        }
    }

    /// 分析イベント名の末尾に使う識別子 (日本語ラベルはそのまま送らない)。
    var analyticsKey: String {
        switch self {
        case .info: return "info"
        case .lyrics: return "lyrics"
        case .history: return "history"
        case .community: return "community"
        }
    }

    /// 実際に画面へ出すタブ。歌詞は JASRAC の許諾 (`LyricsFeature`) に従う。
    /// セグメントバーも初期タブもここを唯一の根拠にする。
    static var available: [SongDetailTab] {
        allCases.filter { $0 != .lyrics || LyricsFeature.isAvailable }
    }

    /// 出せないタブを指定されたときの落とし所。ディープリンクや保存された初期タブが
    /// 歌詞を指していても、載っていないビルドでは情報タブに倒す。
    var resolved: SongDetailTab { Self.available.contains(self) ? self : .info }
}

struct SongSheetContent: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme
    let song: Song
    let navigate: (DetailDestination) -> Void

    /// 開く時の初期タブ。
    init(song: Song, initialTab: SongDetailTab = .info, navigate: @escaping (DetailDestination) -> Void) {
        self.song = song
        self.navigate = navigate
        _tab = State(initialValue: initialTab.resolved)
    }

    /// データ取得・整形担当。5系統のロード + 楽曲情報行/クレジットの整形を保持する。
    @State private var vm = DetailSheetViewModel()
    @State private var editSong: Song?
    @State private var showLoginPrompt = false
    @State private var showPenlightVoteSheet = false
    @State private var showTagPicker = false
    // コーレス (SongCall) / 参考動画 (SongVideo) オープン編集 (確定契約 §4)。
    /// コーレス投稿/編集シート。nil=非表示, .create=新規, .edit(call)=編集。
    @State private var callSheet: SongCommunityEditTarget<SongCall>?
    /// 参考動画投稿/編集シート。
    @State private var videoSheet: SongCommunityEditTarget<SongVideo>?
    /// 未ログインで投稿導線を押した時のログイン誘導。
    @State private var showCommunityLoginPrompt = false

    @State private var tab: SongDetailTab
    /// お気に入りトグル後に依存ビューを再評価させるためのバージョン。
    @State private var markVersion = 0

    private var markService: UserMarkService { UserMarkService.shared }

    /// 配色シード。ソロ曲 (オリジナル歌唱が1人) はそのアイドル個人カラーを使い、
    /// それ以外 (ユニット/全体曲やカラー未設定) はブランド色にフォールバックする。
    private var songSeed: String? {
        if vm.originalArtists.count == 1, let color = vm.originalArtists.first?.color, !color.isEmpty {
            return color
        }
        return vm.brand?.color
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                segmentBar
                    .padding(.horizontal, DS.sp5)
                    .padding(.top, DS.sp4)
                    .padding(.bottom, DS.sp1)

                switch tab.resolved {
                case .info: infoTab
                case .lyrics: lyricsTab
                case .history: historyTab
                case .community: communityTab
                }

                Color.clear.frame(height: DS.sp9)
            }
        }
        .background(DS.bg)
        .navigationTitle(song.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if EditPermission.showEditAffordance {
                        Button {
                            if EditPermission.canEdit {
                                editSong = song
                            } else {
                                showLoginPrompt = true
                            }
                        } label: {
                            Label("この楽曲を編集", systemImage: "pencil")
                        }
                    }
                    NavigationLink {
                        EditHistoryView(recordType: "Song", recordName: song.id, title: song.title)
                    } label: {
                        Label("編集履歴", systemImage: "clock.arrow.circlepath")
                    }
                    Divider()
                    // アプリ内の歌詞は「歌詞」タブへ移した (束ね取得に同梱されるので常時表示できる)。
                    // ここに残すのは外部の歌詞サイト検索だけ。
                    Button { openURL(lyricsURL) } label: {
                        Label("歌詞サイトで探す", systemImage: "safari")
                    }
                    if let appleMusicURL = vm.artworkInfo?.appleMusicURL {
                        Button { openURL(appleMusicURL) } label: {
                            Label("Apple Musicで開く", systemImage: "music.note")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $editSong) { s in
            SongEditView(song: s).environment(database)
        }
        .sheet(isPresented: $showLoginPrompt) {
            LoginToEditSheet(onSignedIn: { if EditPermission.canEdit { editSong = song } })
        }
        .sheet(isPresented: $showPenlightVoteSheet) {
            PenlightVoteSheet(songId: song.id) {
                Task { await vm.loadPenlightVotes(song: song) }
            }
        }
        .sheet(isPresented: $showTagPicker) {
            SongTagPicker(songId: song.id, song: SongWithArtists(song: song, artistNames: song.singerLabel ?? "", performerIdols: vm.originalArtists)) {
                Task { await vm.loadSongTags(song: song) }
            }
        }
        .sheet(item: $callSheet) { target in
            callEditSheet(for: target)
        }
        .sheet(item: $videoSheet) { target in
            videoEditSheet(for: target)
        }
        .sheet(isPresented: $showCommunityLoginPrompt) {
            LoginToEditSheet()
        }
        .task { await vm.loadData(song: song) }
        .onChange(of: tab) { _, newTab in
            // 旧「歌詞を見る」は別画面だったので screen として計測できていた。
            // タブ化に伴い、どのタブが見られているかはここで拾う。
            AppAnalytics.tap("song_detail.tab.\(newTab.analyticsKey)")
        }
        .trackScreen("song_detail")
    }

    // MARK: - Hero (大ジャケ + 曲名 + アーティスト + 主要アクション)

    @ViewBuilder
    private var hero: some View {
        let t = ImasTheme.derive(seed: songSeed, scheme: scheme)
        VStack(spacing: DS.sp4) {
            ArtworkImageView(
                url: vm.artworkInfo?.artworkURL,
                size: 168,
                previewURL: vm.artworkInfo?.previewURL,
                songTitle: song.title,
                seed: songSeed
            )

            VStack(spacing: DS.sp1) {
                Text(song.title)
                    .font(.imasTitle2)
                    .foregroundStyle(DS.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .imasCopyable([
                        CopyItem("曲名をコピー", song.title, key: "song_title"),
                        CopyItem("よみをコピー", song.titleKana, key: "kana"),
                        CopyItem("歌唱者をコピー", vm.artistLine(for: song), key: "artists"),
                    ])
                if let artistLine = vm.artistLine(for: song) {
                    Text(artistLine)
                        .font(.imasSubhead)
                        .foregroundStyle(DS.ink2)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, DS.sp5)

            HStack(spacing: DS.sp3) {
                playAction(t)
                favoriteAction(t)
            }
            .padding(.horizontal, DS.sp5)
        }
        .padding(.top, DS.sp4)
        .padding(.bottom, DS.sp5)
        .frame(maxWidth: .infinity)
        .background(t.heroSurface)
    }

    private var isPreviewing: Bool {
        MusicKitService.shared.isPlaying && MusicKitService.shared.nowPlayingTitle == song.title
    }

    @ViewBuilder
    private func playAction(_ t: ImasTheme) -> some View {
        Button {
            AppAnalytics.tap("song_detail.play")
            if let info = vm.artworkInfo, info.musicKitId != nil {
                Task { await playFull(info) }
            } else if let previewURL = vm.artworkInfo?.previewURL {
                MusicKitService.shared.togglePreview(url: previewURL, title: song.title)
            }
        } label: {
            Label(isPreviewing ? "停止" : "再生", systemImage: isPreviewing ? "stop.fill" : "play.fill")
                .font(.imasSubhead.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(t.onAccent)
                .background(t.accent, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(vm.artworkInfo?.previewURL == nil && vm.artworkInfo?.musicKitId == nil)
        .opacity((vm.artworkInfo?.previewURL == nil && vm.artworkInfo?.musicKitId == nil) ? 0.5 : 1)
    }

    private func playFull(_ info: MusicKitSongInfo) async {
        if MusicKitService.shared.isPlaying
            && MusicKitService.shared.isFullPlayback
            && MusicKitService.shared.nowPlayingTitle == song.title {
            MusicKitService.shared.stop()
            return
        }
        if !MusicKitService.shared.hasAppleMusicSubscription {
            await MusicKitService.shared.requestAuthorization()
            guard MusicKitService.shared.hasAppleMusicSubscription else {
                // サブスク無しは fallback でプレビュー再生。
                if let previewURL = info.previewURL {
                    MusicKitService.shared.togglePreview(url: previewURL, title: song.title)
                }
                return
            }
        }
        await MusicKitService.shared.playFull(songInfo: info, title: song.title)
    }

    @ViewBuilder
    private func favoriteAction(_ t: ImasTheme) -> some View {
        let isFav = markService.bool(.favorite, entity: .song, id: song.id)
        Button {
            AppAnalytics.tap("song_detail.toggle_favorite")
            toggleFavorite()
        } label: {
            Label(isFav ? "お気に入り済み" : "お気に入り", systemImage: isFav ? "star.fill" : "star")
                .font(.imasSubhead.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(isFav ? DS.favorite : t.accent)
                .background(t.chipBg, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
        }
        .buttonStyle(.plain)
        .id(markVersion) // toggle 後に再評価
    }

    private func toggleFavorite() {
        do {
            try markService.toggle(.favorite, entity: .song, id: song.id)
            markVersion += 1
        } catch {
            Logger.database.error("toggle_favorite_failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Segmented

    private var segmentBar: some View {
        ImasSegmented(options: SongDetailTab.available, selection: $tab, seed: songSeed) { $0.label }
    }

    // MARK: - Tab: 情報・歌唱

    private var infoTab: some View {
        SongInfoTab(song: song, seed: songSeed, vm: vm, navigate: navigate) {
            // 参加ライブ登録は履歴タブで個別公演を選んでもらう導線。
            tab = .history
        }
    }

    // MARK: - Tab: 歌詞

    /// 歌詞は束ね取得 (`/songs/{id}/detail`) に同梱されるので、常時読み込みでも
    /// リクエストは増えない。中身は `SongLyricsTab` (VM を読むだけ)。
    private var lyricsTab: some View {
        SongLyricsTab(song: song, seed: songSeed, vm: vm) {
            Task { await vm.loadServerData(song: song) }
        }
    }

    // MARK: - Tab: 披露履歴

    private var historyTab: some View {
        SongHistoryTab(song: song, seed: songSeed, vm: vm, navigate: navigate)
    }

    // MARK: - Tab: コミュニティ

    /// 中身は `SongCommunityTab`。ここではシート表示を伴う操作だけ引き受ける。
    private var communityTab: some View {
        SongCommunityTab(song: song, seed: songSeed, vm: vm, navigate: navigate) { intent in
            handle(intent)
        }
    }

    /// コミュニティタブからの要求を、この画面が持つシート状態へ落とす。
    private func handle(_ intent: SongCommunityIntent) {
        switch intent {
        case .addTag:        startCommunityEdit { showTagPicker = true }
        case .createCall:    startCommunityEdit { callSheet = .create }
        case .editCall(let call):   startCommunityEdit { callSheet = .edit(call) }
        case .createVideo:   startCommunityEdit { videoSheet = .create }
        case .editVideo(let video): startCommunityEdit { videoSheet = .edit(video) }
        case .votePenlight:  startCommunityEdit { showPenlightVoteSheet = true }
        case .removeTag(let id):
            Task { await vm.removeSongTag(song: song, tagId: id) }
        }
    }

    // MARK: - Community edit (コーレス / 参考動画) sheets

    @ViewBuilder
    private func callEditSheet(for target: SongCommunityEditTarget<SongCall>) -> some View {
        Group {
            if let call = target.editing {
                CallEditView(call: call) { Task { await vm.loadCommunityContent(song: song) } }
            } else {
                CallEditView(songId: song.id) { Task { await vm.loadCommunityContent(song: song) } }
            }
        }
        .environment(database)
    }

    @ViewBuilder
    private func videoEditSheet(for target: SongCommunityEditTarget<SongVideo>) -> some View {
        Group {
            if let video = target.editing {
                VideoEditView(video: video) { Task { await vm.loadCommunityContent(song: song) } }
            } else {
                VideoEditView(songId: song.id) { Task { await vm.loadCommunityContent(song: song) } }
            }
        }
        .environment(database)
    }

    /// 投稿/編集導線の共通ゲート: 未ログインはログイン誘導、BAN 済みは何もしない、
    /// ログイン済み・未 BAN のみ `present` を実行する (EditPermission に集約)。
    private func startCommunityEdit(_ present: () -> Void) {
        switch EditPermission.rules.outcomeOnEditTap {
        case .present: present()
        case .promptLogin: showCommunityLoginPrompt = true
        case .ignore: break  // BAN 済み。導線自体を出していない。
        }
    }

    private var lyricsURL: URL {
        if let url = URL.safeHTTP(string: song.lyricsUrl) {
            return url
        }
        let encoded = song.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.uta-net.com/search/?Keyword=\(encoded)") ?? URL(string: "https://www.uta-net.com")!
    }
}
/// 旧 IdolRowLabel 互換 (新規実装は IdolNameRow を直接使うこと)。
private typealias IdolRowLabel = IdolNameRow

// MARK: - タップ可能な履歴行コンポーネント

struct ShowHistoryButton: View {
    @Environment(AppDatabase.self) private var database
    let showId: String
    let eventName: String
    let showName: String
    let date: String
    let navigate: (DetailDestination) -> Void

    var body: some View {
        Button {
            Task {
                if let show = try? await AppContainer.shared.showReading.show(id: showId) {
                    navigate(.show(show))
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: DS.sp2) {
                    Text(eventDisplayName(eventName))
                        .font(.imasSubhead)
                        .foregroundStyle(DS.ink)
                    HStack {
                        Text(showName)
                            .font(.imasCaption)
                            .foregroundStyle(DS.ink2)
                        Spacer()
                        Text(date)
                            .font(.imasCaption)
                            .foregroundStyle(DS.ink2)
                    }
                }
                ImasRowChevron()
            }
        }
    }
}


// MARK: - Tappable Value Row

/// 値全体をタップして遷移する汎用行（LabeledContent のスタイルを維持）

// MARK: - Credits Row

/// 作曲者・作詞者・編曲者を分割してタップ可能に表示する行
