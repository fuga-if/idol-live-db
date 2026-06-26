import os
import SwiftUI

struct SeriesGridView: View {
    @Environment(AppDatabase.self) private var database
    let selectedBrandIds: Set<String>
    let searchText: String
    let onSelect: (SeriesSummary) -> Void

    @State private var series: [SeriesSummary] = []
    @State private var isLoading = false

    var body: some View {
        GenericGridView(
            items: series,
            isLoading: isLoading,
            emptyTitle: "シリーズが見つかりません",
            emptySystemImage: "rectangle.stack",
            onSelect: onSelect
        )
        .clipped()
        .task(id: TaskKey(brandIds: selectedBrandIds, search: searchText)) { await loadSeries() }
        .trackScreen("series_grid")
    }

    private struct TaskKey: Hashable { let brandIds: Set<String>; let search: String }

    private func loadSeries() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try Task.checkCancellation()
            let result = try await AppContainer.shared.songReading.series(
                brandIds: selectedBrandIds,
                query: searchText.isEmpty ? nil : searchText
            )
            try Task.checkCancellation()
            series = result
        } catch is CancellationError {
            // レース回避: キャンセル済みのタスクの結果は捨てる
        } catch {
            Logger.database.error("load_failed series: \(error.localizedDescription)")
        }
    }
}
