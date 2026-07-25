import SwiftUI

/// アプリ唯一のアイドル選択画面。
///
/// 以前は用途ごとに 3 実装が並立し、品質に大差があった:
/// - 出演者選択用 (ブランド絞り込み・グリッド・ユニット一括追加あり)
/// - 楽曲フィルタ用 (395 人を素のリストに全部出すだけ。アバターも絞り込みも無し)
/// - 単一選択用 (どこからも未使用)
/// 同じ「アイドルを選ぶ」行為が別 UI になる理由が無いので、いちばん良かった実装に寄せて統合した。
///
/// - `mode` で単一選択 / 複数選択を切り替える (単一選択はタップ即確定)。
/// - 検索は名前・かな・CV名・別名を対象にする。
struct IdolPickerView: View {
    enum Mode { case single, multi }

    /// ナビバーのタイトル。ツールバー項目が最大 4 つ並ぶので **短く** すること
    /// (長いと iOS が「アイド…」のように省略する)。
    var title: String = "アイドル"
    var mode: Mode = .multi
    /// 呼び出し元が既に持っているアイドル配列。空なら自力でロードする。
    var idols: [Idol] = []
    let initialSelection: Set<String>
    let onCommit: (Set<String>) -> Void

    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    @State private var selection: Set<String>
    @State private var query: String = ""
    @State private var selectedBrandIds: Set<String> = []
    @State private var brands: [Brand] = []
    @State private var loadedIdols: [Idol] = []
    @State private var showUnitPicker = false
    /// リスト/グリッド表示切替。人数が多いとき (全ブランド等) でも顔で見渡せるように。
    @AppStorage("idol_picker_mode") private var displayModeRaw: String = IdolListMode.grid.rawValue

    init(
        title: String = "アイドル",
        mode: Mode = .multi,
        idols: [Idol] = [],
        selected: Set<String> = [],
        onCommit: @escaping (Set<String>) -> Void
    ) {
        self.title = title
        self.mode = mode
        self.idols = idols
        self.initialSelection = selected
        self.onCommit = onCommit
        self._selection = State(initialValue: selected)
    }

    private var displayMode: IdolListMode {
        IdolListMode(rawValue: displayModeRaw) ?? .grid
    }

    /// 表示に使うアイドル。呼び出し元の配列が空 (ロード未完/未指定) なら自力ロード分にフォールバック。
    private var sourceIdols: [Idol] { idols.isEmpty ? loadedIdols : idols }

