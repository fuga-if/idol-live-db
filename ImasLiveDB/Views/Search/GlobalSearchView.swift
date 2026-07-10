import os
import SwiftUI

struct GlobalSearchView: View {
    /// 各タブの個別検索から「全体検索」へ引き継ぐ初期クエリ。空なら通常の空状態で開く。
    var initialQuery: String = ""

    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var results = SearchResults(songs: [], idols: [], events: [])
    @State private var sheetDestination: DetailDestination?
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                Divider()
                resultContent
            }
            .navigationTitle("検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .onAppear {
            if searchText.isEmpty && !initialQuery.isEmpty {
                searchText = initialQuery
                scheduleSearch(initialQuery)
            }
            isTextFieldFocused = true
        }
        .sheet(item: $sheetDestination) { dest in
            DetailSheetView(destination: dest)
                .environment(database)
        }
        .trackScreen("global_search")
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DS.ink2)
            TextField("楽曲・アイドル・イベントを検索", text: $searchText)
                .focused($isTextFieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { commitSearch() }
                .onChange(of: searchText) { _, newValue in scheduleSearch(newValue) }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    results = SearchResults(songs: [], idols: [], events: [])
                    isSearching = false
                    searchTask?.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.ink2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DS.bg)
    }

    // MARK: - Result Content

    @ViewBuilder
    private var resultContent: some View {
        if searchText.isEmpty {
            historyView
        } else if isSearching {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            ImasEmptyState(
                systemImage: "magnifyingglass",
                title: "検索結果がありません",
                message: "\"\(searchText)\" に一致する結果が見つかりませんでした"
            )
        } else {
            List {
                if !results.idols.isEmpty {
                    Section("アイドル") {
                        ForEach(results.idols) { idol in
                            Button { sheetDestination = .idol(idol) } label: {
                                IdolNameRow(idol: idol)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(DS.surface)
                            .listRowSeparatorTint(DS.sep)
                        }
                    }
                }
                if !results.songs.isEmpty {
                    Section("楽曲") {
                        ForEach(results.songs) { song in
                            // Button でラップすると内側のジャケ写プレビュー再生タップが
                            // 吸われるため、行全体は onTapGesture で遷移を受ける。
                            SongTitleRow(song: song)
                                .contentShape(Rectangle())
                                .onTapGesture { sheetDestination = .song(song) }
                                .listRowBackground(DS.surface)
                                .listRowSeparatorTint(DS.sep)
                        }
                    }
                }
                if !results.events.isEmpty {
                    Section("イベント") {
                        ForEach(results.events) { event in
                            Button {
                                sheetDestination = .event(event)
                            } label: {
                                EventNameRow(event: event)
                            }
                            .listRowBackground(DS.surface)
                            .listRowSeparatorTint(DS.sep)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DS.bg)
        }
    }

    // MARK: - History View

    @ViewBuilder
    private var historyView: some View {
        let history = mergedRecentHistory()
        if history.isEmpty {
            ImasEmptyState(
                systemImage: "clock.arrow.circlepath",
                title: "検索履歴はありません"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.bg)
        } else {
            List {
                Section {
                    ForEach(history.prefix(10), id: \.self) { item in
                        Button {
                            searchText = item
                            commitSearch()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock")
                                    .foregroundStyle(DS.ink2)
                                    .frame(width: 20)
                                Text(item)
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
                    }
                } header: {
                    HStack {
                        Text("最近の検索")
                        Spacer()
                        Button("クリア") {
                            SearchHistoryManager.shared.clearAll()
                        }
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DS.bg)
        }
    }

    // MARK: - Logic

    /// events/songs/idols の3スコープの検索履歴を、重複を除きつつ recency 順に近い形でマージする。
    /// 各スコープ内は新しい順に並んでいる (record 時に先頭挿入) が、スコープ間の記録時刻は
    /// 持っていないため、単純連結だと常に同じスコープが先頭を独占して非決定的にも見える。
    /// ここではラウンドロビン方式(各スコープの新しい方から順番に取り出す)でスコープ間の
    /// 偏りを均しつつ、`Set` 化のような順序シャッフルは行わない(再描画のたびに順序が
    /// 変わらないようにするため)。
    private func mergedRecentHistory() -> [String] {
        let lists = [
            SearchHistoryManager.shared.history(for: .events),
            SearchHistoryManager.shared.history(for: .songs),
            SearchHistoryManager.shared.history(for: .idols),
        ]
        var seen = Set<String>()
        var merged: [String] = []
        let maxCount = lists.map(\.count).max() ?? 0
        for index in 0..<maxCount {
            for list in lists {
                guard index < list.count else { continue }
                let item = list[index]
                if seen.insert(item).inserted {
                    merged.append(item)
                }
            }
        }
        return merged
    }

    private func scheduleSearch(_ query: String) {
        searchTask?.cancel()

        guard !query.isEmpty else {
            results = SearchResults(songs: [], idols: [], events: [])
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }

            do {
                let r = try await AppContainer.shared.globalSearchReading.search(query: query)
                try Task.checkCancellation()
                results = r
            } catch is CancellationError {
                // キャンセル済み、結果は捨てる
            } catch {
                Logger.database.error("search_failed: \(error.localizedDescription)")
            }
            if !Task.isCancelled {
                isSearching = false
            }
        }
    }

    private func commitSearch() {
        guard !searchText.isEmpty else { return }
        // グローバル検索なので、直前の検索結果 (results) で実際にヒットしたスコープにのみ記録する。
        // 常に .songs 固定だと、曲に関係ない検索語がタブ別(曲一覧)の検索履歴を汚染してしまう。
        // まだ結果が確定していない/ノーヒットの場合は songs にフォールバックする。
        var matchedScopes: [SearchScope] = []
        if !results.idols.isEmpty { matchedScopes.append(.idols) }
        if !results.songs.isEmpty { matchedScopes.append(.songs) }
        if !results.events.isEmpty { matchedScopes.append(.events) }
        if matchedScopes.isEmpty { matchedScopes = [.songs] }
        for scope in matchedScopes {
            SearchHistoryManager.shared.record(query: searchText, scope: scope)
        }
        scheduleSearch(searchText)
    }
}
