import os
import SwiftUI

enum SongListMode: String, CaseIterable {
    case songs
    case albums
    case series
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
    @State private var isSearching = false
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

    private var searchPrompt: String {
        switch listMode {
        case .songs: "曲名で検索"
        case .albums: "アルバム名で検索"
        case .series: "シリーズ名で検索"
        }
    }

    /// 現在の UI 状態で曲リストを即時再ロードする（チップ解除などフィルタ変更の共通導線）。
    private func reload() {
        vm.scheduleLoad(loadRequest, debounce: false)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isSearching {
                    InTabSearchField(prompt: searchPrompt, text: $searchText, isSearching: $isSearching)
                }
                removableFilterBar
                introDonLaunchBar
                listContent
                    .refreshable {
                        await syncEngine.performIncrementalSync(database: database)
                        await vm.load(loadRequest)
                    }
            }
            .background(DS.bg)
            .onChange(of: searchText) { _, _ in vm.recomputeDisplayed(searchText: searchText) }
                .navigationTitle("楽曲")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { toolbarContent }
                .sheet(isPresented: $showFilter) {
                    SongFilterView(
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
                        await vm.load(loadRequest)
                    } else {
                        await vm.refreshMarkDisplays()
                    }
                }
                .onChange(of: filter.brandIds) { _, _ in reload() }
                .onChange(of: showOtherBrand) { _, _ in reload() }
                .onChange(of: excludeLiveOnly) { _, _ in reload() }
                .trackScreen("song_list")
        }
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
        Button {
            AppAnalytics.tap("song_list.introdon_select")
            onSelectPool?(vm.displayedSongs.map(\.song), selectionRangeLabel)
            dismissSelf()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.imasScaled(15, weight: .bold))
                Text("この範囲で出題")
                    .font(.imasSubhead.weight(.bold))
                Text("\(playable)曲")
                    .font(.imasCaption)
                    .foregroundStyle(playable >= 4 ? .white.opacity(0.85) : Color.white.opacity(0.85))
                Spacer(minLength: 0)
                if playable < 4 {
                    Text("4曲以上必要")
                        .font(.imasCaption.weight(.bold))
                }
                Image(systemName: "chevron.right")
                    .font(.imasScaled(12, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(playable >= 4 ? DS.sys : Color.secondary)
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
                HStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.imasScaled( 14, weight: .bold))
                    Text("この絞り込みでイントロドン")
                        .font(.imasSubhead.weight(.bold))
                    Text("\(playable)曲")
                        .font(.imasCaption)
                        .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
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

    @ViewBuilder
    private var removableFilterBar: some View {
        let chips = activeFilterChips
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
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
            onSearch: {
                AppAnalytics.tap("song_list.search_open")
                isSearching = true
            },
            filterBadge: filterBadgeCount,
            onFilter: {
                AppAnalytics.tap("song_list.filter")
                showFilter = true
            },
            menuActions: songMenuActions
        )
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
                List {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(DS.bg)
            } else if vm.songs.isEmpty && filter.activeFilterCount > 0 {
                ContentUnavailableView.search(text: "条件に一致する楽曲")
            } else {
                let display = vm.displayedSongs
                if !searchText.isEmpty && display.isEmpty {
                    InTabSearchEmptyView(query: searchText)
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

// MARK: - Song Search Screen

private struct SongSearchScreen: View {
    let prompt: String
    let filter: SongSearchFilter
    @Binding var sheetDestination: DetailDestination?

    var body: some View {
        SearchScreen(
            prompt: prompt,
            historyScope: .songs,
            searchAction: { query in
                var f = filter
                f.title = query
                return (try? await AppContainer.shared.songReading.songs(filter: f, sortOrder: .titleKana, ascending: nil)) ?? []
            },
            suggestionsAction: { query in
                (try? await AppContainer.shared.songReading.songSuggestions(query: query, limit: 8)) ?? []
            }
        ) { item in
            Button {
                sheetDestination = .song(item.song)
            } label: {
                SongRowView(item: item)
            }
            .buttonStyle(.plain)
        }
    }
}