    private var filtered: [Idol] {
        var result = sourceIdols
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

    private var selectedIdols: [Idol] {
        sourceIdols.filter { selection.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                brandFilterBar
                if filtered.isEmpty {
                    emptyState
                } else if displayMode == .grid {
                    idolGrid
                } else {
                    idolList
                }
                // 複数選択では、いま何を選んでいるかを常に見えるようにする
                // (スクロールで選択済みが視界から消えるため)。
                if mode == .multi, !selection.isEmpty {
                    Divider().overlay(DS.sep)
                    selectedBar
                }
            }
            .background(DS.bg)
            .navigationTitle(mode == .multi ? "\(title) (\(selection.count))" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .searchable(text: $query, prompt: "アイドル名 / CV名で検索")
            .sheet(isPresented: $showUnitPicker) {
                UnitMemberAddPicker { addedIdolIds in
                    selection.formUnion(addedIdolIds)
                }
                .environment(database)
            }
            .task {
                brands = (try? await AppContainer.shared.brandReading.brands()) ?? []
                if idols.isEmpty {
                    loadedIdols = (try? await AppContainer.shared.idolReading.idols(brandId: nil)) ?? []
                }
            }
            .trackScreen("idol_picker")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                AppAnalytics.tap("idol_picker.display_mode_toggle")
                displayModeRaw = (displayMode == .grid ? IdolListMode.list : .grid).rawValue
            } label: {
                Image(systemName: displayMode == .grid ? "list.bullet" : "square.grid.3x2")
            }
            .accessibilityLabel(displayMode == .grid ? "リスト表示" : "グリッド表示")
        }
        if mode == .multi {
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
                    AppAnalytics.tap("idol_picker.commit")
                    onCommit(selection)
                    dismiss()
                }
                .fontWeight(.bold)
            }
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            ImasEmptyState(
                systemImage: "magnifyingglass",
                title: "見つかりません",
                message: query.isEmpty
                    ? "このブランドに該当するアイドルがいません"
                    : "「\(query)」に一致するアイドルがいません"
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.bg)
    }

    // MARK: - ブランド絞り込み

    @ViewBuilder
    private var brandFilterBar: some View {
        if !brands.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.sp3) {
                    Button { selectedBrandIds = [] } label: {
                        ImasChip(text: "すべて", style: selectedBrandIds.isEmpty ? .selected : .neutral)
                    }
                    .buttonStyle(.plain)
                    ForEach(brands) { brand in
                        Button {
                            if !selectedBrandIds.insert(brand.id).inserted {
                                selectedBrandIds.remove(brand.id)
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
            .background(DS.surface)
            Divider().overlay(DS.sep)
        }
    }

    // MARK: - リスト

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

    private func idolRow(_ idol: Idol) -> some View {
        let isSelected = selection.contains(idol.id)
        return Button {
            toggle(idol)
        } label: {
            HStack(spacing: DS.sp3) {
                IdolAvatarView(idol: idol, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(idol.name)
                        .font(.imasSubhead)
                        .foregroundStyle(DS.ink)
                    if let cv = idol.currentVoiceActor {
                        Text(cv)
                            .font(.imasCaption)
                            .foregroundStyle(DS.ink3)
                    }
                }
                Spacer()
                selectionIndicator(isSelected: isSelected, seed: idol.color)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(idol.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - グリッド

    private var idolGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.sp5) {
                ForEach(grouped, id: \.brand.id) { section in
                    VStack(alignment: .leading, spacing: DS.sp3) {
                        BrandSectionHeader(brand: section.brand, count: section.idols.count)
                            .padding(.horizontal, DS.sp5)
                        LazyVGrid(columns: gridColumns, spacing: DS.sp4) {
                            ForEach(section.idols) { idol in
                                gridCell(idol)
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

    private func gridCell(_ idol: Idol) -> some View {
        let isSelected = selection.contains(idol.id)
        return VStack(spacing: DS.sp2) {
            IdolAvatarView(idol: idol, size: 60)
                .overlay(alignment: .bottomTrailing) {
                    selectionIndicator(isSelected: isSelected, seed: idol.color)
                        .background(DS.bg, in: Circle())
                        // IdolAvatarView は isPick=false でも担当リング込みの外形フレームを確保するため、
                        // 可視アバターは中央に ImasAvatar.ringPadding 分小さく描画される。ここは isPick を
                        // 渡さない (常に false) ので、その余白を差し引いて可視アバターの縁に揃える。
                        .offset(x: 2 - ImasAvatar.ringPadding, y: 2 - ImasAvatar.ringPadding)
                }
                .opacity(isSelected ? 1 : 0.55)
            Text(idol.name)
                .font(.imasCaption)
                .foregroundStyle(DS.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { toggle(idol) }
        .accessibilityLabel(idol.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 選択マーク。色はアイドル固有色から導出する (システム accent を塗らない)。
    private func selectionIndicator(isSelected: Bool, seed: String?) -> some View {
        ImasSelectionMark(isSelected: isSelected, seed: seed)
    }

    // MARK: - 選択中バー

    private var selectedBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.sp3) {
                ForEach(selectedIdols) { idol in
                    ImasRemovableChip(text: idol.name, seed: idol.color) {
                        withAnimation { toggle(idol) }
                    }
                }
            }
            .padding(.horizontal, DS.sp5)
            .padding(.vertical, DS.sp4)
        }
        .background(DS.surface)
    }

    // MARK: - 選択

    private func toggle(_ idol: Idol) {
        AppAnalytics.tap("idol_picker.toggle_idol")
        switch mode {
        case .single:
            // 単一選択はタップで即確定。「決定」を押させる意味がない。
            onCommit([idol.id])
            dismiss()
        case .multi:
            if selection.contains(idol.id) {
                selection.remove(idol.id)
            } else {
                selection.insert(idol.id)
            }
        }
    }
}

// MARK: - ユニットから一括追加

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
                        HStack(spacing: DS.sp3) {
                            Button { selectedBrandIds = [] } label: {
                                ImasChip(text: "すべて", style: selectedBrandIds.isEmpty ? .selected : .neutral)
                            }
                            .buttonStyle(.plain)
                            ForEach(brands) { brand in
                                Button {
                                    if !selectedBrandIds.insert(brand.id).inserted {
                                        selectedBrandIds.remove(brand.id)
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
                    .background(DS.surface)
                    Divider().overlay(DS.sep)
                }
                List(filtered) { unit in
                    Button {
                        AppAnalytics.tap("idol_picker.add_unit")
                        Task {
                            if let members = try? await AppContainer.shared.unitReading.unitMembers(unitId: unit.id) {
                                onAdd(Set(members.map(\.id)))
                                dismiss()
                            }
                        }
                    } label: {
                        HStack(spacing: DS.sp3) {
                            Image(systemName: "person.3.fill")
                                .font(.imasScaled(15))
                                .foregroundStyle(DS.ink2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(unit.name)
                                    .font(.imasSubhead)
                                    .foregroundStyle(DS.ink)
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
