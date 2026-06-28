import os
import SwiftUI

// MARK: - SongSearchPickerView

/// 曲を選ぶ picker。楽曲一覧と同じ見た目 (SongRowView) で、ブランドフィルタ + 曲名検索つき。
/// 複数選択に対応し、一度の起動でまとめて追加できる (セトリ予想で1曲ずつ開き直す手間を解消)。
///
/// セトリ予想 (SetlistPredictionView) で「曲名でしか指定できず追加が難しい」問題への対応として、
/// 一覧と同等の絞り込み体験を提供する。
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

    /// フィルタ UI を出すか (外部から brand/songs を強制している時は隠す)。
    private var showsFilterButton: Bool { restrictedBrandIds == nil && restrictedSongIds == nil }
    /// フィルタが何か当たっているか (ボタンに塗りつぶしを出す判定)。
    private var isFilterActive: Bool {
        !brandIds.isEmpty || castOriginalOnly || excludeLiveOnly || includeRemixes || sortOrder != .titleKana
    }

    @State private var showFilter = false

    var body: some View {
        NavigationStack {
            content
                .background(DS.bg)
                .searchable(text: $query, prompt: "曲名で検索")
                .navigationTitle("曲を追加")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
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
                .sheet(isPresented: $showFilter) {
                    SongPickerFilterSheet(
                        brands: brands,
                        brandIds: $brandIds,
                        sortOrder: $sortOrder,
                        excludeLiveOnly: $excludeLiveOnly,
                        includeRemixes: $includeRemixes,
                        showsCastOriginalToggle: showsCastOriginalToggle,
                        castOriginalOnly: $castOriginalOnly
                    )
                    .presentationDetents([.large])
                }
                .task {
                    brands = (try? await AppContainer.shared.brandReading.brands()) ?? []
                    if let showId {
                        castOriginalSongIds = (try? await AppContainer.shared.songReading.originalSongIds(forShowCastOf: showId)) ?? []
                    }
                    if let restricted = restrictedBrandIds {
                        // 外部強制 brand を初期値に固定 (フィルタボタンは出さない)
                        brandIds = restricted
                    }
                    await load()
                }
                .onChange(of: query) { _, _ in scheduleLoad() }
                .onChange(of: brandIds) { _, _ in Task { await load() } }
                .onChange(of: castOriginalOnly) { _, _ in Task { await load() } }
                .onChange(of: sortOrder) { _, _ in Task { await load() } }
                .onChange(of: excludeLiveOnly) { _, _ in Task { await load() } }
                .onChange(of: includeRemixes) { _, _ in Task { await load() } }
                .trackScreen("song_search_picker")
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
                Spacer()
            }
        } else {
            songList
        }
    }

    private var songList: some View {
        List {
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

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        var filter = SongSearchFilter()
        filter.brandIds = brandIds
        filter.includeRemixes = includeRemixes
        filter.excludeLiveOnly = excludeLiveOnly
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { filter.title = trimmed }
        do {
            var rows = try await AppContainer.shared.songReading.songs(filter: filter, sortOrder: sortOrder, ascending: nil)
            if castOriginalOnly && showsCastOriginalToggle {
                rows = rows.filter { castOriginalSongIds.contains($0.song.id) }
            }
            if let allowed = restrictedSongIds {
                rows = rows.filter { allowed.contains($0.song.id) }
            }
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

/// SongSearchPickerView 専用のフィルタ・並び替えシート。
/// SongListView の SongFilterView は独自フィルタ (担当/お気に入り/メモ/タグ/シリーズ/CD 等) まで
/// 含む大型 sheet なので、ピッカーにはオーバースペック。ここでは検索ピッカーで実用上効きそうな
/// 項目だけに絞っている (絞り込み: ブランド / ライブ履歴のみ曲除外 / リミックス / 出演者オリ曲、
/// 並び順: 五十音 / リリース日 / 披露回数)。
private struct SongPickerFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let brands: [Brand]
    @Binding var brandIds: Set<String>
    @Binding var sortOrder: SongSortOrder
    @Binding var excludeLiveOnly: Bool
    @Binding var includeRemixes: Bool
    let showsCastOriginalToggle: Bool
    @Binding var castOriginalOnly: Bool

    /// ピッカーで意味のある並び順だけ。回収率・現地回収回数は SongListView 専用。
    private let availableSortOrders: [SongSortOrder] = [.titleKana, .releaseDate, .performanceCount]

    private var isAnyFilterActive: Bool {
        !brandIds.isEmpty || excludeLiveOnly || includeRemixes
            || (showsCastOriginalToggle && castOriginalOnly)
            || sortOrder != .titleKana
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
                    }
                    .disabled(!isAnyFilterActive)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}
