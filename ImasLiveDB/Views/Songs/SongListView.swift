import os
import SwiftUI

/// 一覧の検索対象。歌詞以外はすべて手元 (`TextSearchCatalog`) で判定する。
///
/// スコープを混ぜて「すべて」で探す案は捨てた。短い語ほど壊れるからで、
/// 「愛」で曲名を探したいのにアイドル名にも作曲者名にも「愛」は入っている。
/// 結果は常に 1 スコープぶんにして、**他のスコープに何件あるかだけ知らせる**
/// (`SongListView.scopeSuggestionBar`)。混ざらないので「どれで引っかかったか」も
/// 起きず、見落としもしない。
enum SongSearchMode: String, CaseIterable, Hashable {
    case title, performer, creator, lyrics

    /// 画面に出してよい検索対象。
    ///
    /// 歌詞は JASRAC の許諾 (`LyricsFeature`) に従う。サーバ側も未公開の曲は
    /// `status=draft` で一般ユーザーに返さないが、それは「配信されない」保証であって
    /// 「アプリに導線が無い」保証ではない。`SongDetailTab.available` /
    /// `UnifiedSearchScope.available` と同じ流儀で、ここでも導線ごと消す。
    static var available: [SongSearchMode] {
        allCases.filter { $0 != .lyrics || LyricsFeature.isAvailable }
    }

    /// 手元のデータだけで判定できるか。
    ///
    /// 歌詞だけが D1 への問い合わせなので、打鍵ごとに動かせず件数も出せない
    /// (数えるだけでクエリを 1 本消費する)。それ以外は既に読み込み済みの
    /// `songs` から作った索引を舐めるだけで、2,000 曲でも 1 打鍵 0.1ms で終わる。
    var isLocal: Bool { self != .lyrics }

    /// 手元で判定できる対象。件数を出せるのはこれだけ。
    static let localScopes: [SongSearchMode] = allCases.filter(\.isLocal)

    /// 切り替えチップとメニューに出す文言。
    ///
    /// `.title` は表示形式で実際に絞る対象が変わる (曲 / アルバム / シリーズ) ので、
    /// 固定で「曲名」とは書けない。アルバム表示なのにチップが「曲名」だと、
    /// 何を打てばいいのか分からなくなる。
    func label(in listMode: SongListMode) -> String {
        switch self {
        case .title:     listMode.nameFilterLabel
        // 「アイドル」ではなく「歌唱」。ほかの 3 つ (曲名 / 作詞作曲 / 歌詞) が
        // **何と照合するか**を指すのに、ここだけ実体の名前だった。
        // タブ移動のチップ (`CrossTabCountChips`) も「アイドルに N」を出すので、
        // 同じ列に「アイドル」が 2 つ並んで、別の動作が同じ語に見えていた。
        case .performer: "歌唱"
        case .creator:   "作詞作曲"
        case .lyrics:    "歌詞"
        }
    }
}

enum SongListMode: String, CaseIterable {
    case songs
    case albums
    case series

