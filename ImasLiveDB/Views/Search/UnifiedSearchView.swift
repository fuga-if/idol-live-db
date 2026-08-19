import os
import SwiftUI

/// アプリ唯一の検索画面。
///
/// 旧実装は「全体検索 (シート・横断)」「タブ内検索 (インライン絞り込み)」「SearchScreen (push)」
/// の 3 系統が併存し、同じナビバーに虫眼鏡が 2 つ並んでいた。ここではスコープ切替 1 画面に統合し、
/// 検索 = 「探して詳細へ飛ぶ」、フィルタ = 「一覧を絞る」と役割を分ける。
///
/// - 呼び出し元のタブに応じた `initialScope` で開く (楽曲タブから開けば楽曲スコープ)。
/// - 結果タップは sheet ではなく push。旧全体検索は sheet on sheet で行き止まりになっていた。
struct UnifiedSearchView: View {
    /// 外部から引き継ぐ初期クエリ (ディープリンク等)。空なら履歴表示で開く。
    private let initialQuery: String

    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String
    /// 初期スコープは `@State` の初期値として渡す。`onAppear` で代入すると
    /// 最初の 1 フレームだけ `.all` が描かれてセグメントがちらつく。
    @State private var scope: UnifiedSearchScope

    init(initialScope: UnifiedSearchScope = .all, initialQuery: String = "") {
        self.initialQuery = initialQuery
        _scope = State(initialValue: initialScope.resolved)
        _searchText = State(initialValue: initialQuery)
    }

