import NukeUI
import SwiftUI

/// 詳細表示用のモーダルシート（アプリ全体で共通利用）
enum DetailDestination: Identifiable, Hashable {
    case song(Song)
    /// 楽曲詳細を「披露履歴」タブで開く (一覧の披露/回収バッジから直接ジャンプ)。
    case songHistory(Song)
    /// 楽曲詳細を「歌詞」タブで開く (歌詞検索の結果から直接ジャンプ)。
    /// 歌詞タブが載っていないビルドでは `SongDetailTab.resolved` が情報タブに倒す。
    /// `focusLineIds` を渡すとその行までスクロールして色を敷く (歌詞クイズの出題箇所)。
    case songLyrics(Song, focusLineIds: [String] = [])
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
    /// 衣装 1 着の着用公演一覧 (イベントをまたぐ)。
    case costume(CostumeRecord)

    var id: String {
        switch self {
        case .song(let s): return "song_\(s.id)"
        case .songHistory(let s): return "songHistory_\(s.id)"
        case .songLyrics(let s, let focus): return "songLyrics_\(s.id)_\(focus.joined(separator: ","))"
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
        case .costume(let c): return "costume_\(c.id)"
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
        case .songLyrics(let song, let focus):
            SongSheetContent(song: song, initialTab: .lyrics, lyricsFocus: focus, navigate: { navigate($0) })
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
        case .costume(let costume):
            CostumeShowsView(costume: costume, navigate: { navigate($0) })
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

    /// 歌詞タブで示す行 (歌詞クイズの出題箇所)。歌詞が届いたら最初の行までスクロールする。
    let lyricsFocus: [String]

    /// 開く時の初期タブ。
    init(song: Song, initialTab: SongDetailTab = .info, lyricsFocus: [String] = [],
         navigate: @escaping (DetailDestination) -> Void) {
        self.song = song
        self.lyricsFocus = lyricsFocus
        self.navigate = navigate
        _tab = State(initialValue: initialTab.resolved)
    }

    /// データ取得・整形担当。5系統のロード + 楽曲情報行/クレジットの整形を保持する。
    @State private var vm = DetailSheetViewModel()
    @State private var editSong: Song?
    @State private var showLoginPrompt = false
    @State private var showPenlightVoteSheet = false
    @State private var showTagPicker = false
    // 参考動画 (SongVideo) オープン編集 (確定契約 §4)。
    /// 参考動画投稿/編集シート。nil=非表示, .create=新規, .edit(video)=編集。
    @State private var videoSheet: SongCommunityEditTarget<SongVideo>?
    /// 未ログインで投稿導線を押した時のログイン誘導。
    @State private var showCommunityLoginPrompt = false

    @State private var tab: SongDetailTab
    /// 出題箇所へのスクロールは 1 回だけ (読み直しや編集のたびに引き戻さない)。
    @State private var didScrollToFocus = false
    /// 歌詞タブが寄せてほしい行 (再生への追従・タイミング記録の次の行)。
    @State private var lyricsScrollTarget: String?
    /// 指でスクロールしている間と直後は追従で引き戻さない (Apple Music の歌詞と同じ)。
    @State private var lyricsFollowPausedUntil: Date = .distantPast
    /// 補足シート。補足は利用者の投稿が主な入口なので、楽曲編集とは別の軽い導線にしている。
    @State private var showNoteEditor = false
    /// 未ログインで補足の導線を押した時のログイン誘導。
    @State private var showNoteLoginPrompt = false
    /// 補足を直接反映したときの値。`song` は親から渡る固定値なので、送信後すぐ画面に出すために持つ。
    @State private var noteOverride: String??
    /// お気に入りトグル後に依存ビューを再評価させるためのバージョン。
    @State private var markVersion = 0

    private var markService: UserMarkService { UserMarkService.shared }

    /// 画面に出す補足 (直接反映した直後はその値)。
    private var displayNote: String? {
        let note = noteOverride ?? song.note
        return (note?.isEmpty ?? true) ? nil : note
    }

    /// 補足シートに渡す曲 (直接反映した直後の補足を元の値として見せる)。
    private var songWithDisplayNote: Song {
        var current = song
        current.note = displayNote
        return current
    }

    /// 補足の導線。ログイン前ならログインを挟んでから開く (楽曲編集と同じ流れ)。
    private func openNoteEditor() {
        AppAnalytics.tap("song_detail.edit_note")
        if EditPermission.canEdit {
            showNoteEditor = true
        } else {
            showNoteLoginPrompt = true
        }
    }

    /// 配色シード。ソロ曲 (オリジナル歌唱が1人) はそのアイドル個人カラーを使い、
    /// それ以外 (ユニット/全体曲やカラー未設定) はブランド色にフォールバックする。
    private var songSeed: String? {
        if vm.originalArtists.count == 1, let color = vm.originalArtists.first?.color, !color.isEmpty {
            return color
        }
        return vm.brand?.color
    }

    private static let tabsAnchor = "song_detail_tabs"
    private static let scrollSpace = "song_detail_scroll"
    @State private var tabsScrolledPast = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    actionRow
                        .padding(.horizontal, DS.sp5)
                        .padding(.top, DS.sp4)
                    statsBoard
                        .padding(.horizontal, DS.sp5)
                        .padding(.top, DS.sp4)
                    segmentBar
                        .padding(.horizontal, DS.sp5)
                        .padding(.top, DS.sp4)
                        .padding(.bottom, DS.sp1)
                        .id(Self.tabsAnchor)
                        .imasTracksScrolledPast(in: Self.scrollSpace, $tabsScrolledPast)

                    switch tab.resolved {
                    case .info: infoTab
                    case .lyrics: lyricsTab
                    case .history: historyTab
                    case .community: communityTab
                    }

                    Color.clear.frame(height: DS.sp9)
                }
            }
            .coordinateSpace(name: Self.scrollSpace)
            .onChange(of: vm.lyrics) { _, lyrics in scrollToFocus(lyrics, proxy: proxy) }
            .onChange(of: lyricsScrollTarget) { _, target in
                guard let target, tab.resolved == .lyrics, Date() >= lyricsFollowPausedUntil else { return }
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(target, anchor: .center) }
            }
            .modifier(PausesFollowWhileScrolling(until: $lyricsFollowPausedUntil))
            // タブを替えたら、前のタブで下まで流していても次のタブは頭 (タブの見出しの下) から見せる。
            .onChange(of: tab) { _, _ in
                if tabsScrolledPast { proxy.scrollTo(Self.tabsAnchor, anchor: .top) }
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
                    if EditPermission.showEditAffordance {
                        Button { openNoteEditor() } label: {
                            Label(displayNote == nil ? "補足を書く" : "補足を直す", systemImage: "text.bubble")
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
        .sheet(isPresented: $showNoteEditor) {
            SongNoteEditSheet(song: songWithDisplayNote) { noteOverride = .some($0) }
        }
        .sheet(isPresented: $showNoteLoginPrompt) {
            LoginToEditSheet(onSignedIn: { if EditPermission.canEdit { showNoteEditor = true } })
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
        .sheet(item: $videoSheet) { target in
            videoEditSheet(for: target)
        }
        .sheet(isPresented: $showCommunityLoginPrompt) {
            LoginToEditSheet()
        }
        .imasLoadAfterTransition { await vm.loadData(song: song) }
        .onChange(of: tab) { _, newTab in
            // 旧「歌詞を見る」は別画面だったので screen として計測できていた。
            // タブ化に伴い、どのタブが見られているかはここで拾う。
            AppAnalytics.tap("song_detail.tab.\(newTab.analyticsKey)")
        }
        .trackScreen("song_detail")
    }

    /// 歌詞が届いたら出題箇所を画面の中ほどへ寄せる。行の高さが決まってから動かしたいので
    /// 1 拍置く (届いた瞬間はまだ行が並んでいない)。
    private func scrollToFocus(_ lyrics: Lyrics?, proxy: ScrollViewProxy) {
        guard !didScrollToFocus, tab.resolved == .lyrics,
              let target = lyrics?.lines.first(where: { lyricsFocus.contains($0.id) })?.id else { return }
        didScrollToFocus = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(target, anchor: .center) }
        }
    }

    // MARK: - Hero (ジャケを左 + 題・歌唱者・配信日 / 試聴と印 / 数)

    /// 「タイプを出すかどうか」の条件は `vm.infoRows` 側 1 箇所だけに持たせ、ここでは
    /// その行があれば値を拾うだけにする (同じ条件 (`songType` が空/unknown でない) を
    /// 画面側に書き直すと、条件を直すときに片方だけ直し忘れる)。
    private var heroEyebrow: String? {
        var parts: [String] = []
        if let typeRow = vm.infoRows(for: song).first(where: { $0.key == "タイプ" }) {
            parts.append(typeRow.displayValue)
        }
        if let brandName = vm.brand?.shortName { parts.append(brandName) }
        return parts.isEmpty ? nil : parts.joined(separator: " ・ ")
    }

    /// 「配信日 ・ 再生時間」1 行。値と「出すかどうか」はどちらも `vm.infoRows` の
    /// 該当行から拾う (新しい判断をここに増やさない。`infoRows` が唯一の根拠)。
    private var heroReleaseMeta: String? {
        let rows = vm.infoRows(for: song)
        let parts = ["リリース日", "再生時間"].compactMap { key in rows.first { $0.key == key }?.displayValue }
        return parts.isEmpty ? nil : parts.joined(separator: " ・ ")
    }

    @ViewBuilder
    private var hero: some View {
        ImasHero(layout: .leading, eyebrow: heroEyebrow, title: song.title) {
            ArtworkImageView(
                url: vm.artworkInfo?.artworkURL,
                size: 116,
                previewURL: vm.artworkInfo?.previewURL,
                songTitle: song.title, songId: song.id,
                seed: songSeed
            )
        } facts: {
            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                if let artistLine = vm.artistLine(for: song) {
                    artistLineView(artistLine)
                }
                if let meta = heroReleaseMeta {
                    Text(meta).imasText(.imprint, color: DS.ink3)
                }
                // 曲の補足 (「ミリシタ 1 周年記念楽曲」など)。どのタブを開いていても曲の
                // 位置づけが分かるよう、歌唱者・配信日のすぐ下に 1 文で添える。無い曲は何も出さない。
                if let note = displayNote {
                    Text(note)
                        .imasText(.note)
                        .lineLimit(3)
                }
                // KAMISABI (音楽カードゲーム) 収録曲のときだけ、その札をチップで出す。
                // 語 (`kamisabiCardLabel()` = 「KAMISABI 収録」) はコアが決めるので手書きしない。
                if song.hasKamisabiCard {
                    ImasChip(text: kamisabiCardLabel(), style: .themed, seed: songSeed)
                }
            }
        }
        .imasTheme(seed: songSeed)
        .imasCopyable([
            CopyItem("曲名をコピー", song.title, key: "song_title"),
            CopyItem("よみをコピー", song.titleKana, key: "kana"),
            CopyItem("歌唱者をコピー", vm.artistLine(for: song), key: "artists"),
        ])
    }

    /// 歌唱者を「/」で繋いだ 1 行。全体曲は 10 人を超えることがあり、`ImasPerformerChip`
    /// (1 行固定・fixedSize) に入れると画面全体が横に広がって崩れる (原唱 4 人以上の曲は
    /// 605 曲ある)。複数行に折り返せる Text にする。
    private func artistLineView(_ artistLine: String) -> some View {
        // 色の点は付けない (名前の横の点は何も伝えない)。
        Text(artistLine).imasText(.rowSubtitle).lineLimit(2)
    }

    /// 再生 (主ボタン 1 つ) + 印のボタン (お気に入り・KAMISABI 所持)。今ある操作だけ残す
    /// (コール・メモの導線はこのヒーローには元から無いので足さない)。
    private var actionRow: some View {
        HStack(spacing: DS.Space.gap) {
            ImasButton(
                // Apple Music 契約者はフル再生になるので「試聴」とは言えない。
                title: isPreviewing ? "停止" : "再生",
                systemImage: isPreviewing ? "stop.fill" : "play.fill",
                role: .primary,
                size: .large
            ) {
                AppAnalytics.tap("song_detail.play")
                if let info = vm.artworkInfo, info.musicKitId != nil {
                    Task { await playFull(info) }
                } else if let previewURL = vm.artworkInfo?.previewURL {
                    MusicKitService.shared.togglePreview(url: previewURL, songId: song.id)
                }
            }
            .disabled(vm.artworkInfo?.previewURL == nil && vm.artworkInfo?.musicKitId == nil)

            ImasMarkButton(kind: .favorite, isOn: isFavorite, seed: songSeed) {
                AppAnalytics.tap("song_detail.toggle_favorite")
                toggleFavorite()
            }
            .id(markVersion)

            // KAMISABI (音楽カードゲーム) 収録曲のときだけ、カード所持のトグルを出す。
            // 未収録曲にトグルを出すと「持っていない」のか「そもそも対象外」なのか
            // 読み取れなくなるので、収録曲以外には出さない。
            // `.owned` は円盤所有と記号を共有するため、見える名前と読み上げを
            // 「カード所持」に明示する (ImasMarkButton の既定「所有」のままでは何を
            // 記録するボタンか伝わらない)。
            if song.hasKamisabiCard {
                ImasMarkTile(
                    systemImage: isKamisabiOwned ? UserMarkKind.owned.activeIcon : UserMarkKind.owned.icon,
                    label: "カード所持",
                    isOn: isKamisabiOwned,
                    accessibilityText: isKamisabiOwned ? "カード所持済み" : "カード所持を記録"
                ) {
                    AppAnalytics.tap("song_detail.toggle_kamisabi_owned")
                    toggleKamisabiOwned()
                }
                .id(markVersion)
            }
        }
    }

    /// 披露・回収・最終披露 (今ある数をそのまま電光掲示板で)。
    private var statsBoard: some View {
        ImasBoard(cells: boardCells)
    }

    private var boardCells: [ImasBoard.Cell] {
        var cells: [ImasBoard.Cell] = [
            .init(value: "\(vm.history.count)", unit: "回", label: "披露"),
        ]
        if !vm.collectedShows.isEmpty {
            cells.append(.init(value: "\(vm.collectedShows.count)", unit: "公演", label: "回収"))
        }
        if let last = vm.history.first?.date {
            cells.append(.init(value: ShortYearMonth.format(last), label: "最終披露"))
        }
        return cells
    }

    private var isPreviewing: Bool {
        MusicKitService.shared.isPlaying(songId: song.id)
    }

    private var isFavorite: Bool { markService.bool(.favorite, entity: .song, id: song.id) }
    private var isKamisabiOwned: Bool { markService.bool(.owned, entity: .song, id: song.id) }

    private func playFull(_ info: MusicKitSongInfo) async {
        if MusicKitService.shared.isPlaying
            && MusicKitService.shared.isFullPlayback
            && MusicKitService.shared.isPlaying(songId: song.id) {
            MusicKitService.shared.stop()
            return
        }
        if !MusicKitService.shared.hasAppleMusicSubscription {
            await MusicKitService.shared.requestAuthorization()
            guard MusicKitService.shared.hasAppleMusicSubscription else {
                // サブスク無しは fallback でプレビュー再生。
                if let previewURL = info.previewURL {
                    MusicKitService.shared.togglePreview(url: previewURL, songId: song.id)
                }
                return
            }
        }
        await MusicKitService.shared.playFull(songInfo: info, songId: song.id)
    }

    private func toggleFavorite() {
        do {
            try markService.toggle(.favorite, entity: .song, id: song.id)
            markVersion += 1
        } catch {
            LocalWriteFailure.report(error, action: "お気に入りの切り替え")
        }
    }

    /// KAMISABI カード所持トグル。`UserMarkKind.owned` を円盤所有と共有する
    /// (`user_marks` は端末ローカル唯一データで CloudKit には乗らないが、
    /// `UserMarkBackup` 経由の iCloud KVS バックアップはそのまま効く)。
    /// ON/OFF の判定はここでは持たず、保存済みの値を出すだけ。
    private func toggleKamisabiOwned() {
        do {
            try markService.toggle(.owned, entity: .song, id: song.id)
            markVersion += 1
        } catch {
            LocalWriteFailure.report(error, action: "カード所持の記録")
        }
    }

    // MARK: - Segmented

    private var segmentBar: some View {
        ImasTabs(options: SongDetailTab.available, selection: $tab, seed: songSeed) { $0.label }
    }

    // MARK: - Tab: 情報・歌唱

    private var infoTab: some View {
        SongInfoTab(
            song: song, seed: songSeed, vm: vm, navigate: navigate,
            note: displayNote,
            onEditNote: EditPermission.showEditAffordance ? { openNoteEditor() } : nil
        ) {
            // 参加ライブ登録は履歴タブで個別公演を選んでもらう導線。
            tab = .history
        }
    }

    // MARK: - Tab: 歌詞

    /// 歌詞は束ね取得 (`/songs/{id}/detail`) に同梱されるので、常時読み込みでも
    /// リクエストは増えない。中身は `SongLyricsTab` (VM を読むだけ)。
    private var lyricsTab: some View {
        SongLyricsTab(song: song, seed: songSeed, vm: vm, focusLineIds: Set(lyricsFocus),
                      playback: lyricsPlayback) {
            Task { await vm.loadServerData(song: song) }
        }
    }

    /// 歌詞タブとプレイヤーの繋ぎ。追従・記録はフル再生だけ (試聴は位置を突き合わせられない)。
    private var lyricsPlayback: SongLyricsTab.Playback {
        .appleMusic(songId: song.id,
                    startFull: { await startFullForLyrics() },
                    scrollTo: { lyricsScrollTarget = $0 })
    }

    /// タイミング記録のためにフル再生を始める。未契約・Apple Music に無い曲は false。
    /// 試聴へは落とさない (`playFull` と違い、位置を突き合わせられない再生は意味が無い)。
    private func startFullForLyrics() async -> Bool {
        guard let info = vm.artworkInfo, info.musicKitId != nil else { return false }
        let player = MusicKitService.shared
        if !player.hasAppleMusicSubscription {
            await player.requestAuthorization()
            guard player.hasAppleMusicSubscription else { return false }
        }
        await player.playFull(songInfo: info, songId: song.id)
        return player.isFullPlayback && player.nowPlayingSongId == song.id
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
        case .createVideo:   startCommunityEdit { videoSheet = .create }
        case .editVideo(let video): startCommunityEdit { videoSheet = .edit(video) }
        case .votePenlight:  startCommunityEdit { showPenlightVoteSheet = true }
        case .removeTag(let id):
            Task { await vm.removeSongTag(song: song, tagId: id) }
        }
    }

    // MARK: - Community edit (参考動画) sheet

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

/// 指でスクロールしている間と離して数秒は、歌詞の追従で引き戻さない。
/// スクロールの段階が取れるのは iOS 18 から。17 では常に追従する。
private struct PausesFollowWhileScrolling: ViewModifier {
    @Binding var until: Date

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in
                if phase == .interacting || phase == .decelerating {
                    until = Date().addingTimeInterval(4)
                }
            }
        } else {
            content
        }
    }
}
