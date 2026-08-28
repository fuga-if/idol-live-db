import SwiftUI

/// セトリ編集等で曲を 1 つ選ぶための picker。検索バー付き。
struct SongPickerView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    let onPick: (PickedSong) -> Void

    @State private var allSongs: [PickedSong] = []
    @State private var query: String = ""
    @State private var isLoading = true
    /// 絞り込み用の索引。曲を読んだ時に 1 回だけ組む。
    @State private var catalog: TextSearchCatalog?

    private var filtered: [PickedSong] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(allSongs.prefix(100)) }
        // 照合はコア (`domain/text_search_index.rs`) に一任する。ここで
        // `title.lowercased().contains` を書いていたので、**読みで引けなかった**
        // (曲一覧は「みちしるべ」で当たるのに、編集 UI の曲ピッカーだけ当たらない)。
        // 索引が無い (読み込み前) 間は絞り込まない。黙って 0 件にする方が悪い。
        guard let catalog else { return Array(allSongs.prefix(200)) }
        return Array(catalog.filter(allSongs, needle: trimmed).prefix(200))
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ImasLoadingState()
                } else {
                    List(filtered) { song in
                        Button {
                            AppAnalytics.tap("song_picker.select")
                            onPick(song)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: DS.sp1) {
                                Text(song.title)
                                Text(song.id)
                                    .font(.imasCaption2)
                                    .foregroundStyle(DS.ink3)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("曲を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .searchable(text: $query, prompt: "曲名で検索")
            .task {
                do {
                    allSongs = try await AppContainer.shared.songReading.allSongsForPicker()
                    catalog = TextSearchCatalog(fieldsPerItem: allSongs.map { [$0.title, $0.titleKana] })
                    isLoading = false
                } catch {
                    isLoading = false
                }
            }
            .trackScreen("song_picker")
        }
    }
}

struct PickedSong: Identifiable, Hashable {
    let id: String
    let title: String
    /// 検索用の読み。並びには使わない (ピッカーの並びは `title` のバイト列順)。
    let titleKana: String?
}
