import os
import SwiftUI

/// 楽曲フィルタ設定画面（シートで表示）
struct SongFilterView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    /// 一覧を名前で絞り込むテキスト。入力欄は一覧側 (`.searchable`) にあり、
    /// ここでは「絞り込み中」の表示とクリアのためだけに持つ。
    @Binding var nameFilter: String
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

    /// `.task` での初期値復元が済んだか。シリーズ/CD/ライブのピッカーを push → pop すると
    /// `.task` が再実行され、選んだばかりの値を「適用前の filter」で上書きして選択が消える。
    /// 復元は 1 度きりにする。
    @State private var didRestore = false

    @State private var showIdolPicker = false

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
                                .foregroundStyle(DS.pick)
                        }
                        Toggle(isOn: $myMarkFilter.requireFavorite) {
                            Label("お気に入りのみ", systemImage: "star.fill")
                                .foregroundStyle(DS.favorite)
                        }
                        Toggle(isOn: $myMarkFilter.requireNote) {
                            Label("メモがある曲のみ", systemImage: "note.text")
                                .foregroundStyle(DS.warning)
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
                        VStack(alignment: .leading, spacing: DS.sp1) {
                            Text("ライブ限定曲を隠す")
                            Text("セトリにしか無い曲(カバー等)を一覧から隠します。既定 ON")
                                .font(.imasCaption).foregroundStyle(DS.ink3)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                    Toggle(isOn: $showOtherBrand) {
                        VStack(alignment: .leading, spacing: DS.sp1) {
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
                                FlowLayout(spacing: DS.sp2) {
                                    ForEach(names, id: \.self) { name in
                                        Text(name)
                                            .font(.imasCaption)
                                            .padding(.horizontal, DS.sp3)
                                            .padding(.vertical, DS.sp2)
                                            .background(DS.fill)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            Spacer()
                            ImasRowChevron()
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
                    NavigationLink {
                        ListPickerView(title: "シリーズ", items: seriesGroupList, selected: $selectedSeriesGroup)
                    } label: {
                        Text(selectedSeriesGroup ?? "選択なし")
                            .foregroundStyle(selectedSeriesGroup == nil ? DS.ink2 : DS.ink)
                    }
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                // CDシリーズ
                Section("CDシリーズ") {
                    NavigationLink {
                        ListPickerView(title: "CDシリーズ", items: cdSeriesList, selected: $selectedCdSeries)
                    } label: {
                        Text(selectedCdSeries ?? "選択なし")
                            .foregroundStyle(selectedCdSeries == nil ? DS.ink2 : DS.ink)
                    }
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                // ライブ名
                Section("ライブで絞込") {
                    NavigationLink {
                        ListPickerView(title: "ライブ", items: eventNames, selected: $selectedEventName)
                    } label: {
                        Text(selectedEventName ?? "選択なし")
                            .foregroundStyle(selectedEventName == nil ? DS.ink2 : DS.ink)
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
            .imasFilterSheetChrome()
            .toolbar {
                filterSheetToolbar(
                    analyticsPrefix: "song_filter",
                    canReset: hasActiveFilters,
                    onReset: resetAll,
                    onApply: {
                        applyFilter()
                        dismiss()
                    }
                )
            }
            .sheet(isPresented: $showIdolPicker) {
                IdolPickerView(
                    title: "アイドル",
                    idols: idols,
                    selected: selectedIdolIds
                ) { selectedIdolIds = $0 }
                    .environment(database)
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
        !nameFilter.isEmpty ||
        !selectedBrandIds.isEmpty || !selectedIdolIds.isEmpty ||
        !songwriterText.isEmpty || selectedCdSeries != nil || selectedSeriesGroup != nil ||
        selectedEventName != nil || selectedSongType != nil
    }

    private func resetAll() {
        nameFilter = ""
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

        // 既存フィルタから状態を復元 (初回のみ)
        guard !didRestore else { return }
        selectedBrandIds = filter.brandIds
        songwriterText = filter.songwriter ?? ""
        selectedCdSeries = filter.cdSeries
        selectedSeriesGroup = filter.seriesGroup
        selectedEventName = filter.liveName
        selectedSongType = filter.songType
        didRestore = true
    }
}
