import os
import SwiftUI

/// 一覧の検索対象。歌詞はサーバ (D1) に問い合わせる。
enum SongSearchMode: String, CaseIterable, Hashable {
    case title, lyrics

    /// 画面に出してよい検索対象。
    ///
    /// 歌詞は JASRAC の許諾が下りるまで載せない (`LyricsFeature`)。サーバ側も
    /// `status=draft` で一般ユーザーには返さないが、それは「配信されない」保証であって
    /// 「アプリに導線が無い」保証ではない。`SongDetailTab.available` /
    /// `UnifiedSearchScope.available` と同じ流儀で、ここでも導線ごと消す。
    static var available: [SongSearchMode] {
        allCases.filter { $0 != .lyrics || LyricsFeature.isAvailable }
    }

    /// 切り替えチップとメニューに出す文言。
    ///
    /// `.title` は表示形式で実際に絞る対象が変わる (曲 / アルバム / シリーズ) ので、
    /// 固定で「曲名」とは書けない。アルバム表示なのにチップが「曲名」だと、
    /// 何を打てばいいのか分からなくなる。
    func label(in listMode: SongListMode) -> String {
        switch self {
        case .title:  listMode.nameFilterLabel
        case .lyrics: "歌詞"
        }
    }
}

enum SongListMode: String, CaseIterable {
    case songs
    case albums
    case series

    /// 名前絞り込みが絞る対象。
    var nameFilterLabel: String {
        switch self {
        case .songs:  "曲名"
        case .albums: "アルバム名"
        case .series: "シリーズ名"
        }
    }

    /// フィルタシートの入力欄に出す文言。
    /// 一覧側はチップが対象を示すので、こちらの長い文言は使わない。
    var nameFilterPrompt: String { "\(nameFilterLabel)で絞り込み" }
}

