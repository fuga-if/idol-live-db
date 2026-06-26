import os
import SwiftUI

/// 楽曲フィルタ設定画面（シートで表示）
struct SongFilterView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    @Binding var filter: SongSearchFilter
    @Binding var sortOrder: SongSortOrder
    /// nil = sortOrder のデフォルト方向、 true=昇順、 false=降順
    @Binding var sortAscending: Bool?
    @Binding var listMode: SongListMode
    @Binding var collectFilter: SongCollectFilter
    @Binding var myMarkFilter: SongMyMarkFilter
    /// 「その他」(歌枠カバー等 brand_id='other') をブラウズ一覧に出すか。
    @Binding var showOtherBrand: Bool
    /// ライブ履歴のみのファントム曲を一覧から隠すか。
    @Binding var excludeLiveOnly: Bool

    @State private var brands: [Brand] = []
    @State private var idols: [Idol] = []
    @State private var cdSeriesList: [String] = []
    @State private var seriesGroupList: [String] = []
    @State private var eventNames: [String] = []

    // 選択中の状態
    @State private var selectedIdolIds: Set<String> = []
    @State private var songwriterText = ""
    @State private var selectedCdSeries: String? = nil
    @State private var selectedSeriesGroup: String? = nil
    @State private var selectedEventName: String? = nil
    @State private var selectedBrandIds: Set<String> = []
    @State private var selectedSongType: String? = nil

    // サブシート
    @State private var showIdolPicker = false
    @State private var showCdSeriesPicker = false
    @State private var showSeriesPicker = false
    @State private var showEventPicker = false

    var body: some View {
        NavigationStack {
            List {
                // 表示形式
                Section("表示形式") {
                    Picker("表示", selection: $listMode) {
                        Label("楽曲", systemImage: "music.note.list").tag(SongListMode.songs)
                        Label("アルバム", systemImage: "square.grid.2x2").tag(SongListMode.albums)
                        Label("シリーズ", systemImage: "rectangle.stack").tag(SongListMode.series)
                    }
                    .pickerStyle(.segmented)

                    if listMode == .songs {
                        Picker("現地回収", selection: $collectFilter) {
                            ForEach(SongCollectFilter.allCases, id: \.rawValue) { c in
                                Text(c.rawValue).tag(c)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                if listMode == .songs {
                    Section {
                        Toggle(isOn: $myMarkFilter.requireMyPick) {
                            Label("担当アイドルの曲のみ", systemImage: "heart.fill")
                                .foregroundStyle(.pink)
                        }
                        Toggle(isOn: $myMarkFilter.requireFavorite) {
                            Label("お気に入りのみ", systemImage: "star.fill")
                                .foregroundStyle(.yellow)
                        }
                        Toggle(isOn: $myMarkFilter.requireNote) {
                            Label("メモがある曲のみ", systemImage: "note.text")
                                .foregroundStyle(.orange)
                        }
                    } header: {
                        Text("マイマーク")
                    } footer: {
                        Text("チェック ON で AND 条件絞り込み")
                            .font(.imasCaption)
                            .foregroundStyle(DS.ink3)
                    }
                    .listRowBackground(DS.surface)
                    .listRowSeparatorTint(DS.sep)
                }

                // ソート
                Section("並び順") {
                    Picker("ソート", selection: $sortOrder) {
                        ForEach(SongSortOrder.allCases, id: \.rawValue) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.menu)

                    // 方向 toggle (Binding<Bool> に橋渡し: nil なら sortOrder の default を表示値とする)
                    Picker("方向", selection: Binding(
                        get: { sortAscending ?? sortOrder.defaultAscending },
                        set: { sortAscending = $0 }
                    )) {
                        Label("昇順", systemImage: "arrow.up").tag(true)
                        Label("降順", systemImage: "arrow.down").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                // ブランド
                BrandFilterSection(brands: brands, selectedBrandIds: $selectedBrandIds)

                Section {
                    Toggle(isOn: $excludeLiveOnly) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ライブ限定曲を隠す")
                            Text("セトリにしか無い曲(カバー等)を一覧から隠します。既定 ON")
                                .font(.imasCaption).foregroundStyle(DS.ink3)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                    Toggle(isOn: $showOtherBrand) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("「その他」を表示")
                            Text("歌枠で歌っただけのカバー等。既定では隠しています")
                                .font(.imasCaption).foregroundStyle(DS.ink3)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                // 曲タイプ
                Section("曲タイプ") {
                    songTypePicker
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                // アイドル選択
                Section("アイドル") {
                    Button {
                        showIdolPicker = true
                    } label: {
                        HStack {
                            if selectedIdolIds.isEmpty {
                                Text("選択なし")
                                    .foregroundStyle(DS.ink2)
                            } else {
                                let names = selectedIdolNames
                                FlowLayout(spacing: 4) {
                                    ForEach(names, id: \.self) { name in
                                        Text(name)
                                            .font(.imasCaption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(DS.fill)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.imasCaption)
                                .foregroundStyle(DS.ink3)
                        }
                    }
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                // 作詞・作曲・編曲
                Section("作詞 / 作曲 / 編曲者") {
                    TextField("名前を入力", text: $songwriterText)
                        .textFieldStyle(.plain)
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                // シリーズ (series_group: LTF / BRILLI@NT WING 等)
                Section("シリーズ") {
                    Button {
                        showSeriesPicker = true
                    } label: {
                        HStack {
                            Text(selectedSeriesGroup ?? "選択なし")
                                .foregroundStyle(selectedSeriesGroup == nil ? DS.ink2 : DS.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.imasCaption)
                                .foregroundStyle(DS.ink3)
                        }
                    }
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                // CDシリーズ
                Section("CDシリーズ") {
                    Button {
                        showCdSeriesPicker = true
                    } label: {
                        HStack {
                            Text(selectedCdSeries ?? "選択なし")
                                .foregroundStyle(selectedCdSeries == nil ? DS.ink2 : DS.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.imasCaption)
                                .foregroundStyle(DS.ink3)
                        }
                    }
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                // ライブ名
                Section("ライブで絞込") {
                    Button {
                        showEventPicker = true
                    } label: {
                        HStack {
                            Text(selectedEventName ?? "選択なし")
                                .foregroundStyle(selectedEventName == nil ? DS.ink2 : DS.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.imasCaption)
                                .foregroundStyle(DS.ink3)
                        }
                    }
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                // リセット
                if hasActiveFilters {
                    Section {
                        Button(role: .destructive) {
                            resetAll()
                        } label: {
                            Label("すべてリセット", systemImage: "arrow.counterclockwise")
                        }
                    }
                    .listRowBackground(DS.surface)
                    .listRowSeparatorTint(DS.sep)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DS.bg)
            .navigationTitle("フィルタ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("リセット") { AppAnalytics.tap("song_filter.reset"); resetAll() }
                        .disabled(!hasActiveFilters)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("適用") {
                        AppAnalytics.tap("song_filter.apply")
                        applyFilter()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .sheet(isPresented: $showIdolPicker) {
                IdolPickerView(idols: idols, selectedIds: $selectedIdolIds)
                    .environment(database)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showSeriesPicker) {
                ListPickerView(
                    title: "シリーズ",
                    items: seriesGroupList,
                    selected: $selectedSeriesGroup
                )
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showCdSeriesPicker) {
                ListPickerView(
                    title: "CDシリーズ",
                    items: cdSeriesList,
                    selected: $selectedCdSeries
                )
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showEventPicker) {
                ListPickerView(
                    title: "ライブ",
                    items: eventNames,
                    selected: $selectedEventName
                )
                .presentationDetents([.large])
            }
            .task { await loadData() }
            .trackScreen("song_filter")
        }
    }

    // MARK: - Song Type Picker

    private var songTypePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                songTypeChip(value: nil, label: "全て")
                songTypeChip(value: "solo", label: "ソロ")
                songTypeChip(value: "unit", label: "ユニット")
                songTypeChip(value: "all", label: "全体曲")
            }
        }
    }

    private func songTypeChip(value: String?, label: String) -> some View {
        let isSelected = selectedSongType == value
        return Button {
            selectedSongType = value
        } label: {
            ImasChip(text: label, style: isSelected ? .selected : .neutral)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var selectedIdolNames: [String] {
        idols.filter { selectedIdolIds.contains($0.id) }.map(\.name)
    }

    private var hasActiveFilters: Bool {
        !selectedBrandIds.isEmpty || !selectedIdolIds.isEmpty ||
        !songwriterText.isEmpty || selectedCdSeries != nil || selectedSeriesGroup != nil ||
        selectedEventName != nil || selectedSongType != nil
    }

    private func resetAll() {
        selectedBrandIds = []
        selectedIdolIds = []
        songwriterText = ""
        selectedCdSeries = nil
        selectedSeriesGroup = nil
        selectedEventName = nil
        selectedSongType = nil
    }

    private func applyFilter() {
        var f = SongSearchFilter(
            brandIds: selectedBrandIds,
            title: nil,
            idolIds: selectedIdolIds.isEmpty ? nil : Array(selectedIdolIds),
            songwriter: songwriterText.isEmpty ? nil : songwriterText,
            cdSeries: selectedCdSeries,
            liveName: selectedEventName,
            songType: selectedSongType
        )
        f.seriesGroup = selectedSeriesGroup
        filter = f
    }

    private func loadData() async {
        do {
            brands = try await AppContainer.shared.brandReading.brands()
            idols = try await AppContainer.shared.idolReading.idols(brandId: nil)
            cdSeriesList = try await AppContainer.shared.songReading.cdSeriesList()
            seriesGroupList = try await AppContainer.shared.songReading.seriesGroups(brandIds: [])
            eventNames = try await AppContainer.shared.eventReading.eventNames()
        } catch {
            Logger.database.error("load_failed SongFilterView: \(error.localizedDescription)")
        }

        // 既存フィルタから状態を復元
        selectedBrandIds = filter.brandIds
        songwriterText = filter.songwriter ?? ""
        selectedCdSeries = filter.cdSeries
        selectedSeriesGroup = filter.seriesGroup
        selectedEventName = filter.liveName
        selectedSongType = filter.songType
    }
}

// MARK: - Idol Picker

struct IdolPickerView: View {
    @Environment(AppDatabase.self) private var database
    let idols: [Idol]
    @Binding var selectedIds: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var brands: [Brand] = []

    private var filteredIdols: [Idol] {
        guard !searchText.isEmpty else { return idols }
        return idols.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.nameKana ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedIdols: [Idol] {
        idols.filter { selectedIds.contains($0.id) }
    }

    private func idolsForBrand(_ brandId: String) -> [Idol] {
        filteredIdols.filter { $0.brandId == brandId }
    }

    private var visibleBrands: [Brand] {
        brands.filter { !idolsForBrand($0.id).isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    ForEach(visibleBrands) { brand in
                        Section(brand.shortName) {
                            ForEach(idolsForBrand(brand.id)) { idol in
                                Button {
                                    toggleSelection(idol.id)
                                } label: {
                                    idolRow(idol)
                                }
                            }
                        }
                        .listRowBackground(DS.surface)
                        .listRowSeparatorTint(DS.sep)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(DS.bg)
                .searchable(text: $searchText, prompt: "アイドル名で検索")

                // 選択中のアイドル（下部固定）
                if !selectedIds.isEmpty {
                    Divider()
                    selectedBar
                }
            }
            .background(DS.bg)
            .navigationTitle("アイドル選択（\(selectedIds.count)名）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !selectedIds.isEmpty {
                        Button("クリア") {
                            withAnimation { selectedIds = [] }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                        .fontWeight(.bold)
                }
            }
            .task {
                do {
                    brands = try await AppContainer.shared.brandReading.brands()
                } catch {
                    Logger.database.error("fetchBrands failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func idolRow(_ idol: Idol) -> some View {
        HStack(spacing: 0) {
            IdolNameRow(idol: idol, showsChevron: false)
            if selectedIds.contains(idol.id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(DS.ink3)
            }
        }
    }

    private var selectedBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(selectedIdols) { idol in
                    ImasRemovableChip(text: idol.name, seed: idol.color) {
                        withAnimation { toggleSelection(idol.id) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(DS.surface)
    }

    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }
}

// MARK: - List Picker (CDシリーズ / ライブ名 共通)

struct ListPickerView: View {
    let title: String
    let items: [String]
    @Binding var selected: String?
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredItems: [String] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                // 「選択なし」オプション
                Button {
                    selected = nil
                    dismiss()
                } label: {
                    HStack {
                        Text("選択なし")
                            .foregroundStyle(DS.ink2)
                        Spacer()
                        if selected == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                ForEach(filteredItems, id: \.self) { item in
                    Button {
                        selected = item
                        dismiss()
                    } label: {
                        HStack {
                            Text(item)
                                .font(.imasSubhead)
                                .foregroundStyle(DS.ink)
                                .lineLimit(2)
                            Spacer()
                            if selected == item {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .listRowBackground(DS.surface)
                    .listRowSeparatorTint(DS.sep)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DS.bg)
            .searchable(text: $searchText, prompt: "検索")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }
}
