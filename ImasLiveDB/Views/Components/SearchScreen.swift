import SwiftUI

/// YouTube 風検索画面 — 虫眼鏡アイコンタップで push される汎用コンポーネント
struct SearchScreen<Result: Identifiable & Sendable, RowContent: View>: View {
    let prompt: String
    let historyScope: SearchScope
    let searchAction: @MainActor (String) async -> [Result]
    let suggestionsAction: @MainActor (String) async -> [SearchSuggestionItem]
    @ViewBuilder let rowBuilder: (Result) -> RowContent

    @State private var searchText = ""
    @State private var results: [Result] = []
    @State private var suggestions: [SearchSuggestionItem] = []
    @State private var history: [String] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
        }
        .navigationTitle("検索")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            history = SearchHistoryManager.shared.history(for: historyScope)
            isTextFieldFocused = true
        }
        .trackScreen("search")
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DS.ink2)
            TextField(prompt, text: $searchText)
                .focused($isTextFieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit {
                    commitSearch()
                }
                .onChange(of: searchText) { _, newValue in
                    scheduleSearch(newValue)
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    results = []
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

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if searchText.isEmpty {
            historyView
        } else if isSearching {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !suggestions.isEmpty && results.isEmpty {
            suggestionsView
        } else if results.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            resultsList
        }
    }

    private var historyView: some View {
        List {
            if history.isEmpty {
                Text("検索履歴はありません")
                    .foregroundStyle(DS.ink2)
                    .font(.imasSubhead)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(history, id: \.self) { item in
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
                        Spacer()
                        Button("クリア") {
                            AppAnalytics.tap("search.clear_history")
                            SearchHistoryManager.shared.clear(scope: historyScope)
                            history = []
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

    private var suggestionsView: some View {
        List {
            Section("候補") {
                ForEach(suggestions) { item in
                    Button {
                        searchText = item.text
                        commitSearch()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: item.icon)
                                .foregroundStyle(DS.ink2)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.text)
                                    .foregroundStyle(DS.ink)
                                if let subtitle = item.subtitle {
                                    Text(subtitle)
                                        .font(.imasCaption)
                                        .foregroundStyle(DS.ink2)
                                }
                            }
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
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.bg)
    }

    private var resultsList: some View {
        List {
            Section {
                ForEach(results) { result in
                    rowBuilder(result)
                        .listRowBackground(DS.surface)
                        .listRowSeparatorTint(DS.sep)
                }
            } header: {
                Text("\(results.count)件")
                    .font(.imasCaption)
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
            results = []
            suggestions = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            async let s = suggestionsAction(query)
            async let r = searchAction(query)
            let (newSuggestions, newResults) = await (s, r)
            guard !Task.isCancelled else { return }
            suggestions = newSuggestions
            results = newResults
            isSearching = false
        }
    }

    private func commitSearch() {
        guard !searchText.isEmpty else { return }
        SearchHistoryManager.shared.record(query: searchText, scope: historyScope)
        history = SearchHistoryManager.shared.history(for: historyScope)
        scheduleSearch(searchText)
    }

    private func deleteHistoryItem(_ item: String) {
        // SearchHistoryManager に個別削除APIがないため、手動で書き換え
        var current = SearchHistoryManager.shared.history(for: historyScope)
        current.removeAll { $0 == item }
        // 全クリアして再登録（逆順で record）
        SearchHistoryManager.shared.clear(scope: historyScope)
        for h in current.reversed() {
            SearchHistoryManager.shared.record(query: h, scope: historyScope)
        }
        history = SearchHistoryManager.shared.history(for: historyScope)
    }
}
