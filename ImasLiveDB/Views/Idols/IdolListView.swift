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
    @AppStorage("idol_display_mode") private var displayModeRaw: String = IdolDisplayMode.idolName.rawValue
    /// アイドル名表示中に CV 名を別行で併記するか。
    @AppStorage("idol_show_cv") private var showCV: Bool = false

    private var displayMode: IdolDisplayMode {
        IdolDisplayMode(rawValue: displayModeRaw) ?? .idolName
    }
    @State private var selectedBrandIds: Set<String> = []
    /// `selectedBrandIds` に一度でも変化があったか (デフォルトブランドの自動適用も含む)。
    /// true になった後は `onAppear` でのデフォルトブランド再適用を行わない
    /// (ユーザーが明示的にブランドフィルタを解除した状態で、タブ再訪時に無言で
    /// デフォルトが復活するのを防ぐため)。
    @State private var hasUserInteractedWithBrandFilter = false
    @State private var selectedAttribute: String? = nil
    @AppStorage("idols_require_my_pick") private var requireMyPick: Bool = false
    @AppStorage("idols_require_favorite") private var requireFavorite: Bool = false
    @AppStorage("idols_require_note") private var requireNote: Bool = false
    /// 並び順。公式順以外はブランドの区切りを外した通し表示になる。
    @AppStorage("idols_sort_order") private var sortOrderRaw: String = IdolSortOrder.official.rawValue
    /// nil = sortOrder の既定方向、true=昇順、false=降順。
    @AppStorage("idols_sort_ascending") private var sortAscendingRaw: Int = 0
    @State private var collapsedBrands: Set<String> = []
    @State private var sheetIdol: Idol?
    @State private var showFilterSheet = false
    @State private var searchText = ""
    /// 一覧タブ (0=アイドル, 1=ユニット)。
    @State private var listTab = 0
    /// ユニットタブの ViewModel。ここで hoist して `UnitListContent` に注入することで、
    /// タブ切替で `UnitListContent` が再生成されても検索語・ロード済みデータ・スクロール位置を保持する。
    @State private var unitVM = UnitListViewModel()

    private var idolListMode: IdolListMode {
        IdolListMode(rawValue: idolListModeRaw) ?? .list
    }

    private var sortOrder: IdolSortOrder {
        IdolSortOrder(rawValue: sortOrderRaw) ?? .official
    }

    /// AppStorage は Optional<Bool> を持てないので Int で三値を表す (0=既定 / 1=昇順 / 2=降順)。
    private var sortAscending: Bool? {
        switch sortAscendingRaw {
        case 1: return true
        case 2: return false
        default: return nil
        }
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
    /// 再計算 (`task(id:)`) のトリガーキー。並び順もここに含める
    /// (含め忘れると、フィルタシートで並び順を変えても一覧が旧い並びのまま残る)。
    private var filterKey: String {
        "\(brandsKey)_\(selectedAttribute ?? "")_\(requireMyPick)_\(requireFavorite)_\(requireNote)_\(sortOrderRaw)_\(sortAscendingRaw)"
    }

    private var filterBadgeCount: Int {
        var count = activeFilterCount
        if displayMode != .idolName { count += 1 }
        return count
    }

    private var idolMenuActions: [ListToolbarAction] {
        var actions: [ListToolbarAction] = [
            ListToolbarAction(
                id: "grid",
                title: idolListMode == .grid ? "リスト表示" : "グリッド表示",
                systemImage: idolListMode == .grid ? "list.bullet" : "square.grid.3x2"
            ) {
                AppAnalytics.tap("idol_list.grid_toggle")
                idolListModeRaw = (idolListMode == .grid ? IdolListMode.list : .grid).rawValue
            }
        ]
        if filterBadgeCount > 0 {
            actions.append(ListToolbarAction(id: "clear", title: "フィルタを解除",
                                             systemImage: "xmark.circle", isDestructive: true) {
                AppAnalytics.tap("idol_list.filter_clear")
                clearAllFilters()
            })
        }
        return actions
    }

    /// 全フィルタを解除する。`activeFilterCount`/`filterBadgeCount` が数える全項目
    /// (ブランド/属性/表示形式 + 担当/お気に入り/メモ) を漏れなくリセットする。
    /// ユーザーの明示的な操作なので、以後 `onAppear` のデフォルトブランド再適用は行わない。
    private func clearAllFilters() {
        selectedBrandIds = []
        selectedAttribute = nil
        displayModeRaw = IdolDisplayMode.idolName.rawValue
        requireMyPick = false
        requireFavorite = false
        requireNote = false
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                listTabBar
                Group {
                    if listTab == 0 {
                        idolBody
                    } else {
                        UnitListContent(vm: unitVM)
                    }
                }
            }
        }
    }

    /// 一覧タブ (アイドル/ユニット)。ナビゲーションタイトル下・検索バー上に固定表示する。
    private var listTabBar: some View {
        ImasSegmented(labels: ["アイドル", "ユニット"], selection: $listTab)
            .padding(.horizontal, DS.sp5)
            .padding(.top, DS.sp3)
            .padding(.bottom, DS.sp2)
    }

    @ViewBuilder
    private var idolBody: some View {
        VStack(spacing: 0) {
            if vm.isLoading {
                ScrollView {
                    if idolListMode == .grid {
                        ImasGridSkeleton(columns: 4, count: 16)
                    } else {
                        ImasListSkeleton(rows: 12, thumb: .circle).padding(.top, DS.sp3)
                    }
                }
                .scrollDisabled(true)
            } else if !searchText.isEmpty && vm.filteredIdols.isEmpty {
                Spacer()
                ImasEmptyState(
                    systemImage: "line.3.horizontal.decrease",
                    title: "絞り込み結果がありません",
                    message: "「\(searchText)」に一致するアイドルがいません",
                    actionTitle: "絞り込みを解除",
                    action: { searchText = "" }
                )
                Spacer()
            } else if vm.filteredIdols.isEmpty {
                Spacer()
                ImasEmptyState(
                    systemImage: "line.3.horizontal.decrease.circle",
                    title: "該当するアイドルがいません",
                    message: "フィルタ条件を変更するか、フィルタを解除してください。",
                    actionTitle: activeFilterCount > 0 ? "フィルタを解除" : nil,
                    action: activeFilterCount > 0 ? {
                        AppAnalytics.tap("idol_list.filter_clear")
                        clearAllFilters()
                    } : nil
                )
                Spacer()
            } else if idolListMode == .grid {
                IdolGridView(
                    idols: vm.filteredIdols,
                    brands: vm.visibleBrands,
                    pickIds: vm.pickIds,
                    sortOrder: sortOrder,
                    flatHeader: sortOrder.keepsBrandGrouping
                        ? nil
                        : "\(sortOrder.rawValue)順 ・ \(vm.filteredIdols.count)人"
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
            vm.rebuild(filter: filterContext, sortOrder: sortOrder, ascending: sortAscending)
        }
        .toolbar {
            standardListToolbar(
                searchScope: .idols,
                filterBadge: filterBadgeCount,
                onFilter: {
                    AppAnalytics.tap("idol_list.filter")
                    showFilterSheet = true
                },
                menuActions: idolMenuActions
            )
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
                sortOrder: Binding(
                    get: { sortOrder },
                    set: { sortOrderRaw = $0.rawValue }
                ),
                sortAscending: Binding(
                    get: { sortAscending },
                    set: { sortAscendingRaw = $0 == nil ? 0 : ($0! ? 1 : 2) }
                ),
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
        .task { await vm.loadData(filter: filterContext, sortOrder: sortOrder, ascending: sortAscending) }
        // フィルタ変化時のみ再計算
        .task(id: filterKey) {
            vm.refreshPickIds()
            vm.rebuild(filter: filterContext, sortOrder: sortOrder, ascending: sortAscending)
        }
        .onChange(of: selectedBrandIds) { _, _ in
            hasUserInteractedWithBrandFilter = true
        }
        .onAppear {
            if !defaultBrandId.isEmpty && selectedBrandIds.isEmpty && !hasUserInteractedWithBrandFilter {
                selectedBrandIds = [defaultBrandId]
            }
            vm.refreshPickIds()
        }
        .trackScreen("idol_list")
    }

    /// 公式順以外の並びで使う「ブランドの区切りを外した通しリスト」。
    ///
    /// 身長順・年齢順はブランドを跨いで初めて意味を持つ指標なので、セクションで割らない。
    /// 各行には並び替えのキー値を併記して、何順に並んでいるか行から読めるようにする。
    private var flatListSection: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            HStack {
                Text("\(sortOrder.rawValue)順")
                    .font(.imasScaled(13, weight: .semibold))
                    .foregroundStyle(DS.ink2)
                Spacer()
                Text("\(vm.filteredIdols.count)人")
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink3)
            }
            .padding(.horizontal, DS.sp2)

            ImasListContainer {
                ForEach(Array(vm.filteredIdols.enumerated()), id: \.element.id) { index, idol in
                    if index > 0 { ImasRowDivider(inset: 69) }
                    NavigationLink(value: idol) {
                        IdolRowView(
                            idol: idol,
                            brandColor: brandColorHex(for: idol),
                            isPick: vm.pickIds.contains(idol.id),
                            displayName: displayName(for: idol),
                            secondary: secondaryText(for: idol),
                            cvLine: cvText(for: idol),
                            metric: sortOrder.metricLabel(for: idol)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, DS.sp5)
    }

    /// 通しリストではブランド別セクションが無いので、行ごとにブランド色を引く。
    private func brandColorHex(for idol: Idol) -> String? {
        vm.brands.first(where: { $0.id == idol.brandId })?.color
    }

    // MARK: - List Body (ブランド別・inset grouped 風)

    private var listBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.sp6, pinnedViews: []) {
                if !sortOrder.keepsBrandGrouping {
                    flatListSection
                }
                ForEach(vm.visibleBrands) { brand in
                    let group = vm.groupedByBrand[brand.id] ?? []
                    VStack(alignment: .leading, spacing: DS.sp3) {
                        brandSectionHeader(brand, count: group.count)
                            .padding(.horizontal, DS.sp2)

                        if !collapsedBrands.contains(brand.id) {
                            ImasListContainer {
                                ForEach(Array(group.enumerated()), id: \.element.id) { index, idol in
                                    // IdolAvatarView の外形フレームは isPick に関わらず一定 (担当リング込み
                                    // サイズ) になったため、テキスト開始位置は常に旧・担当時相当分右へ寄る。
                                    // 旧インセット (58) にリング分の増分 (+11) を足して追従させる。
                                    if index > 0 { ImasRowDivider(inset: 69) }
                                    NavigationLink(value: idol) {
                                        IdolRowView(
                                            idol: idol,
                                            brandColor: brand.color,
                                            isPick: vm.pickIds.contains(idol.id),
                                            displayName: displayName(for: idol),
                                            secondary: secondaryText(for: idol),
                                            cvLine: cvText(for: idol),
                                            metric: sortOrder.metricLabel(for: idol)
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
            await vm.loadData(filter: filterContext, sortOrder: sortOrder, ascending: sortAscending)
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
    /// 並び替えのキー値 (「17歳」「158cm」等)。並び順が公式順/五十音順のときは nil。
    /// 何順で並んでいるか行から読めないと、並び替えても意味が分からないため出す。
    var metric: String? = nil

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

            if let metric {
                ImasMetricBadge(value: metric, unit: "", seed: idol.color)
                    .padding(.trailing, DS.sp1)
            }

            MyPickToggleButton(id: idol.id)
            FavoriteToggleButton(entity: .idol, id: idol.id)

            ImasRowChevron()
                .padding(.trailing, DS.sp2)
        }
        .padding(.vertical, DS.sp3)
        .padding(.leading, DS.sp2)
        .contentShape(Rectangle())
        .imasCopyable([("アイドル名をコピー", idol.name), ("よみをコピー", idol.nameKana)])
    }
}
