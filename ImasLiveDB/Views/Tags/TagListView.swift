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

    /// 名前絞り込み適用後のタグ。名前・説明の部分一致で絞る。
    private var filteredTags: [CommunityTag] {
        let trimmed = nameFilter.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return vm.tags }
        return vm.tags.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || ($0.description?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            List {
                Section {
                    NameFilterField(prompt: "タグ名で絞り込み", text: $nameFilter)
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
                            Button {
                                AppAnalytics.tap("tag_list.create")
                                showCreateSheet = true
                            } label: {
                                Image(systemName: "plus")
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
        VStack(alignment: .leading, spacing: DS.sp2) {
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
                        .font(.imasCaption2)
                        .foregroundStyle(DS.ink2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, DS.sp1)
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
        .padding(.vertical, DS.sp1)
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
            .padding(.vertical, DS.sp1)
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
