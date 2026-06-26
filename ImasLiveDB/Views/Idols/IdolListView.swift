import os
import SwiftUI

enum IdolDisplayMode: String, CaseIterable {
    case idolName = "アイドル名"
    case cvName = "CV名"
}

enum IdolListMode: String, CaseIterable {
    case list
    case grid
}

struct IdolListView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(CloudKitSyncEngine.self) private var syncEngine
    @AppStorage("defaultBrandId") private var defaultBrandId: String = ""
    @AppStorage("idol_list_mode") private var idolListModeRaw: String = IdolListMode.list.rawValue
    @State private var navPath = NavigationPath()
    @State private var vm = IdolListViewModel()
    @FocusState private var searchFieldFocused: Bool
    @AppStorage("idol_display_mode") private var displayModeRaw: String = IdolDisplayMode.idolName.rawValue
    /// アイドル名表示中に CV 名を別行で併記するか。
    @AppStorage("idol_show_cv") private var showCV: Bool = false

    private var displayMode: IdolDisplayMode {
        IdolDisplayMode(rawValue: displayModeRaw) ?? .idolName
    }
    @State private var selectedBrandIds: Set<String> = []
    @State private var selectedAttribute: String? = nil
    @AppStorage("idols_require_my_pick") private var requireMyPick: Bool = false
    @AppStorage("idols_require_favorite") private var requireFavorite: Bool = false
    @AppStorage("idols_require_note") private var requireNote: Bool = false
    @State private var collapsedBrands: Set<String> = []
    @State private var sheetIdol: Idol?
    @State private var showFilterSheet = false
    @State private var searchText = ""
    @State private var isSearching = false

    private var idolListMode: IdolListMode {
        IdolListMode(rawValue: idolListModeRaw) ?? .list
    }

    private var activeFilterCount: Int {
        (selectedBrandIds.isEmpty ? 0 : 1)
        + (selectedAttribute != nil ? 1 : 0)
        + (requireMyPick ? 1 : 0)
        + (requireFavorite ? 1 : 0)
        + (requireNote ? 1 : 0)
    }

    private var brandsKey: String {
        selectedBrandIds.isEmpty ? "" : selectedBrandIds.sorted().joined(separator: ",")
    }

    /// 絞り込み状態をまとめた識別子（task(id:) 用。selectedBrandIds 等の変化でのみ再計算）。
    private var filterKey: String {
        "\(brandsKey)_\(selectedAttribute ?? "")_\(requireMyPick)_\(requireFavorite)_\(requireNote)"
    }

    private var filterBadgeCount: Int {
        var count = activeFilterCount
        if displayMode != .idolName { count += 1 }
        return count
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                if isSearching { searchBar }

                if !searchText.isEmpty && vm.filteredIdols.isEmpty {
                    InTabSearchEmptyView(query: searchText)
                } else if idolListMode == .grid {
                    IdolGridView(
                        idols: vm.filteredIdols,
                        brands: vm.visibleBrands,
                        pickIds: vm.pickIds
                    ) { idol in
                        sheetIdol = idol
                    }
                } else {
                    listBody
                }
            }
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle("アイドル")
            .navigationBarTitleDisplayMode(.large)
            .onChange(of: searchText) { _, _ in
                vm.rebuild(filter: filterContext)
            }
            .onChange(of: isSearching) { _, newValue in
                searchFieldFocused = newValue
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsToolbarButton()
                }
                ToolbarItem(placement: .topBarLeading) {
                    GlobalSearchToolbarButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            AppAnalytics.tap("idol_list.grid_toggle")
                            idolListModeRaw = (idolListMode == .grid ? IdolListMode.list : .grid).rawValue
                        } label: {
                            Image(systemName: idolListMode == .grid ? "list.bullet" : "square.grid.3x2")
                        }

                        Button {
                            AppAnalytics.tap("idol_list.search_open")
                            isSearching = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }

                        if filterBadgeCount > 0 {
                            Button {
                                AppAnalytics.tap("idol_list.filter_clear")
                                selectedBrandIds = []
                                selectedAttribute = nil
                                displayModeRaw = IdolDisplayMode.idolName.rawValue
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("フィルタを解除")
                        }

                        FilterBarButton(activeCount: filterBadgeCount) {
                            AppAnalytics.tap("idol_list.filter")
                            showFilterSheet = true
                        }
                    }
                    .tint(DS.ink)
                }
            }
            .navigationDestination(for: Idol.self) { idol in
                IdolDetailView(idol: idol)
            }
            .sheet(item: $sheetIdol) { idol in
                DetailSheetView(destination: .idol(idol))
                    .environment(database)
            }
            .sheet(isPresented: $showFilterSheet) {
                IdolFilterSheet(
                    selectedBrandIds: $selectedBrandIds,
                    selectedAttribute: $selectedAttribute,
                    displayMode: Binding(
                        get: { displayMode },
                        set: { displayModeRaw = $0.rawValue }
                    ),
                    showCV: $showCV,
                    requireMyPick: $requireMyPick,
                    requireFavorite: $requireFavorite,
                    requireNote: $requireNote
                )
                .environment(database)
                .presentationDetents([.medium, .large])
            }
            .task { await vm.loadData(filter: filterContext) }
            // フィルタ変化時のみ再計算
            .task(id: filterKey) {
                vm.refreshPickIds()
                vm.rebuild(filter: filterContext)
            }
            .onAppear {
                if !defaultBrandId.isEmpty && selectedBrandIds.isEmpty {
                    selectedBrandIds = [defaultBrandId]
                }
                vm.refreshPickIds()
            }
            .trackScreen("idol_list")
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(DS.ink3)
            TextField("アイドル・CV名で検索", text: $searchText)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .focused($searchFieldFocused)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(DS.ink3)
                }
            }
            Button("キャンセル") {
                searchText = ""
                isSearching = false
                searchFieldFocused = false
            }
            .font(.imasSubhead)
            .tint(DS.sys)
        }
        .padding(.horizontal, DS.sp4)
        .padding(.vertical, DS.sp3)
        .background(DS.surface)
        .overlay(alignment: .bottom) { Divider().overlay(DS.sep) }
    }

    // MARK: - List Body (ブランド別・inset grouped 風)

    private var listBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.sp6, pinnedViews: []) {
                ForEach(vm.visibleBrands) { brand in
                    let group = vm.groupedByBrand[brand.id] ?? []
                    VStack(alignment: .leading, spacing: DS.sp3) {
                        brandSectionHeader(brand, count: group.count)
                            .padding(.horizontal, DS.sp2)

                        if !collapsedBrands.contains(brand.id) {
                            ImasListContainer {
                                ForEach(Array(group.enumerated()), id: \.element.id) { index, idol in
                                    if index > 0 { Divider().overlay(DS.sep).padding(.leading, 58) }
                                    NavigationLink(value: idol) {
                                        IdolRowView(
                                            idol: idol,
                                            brandColor: brand.color,
                                            isPick: vm.pickIds.contains(idol.id),
                                            displayName: displayName(for: idol),
                                            secondary: secondaryText(for: idol),
                                            cvLine: cvText(for: idol)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DS.sp5)
                }
            }
            .padding(.top, DS.sp3)
            .padding(.bottom, DS.sp7)
        }
        .refreshable {
            await syncEngine.performIncrementalSync(database: database)
            await vm.loadData(filter: filterContext)
        }
    }

    // MARK: - Section Header

    private func brandSectionHeader(_ brand: Brand, count: Int) -> some View {
        Button {
            toggleBrand(brand.id)
        } label: {
            HStack(spacing: DS.sp3) {
                BrandSectionHeader(brand: brand, count: count)
                Image(systemName: collapsedBrands.contains(brand.id) ? "chevron.right" : "chevron.down")
                    .font(.imasScaled( 12, weight: .semibold))
                    .foregroundStyle(DS.ink3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleBrand(_ brandId: String) {
        if collapsedBrands.contains(brandId) {
            collapsedBrands.remove(brandId)
        } else {
            collapsedBrands.insert(brandId)
        }
    }

    // MARK: - Filter Context

    /// View 側の選択状態 + マーク集合 (UserMarkService 参照は @Observable 観測のため View 文脈) を
    /// 純粋 UseCase 用の条件オブジェクトへまとめる。castNames は VM 側で補完するので渡さない。
    private var filterContext: IdolFilterContext {
        let markService = UserMarkService.shared
        var ctx = IdolFilterContext(
            selectedBrandIds: selectedBrandIds,
            selectedAttribute: selectedAttribute,
            searchText: searchText)
        if requireMyPick {
            ctx.requireMyPick = true
            ctx.myPickIds = Set(markService.allMarked(kind: .myPick, entity: .idol))
        }
        if requireFavorite {
            ctx.requireFavorite = true
            ctx.favoriteIds = Set(markService.allMarked(kind: .favorite, entity: .idol))
        }
        if requireNote {
            ctx.requireNote = true
            ctx.noteIds = Set(markService.allMarked(kind: .note, entity: .idol))
        }
        return ctx
    }

    // MARK: - Row Text

    private func displayName(for idol: Idol) -> String {
        displayMode == .cvName ? (vm.castNames[idol.id] ?? idol.name) : idol.name
    }

    /// 2 行目 (読み or アイドル名)。CV 表示中はタイトルが CV 名なので副題はアイドル名、
    /// それ以外は読み (旧実装は CV 表示でも読みがアイドルのままだった不整合を解消)。
    private func secondaryText(for idol: Idol) -> String? {
        displayMode == .cvName ? idol.name : idol.nameKana
    }

    /// 3 行目の CV 行 (別行)。CV 併記 ON かつアイドル名表示中のみ
    /// (CV 表示中は CV がタイトルなので併記不要)。読みと連結せず独立行で出して途中改行を防ぐ。
    private func cvText(for idol: Idol) -> String? {
        guard showCV, displayMode == .idolName, let cv = vm.castNames[idol.id] else { return nil }
        return "CV: \(cv)"
    }
}

// MARK: - IdolRowView

/// 行頭リードバー (アイドル色/ブランド) + IdolAvatarView(担当は二重輪) + 名前 + サブ(よみ/CV) + シェブロン。
private struct IdolRowView: View {
    let idol: Idol
    var brandColor: String? = nil
    var isPick: Bool = false
    let displayName: String
    var secondary: String? = nil
    var cvLine: String? = nil

    var body: some View {
        HStack(spacing: DS.sp3) {
            ImasLeadBar(seed: idol.color, brand: brandColor)
                .padding(.vertical, 5)

            IdolAvatarView(idol: idol, size: 40, isPick: isPick)

            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.imasSubhead.weight(.semibold))
                    .foregroundStyle(DS.ink)
                    .lineLimit(1)
                if let secondary, !secondary.isEmpty {
                    Text(secondary)
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                        .lineLimit(1)
                }
                if let cvLine, !cvLine.isEmpty {
                    Text(cvLine)
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DS.sp2)

            MyPickToggleButton(id: idol.id)
            FavoriteToggleButton(entity: .idol, id: idol.id)

            Image(systemName: "chevron.right")
                .font(.imasScaled( 14, weight: .semibold))
                .foregroundStyle(DS.ink3)
                .padding(.trailing, DS.sp2)
        }
        .padding(.vertical, DS.sp3)
        .padding(.leading, DS.sp2)
        .contentShape(Rectangle())
    }
}

// MARK: - Idol Search Screen

private struct IdolSearchScreen: View {
    let idols: [Idol]
    let castNames: [String: String]
    @Binding var sheetIdol: Idol?

    var body: some View {
        SearchScreen(
            prompt: "アイドル・CV名で検索",
            historyScope: .idols,
            searchAction: { query in
                let lower = query.lowercased()
                return idols.filter { idol in
                    idol.name.lowercased().contains(lower) ||
                    idol.nameKana?.lowercased().contains(lower) == true ||
                    (castNames[idol.id] ?? "").lowercased().contains(lower)
                }
            },
            suggestionsAction: { query in
                let lower = query.lowercased()
                return idols
                    .filter {
                        $0.name.lowercased().contains(lower) ||
                        $0.nameKana?.lowercased().contains(lower) == true ||
                        (castNames[$0.id] ?? "").lowercased().contains(lower)
                    }
                    .prefix(8)
                    .map { idol in
                        SearchSuggestionItem(
                            text: idol.name,
                            subtitle: castNames[idol.id].map { "CV: \($0)" },
                            icon: "person.fill"
                        )
                    }
            }
        ) { idol in
            Button {
                sheetIdol = idol
            } label: {
                IdolNameRow(idol: idol, subtitle: idol.nameKana)
            }
            .buttonStyle(.plain)
        }
    }
}
