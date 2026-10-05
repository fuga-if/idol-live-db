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
    /// コールガイド (歌詞行のコール・手拍子) が書き込まれている曲だけに絞るか。
    @Binding var callGuideOnly: Bool
    /// 歌詞のタイミング (行の再生位置) が記録されている曲だけに絞るか。
    @Binding var lyricTimingOnly: Bool
    @Binding var partsOnly: Bool
    /// 音楽カードゲーム「KAMISABI」の収録曲だけに絞るか。
    @Binding var kamisabiOnly: Bool

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
                ImasListSection("表示形式") {
                    ImasSegmented(options: SongListMode.allCases, selection: $listMode) { mode in
                        switch mode {
                        case .songs: "楽曲"
                        case .albums: "アルバム"
                        case .series: "シリーズ"
                        }
                    }
                    .padding(.horizontal, DS.Space.rowH)
                    .padding(.vertical, DS.Space.gap)

                    if listMode == .songs {
                        ImasSegmented(options: SongCollectFilter.allCases, selection: $collectFilter) { $0.rawValue }
                            .padding(.horizontal, DS.Space.rowH)
                            .padding(.vertical, DS.Space.gap)
                    }
                }

                if listMode == .songs {
                    ImasListSection("マイマーク", footer: "チェック ON で AND 条件絞り込み") {
                        ImasToggleRow(title: "担当アイドルの曲のみ", systemImage: "heart.fill", isOn: $myMarkFilter.requireMyPick)
                        ImasToggleRow(title: "お気に入りのみ", systemImage: "star.fill", isOn: $myMarkFilter.requireFavorite)
                        ImasToggleRow(title: "メモがある曲のみ", systemImage: "note.text", isOn: $myMarkFilter.requireNote)
                    }
                }

                if listMode == .songs, LyricsFeature.isAvailable {
                    ImasListSection("コールガイド・タイミング・パート分け",
                                    footer: "歌詞の行にコール・手拍子や、再生に合わせて追いかけるための時刻、誰が歌うかが書き込まれている曲だけを表示します (通信が必要)。") {
                        ImasToggleRow(title: "コールガイドがある曲のみ", systemImage: "hands.clap.fill", isOn: $callGuideOnly)
                        ImasToggleRow(title: "歌詞のタイミングがある曲のみ", systemImage: "metronome", isOn: $lyricTimingOnly)
                        ImasToggleRow(title: "パート分けがある曲のみ", systemImage: "person.2.fill", isOn: $partsOnly)
                    }
                }

                // ソート
                ImasListSection("並び順") {
                    ImasMenuRow(title: "並び順", options: SongSortOrder.allCases, selection: $sortOrder) { $0.rawValue }
                    sortDirectionRow
                }

                // ブランド
                BrandFilterSection(brands: brands, selectedBrandIds: $selectedBrandIds)

                ImasListSection {
                    ImasToggleRow(title: "ライブ限定曲を隠す",
                                 subtitle: "セトリにしか無い曲(カバー等)を一覧から隠します。既定 ON",
                                 isOn: $excludeLiveOnly)
                    ImasToggleRow(title: "「その他」を表示",
                                 subtitle: "歌枠で歌っただけのカバー等。既定では隠しています",
                                 isOn: $showOtherBrand)
                }

                if listMode == .songs {
                    ImasListSection("KAMISABI",
                                    footer: "音楽カードゲーム「KAMISABI」にカードが収録されている曲だけを表示します。") {
                        // 収録はカタログの事実、所持 (UserMarkKind.owned) はユーザーのマーク。
                        // 別物なので同じ記号 (shippingbox) を流用しない。
                        ImasToggleRow(title: "KAMISABI収録曲のみ", systemImage: "suit.club.fill", isOn: $kamisabiOnly)
                    }
                }

                // 曲タイプ
                ImasListSection("曲タイプ") {
                    songTypePicker
                        .padding(.horizontal, DS.Space.rowH)
                        .padding(.vertical, DS.Space.gap)
                }

                // アイドル選択
                ImasListSection("アイドル") {
                    Button {
                        showIdolPicker = true
                    } label: {
                        HStack(alignment: .top, spacing: DS.Space.rowGap) {
                            if selectedIdolIds.isEmpty {
                                Text("選択なし").imasText(.value, color: DS.ink2)
                            } else {
                                ImasChipFlow {
                                    ForEach(selectedIdolNames, id: \.self) { name in
                                        ImasChip(text: name, style: .neutral)
                                    }
                                }
                            }
                            Spacer(minLength: DS.Space.gap)
                            ImasRowChevron()
                        }
                        .padding(.horizontal, DS.Space.rowH)
                        .padding(.vertical, DS.Space.rowV)
                        .frame(minHeight: DS.Size.touch)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.imasRow)
                }

                // 作詞・作曲・編曲
                ImasListSection("作詞 / 作曲 / 編曲者") {
                    ImasTextFieldRow(title: "名前", text: $songwriterText, prompt: "名前を入力")
                }

                // シリーズ (series_group: LTF / BRILLI@NT WING 等)
                ImasListSection("シリーズ") {
                    NavigationLink {
                        ListPickerView(title: "シリーズ", items: seriesGroupList, selected: $selectedSeriesGroup)
                    } label: {
                        ImasNavRow(title: "シリーズ", value: selectedSeriesGroup ?? "選択なし")
                    }
                }

                // CDシリーズ
                ImasListSection("CDシリーズ") {
                    NavigationLink {
                        ListPickerView(title: "CDシリーズ", items: cdSeriesList, selected: $selectedCdSeries)
                    } label: {
                        ImasNavRow(title: "CDシリーズ", value: selectedCdSeries ?? "選択なし")
                    }
                }

                // ライブ名
                ImasListSection("ライブで絞込") {
                    NavigationLink {
                        ListPickerView(title: "ライブ", items: eventNames, selected: $selectedEventName)
                    } label: {
                        ImasNavRow(title: "ライブ", value: selectedEventName ?? "選択なし")
                    }
                }

                // リセット
                if hasActiveFilters {
                    ImasListSection {
                        ImasActionRow(title: "すべてリセット", systemImage: "arrow.counterclockwise", kind: .destructive) {
                            resetAll()
                        }
                    }
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

    /// 並び順の方向 (昇順・降順)。
    private var sortDirectionRow: some View {
        HStack {
            Text("方向").imasText(.rowLabel)
            Spacer(minLength: DS.Space.gap)
            ImasSegmented(options: [true, false], selection: Binding(
                get: { sortAscending ?? sortOrder.defaultAscending },
                set: { sortAscending = $0 }
            )) { $0 ? "昇順" : "降順" }
        }
        .padding(.horizontal, DS.Space.rowH)
        .padding(.vertical, DS.Space.rowVCompact)
        .frame(minHeight: DS.Size.touch)
    }

    // MARK: - Song Type Picker

    private var songTypePicker: some View {
        ImasChipRow {
            songTypeChip(value: nil, label: "全て")
            // 絞り込みは今までどおり先頭の 3 種 (ソロ / ユニット / 全体曲)。語はコアの vocabulary。
            ForEach(Vocab.table.songTypes.prefix(3), id: \.value) { term in
                songTypeChip(value: term.value, label: term.shortLabel)
            }
        }
    }

    private func songTypeChip(value: String?, label: String) -> some View {
        ImasFilterChip(text: label, isSelected: selectedSongType == value) {
            selectedSongType = value
        }
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
