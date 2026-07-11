import SwiftUI

/// ユニット一覧 (曲ありユニットのみ)。IdolListView と同じ骨格 (ブランド別グループ化 + list/grid
/// 切替 + 検索) を踏襲する。フィルタ (担当/お気に入り等) は UserMark が unit を扱わないため無し。
struct UnitListView: View {
    @Environment(AppDatabase.self) private var database
    @AppStorage("unit_list_mode") private var listModeRaw: String = IdolListMode.list.rawValue
    @State private var navPath = NavigationPath()
    @State private var vm = UnitListViewModel()
    @State private var collapsedBrands: Set<String> = []
    @State private var sheetUnit: Unit?
    @State private var searchText = ""
    @State private var isSearching = false

    private var listMode: IdolListMode {
        IdolListMode(rawValue: listModeRaw) ?? .list
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                if isSearching {
                    InTabSearchField(prompt: "ユニット名で検索", text: $searchText, isSearching: $isSearching)
                }

                if vm.isLoading {
                    ScrollView {
                        if listMode == .grid {
                            ImasGridSkeleton(columns: 4, count: 16)
                        } else {
                            ImasListSkeleton(rows: 12, thumb: .circle).padding(.top, DS.sp3)
                        }
                    }
                    .scrollDisabled(true)
                } else if !searchText.isEmpty && vm.filteredUnits.isEmpty {
                    InTabSearchEmptyView(query: searchText)
                } else if listMode == .grid {
                    gridBody
                } else {
                    listBody
                }
            }
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle("ユニット")
            .navigationBarTitleDisplayMode(.large)
            .onChange(of: searchText) { _, new in
                vm.rebuild(searchText: new)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        AppAnalytics.tap("unit_list.search_open")
                        isSearching = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("検索")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        AppAnalytics.tap("unit_list.grid_toggle")
                        listModeRaw = (listMode == .grid ? IdolListMode.list : .grid).rawValue
                    } label: {
                        Image(systemName: listMode == .grid ? "list.bullet" : "square.grid.3x2")
                    }
                    .accessibilityLabel(listMode == .grid ? "リスト表示" : "グリッド表示")
                }
            }
            .navigationDestination(for: Unit.self) { unit in
                UnitDetailView(unit: unit)
            }
            .sheet(item: $sheetUnit) { unit in
                DetailSheetView(destination: .unit(unit))
                    .environment(database)
            }
            .task { await vm.loadData() }
            .trackScreen("unit_list")
        }
    }

    // MARK: - List Body (ブランド別・inset grouped 風、IdolListView と同型)

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
                                ForEach(Array(group.enumerated()), id: \.element.id) { index, unit in
                                    if index > 0 { Divider().overlay(DS.sep).padding(.leading, 69) }
                                    NavigationLink(value: unit) {
                                        UnitRowView(unit: unit, brandColor: brand.color)
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
    }

    private func brandSectionHeader(_ brand: Brand, count: Int) -> some View {
        Button {
            toggleBrand(brand.id)
        } label: {
            HStack(spacing: DS.sp3) {
                BrandSectionHeader(brand: brand, count: count, unit: "組")
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

    // MARK: - Grid Body (アバター(カスタム画像 or アイコン) + 名前 + ブランド色チップ)

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DS.sp3), count: 4)
    }

    private var gridBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.sp6) {
                ForEach(vm.visibleBrands) { brand in
                    VStack(alignment: .leading, spacing: DS.sp4) {
                        BrandSectionHeader(brand: brand, count: (vm.groupedByBrand[brand.id] ?? []).count, unit: "組")
                            .padding(.horizontal, DS.sp5)

                        LazyVGrid(columns: gridColumns, spacing: DS.sp5) {
                            ForEach(vm.groupedByBrand[brand.id] ?? []) { unit in
                                unitGridCell(unit, brand: brand)
                            }
                        }
                        .padding(.horizontal, DS.sp4)
                    }
                }
            }
            .padding(.top, DS.sp4)
            .padding(.bottom, DS.sp7)
        }
    }

    private func unitGridCell(_ unit: Unit, brand: Brand) -> some View {
        VStack(spacing: DS.sp2) {
            UnitAvatarView(unit: unit, size: 60)
            Text(unit.displayName)
                .font(.imasCaption)
                .foregroundStyle(DS.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            ImasChip(text: brand.shortName, seed: brand.color)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            AppAnalytics.tap("unit_list.grid_select")
            sheetUnit = unit
        }
    }
}

// MARK: - UnitRowView

/// 行頭リードバー (ブランド色) + アバター (`UnitAvatarView`) + 名前 + シェブロン。IdolRowView と同型。
private struct UnitRowView: View {
    let unit: Unit
    var brandColor: String? = nil

    var body: some View {
        HStack(spacing: DS.sp3) {
            ImasLeadBar(seed: nil, brand: brandColor)
                .padding(.vertical, 5)

            UnitAvatarView(unit: unit, size: 40)

            Text(unit.displayName)
                .font(.imasSubhead.weight(.semibold))
                .foregroundStyle(DS.ink)
                .lineLimit(1)

            Spacer(minLength: DS.sp2)

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
