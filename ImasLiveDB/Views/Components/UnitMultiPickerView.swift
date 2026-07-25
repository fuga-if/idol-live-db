import SwiftUI

/// お題作成・投票でユニットを複数選択する picker。
/// IdolPickerView と同じ感覚で、ブランドフィルタ + 検索 + リスト/グリッド切替に対応する。
struct UnitMultiPickerView: View {
    let initialSelection: Set<String>
    let units: [Unit]
    let onCommit: (Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selection: Set<String>
    @State private var query: String = ""
    @State private var selectedBrandIds: Set<String> = []
    @State private var brands: [Brand] = []
    /// 呼び出し元が units を渡さなかった (空) 場合に自力ロードした全ユニット。
    @State private var loadedUnits: [Unit] = []
    /// リスト/グリッド表示切替。
    @State private var displayMode: IdolListMode = .grid

    init(
        selected: Set<String>,
        units: [Unit],
        onCommit: @escaping (Set<String>) -> Void
    ) {
        self.initialSelection = selected
        self.units = units
        self.onCommit = onCommit
        self._selection = State(initialValue: selected)
    }

    /// 表示に使うユニット。呼び出し元の配列が空 (ロード未完/失敗) なら自力ロード分にフォールバック。
    private var sourceUnits: [Unit] { units.isEmpty ? loadedUnits : units }

    private var filtered: [Unit] {
        var result = sourceUnits
        if !selectedBrandIds.isEmpty {
            result = result.filter { selectedBrandIds.contains($0.brandId) }
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let lower = trimmed.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(lower)
                    || ($0.nameAlt?.lowercased().contains(lower) == true)
            }
        }
        return result
    }

    private var grouped: [(brand: Brand, units: [Unit])] {
        let byBrand = Dictionary(grouping: filtered) { $0.brandId }
        return brands.compactMap { brand in
            guard let list = byBrand[brand.id], !list.isEmpty else { return nil }
            return (brand: brand, units: list)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                brandFilterBar
                if displayMode == .grid {
                    unitGrid
                } else {
                    unitList
                }
            }
            .navigationTitle("ユニットを選択 (\(selection.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        AppAnalytics.tap("unit_multi_picker.display_mode_toggle")
                        displayMode = displayMode == .grid ? .list : .grid
                    } label: {
                        Image(systemName: displayMode == .grid ? "list.bullet" : "square.grid.3x2")
                    }
                    .accessibilityLabel(displayMode == .grid ? "リスト表示" : "グリッド表示")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("決定") {
                        AppAnalytics.tap("unit_multi_picker.commit")
                        onCommit(selection)
                        dismiss()
                    }
                }
            }
            .searchable(text: $query, prompt: "ユニット名で検索")
            .task {
                brands = (try? await AppContainer.shared.brandReading.brands()) ?? []
                if units.isEmpty {
                    // 呼び出し元 (Poll候補ピッカー等) は曲ありユニットのみを渡す前提だが、
                    // 万一空のまま呼ばれた場合のフォールバックも同じ母集団に揃える。
                    loadedUnits = (try? await AppContainer.shared.unitReading.unitsWithSongs()) ?? []
                }
            }
            .trackScreen("unit_multi_picker")
        }
    }

    @ViewBuilder
    private var brandFilterBar: some View {
        if !brands.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button { selectedBrandIds = [] } label: {
                        ImasChip(text: "すべて", style: selectedBrandIds.isEmpty ? .selected : .neutral)
                    }
                    .buttonStyle(.plain)
                    ForEach(brands) { brand in
                        Button {
                            if selectedBrandIds.contains(brand.id) {
                                selectedBrandIds.remove(brand.id)
                            } else {
                                selectedBrandIds.insert(brand.id)
                            }
                        } label: {
                            ImasChip(text: brand.shortName,
                                      style: selectedBrandIds.contains(brand.id) ? .selected : .neutral,
                                      brand: brand.color)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DS.sp4)
                .padding(.vertical, DS.sp3)
            }
            .background(.regularMaterial)
        }
    }

    @ViewBuilder
    private var unitList: some View {
        List {
            ForEach(grouped, id: \.brand.id) { section in
                Section(section.brand.shortName) {
                    ForEach(section.units) { unit in
                        unitRow(unit)
                    }
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.bg)
    }

    @ViewBuilder
    private func unitRow(_ unit: Unit) -> some View {
        let isSelected = selection.contains(unit.id)
        Button {
            toggle(unit)
        } label: {
            HStack(spacing: DS.sp3) {
                UnitAvatarView(unit: unit, size: 40)
                Text(unit.displayName)
                Spacer()
                ImasSelectionMark(isSelected: isSelected, brand: unit.brandId)
            }
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ unit: Unit) {
        AppAnalytics.tap("unit_multi_picker.toggle_unit")
        if selection.contains(unit.id) {
            selection.remove(unit.id)
        } else {
            selection.insert(unit.id)
        }
    }

    // MARK: - Grid

    private var unitGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.sp5) {
                ForEach(grouped, id: \.brand.id) { section in
                    VStack(alignment: .leading, spacing: DS.sp3) {
                        BrandSectionHeader(brand: section.brand, count: section.units.count)
                            .padding(.horizontal, DS.sp5)
                        LazyVGrid(columns: gridColumns, spacing: DS.sp4) {
                            ForEach(section.units) { unit in
                                gridCell(unit)
                            }
                        }
                        .padding(.horizontal, DS.sp4)
                    }
                }
            }
            .padding(.top, DS.sp3)
            .padding(.bottom, DS.sp7)
        }
        .background(DS.bg)
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DS.sp3), count: 4)
    }

    private func gridCell(_ unit: Unit) -> some View {
        let isSelected = selection.contains(unit.id)
        return VStack(spacing: DS.sp2) {
            UnitAvatarView(unit: unit, size: 60)
                .overlay(alignment: .bottomTrailing) {
                    ImasSelectionMark(isSelected: isSelected, brand: unit.brandId)
                        .background(DS.bg, in: Circle())
                        .offset(x: 2, y: 2)
                }
                .opacity(isSelected ? 1 : 0.55)
            Text(unit.displayName)
                .font(.imasCaption)
                .foregroundStyle(DS.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { toggle(unit) }
    }
}
