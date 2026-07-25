import os
import SwiftUI

// MARK: - SongSearchPickerView

/// 曲を選ぶ picker。楽曲一覧と同じ見た目 (SongRowView) で、通常の楽曲一覧 (SongFilterView) と
/// 遜色ない絞り込み体験を提供する: ブランド・曲名・作詞作曲編曲者・タグ・アイドル・曲タイプ・
/// シリーズ/CDシリーズ・マイマーク (担当/お気に入り)。複数選択に対応し、一度の起動でまとめて
/// 追加できる (セトリ予想で1曲ずつ開き直す手間を解消)。
///
/// セトリ予想 (SetlistPredictionView) や投票お題への曲追加で「曲名でしか指定できず追加が難しい」
/// 問題への対応として作られたが、絞り込み手段が曲名検索だけでは弱い (作家買い・タグから探す等の
/// 導線が無い) という声を受けて、通常の楽曲一覧とほぼ同じ絞り込み手段を持つよう拡張している。
struct SongSearchPickerView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss
    /// 「出演者のオリ曲のみ」絞り込みの対象公演。 nil ならトグルを出さない。
    var showId: String? = nil
    /// ブランドを外から強制する場合に指定 (例: 投票お題が brand スコープの時)。
    /// 値があるとき、ブランドフィルタ chip 列は出さず、検索は常にこの集合内に限定される。
    var restrictedBrandIds: Set<String>? = nil
    /// 検索対象を特定の曲 ID 集合に限定する (例: 投票お題が manual スコープの時)。
    /// 値があるとき、ブランドフィルタも非表示にし、ヒットは集合内のみ。
    var restrictedSongIds: Set<String>? = nil
    /// 選択確定時に選んだ曲をまとめて返す (選択順を保持)。
    let onSubmit: ([Song]) -> Void

    private var markService: UserMarkService { UserMarkService.shared }

    @State private var query = ""
    @State private var brandIds: Set<String> = []
    @State private var brands: [Brand] = []
    @State private var results: [SongWithArtists] = []
    @State private var isLoading = true
    @State private var loadToken = 0
    /// 選択中の曲 (選択順を保持。フィルタを跨いでも維持される)。
    @State private var selected: [Song] = []
    /// 出演者がオリメンの曲 song_id 集合 (showId 指定時のみ読み込む)。 空ならトグル非表示。
    @State private var castOriginalSongIds: Set<String> = []
    /// 「出演者のオリ曲のみ」トグルの ON/OFF。 デフォルト OFF。
    @State private var castOriginalOnly = false
    /// 並び順。デフォルトは 五十音順。
    @State private var sortOrder: SongSortOrder = .titleKana
    /// ライブ履歴 (セトリ) にしか存在しない、メタ皆無のファントム曲を除外するか。
    @State private var excludeLiveOnly = false
    /// リミックスを含めるか (デフォルトは含めない、原曲だけ出す)。
    @State private var includeRemixes = false
    /// 作詞・作曲・編曲者名での検索 (SongFilterView と同じ songwriter フィルタを使う)。
    @State private var songwriterText = ""
    /// 曲タイプ (ソロ/ユニット/全体曲)。nil = 全て。
    @State private var songType: String? = nil
    /// アイドルで絞り込み (歌唱に関わる曲のみ)。
    @State private var selectedIdolIds: Set<String> = []
    @State private var idols: [Idol] = []
    /// シリーズ (series_group) / CD シリーズでの絞り込み。
    @State private var selectedSeriesGroup: String? = nil
    @State private var selectedCdSeries: String? = nil
    @State private var seriesGroupList: [String] = []
    @State private var cdSeriesList: [String] = []
    /// マイマーク (担当/お気に入り) での絞り込み。楽曲一覧と同じ純粋ロジック (applySongMarkFilters) で適用。
    @State private var myMarkFilter = SongMyMarkFilter()
    /// タグ絞り込み。複数選択時は AND (全タグを含む曲)。曲一覧の TagFilterPicker と同じ仕組み。
    @State private var selectedTags: [CommunityTag] = []
    /// selectedTags から解決した song_id 集合 (nil = 絞り込みなし)。
    @State private var tagSongIds: Set<String>? = nil
    /// タグ絞り込みの解決に失敗したか (オフライン等)。失敗時は既存の絞り込みを保持し 0 件と誤読しない。
    @State private var tagFilterError = false

    /// フィルタ UI を出すか (外部から brand/songs を強制している時は隠す)。
    private var showsFilterButton: Bool { restrictedBrandIds == nil && restrictedSongIds == nil }
    /// フィルタが何か当たっているか (ボタンに塗りつぶしを出す判定)。
    private var isFilterActive: Bool {
        let basic = !brandIds.isEmpty || castOriginalOnly || excludeLiveOnly || includeRemixes
            || sortOrder != .titleKana || !songwriterText.isEmpty
        let advanced = !selectedTags.isEmpty || songType != nil || !selectedIdolIds.isEmpty
            || selectedSeriesGroup != nil || selectedCdSeries != nil || myMarkFilter.isActive
        return basic || advanced
    }

    @State private var showFilter = false

    var body: some View {
        NavigationStack {
            reactiveContent
                .trackScreen("song_search_picker")
        }
    }

    /// 即時 (デバウンスなし) 再検索をトリガする state 一式。1つの Equatable にまとめることで
    /// onChange の数を絞り、SwiftUI の型検査が長時間化するのを防ぐ (曲名/作家名検索は別途デバウンス)。
    private struct ReloadTrigger: Equatable {
        var brandIds: Set<String>
        var castOriginalOnly: Bool
        var sortOrder: SongSortOrder
        var excludeLiveOnly: Bool
        var includeRemixes: Bool
        var songType: String?
        var selectedIdolIds: Set<String>
        var selectedSeriesGroup: String?
        var selectedCdSeries: String?
        var myMarkFilter: SongMyMarkFilter
    }

    private var reloadTrigger: ReloadTrigger {
        ReloadTrigger(brandIds: brandIds, castOriginalOnly: castOriginalOnly, sortOrder: sortOrder,
                      excludeLiveOnly: excludeLiveOnly, includeRemixes: includeRemixes, songType: songType,
                      selectedIdolIds: selectedIdolIds, selectedSeriesGroup: selectedSeriesGroup,
                      selectedCdSeries: selectedCdSeries, myMarkFilter: myMarkFilter)
    }

    /// `baseContent` に絞り込み系 state の変化 → 再検索を配線する。
    private var reactiveContent: some View {
        baseContent
            .onChange(of: query) { _, _ in scheduleLoad() }
            .onChange(of: songwriterText) { _, _ in scheduleLoad() }
            .onChange(of: reloadTrigger) { _, _ in Task { await load() } }
            .onChange(of: selectedTags) { _, tags in Task { await resolveTagFilter(tags) } }
    }

    private var baseContent: some View {
        content
            .background(DS.bg)
            .searchable(text: $query, prompt: "曲名で検索")
            .navigationTitle("曲を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showFilter) {
                SongPickerFilterSheet(
                    brands: brands,
                    brandIds: $brandIds,
                    sortOrder: $sortOrder,
                    excludeLiveOnly: $excludeLiveOnly,
                    includeRemixes: $includeRemixes,
                    showsCastOriginalToggle: showsCastOriginalToggle,
                    castOriginalOnly: $castOriginalOnly,
                    songwriterText: $songwriterText,
                    songType: $songType,
                    idols: idols,
                    selectedIdolIds: $selectedIdolIds,
                    seriesGroupList: seriesGroupList,
                    selectedSeriesGroup: $selectedSeriesGroup,
                    cdSeriesList: cdSeriesList,
                    selectedCdSeries: $selectedCdSeries,
                    myMarkFilter: $myMarkFilter,
                    selectedTags: $selectedTags
                )
                .environment(database)
                .presentationDetents([.large])
            }
            .task {
                brands = (try? await AppContainer.shared.brandReading.brands()) ?? []
                idols = (try? await AppContainer.shared.idolReading.idols(brandId: nil)) ?? []
                seriesGroupList = (try? await AppContainer.shared.songReading.seriesGroups(brandIds: [])) ?? []
                cdSeriesList = (try? await AppContainer.shared.songReading.cdSeriesList()) ?? []
                if let showId {
                    castOriginalSongIds = (try? await AppContainer.shared.songReading.originalSongIds(forShowCastOf: showId)) ?? []
                }
                if let restricted = restrictedBrandIds {
                    // 外部強制 brand を初期値に固定 (フィルタボタンは出さない)
                    brandIds = restricted
                }
                await load()
            }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("キャンセル") { dismiss() }
        }
        if showsFilterButton {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showFilter = true } label: {
                    Image(systemName: isFilterActive
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("フィルター")
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(selected.isEmpty ? "追加" : "追加 (\(selected.count))") {
                AppAnalytics.tap("song_search_picker.submit")
                onSubmit(selected)
                dismiss()
            }
            .disabled(selected.isEmpty)
            .fontWeight(.semibold)
        }
    }

    /// 出演者のオリ曲が1件以上あるときだけトグルを出す (空なら誤って0件表示にしない)。
    private var showsCastOriginalToggle: Bool { !castOriginalSongIds.isEmpty }

    /// 検索本体 (ローディング / 結果空 / リスト)。
    @ViewBuilder
    private var content: some View {
        if isLoading {
            // 楽曲一覧と同じスケルトン (ジャケ + タイトル2行) を出す。
            ScrollView {
                ImasListSkeleton(rows: 12, thumb: .square)
                    .padding(.top, DS.sp3)
            }
            .scrollDisabled(true)
        } else if results.isEmpty {
            VStack(spacing: 0) {
                ImasEmptyState(
                    systemImage: "magnifyingglass",
                    title: "見つかりません",
                    message: query.isEmpty ? "右上のフィルターか曲名で絞り込めます" : "「\(query)」に一致する楽曲がありません"
                )
                if tagFilterError {
                    Text("タグ絞り込みの取得に失敗しました。電波状況をご確認ください。")
                        .font(.imasCaption).foregroundStyle(DS.warning)
                        .padding(.top, 8)
                }
                Spacer()
            }
        } else {
            songList
        }
    }

    private var songList: some View {
        List {
            if tagFilterError {
                Section {
                    Label("タグ絞り込みの取得に失敗しました (表示中の結果には未反映です)", systemImage: "exclamationmark.triangle")
                        .font(.imasCaption).foregroundStyle(DS.warning)
                }
                .listRowBackground(DS.surface)
            }
            Section {
                ForEach(results) { item in
                    let isOn = selected.contains { $0.id == item.song.id }
                    Button {
                        toggle(item.song)
                    } label: {
                        HStack(spacing: DS.sp3) {
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .font(.imasTitle3)
                                .foregroundStyle(isOn ? DS.pick : DS.ink3)
                            SongRowView(item: item)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: DS.sp5, bottom: 0, trailing: DS.sp5))
                    .listRowBackground(isOn ? DS.fill : DS.surface)
                    .listRowSeparatorTint(DS.sep)
                }
            } header: {
                Text(selected.isEmpty ? "\(results.count)曲" : "\(results.count)曲 ・ \(selected.count)曲選択中")
                    .font(.imasCaption).foregroundStyle(DS.ink3)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.bg)
    }

    private func toggle(_ song: Song) {
        if let idx = selected.firstIndex(where: { $0.id == song.id }) {
            selected.remove(at: idx)
        } else {
            selected.append(song)
        }
    }

    // MARK: - Data

    /// 入力中の連打を抑えるための簡易デバウンス。
    private func scheduleLoad() {
        loadToken += 1
        let token = loadToken
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard token == loadToken else { return }
            await load()
        }
    }

    /// タグ絞り込みの song_id 集合を解決する (曲一覧の SongListViewModel.resolveTagFilter と同じ仕組み)。
    /// 複数選択時は各タグの song_id 集合の積集合 (AND)。取得失敗時は既存の絞り込みを保持する。
    private func resolveTagFilter(_ tags: [CommunityTag]) async {
        guard !tags.isEmpty else {
            tagSongIds = nil
            tagFilterError = false
            await load()
            return
        }
        var intersection: Set<String>?
        var failed = false
        for tag in tags {
            do {
                let tagSongs = try await CommunityAPI.shared.tag(id: tag.id).songs
                let ids = Set(tagSongs.map(\.songId))
                intersection = intersection.map { $0.intersection(ids) } ?? ids
            } catch {
                failed = true
            }
        }
        tagFilterError = failed
        guard !failed else { return }
        tagSongIds = intersection ?? []
        await load()
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        var filter = SongSearchFilter()
        filter.brandIds = brandIds
        filter.includeRemixes = includeRemixes
        filter.excludeLiveOnly = excludeLiveOnly
        filter.songType = songType
        filter.idolIds = selectedIdolIds.isEmpty ? nil : Array(selectedIdolIds)
        filter.seriesGroup = selectedSeriesGroup
        filter.cdSeries = selectedCdSeries
        let trimmedTitle = query.trimmingCharacters(in: .whitespaces)
        if !trimmedTitle.isEmpty { filter.title = trimmedTitle }
        let trimmedWriter = songwriterText.trimmingCharacters(in: .whitespaces)
        if !trimmedWriter.isEmpty { filter.songwriter = trimmedWriter }
        do {
            var rows = try await AppContainer.shared.songReading.songs(filter: filter, sortOrder: sortOrder, ascending: nil)
            if castOriginalOnly && showsCastOriginalToggle {
                rows = rows.filter { castOriginalSongIds.contains($0.song.id) }
            }
            if let allowed = restrictedSongIds {
                rows = rows.filter { allowed.contains($0.song.id) }
            }

            var ctx = SongMarkFilterContext(collectFilter: .all)
            if myMarkFilter.requireFavorite {
                ctx.requireFavorite = true
                ctx.favoriteIds = Set(markService.allMarked(kind: .favorite, entity: .song))
            }
            if myMarkFilter.requireNote {
                ctx.requireNote = true
                ctx.noteIds = Set(markService.allMarked(kind: .note, entity: .song))
            }
            if myMarkFilter.requireMyPick {
                ctx.requireMyPick = true
                let pickIdols = Set(markService.allMarked(kind: .myPick, entity: .idol))
                ctx.myPickSongIds = pickIdols.isEmpty
                    ? [] : Set((try? await AppContainer.shared.songReading.songIdsWithAnyArtist(idolIds: pickIdols)) ?? [])
            }
            if let tagSongIds { ctx.tagSongIds = tagSongIds }
            rows = applySongMarkFilters(rows, ctx)

            let map = (try? await AppContainer.shared.songReading.songPerformerIdolsMap(songIds: rows.map(\.song.id))) ?? [:]
            for i in rows.indices {
                rows[i].performerIdols = map[rows[i].song.id] ?? []
            }
            results = rows
        } catch {
            Logger.database.error("load_failed song_picker: \(error.localizedDescription)")
            results = []
        }
    }
}

