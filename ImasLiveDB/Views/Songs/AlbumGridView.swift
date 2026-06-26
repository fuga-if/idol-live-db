import os
import SwiftUI

struct AlbumGridView: View {
    @Environment(AppDatabase.self) private var database
    let selectedBrandIds: Set<String>
    let searchText: String
    let onSelect: (AlbumSummary) -> Void

    @State private var albums: [AlbumSummary] = []
    @State private var isLoading = false

    var body: some View {
        GenericGridView(
            items: albums,
            isLoading: isLoading,
            emptyTitle: "アルバムが見つかりません",
            emptySystemImage: "square.grid.2x2",
            onSelect: onSelect
        )
        .clipped()
        .task(id: TaskKey(brandIds: selectedBrandIds, search: searchText)) { await loadAlbums() }
        .trackScreen("album_grid")
    }

    private struct TaskKey: Hashable { let brandIds: Set<String>; let search: String }

    private func loadAlbums() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try Task.checkCancellation()
            let result = try await AppContainer.shared.songReading.albums(
                brandIds: selectedBrandIds,
                query: searchText.isEmpty ? nil : searchText
            )
            try Task.checkCancellation()
            albums = result
        } catch is CancellationError {
            // レース回避: キャンセル済みのタスクの結果は捨てる
        } catch {
            Logger.database.error("load_failed albums: \(error.localizedDescription)")
        }
    }
}
