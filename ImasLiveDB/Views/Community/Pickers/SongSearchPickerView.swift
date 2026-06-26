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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                brandFilterBar

                if isLoading {
                    Spacer(); ProgressView(); Spacer()
                } else if results.isEmpty {
                    ImasEmptyState(
                        systemImage: "magnifyingglass",
                        title: "見つかりません",
                        message: query.isEmpty ? "ブランドや曲名で絞り込めます" : "「\(query)」に一致する楽曲がありません"
                    )
                    Spacer()
                } else {
                    songList
                }
            }
            .background(DS.bg)
            .searchable(text: $query, prompt: "曲名で検索")
            .navigationTitle("曲を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
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
            .task {
                brands = (try? await AppContainer.shared.brandReading.brands()) ?? []
                if let showId {
                    castOriginalSongIds = (try? await AppContainer.shared.songReading.originalSongIds(forShowCastOf: showId)) ?? []
                }
                await load()
            }
            .onChange(of: query) { _, _ in scheduleLoad() }
            .onChange(of: brandIds) { _, _ in Task { await load() } }
            .onChange(of: castOriginalOnly) { _, _ in Task { await load() } }
            .trackScreen("song_search_picker")
        }
    }

    /// 出演者のオリ曲が1件以上あるときだけトグルを出す (空なら誤って0件表示にしない)。
    private var showsCastOriginalToggle: Bool { !castOriginalSongIds.isEmpty }

    // MARK: - ブランドフィルタ chip 列

    private var brandFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.sp2) {
                if showsCastOriginalToggle {
                    Button {
                        AppAnalytics.tap("song_search_picker.cast_original_toggle")
                        castOriginalOnly.toggle()
                    } label: {
                        ImasChip(
                            text: "出演者のオリ曲",
                            systemImage: castOriginalOnly ? "checkmark" : "person.2",
                            style: castOriginalOnly ? .selected : .neutral
                        )
                    }
                    .buttonStyle(.plain)
                }
                Button { brandIds.removeAll() } label: {
                    ImasChip(text: "すべて", style: brandIds.isEmpty ? .selected : .neutral)
                }
                .buttonStyle(.plain)
                ForEach(brands) { brand in
                    let on = brandIds.contains(brand.id)
                    Button {
                        if on { brandIds.remove(brand.id) } else { brandIds.insert(brand.id) }
                    } label: {
                        ImasChip(text: brand.shortName, style: on ? .selected : .neutral, seed: brand.color)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.sp5)
            .padding(.vertical, DS.sp3)
        }
        .background(DS.bg)
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
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { filter.title = trimmed }
        do {
            var rows = try await AppContainer.shared.songReading.songs(filter: filter, sortOrder: .titleKana, ascending: nil)
            if castOriginalOnly && showsCastOriginalToggle {
                rows = rows.filter { castOriginalSongIds.contains($0.song.id) }
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