struct SongListView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(CloudKitSyncEngine.self) private var syncEngine
    @State private var vm = SongListViewModel()
    @State private var filter = SongSearchFilter()
    @State private var sortOrder: SongSortOrder = .titleKana
    /// nil = sortOrder のデフォルト方向、 true=昇順、 false=降順
    @State private var sortAscending: Bool? = nil
    @State private var showFilter = false
    @State private var sheetDestination: DetailDestination?
    @State private var searchText = ""
    /// 曲名で絞るか、歌詞で絞るか。歌詞はサーバに問い合わせる。
    @State private var searchMode: SongSearchMode = .title
    /// 歌詞検索の結果 (song_id)。nil = まだ検索していない。
    @State private var lyricsMatchIds: Set<String>?
    @State private var lyricsSearching = false
    /// 新規曲作成 sheet。
    @State private var showSongCreate = false
    /// 未ログイン時のログイン誘導 sheet。
    @State private var showLoginPrompt = false
    @AppStorage("songListMode") private var listMode: SongListMode = .songs
    @AppStorage("songs_collect_filter") private var collectFilter: SongCollectFilter = .all
    /// 「その他」(歌枠カバー等 brand_id='other') を一覧に出すか。既定 OFF で隠す。
    @AppStorage("songs_show_other_brand") private var showOtherBrand = false
    /// ライブ履歴のみのファントム曲 (セトリにしか無いカバー等) を一覧から隠す。既定 ON。
    @AppStorage("songs_exclude_live_only") private var excludeLiveOnly = true
    /// マイマーク絞り込み (担当/お気に入り/メモ)。 旧 MyMarks タブの統合後継。
    @State private var myMarkFilter = SongMyMarkFilter()
    /// コミュニティタグ絞り込み (複数指定可)。選択タグ全てが付いた曲 (AND) に絞る。
    @State private var selectedTags: [CommunityTag] = []
    @State private var showTagPicker = false
    @State private var showIntroDon = false
    /// 曲一覧の「この絞り込みでイントロドン」導線の表示/非表示 (設定アプリから戻せる)。
    @AppStorage("songlist_introdon_bar_hidden") private var introDonBarHidden = false

    /// イントロドン設定から「絞り込んで出題」で来た時の選択モード。
    /// true のとき常に「この範囲で出題」ボタンを出し、押すと onSelectPool で呼び元へ返す。
    var selectionMode = false
    var onSelectPool: (([Song], String) -> Void)? = nil
    @Environment(\.dismiss) private var dismissSelf

    private var activeFilterCount: Int { filter.activeFilterCount }

    /// 現在の UI 状態をデータ取得用リクエストへまとめる。
    private var loadRequest: SongListRequest {
        SongListRequest(
            filter: filter,
            sortOrder: sortOrder,
            sortAscending: sortAscending,
            showOtherBrand: showOtherBrand,
            excludeLiveOnly: excludeLiveOnly,
            collectFilter: collectFilter,
            myMarkFilter: myMarkFilter,
            selectedTagCount: selectedTags.count,
            searchText: searchText)
    }

    /// 現在の UI 状態で曲リストを即時再ロードする（チップ解除などフィルタ変更の共通導線）。
    private func reload() {
        vm.scheduleLoad(loadRequest, debounce: false)
    }

    var body: some View {
        // selectionMode = true (イントロドン設定画面から push されてくるケース) では、
        // 親が既に NavigationStack を持っているため自前で持つとネストになり、
        // タイトルバー領域が二重表示されて空白が大きく出る + 戻る操作が2回分働く。
        // root 用途 (タブの root) でだけ自前 NavigationStack を使う。
        if selectionMode {
            content
        } else {
            NavigationStack {
                content
            }
        }
    }

    /// 歌詞検索を投げて、結果 (song_id) で一覧を絞る。
    private func runLyricsSearchIfNeeded() {
        guard searchMode == .lyrics else { return }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        lyricsSearching = true
        Task {
            defer { lyricsSearching = false }
            do {
                let hits = try await AppContainer.shared.lyricsSearchReading
                    .searchLyrics(query: LyricsQueryNode.simpleQuery(query))
                lyricsMatchIds = Set(hits.map(\.songId))
                vm.recomputeDisplayed(searchText: "", lyricsMatchIds: lyricsMatchIds)
            } catch {
                Logger.database.error("lyrics_list_search_failed: \(error.localizedDescription)")
                lyricsMatchIds = []
                vm.recomputeDisplayed(searchText: "", lyricsMatchIds: [])
            }
        }
    }

    @ViewBuilder
    private var content: some View {
            VStack(spacing: 0) {
                removableFilterBar
                tagFilterErrorBanner
                introDonLaunchBar
                listContent
                    .refreshable {
                        await syncEngine.performIncrementalSync(database: database)
                        await vm.scheduleLoad(loadRequest, debounce: false).value
                    }
            }
            .background(DS.bg)
            // 絞り込み欄がナビバーの中にあるので `.searchable` のキャンセルボタンが無い。
            // スクロールでキーボードを閉じられないと、打った後に一覧が半分隠れたままになる。
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: searchText) { _, _ in
                // 歌詞は打鍵ごとに投げない (D1 の読み取りを打鍵数で消費しないため)。
                // 確定するまでは前回の結果を消して、古い結果が残らないようにする。
                if searchMode == .lyrics {
                    lyricsMatchIds = nil
                    vm.recomputeDisplayed(searchText: "")
                } else {
                    vm.recomputeDisplayed(searchText: searchText)
                }
            }
                .onChange(of: searchMode) { _, _ in
                    lyricsMatchIds = nil
                    vm.recomputeDisplayed(searchText: searchMode == .lyrics ? "" : searchText)
                }
                .navigationTitle("楽曲")
                // 絞り込みフィールドをナビバー内に置くので、タイトルは常に inline。
                // (.large だと大タイトル 52pt + バーの 2 行になり、畳んだ意味が無くなる)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .sheet(isPresented: $showFilter) {
                    SongFilterView(
                        nameFilter: $searchText,
                        filter: $filter,
                        sortOrder: $sortOrder,
                        sortAscending: $sortAscending,
                        listMode: $listMode,
                        collectFilter: $collectFilter,
                        myMarkFilter: $myMarkFilter,
                        showOtherBrand: $showOtherBrand,
                        excludeLiveOnly: $excludeLiveOnly
                    )
                    .environment(database)
                    .presentationDetents([.medium, .large])
                    .onDisappear { reload() }
                }
                .sheet(item: $sheetDestination) { dest in
                    DetailSheetView(destination: dest)
                        .environment(database)
                }
                .sheet(isPresented: $showSongCreate, onDismiss: { reload() }) {
                    SongEditView(newSongBrandId: filter.brandIds.count == 1 ? filter.brandIds.first : nil)
                        .environment(database)
                }
                .sheet(isPresented: $showLoginPrompt) {
                    LoginToEditSheet(onSignedIn: { if EditPermission.canEdit { showSongCreate = true } })
                }
                .sheet(isPresented: $showTagPicker) {
                    TagFilterPicker(initialSelection: selectedTags, onDone: applyTagFilter)
                }
                .navigationDestination(isPresented: $showIntroDon) {
                    // いま表示中(絞り込み済み)の曲をそのまま出題プールにしてイントロドンへ。
                    IntroGameSetupView(
                        presetPool: vm.displayedSongs.map(\.song),
                        presetLabel: "曲一覧の絞り込み"
                    )
                    .environment(database)
                }
                // 初回(またはマーク依存フィルタ時)だけ全件ロード。タブ再表示のたびに
                // 重い fetchSongs+出演者マップを走らせてスピナーを出さないよう、既にロード済みなら
                // 行アイコン用のマーク集合だけ軽く更新する (他タブでのお気に入り変更を反映)。
                .task {
                    if vm.songs.isEmpty || isMarkDependentFilterActive {
                        await vm.scheduleLoad(loadRequest, debounce: false).value
                    } else {
                        await vm.refreshMarkDisplays()
                    }
                }
                .onChange(of: filter.brandIds) { _, _ in reload() }
                .onChange(of: showOtherBrand) { _, _ in reload() }
                .onChange(of: excludeLiveOnly) { _, _ in reload() }
                .trackScreen("song_list")
    }

    /// 新規曲作成導線。ログイン済みなら作成 sheet、未ログインならログイン誘導。
    private func startCreate() {
        if EditPermission.canEdit {
            showSongCreate = true
        } else {
            showLoginPrompt = true
        }
    }

    /// 適用中フィルタの removable チップ列 (デザインの filters セクション)。
    /// マイマーク / 回収 / 表示形式 / タグ を横スクロールで一覧し、各チップ右の × で個別解除。
    /// いま表示中の曲でイントロドンを始める導線 (絞り込みバーの直下)。
    /// 絞り込み/検索している時のみ・4曲以上・非表示でないとき表示。
    @ViewBuilder
    private var introDonLaunchBar: some View {
        let playable = IntroGameSession.playable(vm.displayedSongs.map(\.song)).count
        if selectionMode {
            // イントロドン設定から「絞り込んで出題」で来た選択モード。
            // 絞り込みの有無に関わらず常に出し、押したら呼び元(設定)に範囲を返して戻る。
            selectionConfirmBar(playable: playable)
        } else {
            let filtering = filterBadgeCount > 0 || !searchText.isEmpty
            if filtering && playable >= 4 && !introDonBarHidden {
                normalIntroDonBar(playable: playable)
            }
        }
    }

    @ViewBuilder
    private func selectionConfirmBar(playable: Int) -> some View {
        // 呼び元 (IntroGameSetupView) が onSelectPool 内で showSongFilter = false を実行する
        // ことで navigationDestination が解除されて 1 回戻る。ここで追加で dismissSelf() を
        // 呼ぶと 2 回戻りになる (= 設定画面を更に飛び越えて IntroDonHome まで戻る) ため、
        // dismiss はせず onSelectPool だけ呼ぶ。
        Button {
            AppAnalytics.tap("song_list.introdon_select")
            onSelectPool?(vm.displayedSongs.map(\.song), selectionRangeLabel)
        } label: {
            HStack(spacing: DS.sp3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.imasScaled(15, weight: .bold))
                Text("この範囲で出題")
                    .font(.imasSubhead.weight(.bold))
                Text("\(playable)曲")
                    .font(.imasCaption)
                    .opacity(0.85)
                Spacer(minLength: 0)
                if playable < 4 {
                    Text("4曲以上必要")
                        .font(.imasCaption.weight(.bold))
                }
                Image(systemName: "chevron.right")
                    .font(.imasScaled(12, weight: .bold))
            }
            // DS.sys はシステムのテキスト色 (ダーク=白 / ライト=黒)。背景にこれを使うと、
            // 上に乗せる文字色は必ず DS.onSys (反転色) でなければならない。
            // 旧コードは固定 .white を載せており、ダークモードで「白背景白文字」になっていた。
            .padding(.horizontal, DS.sp5)
            .padding(.vertical, DS.sp4)
            .frame(maxWidth: .infinity)
            .foregroundStyle(playable >= 4 ? DS.onSys : Color.white)
            .background(playable >= 4 ? AnyShapeStyle(DS.sys) : AnyShapeStyle(Color.secondary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(playable < 4)
    }

    /// いま表示中の曲でこの場でイントロドンを始める通常導線 (絞り込みバー直下)。
    @ViewBuilder
    private func normalIntroDonBar(playable: Int) -> some View {
        HStack(spacing: 0) {
            Button {
                AppAnalytics.tap("song_list.introdon")
                showIntroDon = true
            } label: {
                HStack(spacing: DS.sp3) {
                    Image(systemName: "music.note.list")
                        .font(.imasScaled( 14, weight: .bold))
                    Text("この絞り込みでイントロドン")
                        .font(.imasSubhead.weight(.bold))
                    Text("\(playable)曲")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(DS.sys)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                AppAnalytics.tap("song_list.introdon_hide")
                withAnimation { introDonBarHidden = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.imasScaled( 12, weight: .bold))
                    .foregroundStyle(DS.ink2)
                    .padding(.leading, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("イントロドン導線を隠す")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DS.sys.opacity(0.10))
    }

    /// 選択モードで呼び元に返す範囲ラベル (適用中フィルタの簡潔な説明)。
    private var selectionRangeLabel: String {
        if !searchText.isEmpty { return "「\(searchText)」検索" }
        let chips = activeFilterChips
        if !chips.isEmpty { return chips.map(\.label).joined(separator: "・") }
        return "曲一覧の絞り込み"
    }

    /// タグ絞り込みの取得に失敗した (オフライン等) ことを知らせるバナー。
    /// 「タグに合致する曲が0件」との誤読を避けるため、`resolveTagFilter` は失敗時に一覧を
    /// 空にせず本フラグだけ立てる。ここでその状態をユーザーに明示する。
    @ViewBuilder
    private var tagFilterErrorBanner: some View {
        if vm.tagFilterError {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.imasCaption)
                    .foregroundStyle(DS.warning)
                Text("タグ絞り込みの取得に失敗しました。表示中の一覧にはタグ条件が反映されていません。")
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
            }
            .padding(.horizontal, DS.sp5)
            .padding(.vertical, DS.sp2)
        }
    }

    @ViewBuilder
    private var removableFilterBar: some View {
        let chips = activeFilterChips
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.sp3) {
                    ForEach(chips) { chip in
                        ImasRemovableChip(text: chip.label, onRemove: chip.remove)
                    }
                }
                .padding(.horizontal, DS.sp5)
                .padding(.vertical, DS.sp2)
            }
        }
    }

    /// 行頭に並ぶ removable フィルタチップの定義。
    private struct ActiveFilterChip: Identifiable {
        let id: String
        let label: String
        let remove: () -> Void
    }

    private var activeFilterChips: [ActiveFilterChip] {
        var chips: [ActiveFilterChip] = []
        if myMarkFilter.requireMyPick {
            chips.append(.init(id: "pick", label: "担当") { myMarkFilter.requireMyPick = false; reload() })
        }
        if myMarkFilter.requireFavorite {
            chips.append(.init(id: "fav", label: "お気に入り") { myMarkFilter.requireFavorite = false; reload() })
        }
        if myMarkFilter.requireNote {
            chips.append(.init(id: "note", label: "メモあり") { myMarkFilter.requireNote = false; reload() })
        }
        switch collectFilter {
        case .all: break
        case .collected:
            chips.append(.init(id: "collected", label: "現地回収済") { collectFilter = .all; reload() })
        case .uncollected:
            chips.append(.init(id: "uncollected", label: "未回収") { collectFilter = .all; reload() })
        }
        if let series = filter.seriesGroup, !series.isEmpty {
            chips.append(.init(id: "series", label: series) { filter.seriesGroup = nil; reload() })
        }
        for tag in selectedTags {
            // 重複なしの曲数を表示 (totalUses は票数合計=同曲への複数票を含み実曲数とズレるため使わない)。
            // 単一タグ時は取得済みの該当曲数、複数タグ時は名前のみ。
            let label: String
            if selectedTags.count == 1, !vm.tagVoteCounts.isEmpty {
                label = "\(tag.name) \(vm.tagVoteCounts.count)曲"
            } else {
                label = tag.name
            }
            chips.append(.init(id: "tag_\(tag.id)", label: label) { removeTag(tag) })
        }
        return chips
    }

    /// 個別タグの解除。残ったタグで再計算する。
    private func removeTag(_ tag: CommunityTag) {
        applyTagFilter(selectedTags.filter { $0.id != tag.id })
    }

    @ViewBuilder
    private var listContent: some View {
        switch listMode {
        case .songs:
            songsListContent
        case .albums:
            AlbumGridView(
                selectedBrandIds: filter.brandIds,
                searchText: searchText
            ) { album in
                sheetDestination = .filteredSongs(.cdSeries(album.cdSeries))
            }
            .environment(database)
        case .series:
            SeriesGridView(
                selectedBrandIds: filter.brandIds,
                searchText: searchText
            ) { series in
                sheetDestination = .filteredSongs(.seriesGroup(series.name))
            }
            .environment(database)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        standardListToolbar(
            filterBadge: filterBadgeCount,
            onFilter: {
                AppAnalytics.tap("song_list.filter")
                showFilter = true
            },
            menuActions: songMenuActions
        ) {
            ListSearchField(
                prompt: searchPrompt,
                text: $searchText,
                onSubmit: runLyricsSearchIfNeeded
            ) {
                searchModeChip
            }
        }
    }

    /// 入力欄のプレースホルダ。
    ///
    /// チップが対象を示しているなら動詞だけでいい。「曲名⌄ 曲名で絞り込み」と二重に書くと
    /// 狭い欄が更に読みにくくなる。チップを出していないとき (歌詞が未許諾で 1 択のとき) は
    /// 対象がどこにも書かれないので、こちらで明示する。
    private var searchPrompt: String {
        guard SongSearchMode.available.count > 1 else { return listMode.nameFilterPrompt }
        return searchMode == .lyrics ? "一節を入力" : "絞り込み"
    }

    /// 入力欄の頭に差す 曲名 / 歌詞 の切り替え。
    ///
    /// `.searchScopes` の全幅セグメントだと行を 1 本余分に食い、畳んだヘッダーが元に戻る。
    /// 入力欄の中のチップなら、何を探しているかを見せたまま 1 行に収まる。
    ///
    /// 選べる対象が 1 つしかない (歌詞が未許諾で落ちている) ときは丸ごと出さない。
    /// 押しても 1 択しか出ないメニューは、狭い欄の幅を食うだけで何の役にも立たない。
    @ViewBuilder
    private var searchModeChip: some View {
        let modes = SongSearchMode.available
        if modes.count > 1 {
            Menu {
                Picker("検索対象", selection: $searchMode) {
                    ForEach(modes, id: \.self) {
                        Text($0.label(in: listMode)).tag($0)
                    }
                }
            } label: {
                HStack(spacing: 1) {
                    Text(searchMode.label(in: listMode))
                        .font(.imasCaption.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.imasScaled(8, weight: .semibold))
                }
                .foregroundStyle(DS.ink2)
                .padding(.horizontal, DS.sp2)
                .padding(.vertical, 2)
                .background(DS.surface, in: Capsule())
                .lineLimit(1)
                .fixedSize()
            }
            .accessibilityLabel("検索対象: \(searchMode.label(in: listMode))")
        }
    }

    private var songMenuActions: [ListToolbarAction] {
        var actions: [ListToolbarAction] = []
        if EditPermission.showEditAffordance {
            actions.append(ListToolbarAction(id: "add", title: "曲を追加", systemImage: "plus") {
                AppAnalytics.tap("song_list.add")
                startCreate()
            })
        }
        actions.append(ListToolbarAction(
            id: "tag",
            title: selectedTags.isEmpty ? "タグで絞り込み" : "タグ: \(selectedTags.count)件",
            systemImage: selectedTags.isEmpty ? "tag" : "tag.fill"
        ) {
            AppAnalytics.tap("song_list.tag_filter")
            showTagPicker = true
        })
        if filterBadgeCount > 0 {
            actions.append(ListToolbarAction(id: "clear", title: "フィルタを解除",
                                             systemImage: "xmark.circle", isDestructive: true) {
                AppAnalytics.tap("song_list.filter_clear")
                resetAllFilters()
            })
        }
        return actions
    }

    private func resetAllFilters() {
        filter = SongSearchFilter()
        sortOrder = .titleKana
        sortAscending = nil
        listMode = .songs
        collectFilter = .all
        myMarkFilter = SongMyMarkFilter()
        selectedTags = []
        Task {
            await vm.resolveTagFilter([])
            reload()
        }
    }

    /// タグ絞り込みを適用。複数選択時は各タグの song_id 集合の **積集合** (AND) を取り、
    /// その曲だけ表示する。0 件選択なら絞り込み解除。集合解決は VM が担う。
    private func applyTagFilter(_ tags: [CommunityTag]) {
        selectedTags = tags
        if !tags.isEmpty { listMode = .songs }
        Task {
            await vm.resolveTagFilter(tags)
            reload()
        }
    }

    /// 絞り込みバッジには表示形式・回収フィルタ状態 + マイマーク絞り込みも含める
    private var filterBadgeCount: Int {
        var count = activeFilterCount
        if listMode != .songs { count += 1 }
        if collectFilter != .all { count += 1 }
        if !selectedTags.isEmpty { count += 1 }
        count += myMarkFilter.activeCount
        return count
    }

    // MARK: - Views

    private var songsListContent: some View {
        Group {
            if vm.isLoading {
                ScrollView {
                    ImasListSkeleton(rows: 12, thumb: .square)
                        .padding(.top, DS.sp3)
                }
                .scrollDisabled(true)
                .background(DS.bg)
            } else if vm.songs.isEmpty && filter.activeFilterCount > 0 {
                ImasEmptyState(
                    systemImage: "line.3.horizontal.decrease",
                    title: "条件に一致する楽曲がありません",
                    message: "フィルタ条件を変更するか、フィルタを解除してください。"
                )
            } else {
                let display = vm.displayedSongs
                if !searchText.isEmpty && display.isEmpty {
                    ImasEmptyState(
                        systemImage: "line.3.horizontal.decrease",
                        title: "絞り込み結果がありません",
                        message: "「\(searchText)」に一致する楽曲がありません"
                    )
                } else {
                    VStack(spacing: 0) {
                        countSortBar(count: display.count)
                        songsList(display)
                    }
                }
            }
        }
    }

    /// 件数 + ソートコントロール (デザインの csort 行)。ソートボタンはフィルタシートを開く。
    private func countSortBar(count: Int) -> some View {
        HStack {
            (Text("\(count)").font(.imasDisplay(15, weight: .bold)).foregroundStyle(DS.ink)
                + Text(" 件").font(.imasFootnote).foregroundStyle(DS.ink2))
            Spacer()
            Button {
                showFilter = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.imasScaled( 13, weight: .semibold))
                        .foregroundStyle(DS.ink2)
                    Text(sortOrder.rawValue)
                        .font(.imasScaled( 13.5, weight: .semibold))
                        .foregroundStyle(DS.ink)
                    Image(systemName: "chevron.down")
                        .font(.imasScaled( 11, weight: .semibold))
                        .foregroundStyle(DS.ink2)
                }
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("並び替え: \(sortOrder.rawValue)")
        }
        .padding(.horizontal, DS.sp5)
        .padding(.top, DS.sp2)
        .padding(.bottom, DS.sp2)
    }

    private func songsList(_ display: [SongWithArtists]) -> some View {
        List {
            ForEach(display) { item in
                // iOS 18 では Button label 内に Button (再生ボタン等) を
                // 入れ子にすると tap が両方とも吸われて反応領域が狭くなる。
                // 行全体は onTapGesture で受け、内側の再生ボタンは独立して機能させる。
                SongRowView(
                    item: item,
                    collectedCount: vm.collectedCounts[item.song.id],
                    isFavorite: vm.favoriteSongIds.contains(item.song.id),
                    isMyPick: vm.myPickSongIds.contains(item.song.id),
                    hasNote: vm.notedSongIds.contains(item.song.id),
                    onCollectedTap: { sheetDestination = .songHistory(item.song) },
                    tagVoteCount: selectedTags.count == 1 ? vm.tagVoteCounts[item.song.id] : nil
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    sheetDestination = .song(item.song)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: DS.sp5, bottom: 0, trailing: DS.sp5))
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.bg)
    }

    // MARK: - Data

    /// マーク集合に依存する絞り込みが効いているか (結果セット自体がマークで変わる)。
    /// これが効いている時はタブ再表示でも全件再取得して整合させる。
    private var isMarkDependentFilterActive: Bool {
        myMarkFilter.requireFavorite || myMarkFilter.requireNote || myMarkFilter.requireMyPick
            || collectFilter != .all
    }
}
