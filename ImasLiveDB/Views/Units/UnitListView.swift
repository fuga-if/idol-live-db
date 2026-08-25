import SwiftUI

/// ユニット一覧 (曲ありユニットのみ) の単独 push 先。中身は `UnitListContent` に委譲する。
/// `IdolListView` の「ユニット」タブは `UnitListContent` を直接埋め込んで使うため、
/// このラッパーは単独 push で開きたい呼び出し元向けに残してある。
struct UnitListView: View {
    // IdolListView の「ユニット」タブと同じ理由で、ViewModel はここで hoist して保持する
    // (UnitListContent 側の @State にすると、呼び出し元の再描画のたびに新しい
    // UnitListContent() が作られる場合に状態が失われるため)。
    @State private var vm = UnitListViewModel()

    var body: some View {
        NavigationStack {
            UnitListContent(vm: vm)
        }
    }
}

/// ユニット一覧の中身 (ブランド別グループ化 + list/grid 切替 + 検索)。IdolListView と同じ骨格を
/// 踏襲する。フィルタ (担当/お気に入り等) は UserMark が unit を扱わないため無し。
/// `NavigationStack` を own しない (呼び出し元の NavigationStack にそのまま組み込める形)。
/// ViewModel は呼び出し元が hoist して注入する (IdolListView の「ユニット」タブ切替時に
/// ビューが再生成されても、検索語・ロード済みデータ・スクロール位置を保持するため)。
struct UnitListContent: View {
    @Environment(AppDatabase.self) private var database
    @AppStorage("unit_list_mode") private var listModeRaw: String = IdolListMode.list.rawValue
    /// `@Bindable` で vm のプロパティに `$vm.xxx` バインディングを張る。UI 状態 (検索語/検索中/
    /// ブランド折り畳み/シート対象) は全て vm 側に持たせているため、View 自体が再生成されても消えない。
    @Bindable var vm: UnitListViewModel
    /// 絞り込み欄を自前で出すか。
    ///
    /// `IdolListView` の「ユニット」タブはナビバーの中に絞り込み欄を持っているので `false`。
    /// 自前でも出すと 1 画面に絞り込み欄が 2 つ並び、どちらが効くのか分からなくなる。
    var showsFilterField = true

    private var listMode: IdolListMode {
        IdolListMode(rawValue: listModeRaw) ?? .list
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsFilterField {
                NameFilterField(prompt: "ユニット名で絞り込み", text: $vm.searchText)
                    .padding(.horizontal, DS.sp5)
                    .padding(.bottom, DS.sp3)
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
            } else if !vm.searchText.isEmpty && vm.filteredUnits.isEmpty {
                Spacer()
                ImasEmptyState(
                    systemImage: "line.3.horizontal.decrease",
                    title: "絞り込み結果がありません",
                    message: "「\(vm.searchText)」に一致するユニットがありません",
                    actionTitle: "絞り込みを解除",
                    action: { vm.searchText = "" }
                )
                Spacer()
            } else if vm.filteredUnits.isEmpty {
                Spacer()
                ImasEmptyState(
                    systemImage: "person.3",
                    title: "ユニットがありません",
                    message: "登録されているユニットがまだありません。"
                )
                Spacer()
            } else if listMode == .grid {
                gridBody
            } else {
                listBody
            }
        }
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle("ユニット")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: vm.searchText) { _, new in
            vm.rebuild(searchText: new)
        }
        .toolbar {
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
        .sheet(item: $vm.sheetUnit) { unit in
            DetailSheetView(destination: .unit(unit))
                .environment(database)
        }
        .task { await vm.loadData() }
        .trackScreen("unit_list")
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

                        if !vm.collapsedBrands.contains(brand.id) {
                            ImasListContainer {
                                ForEach(Array(group.enumerated()), id: \.element.id) { index, unit in
                                    if index > 0 { ImasRowDivider(inset: 69) }
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
                Image(systemName: vm.collapsedBrands.contains(brand.id) ? "chevron.right" : "chevron.down")
                    .font(.imasScaled( 12, weight: .semibold))
                    .foregroundStyle(DS.ink3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleBrand(_ brandId: String) {
        if vm.collapsedBrands.contains(brandId) {
            vm.collapsedBrands.remove(brandId)
        } else {
            vm.collapsedBrands.insert(brandId)
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
        Button {
            AppAnalytics.tap("unit_list.grid_select")
            vm.sheetUnit = unit
        } label: {
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
        }
        .buttonStyle(.plain)
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

            ImasRowChevron()
                .padding(.trailing, DS.sp2)
        }
        .padding(.vertical, DS.sp3)
        .padding(.leading, DS.sp2)
        .contentShape(Rectangle())
    }
}
