import os
import SwiftUI

struct GlobalSearchView: View {
    /// 各タブの個別検索から「全体検索」へ引き継ぐ初期クエリ。空なら通常の空状態で開く。
    var initialQuery: String = ""

    @Environment(AppDatabase.self) private var database
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
            ContentUnavailableView.search(text: searchText)
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
                            Button { sheetDestination = .song(song) } label: {
                                SongTitleRow(song: song)
                            }
                            .buttonStyle(.plain)
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

    private var historyView: some View {
        let history = SearchHistoryManager.shared.history(for: .events) +
                      SearchHistoryManager.shared.history(for: .songs) +
                      SearchHistoryManager.shared.history(for: .idols)
        return List {
            if history.isEmpty {
                Text("検索履歴はありません")
                    .foregroundStyle(DS.ink2)
                    .font(.imasSubhead)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(Array(Set(history)).prefix(10), id: \.self) { item in
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
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.bg)
    }

    // MARK: - Logic

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
        SearchHistoryManager.shared.record(query: searchText, scope: .songs)
        scheduleSearch(searchText)
    }
}
