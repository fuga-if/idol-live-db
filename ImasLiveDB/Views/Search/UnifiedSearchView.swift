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
    /// 各タブの虫眼鏡から引き継ぐ初期スコープ。
    var initialScope: UnifiedSearchScope = .all
    /// 外部から引き継ぐ初期クエリ (ディープリンク等)。空なら履歴表示で開く。
    var initialQuery: String = ""

    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var scope: UnifiedSearchScope = .all
    @State private var results = SearchResults(songs: [], idols: [], events: [])
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var path: [DetailDestination] = []
    @State private var historyVersion = 0
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                searchField
                scopeBar
                Divider().overlay(DS.sep)
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
            scope = initialScope
            if searchText.isEmpty && !initialQuery.isEmpty {
                searchText = initialQuery
                scheduleSearch(initialQuery)
            }
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
                        .font(.imasScaled(15))
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

    private var scopeBar: some View {
        ImasSegmented(options: UnifiedSearchScope.allCases, selection: $scope) { $0.label }
            .padding(.horizontal, DS.sp5)
            .padding(.bottom, DS.sp4)
            // スコープを変えたら、そのスコープの検索結果を取り直す
            // (「すべて」は 各20件上限、スコープ指定時はより深く引く)。
            .onChange(of: scope) { _, _ in
                AppAnalytics.tap("search.scope_change")
                guard !searchText.isEmpty else { return }
                scheduleSearch(searchText, debounce: false)
            }
    }

    // MARK: - 本体

    @ViewBuilder
    private var content: some View {
        if searchText.isEmpty {
            historyView
        } else if isSearching {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.bg)
        } else if visibleResultCount == 0 {
            ImasEmptyState(
                systemImage: "magnifyingglass",
                title: "見つかりません",
                message: "「\(searchText)」に一致する\(scope.emptyNoun)がありません"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, DS.sp8)
            .background(DS.bg)
        } else {
            resultsList
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
                            SongTitleRow(song: song)
                        }
                        .listRowBackground(DS.surface)
                        .listRowSeparatorTint(DS.sep)
                    }
                } header: {
                    resultSectionHeader("楽曲", count: results.songs.count)
                }
            }
            if scope.includes(.events), !results.events.isEmpty {
                Section {
                    ForEach(results.events) { event in
                        NavigationLink(value: DetailDestination.event(event)) {
                            EventNameRow(event: event)
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
        return count
    }

    private func clearResults() {
        results = SearchResults(songs: [], idols: [], events: [])
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

        isSearching = true
        let currentScope = scope
        searchTask = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            do {
                let r = try await fetchResults(query: trimmed, scope: currentScope)
                try Task.checkCancellation()
                results = r
                isSearching = false
            } catch is CancellationError {
                // キャンセル済み。結果は捨てる (isSearching は後続タスクが引き継ぐ)。
            } catch {
                Logger.database.error("search_failed: \(error.localizedDescription)")
                isSearching = false
            }
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
        }
    }

    private func commitSearch() {
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
    case all, events, songs, idols

    var label: String {
        switch self {
        case .all:    "すべて"
        case .events: "ライブ"
        case .songs:  "楽曲"
        case .idols:  "アイドル"
        }
    }

    var prompt: String {
        switch self {
        case .all:    "ライブ・楽曲・アイドルを検索"
        case .events: "ライブ名 / 会場で検索"
        case .songs:  "曲名で検索"
        case .idols:  "アイドル名 / CV名で検索"
        }
    }

    var emptyNoun: String {
        switch self {
        case .all:    "項目"
        case .events: "ライブ"
        case .songs:  "楽曲"
        case .idols:  "アイドル"
        }
    }

    /// このスコープで結果セクションを表示するか。
    func includes(_ other: UnifiedSearchScope) -> Bool { self == .all || self == other }

    /// 履歴の読み書き対象。`.all` は 3 スコープ全部。
    var historyScopes: [SearchScope] {
        switch self {
        case .all:    [.events, .songs, .idols]
        case .events: [.events]
        case .songs:  [.songs]
        case .idols:  [.idols]
        }
    }
}
