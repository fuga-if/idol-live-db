import SwiftUI

/// セトリ編集等で曲を 1 つ選ぶための picker。検索バー付き。
struct SongPickerView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    let onPick: (PickedSong) -> Void

    @State private var allSongs: [PickedSong] = []
    @State private var query: String = ""
    @State private var isLoading = true

    private var filtered: [PickedSong] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(allSongs.prefix(100)) }
        let lower = trimmed.lowercased()
        return allSongs.filter { $0.title.lowercased().contains(lower) }.prefix(200).map { $0 }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    List(filtered) { song in
                        Button {
                            AppAnalytics.tap("song_picker.select")
                            onPick(song)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                Text(song.id)
                                    .font(.imasScaled(11))
                                    .foregroundStyle(.tertiary)
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
}
