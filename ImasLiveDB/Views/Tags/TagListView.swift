import SwiftUI

/// タグ画面の push 遷移先。値ベース push にして二重 push をスロットルで防ぐ。
enum TagRoute: Hashable {
    case detail(id: String, name: String)
    case search
}

struct TagListView: View {
    @State private var navPath = NavigationPath()
    @State private var tags: [CommunityTag] = []
    @State private var selectedCategory = ""
    @State private var selectedSort = "popular"
    @State private var isLoading = false
    @State private var showCreateSheet = false
    @State private var showFilterSheet = false
    @State private var loadTask: Task<Void, Never>?

    private let categories: [(value: String, label: String)] = [
        ("", "全て"), ("mood", "ムード"), ("scene", "シーン"), ("special", "特別"), ("free", "フリー")
    ]
    private let sortOptions: [(value: String, label: String)] = [
        ("popular", "人気"), ("recent", "新着"), ("name", "名前")
    ]

    private var activeFilterCount: Int {
        selectedCategory.isEmpty ? 0 : 1
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            List {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                } else if tags.isEmpty {
                    Text("タグはまだありません")
                        .foregroundStyle(DS.ink2)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(Array(tags.enumerated()), id: \.element.id) { idx, tag in
                        NavigationLink(value: TagRoute.detail(id: tag.id, name: tag.name)) {
                            // 人気ソート時は順位を出して「人気ランキング」として見せる。
                            TagRowView(tag: tag, rank: selectedSort == "popular" ? idx + 1 : nil)
                        }
                        .listRowBackground(DS.surface)
                        .listRowSeparatorTint(DS.sep)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DS.bg)
            .navigationTitle("タグ")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        NavigationLink(value: TagRoute.search) {
                            Image(systemName: "magnifyingglass")
                        }

                        FilterBarButton(activeCount: activeFilterCount) {
                            showFilterSheet = true
                        }

                        Button {
                            AppAnalytics.tap("tag_list.create")
                            showCreateSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Picker("並び順", selection: $selectedSort) {
                        ForEach(sortOptions, id: \.value) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationDestination(for: TagRoute.self) { route in
                switch route {
                case let .detail(id, name):
                    TagDetailView(tagId: id, tagName: name)
                case .search:
                    TagSearchScreen()
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                TagCreateSheet()
            }
            .sheet(isPresented: $showFilterSheet) {
                TagFilterSheet(
                    categories: categories,
                    sortOptions: sortOptions,
                    selectedCategory: $selectedCategory,
                    selectedSort: $selectedSort
                )
                .presentationDetents([.medium, .large])
                .onDisappear { scheduleLoadTags(debounce: false) }
            }
            .task { await loadTags() }
            .onChange(of: selectedCategory) { _, _ in scheduleLoadTags(debounce: false) }
            .onChange(of: selectedSort) { _, _ in scheduleLoadTags(debounce: false) }
            .trackScreen("tag_list")
        }
    }

    private func scheduleLoadTags(debounce: Bool) {
        loadTask?.cancel()
        loadTask = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            await loadTags()
        }
    }

    private func loadTags() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try Task.checkCancellation()
            let result = try await CommunityAPI.shared.tags(
                search: "",
                category: selectedCategory,
                sort: selectedSort
            )
            try Task.checkCancellation()
            tags = result
        } catch is CancellationError {
            // キャンセル済み
        } catch {
            tags = []
        }
    }
}

struct TagRowView: View {
    let tag: CommunityTag
    /// 人気ランキングでの順位 (1始まり)。nil の時は順位を出さない。
    var rank: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let rank {
                    TagRankBadge(rank: rank)
                }
                if let hexColor = tag.color {
                    Circle()
                        .fill(Color(hexColor: hexColor))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
                Text(tag.name)
                    .font(.imasSubhead.weight(.semibold))
                    .accessibilityLabel("タグ: \(tag.name)")
                if let cat = tag.category {
                    Text(cat.rawValue)
                        .font(.imasScaled(11))
                        .foregroundStyle(DS.ink2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DS.fill)
                        .clipShape(Capsule())
                }
                Spacer()
                if let uses = tag.totalUses, uses > 0 {
                    Text("\(uses)曲")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                }
            }
            if let desc = tag.description, !desc.isEmpty {
                Text(desc.prefix(40))
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Rank Badge

/// 人気ランキングの順位バッジ。上位3つはメダル色 (金/銀/銅)、それ以降はグレー。
/// タグ一覧・楽曲一覧のタグ絞り込みで共用する。
struct TagRankBadge: View {
    let rank: Int

    var body: some View {
        Text("\(rank)")
            .font(.imasCaption.bold().monospacedDigit())
            .foregroundStyle(textColor)
            .frame(minWidth: 22)
            .padding(.vertical, 2)
            .padding(.horizontal, 5)
            .background(bgColor, in: Capsule())
            .accessibilityLabel("\(rank)位")
    }

    private var medalColor: Color? {
        switch rank {
        case 1: return Color(red: 0.91, green: 0.66, blue: 0.0)   // 金
        case 2: return Color(red: 0.66, green: 0.69, blue: 0.72)  // 銀
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20)  // 銅
        default: return nil
        }
    }

    private var textColor: Color { medalColor ?? DS.ink2 }
    private var bgColor: Color { (medalColor ?? DS.ink3).opacity(0.16) }
}

// MARK: - Tag Search Screen

private struct TagSearchScreen: View {
    var body: some View {
        SearchScreen(
            prompt: "タグを検索",
            historyScope: .submissions,
            searchAction: { query in
                (try? await CommunityAPI.shared.tags(search: query, category: "", sort: "popular")) ?? []
            },
            suggestionsAction: { query in
                let results = (try? await CommunityAPI.shared.tags(search: query, category: "", sort: "popular")) ?? []
                return results.prefix(8).map { tag in
                    SearchSuggestionItem(text: tag.name, subtitle: tag.description, icon: "tag")
                }
            }
        ) { tag in
            NavigationLink(value: TagRoute.detail(id: tag.id, name: tag.name)) {
                TagRowView(tag: tag)
            }
        }
    }
}