    @State private var results = SearchResults(songs: [], idols: [], events: [])
    /// 歌詞検索のヒット (サーバ) と、その song_id を同梱 SQLite で引き直した曲。
    /// サーバはマスタを持っていないので、曲名・アーティストはこちらで解決する。
    @State private var lyricsHits: [LyricsSearchHit] = []
    @State private var lyricsSongs: [String: Song] = [:]
    /// 歌詞検索が未ログインで弾かれた状態。空振りと区別して案内を出す。
    @State private var lyricsNeedsLogin = false
    /// 検索そのものが失敗した (通信/サーバエラー)。これも空振りと区別する。
    @State private var searchFailed = false
    /// 歌詞スコープで入力はあるがまだ確定 (Enter) していない。空振りと区別して案内を出す。
    @State private var lyricsAwaitingSubmit = false
    /// 歌詞検索の検索式。括弧を打たせず、インデントで入れ子を見せる。
    @State private var lyricsQuery = LyricsQueryNode.initialRoot()
    /// 簡易検索の入力 (空白区切り = OR)。
    @State private var lyricsSimpleText = ""
    /// 詳細検索 (AND/OR の組み立て) を使うか。既定は簡易。
    /// まとまりを作る操作は難しいので、必要な人だけが開く形にする。
    @AppStorage("lyrics_search_advanced") private var lyricsAdvanced = false
    /// event_id → 検索語に一致した会場名。「武道館」で検索した時に、ライブ名だけ並んで
    /// なぜヒットしたか分からない状態を避けるため、一致理由として行に出す。
    @State private var matchedVenues: [String: String] = [:]
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var path: [DetailDestination] = []
    @State private var historyVersion = 0
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if scope == .lyrics {
                    lyricsInput
                } else {
                    searchField
                }
                scopeBar
                ImasRowDivider()
                content
            }
            .background(DS.bg)
            .navigationTitle("検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .navigationDestination(for: DetailDestination.self) { dest in
                DetailContentView(destination: dest) { path.append($0) }
            }
        }
        .onAppear {
            if !initialQuery.isEmpty { scheduleSearch(initialQuery, debounce: false) }
            isTextFieldFocused = true
        }
        .trackScreen("search")
    }

    // MARK: - 検索フィールド

    private var searchField: some View {
        HStack(spacing: DS.sp3) {
            Image(systemName: "magnifyingglass")
                .font(.imasScaled(15, weight: .semibold))
                .foregroundStyle(DS.ink3)
            TextField(scope.prompt, text: $searchText)
                .font(.imasBody)
                .foregroundStyle(DS.ink)
                .focused($isTextFieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { commitSearch() }
                .onChange(of: searchText) { _, newValue in scheduleSearch(newValue) }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    clearResults()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.imasSubhead)
                        .foregroundStyle(DS.ink3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("入力をクリア")
            }
        }
        .padding(.horizontal, DS.sp4)
        .padding(.vertical, 9)
        .background(DS.fill, in: Capsule())
        .padding(.horizontal, DS.sp5)
        .padding(.top, DS.sp3)
        .padding(.bottom, DS.sp4)
    }

    /// 歌詞検索の入力。既定は簡易 (1つの欄・空白で OR)、必要なら詳細に開く。
    @ViewBuilder
    private var lyricsInput: some View {
        VStack(alignment: .leading, spacing: DS.sp2) {
            if lyricsAdvanced {
                // 条件が増えると縦に伸びてナビバーへ潜り込むので、高さを切ってスクロールさせる。
                // 上限は画面の3割強。これを超えると結果が1件も見えなくなり、
                // 何を検索しているのか分からなくなる。
                ScrollView {
                    LyricsQueryBuilderView(root: lyricsQuery) { commitSearch() }
                }
                .frame(maxHeight: 240)
                .scrollBounceBehavior(.basedOnSize)
            } else {
                HStack(spacing: DS.sp3) {
                    Image(systemName: "magnifyingglass")
                        .font(.imasScaled(15, weight: .semibold))
                        .foregroundStyle(DS.ink3)
                    TextField("歌詞の一節 (空白で区切ると すべて含む)", text: $lyricsSimpleText)
                        .font(.imasBody)
                        .foregroundStyle(DS.ink)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .onSubmit { commitSearch() }
                    if !lyricsSimpleText.isEmpty {
                        Button {
                            lyricsSimpleText = ""
                            clearResults()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.imasSubhead)
                                .foregroundStyle(DS.ink3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("入力をクリア")
                    }
                }
                .padding(.horizontal, DS.sp4)
                .padding(.vertical, 9)
                .background(DS.fill, in: Capsule())
                .padding(.horizontal, DS.sp5)
            }

            Button {
                // 打った内容を持ち越す。切り替えただけで打ち直しになると使われない。
                if lyricsAdvanced {
                    lyricsSimpleText = lyricsQuery.flattenedTerms()
                } else {
                    lyricsQuery = LyricsQueryNode.fromSimple(lyricsSimpleText)
                }
                lyricsAdvanced.toggle()
                AppAnalytics.tap("lyrics_search.toggle_advanced")
            } label: {
                Label(lyricsAdvanced ? "簡易検索に戻す" : "詳細検索",
                      systemImage: lyricsAdvanced ? "chevron.up" : "slider.horizontal.3")
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DS.sp5)
        }
        .padding(.top, DS.sp3)
        .padding(.bottom, DS.sp3)
    }

    private var scopeBar: some View {
        ImasSegmented(options: UnifiedSearchScope.available, selection: $scope) { $0.label }
            .padding(.horizontal, DS.sp5)
            .padding(.bottom, DS.sp4)
            // スコープを変えたら、そのスコープの検索結果を取り直す
            // (「すべて」は 各20件上限、スコープ指定時はより深く引く)。
            .onChange(of: scope) { _, newScope in
                AppAnalytics.tap("search.scope_change")
                if newScope == .lyrics {
                    // 他スコープの入力語をビルダーの1つ目に引き継ぐ。スコープを
                    // 変えただけで打ち直しになるのは手間なので。
                    let carried = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !carried.isEmpty, lyricsSimpleText.isEmpty, !lyricsQuery.hasAnyTerm {
                        lyricsSimpleText = carried
                    }
                    clearResults()
                    return
                }
                guard !searchText.isEmpty else { return }
                scheduleSearch(searchText, debounce: false)
            }
    }

    // MARK: - 本体

    @ViewBuilder
    private var content: some View {
        if scope == .lyrics && searchText.isEmpty {
            // 歌詞は打鍵ごとに投げない (D1 の読み取りを打鍵数で消費しないため)。
            // 履歴ではなく「検索する」を出して、確定待ちだと分かるようにする。
            ImasEmptyState(
                systemImage: "text.magnifyingglass",
                title: "歌詞を検索",
                message: lyricsAdvanced
                    ? "条件を入れて検索してください。行頭の「かつ / または」でつなぎ方を変えられます。"
                    : "歌詞の一節を入れて検索してください。空白で区切ると、すべてを含む曲に絞れます。",
                actionTitle: lyricsHasInput ? "検索する" : nil,
                action: lyricsHasInput ? { commitSearch() } : nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, DS.sp6)
            .background(DS.bg)
        } else if searchText.isEmpty {
            historyView
        } else if isSearching {
            ImasLoadingState()
                .background(DS.bg)
        } else if visibleResultCount == 0 {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, DS.sp8)
                .background(DS.bg)
        } else {
            resultsList
        }
    }

    /// 結果ゼロの見せ方。「失敗」「ログインが要る」「本当に無い」を混ぜない。
    @ViewBuilder
    private var emptyState: some View {
        if searchFailed {
            ImasEmptyState(
                systemImage: "exclamationmark.triangle",
                title: "検索できませんでした",
                message: "通信環境を確認して、もう一度お試しください。",
                actionTitle: "再試行",
                action: { scheduleSearch(searchText, debounce: false) }
            )
        } else if lyricsAwaitingSubmit {
            // 打鍵ごとに投げない仕様なので、待っているのだと分かるようにする。
            ImasEmptyState(
                systemImage: "return",
                title: "歌詞を検索",
                message: "「\(searchText)」を含む歌詞を探します。",
                actionTitle: "検索する",
                action: { commitSearch() }
            )
        } else if lyricsNeedsLogin {
            ImasEmptyState(
                systemImage: "person.crop.circle.badge.questionmark",
                title: "歌詞の検索にはログインが必要です",
                message: "ログインすると、登録済みの曲の歌詞を検索できます。"
            )
        } else {
            ImasEmptyState(
                systemImage: "magnifyingglass",
                title: "見つかりません",
                message: "「\(searchText)」に一致する\(scope.emptyNoun)がありません"
            )
        }
    }

    private var resultsList: some View {
        List {
            if scope.includes(.idols), !results.idols.isEmpty {
                Section {
                    ForEach(results.idols) { idol in
                        NavigationLink(value: DetailDestination.idol(idol)) {
                            IdolNameRow(idol: idol, subtitle: idol.nameKana, showsChevron: false)
                        }
                        .listRowBackground(DS.surface)
                        .listRowSeparatorTint(DS.sep)
                    }
                } header: {
                    resultSectionHeader("アイドル", count: results.idols.count)
                }
            }
            if scope.includes(.songs), !results.songs.isEmpty {
                Section {
                    ForEach(results.songs) { song in
                        NavigationLink(value: DetailDestination.song(song)) {
                            // NavigationLink が自前で > を出すので、行側の > は消す
                            // (アイドル行と同じ扱い)。
                            SongTitleRow(song: song, showsChevron: false)
                        }
                        .listRowBackground(DS.surface)
                        .listRowSeparatorTint(DS.sep)
                    }
                } header: {
                    resultSectionHeader("楽曲", count: results.songs.count)
                }
            }
            if scope.includes(.lyrics), !lyricsHits.isEmpty {
                Section {
                    ForEach(lyricsHits) { hit in
                        if let song = lyricsSongs[hit.songId] {
                            NavigationLink(value: DetailDestination.songLyrics(song)) {
                                LyricsSearchRow(song: song, hit: hit)
                            }
                            .listRowBackground(DS.surface)
                            .listRowSeparatorTint(DS.sep)
                        }
                    }
                } header: {
                    resultSectionHeader("歌詞", count: lyricsHits.count)
                }
            }
            if scope.includes(.events), !results.events.isEmpty {
                Section {
                    ForEach(results.events) { event in
                        NavigationLink(value: DetailDestination.event(event)) {
                            EventNameRow(event: event, subtitle: matchedVenues[event.id],
                                         showsChevron: false)
                        }
                        .listRowBackground(DS.surface)
                        .listRowSeparatorTint(DS.sep)
                    }
                } header: {
                    resultSectionHeader("ライブ", count: results.events.count)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.bg)
    }

    private func resultSectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.imasScaled(13, weight: .semibold))
                .foregroundStyle(DS.ink2)
            Spacer()
            Text("\(count)件")
                .font(.imasCaption)
                .foregroundStyle(DS.ink3)
        }
    }

    // MARK: - 履歴

    @ViewBuilder
    private var historyView: some View {
        let history = recentHistory()
        if history.isEmpty {
            ImasEmptyState(
                systemImage: "magnifyingglass",
                title: "検索履歴はありません",
                message: "\(scope.emptyNoun)を名前で探せます"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, DS.sp8)
            .background(DS.bg)
        } else {
            List {
                Section {
                    ForEach(history, id: \.self) { item in
                        Button {
                            searchText = item
                            commitSearch()
                        } label: {
                            HStack(spacing: DS.sp3) {
                                Image(systemName: "clock")
                                    .font(.imasScaled(14))
                                    .foregroundStyle(DS.ink3)
                                    .frame(width: 20)
                                Text(item)
                                    .font(.imasSubhead)
                                    .foregroundStyle(DS.ink)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.imasCaption)
                                    .foregroundStyle(DS.ink3)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(DS.surface)
                        .listRowSeparatorTint(DS.sep)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteHistoryItem(item)
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("最近の検索")
                            .font(.imasScaled(13, weight: .semibold))
                            .foregroundStyle(DS.ink2)
                        Spacer()
                        Button("クリア") {
                            AppAnalytics.tap("search.clear_history")
                            for s in scope.historyScopes {
                                SearchHistoryManager.shared.clear(scope: s)
                            }
                            historyVersion += 1
                        }
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DS.bg)
            .id(historyVersion)
        }
    }

    /// 現在スコープの検索履歴。「すべて」は 3 スコープをラウンドロビンでマージする。
    ///
    /// 各スコープ内は新しい順に並んでいる (record 時に先頭挿入) が、スコープ間の記録時刻は
    /// 持っていないため単純連結だと 1 スコープが先頭を独占する。ラウンドロビンで偏りを均しつつ、
    /// `Set` 化のような順序シャッフルは行わない (再描画のたびに順序が変わらないようにするため)。
    private func recentHistory() -> [String] {
        let lists = scope.historyScopes.map { SearchHistoryManager.shared.history(for: $0) }
        guard lists.count > 1 else { return Array((lists.first ?? []).prefix(15)) }

        var seen = Set<String>()
        var merged: [String] = []
        let maxCount = lists.map(\.count).max() ?? 0
        for index in 0 ..< maxCount {
            for list in lists where index < list.count {
                if seen.insert(list[index]).inserted { merged.append(list[index]) }
            }
        }
        return Array(merged.prefix(15))
    }

    private func deleteHistoryItem(_ item: String) {
        for s in scope.historyScopes {
            SearchHistoryManager.shared.remove(query: item, scope: s)
        }
        historyVersion += 1
    }

    // MARK: - 検索実行

    private var visibleResultCount: Int {
        var count = 0
        if scope.includes(.idols) { count += results.idols.count }
        if scope.includes(.songs) { count += results.songs.count }
        if scope.includes(.events) { count += results.events.count }
        if scope.includes(.lyrics) { count += lyricsHits.count }
        return count
    }

    /// 歌詞検索に入力があるか (簡易/詳細のどちらでも)。
    private var lyricsHasInput: Bool {
        lyricsAdvanced
            ? lyricsQuery.hasAnyTerm
            : !lyricsSimpleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func clearResults() {
        results = SearchResults(songs: [], idols: [], events: [])
        matchedVenues = [:]
        lyricsHits = []
        lyricsSongs = [:]
        lyricsNeedsLogin = false
        searchFailed = false
        lyricsAwaitingSubmit = false
        isSearching = false
        searchTask?.cancel()
    }

    private func scheduleSearch(_ query: String, debounce: Bool = true) {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearResults()
            return
        }

        let currentScope = scope

        // サーバを叩くスコープ (歌詞) は入力中に検索しない。確定 (Enter) で初めて投げる。
        //
        // debounce を挟んでも、打ち直すたびに Worker と D1 を叩くことになる。
        // 歌詞検索は1回で D1 の全走査に近い読み取りが走る (索引で候補は絞れるが、
        // 候補の検証で本文を読む) ので、無料枠を打鍵回数で消費する形にしたくない。
        // ローカル DB で完結する他スコープは従来どおり打ちながら絞る。
        if currentScope.isServerBacked && debounce {
            lyricsHits = []
            lyricsSongs = [:]
            lyricsNeedsLogin = false
            searchFailed = false
            isSearching = false
            lyricsAwaitingSubmit = true
            return
        }
        lyricsAwaitingSubmit = false

        isSearching = true
        searchFailed = false
        searchTask = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            do {
                if currentScope == .lyrics {
                    try await searchLyrics(query: trimmed)
                } else {
                    let r = try await fetchResults(query: trimmed, scope: currentScope)
                    try Task.checkCancellation()
                    results = r
                    matchedVenues = await resolveMatchedVenues(query: trimmed, events: r.events)
                }
                isSearching = false
            } catch is CancellationError {
                // キャンセル済み。結果は捨てる (isSearching は後続タスクが引き継ぐ)。
            } catch {
                // 失敗を空振りと同じ「見つかりません」で出さない。区別が付かないと、
                // サーバ側の不具合が「その語は無いんだな」に見えて発覚が遅れる。
                Logger.database.error("search_failed: \(error.localizedDescription)")
                searchFailed = true
                isSearching = false
            }
        }
    }

    /// 歌詞検索。サーバは song_id とスニペットしか返さないので、曲そのものは
    /// 同梱 SQLite から引き直す (サーバはマスタを持っていない)。
    private func searchLyrics(query: String) async throws {
        lyricsNeedsLogin = false
        guard query.count >= LyricsAPI.minSearchLength else {
            lyricsHits = []
            lyricsSongs = [:]
            return
        }
        do {
            let hits = try await AppContainer.shared.lyricsSearchReading.searchLyrics(query: query)
            try Task.checkCancellation()
            // 曲が引けなかったヒットは表示できないので落とす (端末の DB が古い場合など)。
            // 併せて一覧と同じ規則で派生曲 (ソロ Ver. / Remix) とその他ブランドを外す。
            // 派生曲は歌詞が親と同一なので、残すと同じ歌詞が何件も並んで読めなくなる。
            let songs = try await AppContainer.shared.songReading
                .listableSongs(ids: hits.map(\.songId))
            try Task.checkCancellation()
            let byId = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
            lyricsSongs = byId
            lyricsHits = hits.filter { byId[$0.songId] != nil }
        } catch APIClientError.notAuthorized {
            // 歌詞はログイン必須。空振りと区別して案内を出す。
            lyricsNeedsLogin = true
            lyricsHits = []
            lyricsSongs = [:]
        }
    }

    /// スコープに応じた取得。「すべて」は横断検索 (各20件上限) を 1 発、
    /// スコープ指定時は該当エンティティのポートを深い上限で引く。
    private func fetchResults(query: String, scope: UnifiedSearchScope) async throws -> SearchResults {
        let container = AppContainer.shared
        switch scope {
        case .all:
            return try await container.globalSearchReading.search(query: query)
        case .idols:
            let idols = try await container.idolReading.searchIdols(query: query, limit: 200)
            return SearchResults(songs: [], idols: idols, events: [])
        case .songs:
            let songs = try await container.songReading.searchSongs(query: query, limit: 200)
            return SearchResults(songs: songs, idols: [], events: [])
        case .events:
            let events = try await container.eventReading.searchEventsByNameOrVenue(query: query, limit: 200)
            return SearchResults(songs: [], idols: [], events: events)
        case .lyrics:
            // 歌詞はローカル DB に無いので別経路 (searchLyrics)。ここには来ない。
            return SearchResults(songs: [], idols: [], events: [])
        }
    }

    /// 会場一致で拾えたイベントの会場名を解決する。ライブ名自体が一致している行には出さない
    /// (自明な情報でリストを埋めないため)。
    private func resolveMatchedVenues(query: String, events: [Event]) async -> [String: String] {
        guard !events.isEmpty else { return [:] }
        let lower = query.lowercased()
        let byVenueOnly = events.filter { !$0.name.lowercased().contains(lower) }
        guard !byVenueOnly.isEmpty else { return [:] }
        return (try? await AppContainer.shared.showReading.venuesMatching(
            query: query,
            eventIds: byVenueOnly.map(\.id)
        )) ?? [:]
    }

    private func commitSearch() {
        // 歌詞スコープの入力は専用の口にある。確定のたびに式へ組み立て直す。
        if scope == .lyrics {
            searchText = lyricsAdvanced
                ? lyricsQuery.serialized()
                : LyricsQueryNode.simpleQuery(lyricsSimpleText)
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // 「すべて」スコープでは、実際にヒットしたスコープにだけ記録する。常に固定スコープへ
        // 記録すると、曲に関係ない検索語が楽曲の履歴を汚染してしまう。
        for s in recordScopes() {
            SearchHistoryManager.shared.record(query: trimmed, scope: s)
        }
        historyVersion += 1
        scheduleSearch(trimmed, debounce: false)
    }

    private func recordScopes() -> [SearchScope] {
        guard scope == .all else { return scope.historyScopes }
        var matched: [SearchScope] = []
        if !results.idols.isEmpty { matched.append(.idols) }
        if !results.songs.isEmpty { matched.append(.songs) }
        if !results.events.isEmpty { matched.append(.events) }
        return matched.isEmpty ? [.songs] : matched
    }
}

// MARK: - スコープ

/// 検索スコープ。`SearchScope` (履歴保存キー) とは別物で、こちらは UI 上の絞り込み単位。
enum UnifiedSearchScope: String, CaseIterable, Hashable {
    case all, events, songs, idols, lyrics

    /// 画面に出すスコープ。歌詞は JASRAC の許諾が下りるまで Release ビルドに載せない
    /// (`LyricsFeature`)。`SongDetailTab.available` と同じ流儀。
    static var available: [UnifiedSearchScope] {
        allCases.filter { $0 != .lyrics || LyricsFeature.isAvailable }
    }

    /// 出せないスコープを指定されたときの落とし所。
    var resolved: UnifiedSearchScope { Self.available.contains(self) ? self : .all }

    var label: String {
        switch self {
        case .all:    "すべて"
        case .events: "ライブ"
        case .songs:  "楽曲"
        case .idols:  "アイドル"
        case .lyrics: "歌詞"
        }
    }

    var prompt: String {
        switch self {
        case .all:    "ライブ・楽曲・アイドルを検索"
        case .events: "ライブ名 / 会場で検索"
        case .songs:  "曲名で検索"
        case .idols:  "アイドル名 / CV名で検索"
        case .lyrics: "歌詞の一節で検索"
        }
    }

    var emptyNoun: String {
        switch self {
        case .all:    "項目"
        case .events: "ライブ"
        case .songs:  "楽曲"
        case .idols:  "アイドル"
        case .lyrics: "歌詞"
        }
    }

    /// サーバ (D1) に問い合わせるスコープか。ローカル DB で完結しないので、
    /// debounce やログイン要求の扱いが他と違う。
    var isServerBacked: Bool { self == .lyrics }

    /// このスコープで結果セクションを表示するか。
    ///
    /// 歌詞は `.all` に混ぜない。`.all` は同梱 SQLite で完結する即応検索なのに対し、
    /// 歌詞はネットワーク + 認証が要る。混ぜると 1 文字打つたびに Worker を叩くことになり、
    /// 無料枠 (10万req/日) を検索で焼く。探しに来た人だけがスコープを選んで叩く形にする。
    func includes(_ other: UnifiedSearchScope) -> Bool {
        if other == .lyrics { return self == .lyrics }
        return self == .all || self == other
    }

    /// 履歴の読み書き対象。`.all` は 3 スコープ全部。
    ///
    /// 歌詞検索は専用キーを作らず楽曲の履歴に載せる。探しているものは結局曲であって、
    /// 「歌詞で探したか曲名で探したか」で履歴を分けても使う側の得にならない。
    var historyScopes: [SearchScope] {
        switch self {
        case .all:    [.events, .songs, .idols]
        case .events: [.events]
        case .songs, .lyrics: [.songs]
        case .idols:  [.idols]
        }
    }
}
