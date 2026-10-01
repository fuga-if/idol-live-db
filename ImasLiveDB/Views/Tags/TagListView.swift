import SwiftUI

/// タグ画面の push 遷移先。値ベース push にして二重 push をスロットルで防ぐ。
enum TagRoute: Hashable {
    case detail(id: String, name: String)
}

struct TagListView: View {
    @State private var navPath = NavigationPath()
    @State private var vm = TagListViewModel()
    @State private var selectedCategory = ""
    @State private var selectedSort = "popular"
    @State private var showCreateSheet = false
    @State private var showFilterSheet = false
    /// 一覧の名前絞り込み。タグは全件 (limit 1000) を取得済みなのでクライアント側で絞る。
    @State private var nameFilter = ""

    private let categories: [(value: String, label: String)] = [
        ("", "全て"), ("mood", "ムード"), ("scene", "シーン"), ("special", "特別"), ("free", "フリー")
    ]
    private let sortOptions: [(value: String, label: String)] = [
        ("popular", "人気"), ("recent", "新着"), ("name", "名前")
    ]

    private var activeFilterCount: Int {
        (selectedCategory.isEmpty ? 0 : 1) + (nameFilter.isEmpty ? 0 : 1)
    }

    /// 名前絞り込み用の索引。`vm.tags` が入れ替わった時だけ組み直す。
    /// 照合はコア (`domain/text_search_index.rs`) に一任するので、他の一覧と同じく
    /// ひらがな↔カタカナを畳む (タグ名はユーザーが打つ自由文字列なので揺れが大きい)。
    @State private var catalog: TextSearchCatalog?

    /// 名前絞り込み適用後のタグ。名前・説明の部分一致で絞る。
    private var filteredTags: [CommunityTag] {
        let trimmed = nameFilter.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return vm.tags }
        // 索引が無い間は絞り込まない (黙って 0 件にする方が悪い)。
        guard let catalog else { return vm.tags }
        return catalog.filter(vm.tags, needle: trimmed)
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            List {
                Section {
                    ImasNameFilterField(prompt: "タグ名で絞り込み", text: $nameFilter)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                }
                .listRowBackground(Color.clear)

                if vm.isLoading {
                    ImasInlineLoading()
                        .listRowBackground(Color.clear)
                } else if filteredTags.isEmpty {
                    ImasEmptyState(
                        systemImage: nameFilter.isEmpty ? "tag" : "line.3.horizontal.decrease",
                        title: nameFilter.isEmpty ? "タグはまだありません" : "絞り込み結果がありません",
                        message: nameFilter.isEmpty ? nil : "「\(nameFilter)」に一致するタグがありません"
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(Array(filteredTags.enumerated()), id: \.element.id) { idx, tag in
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
                    HStack(spacing: DS.sp3) {
                        FilterBarButton(activeCount: activeFilterCount) {
                            showFilterSheet = true
                        }

                        // 未サインイン時は押しても汎用エラーになりログイン導線も出ないため、
                        // PollListView と同様にボタン自体を出し分ける。
                        if AuthService.shared.isSignedIn {
                            ImasToolbarButton(systemImage: "plus", label: "タグを作成") {
                                AppAnalytics.tap("tag_list.create")
                                showCreateSheet = true
                            }
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
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                TagCreateSheet(onCreated: { newTag in
                    vm.insertCreated(newTag)
                })
            }
            .sheet(isPresented: $showFilterSheet) {
                TagFilterSheet(
                    categories: categories,
                    sortOptions: sortOptions,
                    selectedCategory: $selectedCategory,
                    selectedSort: $selectedSort
                )
                .presentationDetents([.medium, .large])
                .onDisappear { vm.scheduleLoad(category: selectedCategory, sort: selectedSort, debounce: false) }
            }
            .task { await vm.load(category: selectedCategory, sort: selectedSort) }
            // タグは category / sort を変えるたびに読み直す。索引もそれに追随させる
            // (id 列を鍵にするので、件数が同じで中身だけ入れ替わっても組み直る)。
            .onChange(of: vm.tags.map(\.id), initial: true) { _, _ in
                catalog = TextSearchCatalog(fieldsPerItem: vm.tags.map { [$0.name, $0.description] })
            }
            .onChange(of: selectedCategory) { _, _ in vm.scheduleLoad(category: selectedCategory, sort: selectedSort, debounce: false) }
            .onChange(of: selectedSort) { _, _ in vm.scheduleLoad(category: selectedCategory, sort: selectedSort, debounce: false) }
            .trackScreen("tag_list")
        }
    }
}

struct TagRowView: View {
    let tag: CommunityTag
    /// 人気ランキングでの順位 (1始まり)。nil の時は順位を出さない。
    var rank: Int? = nil

    var body: some View {
        HStack(spacing: DS.Space.gapTight) {
            if let rank {
                ImasRankBadge(rank: rank)
            }
            ImasRow(
                title: tag.name,
                subtitle: tag.description.flatMap { $0.isEmpty ? nil : String($0.prefix(40)) },
                leading: tag.color.map { .custom(AnyView(ImasSwatch(hex: $0.rawValue, size: .small)), width: 16) } ?? .none,
                trailing: .custom(AnyView(
                    HStack(spacing: DS.Space.gapTight) {
                        if let cat = tag.category {
                            ImasBadge(text: cat.rawValue, kind: .neutral)
                        }
                        if let uses = tag.totalUses, uses > 0 {
                            Text("\(uses)曲").imasText(.meta)
                        }
                    }
                )),
                density: .compact
            )
            .accessibilityLabel("タグ: \(tag.name)")
        }
    }
}
