import SwiftUI

/// セトリ編集等で出演アイドルを複数選択する picker。 IdolListView と同じ感覚で
/// ブランドフィルタ + 検索 + ユニットから一括追加が可能。
struct IdolMultiPickerView: View {
    let initialSelection: Set<String>
    let idols: [Idol]
    let onCommit: (Set<String>) -> Void

    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    @State private var selection: Set<String>
    @State private var query: String = ""
    @State private var selectedBrandIds: Set<String> = []
    @State private var brands: [Brand] = []
    @State private var showUnitPicker = false

    init(
        selected: Set<String>,
        idols: [Idol],
        onCommit: @escaping (Set<String>) -> Void
    ) {
        self.initialSelection = selected
        self.idols = idols
        self.onCommit = onCommit
        self._selection = State(initialValue: selected)
    }

    private var filtered: [Idol] {
        var result = idols
        if !selectedBrandIds.isEmpty {
            result = result.filter { selectedBrandIds.contains($0.brandId) }
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let lower = trimmed.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(lower)
                    || ($0.nameKana?.lowercased().contains(lower) == true)
                    || ($0.voiceActors?.lowercased().contains(lower) == true)
                    || ($0.aliases?.lowercased().contains(lower) == true)
            }
        }
        return result
    }

    private var grouped: [(brand: Brand, idols: [Idol])] {
        let byBrand = Dictionary(grouping: filtered) { $0.brandId }
        return brands.compactMap { brand in
            guard let list = byBrand[brand.id], !list.isEmpty else { return nil }
            return (brand: brand, idols: list)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                brandFilterBar
                idolList
            }
            .navigationTitle("出演者を選択 (\(selection.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showUnitPicker = true
                    } label: {
                        Image(systemName: "person.3.fill")
                    }
                    .accessibilityLabel("ユニットから追加")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("決定") {
                        AppAnalytics.tap("idol_multi_picker.commit")
                        onCommit(selection)
                        dismiss()
                    }
                }
            }
            .searchable(text: $query, prompt: "アイドル名 / 声優名で検索")
            .sheet(isPresented: $showUnitPicker) {
                UnitMemberAddPicker { addedIdolIds in
                    selection.formUnion(addedIdolIds)
                }
                .environment(database)
            }
            .task {
                brands = (try? await AppContainer.shared.brandReading.brands()) ?? []
            }
            .trackScreen("idol_multi_picker")
        }
    }

    @ViewBuilder
    private var brandFilterBar: some View {
        if !brands.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    BrandChip(label: "すべて", isOn: selectedBrandIds.isEmpty) {
                        selectedBrandIds = []
                    }
                    ForEach(brands) { brand in
                        BrandChip(label: brand.shortName, isOn: selectedBrandIds.contains(brand.id)) {
                            if selectedBrandIds.contains(brand.id) {
                                selectedBrandIds.remove(brand.id)
                            } else {
                                selectedBrandIds.insert(brand.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.regularMaterial)
        }
    }

    @ViewBuilder
    private var idolList: some View {
        List {
            ForEach(grouped, id: \.brand.id) { section in
                Section(section.brand.shortName) {
                    ForEach(section.idols) { idol in
                        idolRow(idol)
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
    private func idolRow(_ idol: Idol) -> some View {
        Button {
            AppAnalytics.tap("idol_multi_picker.toggle_idol")
            if selection.contains(idol.id) {
                selection.remove(idol.id)
            } else {
                selection.insert(idol.id)
            }
        } label: {
            HStack {
                Image(systemName: selection.contains(idol.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selection.contains(idol.id) ? Color.accentColor : DS.ink2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(idol.name)
                    if let cv = idol.currentVoiceActor {
                        Text(cv)
                            .font(.imasCaption)
                            .foregroundStyle(DS.ink3)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

private struct BrandChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.imasCaption.weight(isOn ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? Color.accentColor : DS.fill)
                .foregroundStyle(isOn ? Color.white : DS.ink)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// ユニット選択 → メンバー一括追加用 sub-picker。
private struct UnitMemberAddPicker: View {
    let onAdd: (Set<String>) -> Void

    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    @State private var units: [Unit] = []
    @State private var query: String = ""
    @State private var brands: [Brand] = []
    @State private var selectedBrandIds: Set<String> = []

    private var filtered: [Unit] {
        var result = units
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !brands.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            BrandChip(label: "すべて", isOn: selectedBrandIds.isEmpty) {
                                selectedBrandIds = []
                            }
                            ForEach(brands) { brand in
                                BrandChip(label: brand.shortName, isOn: selectedBrandIds.contains(brand.id)) {
                                    if selectedBrandIds.contains(brand.id) {
                                        selectedBrandIds.remove(brand.id)
                                    } else {
                                        selectedBrandIds.insert(brand.id)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .background(.regularMaterial)
                }
                List(filtered) { unit in
                    Button {
                        AppAnalytics.tap("idol_multi_picker.add_unit")
                        Task {
                            if let members = try? await AppContainer.shared.unitReading.unitMembers(unitId: unit.id) {
                                let ids = Set(members.map(\.id))
                                onAdd(ids)
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "person.3.fill")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(unit.name)
                                if let alt = unit.nameAlt, !alt.isEmpty {
                                    Text(alt)
                                        .font(.imasCaption)
                                        .foregroundStyle(DS.ink3)
                                }
                            }
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(DS.ink2)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(DS.surface)
                    .listRowSeparatorTint(DS.sep)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(DS.bg)
            }
            .navigationTitle("ユニットから追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .searchable(text: $query, prompt: "ユニット名で検索")
            .task {
                brands = (try? await AppContainer.shared.brandReading.brands()) ?? []
                units = (try? await AppContainer.shared.unitReading.allUnits()) ?? []
            }
        }
    }
}
