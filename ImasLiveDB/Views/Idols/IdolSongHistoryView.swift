import os
import SwiftUI

struct IdolSongHistoryView: View {
    @Environment(AppDatabase.self) private var database
    let idol: Idol
    let song: Song
    let navigate: (DetailDestination) -> Void

    @State private var history: [CastShowRow] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if history.isEmpty {
                ContentUnavailableView(
                    "披露履歴がありません",
                    systemImage: "music.microphone",
                    description: Text("\(idol.name) による「\(song.title)」の披露記録はありません")
                )
            } else {
                List {
                    Section {
                        ForEach(Array(history.enumerated()), id: \.offset) { _, row in
                            ShowHistoryButton(
                                showId: row.showId,
                                eventName: row.eventName,
                                showName: row.showName,
                                date: row.date,
                                navigate: navigate
                            )
                        }
                    } header: {
                        Text("全\(history.count)回")
                            .font(.imasCaption)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("\(idol.name) × \(song.title)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadHistory() }
        .trackScreen("idol_song_history")
    }

    private func loadHistory() async {
        isLoading = true
        defer { isLoading = false }
        do {
            history = try await AppContainer.shared.idolReading.idolSongHistory(idolId: idol.id, songId: song.id)
        } catch {
            Logger.database.error("load_failed idol_song_history: \(error.localizedDescription)")
            history = []
        }
    }
}