    /// 名前絞り込みが絞る対象。検索欄の頭のチップに出す。
    var nameFilterLabel: String {
        switch self {
        case .songs:  "曲名"
        case .albums: "アルバム名"
        case .series: "シリーズ名"
        }
    }
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
    @State private var searchText = SongListView.initialSearchText()
    /// 曲名で絞るか、歌詞で絞るか。歌詞はサーバに問い合わせる。
    @State private var searchMode: SongSearchMode = .title
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
    /// 「コールガイドがある曲のみ」。
    /// ⚠️ `@AppStorage` にしないこと。通信が要る絞り込みが起動直後から効いていると、
    /// オフライン起動時に理由の分からない空一覧になる。
    @State private var callGuideOnly = false
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
            callGuideOnly: callGuideOnly,
            // 歌詞モードの入力は手元で絞れる語ではない。そのまま渡すと再ロードのたびに
            // 曲名で絞り直され、歌詞で当たった曲まで落ちる。
            searchText: searchMode.isLocal ? searchText : "",
            searchScope: searchMode)
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

    /// 歌詞検索を投げて、結果で一覧を絞る。一致箇所のスニペットは行に出すため保持する。
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
                vm.applyFilter(searchText: "", scope: .lyrics,
                               lyricsHits: Dictionary(hits.map { ($0.songId, $0.snippets) },
                                                      uniquingKeysWith: { a, _ in a }))
            } catch {
                Logger.database.error("lyrics_list_search_failed: \(error.localizedDescription)")
                vm.applyFilter(searchText: "", scope: .lyrics, lyricsHits: [:])
            }
        }
    }

    /// 入力か対象が変わったときの絞り込み直し。
    ///
    /// 歌詞は打鍵ごとに投げない (D1 の読み取りを打鍵数で消費しないため)。確定するまでは
    /// 前回の結果を捨てて、古い結果が残らないようにする。
    private func searchInputChanged() {
        vm.applyFilter(searchText: searchMode.isLocal ? searchText : "",
                       scope: searchMode,
                       lyricsHits: .some(nil))
    }

    @ViewBuilder
    private var content: some View {
            VStack(spacing: 0) {
                scopeSuggestionBar
                // 同じ語がアイドル・ライブに何件あるか。スコープ切替の直下に置くのは、
                // 「打った語の行き先」という点で利用者にとって同じ判断だから。
                CrossTabCountChips(query: searchText, from: .songs)
                removableFilterBar
                tagFilterErrorBanner
                callGuideFilterErrorBanner
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
            .onChange(of: searchText) { _, _ in searchInputChanged() }
                .onChange(of: searchMode) { _, _ in
                    searchInputChanged()
                    // 対象を切り替えたのは明示的な操作なので、入力が残っているならその場で引き直す。
                    // 打鍵のたびに投げるわけではないので D1 の読み取りは無駄にならない。
                    runLyricsSearchIfNeeded()
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
                        excludeLiveOnly: $excludeLiveOnly,
                        callGuideOnly: $callGuideOnly
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
                // 集合の解決に通信が要るので、他のトグルと違って解決を待ってから引き直す。
                .onChange(of: callGuideOnly) { _, enabled in
                    Task {
                        await vm.resolveCallGuideFilter(enabled)
                        reload()
                    }
                }
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

    /// 「ほかのスコープにも当たりがある」ことを知らせる行。
    ///
    /// スコープを混ぜないので結果は常に 1 種類ぶんで、「曲名だけで絞りたかったのに」も
    /// 「どれで引っかかったか分からない」も起きない。代わりに見落とす恐れがあるので、
    /// 件数だけ出して 1 タップで移れるようにする。
    ///
    /// 歌詞に件数が付かないのは、数えるだけで D1 のクエリを 1 本消費するから。
    /// 誘い文句だけ置いて、押したときに初めて投げる。
    /// 起動時に入れておく検索語。通常は空。
    ///
    /// DEBUG では `INITIAL_SEARCH` で埋められる。検索欄に文字が入っている状態
    /// (スコープ切替のチップ列・「別のタブ」の件数) は、打たないと出ない一方で
    /// シミュレータには文字入力の口が無く、スクショが撮れなかった。
    /// `SCREENSHOT_MODE` / `INITIAL_TAB` / `DAILY_PICK_KIND` と同じ流儀。
    static func initialSearchText() -> String {
        #if DEBUG
        return ProcessInfo.processInfo.environment["INITIAL_SEARCH"] ?? ""
        #else
        return ""
        #endif
    }

    @ViewBuilder
    private var scopeSuggestionBar: some View {
        let suggestions = scopeSuggestions
        if !suggestions.isEmpty || showsLyricsSuggestion {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.sp3) {
                    Text("ほかに")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink3)
                    ForEach(suggestions, id: \.scope) { item in
                        scopeChip(label: "\(item.scope.label(in: listMode)) \(item.count)件",
                                  scope: item.scope)
                    }
                    if showsLyricsSuggestion {
                        scopeChip(label: "歌詞で探す", scope: .lyrics)
                    }
                }
                .padding(.horizontal, DS.sp5)
                .padding(.vertical, DS.sp2)
            }
        }
    }

    /// 表示中でないスコープのうち、1 件以上当たるもの。
    ///
    /// 件数は VM が絞り込みと同じ走査で出したものを読むだけ。ここで数えると
    /// `body` 評価のたびに 2,000 曲を走査することになる。
    private var scopeSuggestions: [(scope: SongSearchMode, count: Int)] {
        SongSearchMode.localScopes.compactMap { scope in
            guard let count = vm.otherScopeCounts[scope], count > 0 else { return nil }
            return (scope, count)
        }
    }

    /// 歌詞の誘いは、入力があって歌詞を見ていないときだけ。件数は出さない。
    private var showsLyricsSuggestion: Bool {
        LyricsFeature.isAvailable && searchMode != .lyrics && !searchText.isEmpty
    }

    private func scopeChip(label: String, scope: SongSearchMode) -> some View {
        // 見た目は下のフィルタチップ列 (`removableFilterBar`) と揃える。
        // 自前で組むと同じ VStack に並ぶチップだけ字送りと余白がずれる。
        ImasFilterChip(text: label, isSelected: false) {
            AppAnalytics.tap("song_list.scope_suggestion")
            searchMode = scope
        }
    }

    /// 適用中フィルタの removable チップ列 (デザインの filters セクション)。
    /// マイマーク / 回収 / 表示形式 / タグ を横スクロールで一覧し、各チップ右の × で個別解除。
    /// いま表示中の曲でイントロドンを始める導線 (絞り込みバーの直下)。
    /// 絞り込み/検索している時のみ・4曲以上・非表示でないとき表示。
    @ViewBuilder
    private var introDonLaunchBar: some View {
        // 出題範囲はあいまい候補 (`vm.fuzzySongs`) を含めない。「もしかして」は
        // 目で見て選んでもらうための提案なので、黙って出題母集団に混ぜると
        // 打った覚えのない曲が出る。範囲は打った通りに当たった曲だけ。
        // (そのため選択モードでは一覧側にも候補を出さない → `songsListContent`)
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

    /// コールガイド絞り込みの取得に失敗した (オフライン等) ことを知らせるバナー。
    /// タグ側と同じく、失敗時は絞り込みを適用しないので一覧は絞られていない。
    @ViewBuilder
    private var callGuideFilterErrorBanner: some View {
        if vm.callGuideFilterError {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.imasCaption)
                    .foregroundStyle(DS.warning)
                Text("コールガイドの情報を取得できませんでした。表示中の一覧にはコールガイド条件が反映されていません。")
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
        if callGuideOnly {
            // 解除の後始末 (集合を捨てて引き直す) は `onChange(of: callGuideOnly)` が担う。
            chips.append(.init(id: "call_guide", label: "コールガイドあり") { callGuideOnly = false })
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
            // 何を絞るかはチップが示すので、プレースホルダは動詞だけでいい。
            // 「曲名⌄ 曲名で絞り込み」と二重に書くと、狭い欄が更に読みにくくなる。
            ListSearchField(
                prompt: searchMode == .lyrics ? "一節を入力" : "絞り込み",
                text: $searchText,
                onSubmit: runLyricsSearchIfNeeded
            ) {
                searchModeChip
            }
        }
    }

    /// 入力欄の頭に差す 曲名 / 歌詞 の切り替え。
    ///
    /// `.searchScopes` の全幅セグメントだと行を 1 本余分に食い、畳んだヘッダーが元に戻る。
    /// 入力欄の中のチップなら、何を探しているかを見せたまま 1 行に収まる。
    ///
    private var searchModeChip: some View {
        Menu {
            Picker("検索対象", selection: $searchMode) {
                ForEach(SongSearchMode.available, id: \.self) {
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
        // こちらも解除は onChange に任せる (二重に reload しない)。
        callGuideOnly = false
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
        if callGuideOnly { count += 1 }
        count += myMarkFilter.activeCount
        return count
    }

    // MARK: - Views

    private var songsListContent: some View {
        Group {
            // 歌詞検索中もスケルトンにする。前の結果を消した直後は絞り込み無しの状態
            // (= 全曲) なので、そのまま出すと 1,991 件が一瞬めくれてから絞られる。
            if vm.isLoading || lyricsSearching {
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
                // あいまい候補しか無い状態 (打ち間違い・かな入力) を「0 件」と言わない。
                // それを拾うためのあいまい検索なので、空状態はどちらも空のときだけ。
                //
                // ただし選択モードでは候補を出さない。確定ボタンが呼び元へ渡す母集団は
                // `vm.displayedSongs` (= 打った通りに当たった曲) だけなので、候補を並べると
                // 見えている行と件数が出題範囲と食い違い、押した瞬間に黙って除外される。
                let fuzzy: [SongWithArtists] = selectionMode ? [] : vm.fuzzySongs
                if !searchText.isEmpty && display.isEmpty && fuzzy.isEmpty {
                    ImasEmptyState(
                        systemImage: "line.3.horizontal.decrease",
                        title: "絞り込み結果がありません",
                        message: "「\(searchText)」に一致する楽曲がありません"
                    )
                } else {
                    VStack(spacing: 0) {
                        countSortBar(count: display.count + fuzzy.count)
                        songsList(display, fuzzy: fuzzy)
                    }
                }
            }
        }
        // 空状態は自分では縦に伸びないので、そのままだと上下に白帯を残して
        // 画面の真ん中に浮く (スコープの件数チップまで一緒に下がる)。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// 並び順の根拠として行に出す指標。その順で並べていない時は出さない。
    ///
    /// 出しっぱなしにすると、どの並びでも同じ情報が載って「今は何で並んでいるか」の
    /// 手掛かりにならない。並びを変えた時だけ増える方が、変えた結果として読める。
    private func rowMetric(for songId: String) -> SongRowMetric? {
        let total = vm.performanceCounts[songId] ?? 0
        switch sortOrder {
        case .performanceCount:
            return .performances(total)
        case .collectedRate:
            return .collectRate(collected: vm.collectedCounts[songId] ?? 0, total: total)
        case .titleKana, .releaseDate, .collectedCount:
            // 現地回収回数順は行の ✓N バッジが既に根拠になっている。
            return nil
        }
    }

    private func songsList(_ display: [SongWithArtists], fuzzy: [SongWithArtists]) -> some View {
        List {
            ForEach(display) { songRow($0) }
            if !fuzzy.isEmpty {
                // 打った通りではない候補なので、区切って理由を書く。黙って下に足すと
                // 「なぜこの曲が出ているのか」が読めず、一致の精度を疑わせる。
                ImasSectionHeader(title: "もしかして", tight: true)
                    .padding(.top, DS.sp4)
                    .padding(.bottom, DS.sp2)
                    .listRowInsets(EdgeInsets(top: 0, leading: DS.sp5, bottom: 0, trailing: DS.sp5))
                    .listRowBackground(DS.bg)
                    .listRowSeparator(.hidden)
                ForEach(fuzzy) { songRow($0) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.bg)
    }

    private func songRow(_ item: SongWithArtists) -> some View {
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
            tagVoteCount: selectedTags.count == 1 ? vm.tagVoteCounts[item.song.id] : nil,
            lyricsSnippets: vm.lyricsHits?[item.song.id] ?? [],
            searchMatch: searchText.isEmpty
                ? nil : SongRowMatch(text: searchText, scope: searchMode),
            metric: rowMetric(for: item.song.id)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            sheetDestination = .song(item.song)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: DS.sp5, bottom: 0, trailing: DS.sp5))
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
    }

    // MARK: - Data

    /// マーク集合に依存する絞り込みが効いているか (結果セット自体がマークで変わる)。
    /// これが効いている時はタブ再表示でも全件再取得して整合させる。
    private var isMarkDependentFilterActive: Bool {
        myMarkFilter.requireFavorite || myMarkFilter.requireNote || myMarkFilter.requireMyPick
            || collectFilter != .all
    }
}