// MARK: - SongPickerFilterSheet

/// SongSearchPickerView 専用のフィルタ・並び替えシート。通常の楽曲一覧 (SongFilterView) と
/// ほぼ同じ絞り込み手段 (ブランド/曲タイプ/アイドル/作詞作曲編曲者/シリーズ/CDシリーズ/
/// マイマーク/タグ) を持つ。一覧専用の表示形式(リスト/アルバム/シリーズ切替)・現地回収フィルタ・
/// ライブで絞込 (liveName) は、ピッカーの用途 (曲を選んで追加するだけ) には不要なので省いている。
private struct SongPickerFilterSheet: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss
    let brands: [Brand]
    @Binding var brandIds: Set<String>
    @Binding var sortOrder: SongSortOrder
    @Binding var excludeLiveOnly: Bool
    @Binding var includeRemixes: Bool
    let showsCastOriginalToggle: Bool
    @Binding var castOriginalOnly: Bool
    @Binding var songwriterText: String
    @Binding var songType: String?
    let idols: [Idol]
    @Binding var selectedIdolIds: Set<String>
    let seriesGroupList: [String]
    @Binding var selectedSeriesGroup: String?
    let cdSeriesList: [String]
    @Binding var selectedCdSeries: String?
    @Binding var myMarkFilter: SongMyMarkFilter
    @Binding var selectedTags: [CommunityTag]

    @State private var showIdolPicker = false
    @State private var showTagPicker = false

    /// ピッカーで意味のある並び順だけ。回収率・現地回収回数は SongListView 専用。
    private let availableSortOrders: [SongSortOrder] = [.titleKana, .releaseDate, .performanceCount]

    private var isAnyFilterActive: Bool {
        let basic = !brandIds.isEmpty || excludeLiveOnly || includeRemixes
            || (showsCastOriginalToggle && castOriginalOnly) || sortOrder != .titleKana || !songwriterText.isEmpty
        let advanced = songType != nil || !selectedIdolIds.isEmpty || selectedSeriesGroup != nil
            || selectedCdSeries != nil || myMarkFilter.isActive || !selectedTags.isEmpty
        return basic || advanced
    }

    private var selectedIdolNames: [String] {
        idols.filter { selectedIdolIds.contains($0.id) }.map(\.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("並び順", selection: $sortOrder) {
                        ForEach(availableSortOrders, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                } header: {
                    Text("並び順")
                }

                Section {
                    Toggle(isOn: $myMarkFilter.requireMyPick) {
                        Label("担当アイドルの曲のみ", systemImage: "heart.fill").foregroundStyle(DS.pick)
                    }
                    Toggle(isOn: $myMarkFilter.requireFavorite) {
                        Label("お気に入りのみ", systemImage: "star.fill").foregroundStyle(DS.favorite)
                    }
                } header: {
                    Text("マイマーク")
                }

                Section {
                    Button {
                        showTagPicker = true
                    } label: {
                        HStack {
                            if selectedTags.isEmpty {
                                Text("選択なし").foregroundStyle(DS.ink2)
                            } else {
                                Text(selectedTags.map(\.name).joined(separator: " ＋ "))
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.imasCaption).foregroundStyle(DS.ink3)
                        }
                    }
                } header: {
                    Text("タグ")
                } footer: {
                    Text("複数選択時は全てのタグを含む曲だけに絞り込みます。")
                        .font(.imasScaled(11)).foregroundStyle(.tertiary)
                }

                BrandFilterSection(brands: brands, selectedBrandIds: $brandIds)

                Section {
                    Toggle("ライブ履歴のみの曲を隠す", isOn: $excludeLiveOnly)
                    Toggle("リミックスを含める", isOn: $includeRemixes)
                    if showsCastOriginalToggle {
                        Toggle("出演者のオリ曲のみ", isOn: $castOriginalOnly)
                    }
                } header: {
                    Text("絞り込み")
                } footer: {
                    Text("「ライブ履歴のみ」は、セトリ追加で生まれただけでカタログ情報が無い曲 (カバー・歌枠等) を隠します。")
                        .font(.imasScaled(11)).foregroundStyle(.tertiary)
                }

                Section("曲タイプ") {
                    songTypePicker
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section("アイドル") {
                    Button {
                        showIdolPicker = true
                    } label: {
                        HStack {
                            if selectedIdolIds.isEmpty {
                                Text("選択なし").foregroundStyle(DS.ink2)
                            } else {
                                FlowLayout(spacing: 4) {
                                    ForEach(selectedIdolNames, id: \.self) { name in
                                        Text(name)
                                            .font(.imasCaption)
                                            .padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(DS.fill)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.imasCaption).foregroundStyle(DS.ink3)
                        }
                    }
                }

                Section("作詞 / 作曲 / 編曲者") {
                    TextField("名前を入力", text: $songwriterText).textFieldStyle(.plain)
                }

                Section("シリーズ") {
                    NavigationLink {
                        ListPickerView(title: "シリーズ", items: seriesGroupList, selected: $selectedSeriesGroup)
                    } label: {
                        Text(selectedSeriesGroup ?? "選択なし")
                            .foregroundStyle(selectedSeriesGroup == nil ? DS.ink2 : DS.ink)
                    }
                }

                Section("CDシリーズ") {
                    NavigationLink {
                        ListPickerView(title: "CDシリーズ", items: cdSeriesList, selected: $selectedCdSeries)
                    } label: {
                        Text(selectedCdSeries ?? "選択なし")
                            .foregroundStyle(selectedCdSeries == nil ? DS.ink2 : DS.ink)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.bg)
            .navigationTitle("フィルター / 並び順")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("リセット") {
                        brandIds.removeAll()
                        sortOrder = .titleKana
                        excludeLiveOnly = false
                        includeRemixes = false
                        castOriginalOnly = false
                        songwriterText = ""
                        songType = nil
                        selectedIdolIds.removeAll()
                        selectedSeriesGroup = nil
                        selectedCdSeries = nil
                        myMarkFilter = SongMyMarkFilter()
                        selectedTags.removeAll()
                    }
                    .disabled(!isAnyFilterActive)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }.fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showIdolPicker) {
                IdolPickerView(
                    title: "アイドルで絞り込み",
                    idols: idols,
                    selected: selectedIdolIds
                ) { selectedIdolIds = $0 }
                    .environment(database)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showTagPicker) {
                TagFilterPicker(initialSelection: selectedTags) { selectedTags = $0 }
            }
        }
    }

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
        let isSelected = songType == value
        return Button {
            songType = value
        } label: {
            ImasChip(text: label, style: isSelected ? .selected : .neutral)
        }
        .buttonStyle(.plain)
    }
}
