import SwiftUI

// MARK: - ShowSearchPickerView

struct ShowSearchPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (ShowWithEventName) -> Void

    @State private var query = ""
    @State private var results: [ShowWithEventName] = []
    /// 検索デバウンス用の世代 ID (SongSearchPickerView.scheduleLoad と同方式)。
    @State private var searchToken = 0

    var body: some View {
        NavigationStack {
            List {
                if results.isEmpty && !query.isEmpty {
                    ImasEmptyState(
                        systemImage: "magnifyingglass",
                        title: "見つかりません",
                        message: "「\(query)」に一致する公演がありません"
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } else if results.isEmpty && query.isEmpty {
                    ImasEmptyState(
                        systemImage: "ticket",
                        title: "公演を検索",
                        message: "公演名またはイベント名を入力して検索してください"
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                ForEach(results) { show in
                    Button {
                        AppAnalytics.tap("show_search_picker.select")
                        onSelect(show)
                        dismiss()
                    } label: {
                        ImasShowRow(date: String(show.date.prefix(10)), title: show.name,
                                   subtitle: eventDisplayName(show.eventName))
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DS.bg)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "公演名・イベント名で検索")
            .navigationTitle("公演を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("キャンセル")
                }
            }
            .onChange(of: query) { _, newValue in
                scheduleSearch(query: newValue)
            }
            .task {
                results = (try? await AppContainer.shared.showReading.allShows(limit: 50)) ?? []
            }
            .trackScreen("show_search_picker")
        }
    }

    /// 入力中の連打を抑える簡易デバウンス + 古い検索結果が新しい入力を上書きしないための
    /// 世代ガード。
    private func scheduleSearch(query: String) {
        searchToken += 1
        let token = searchToken
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard token == searchToken else { return }
            await performSearch(query: query)
        }
    }

    private func performSearch(query: String) async {
        if query.isEmpty {
            results = (try? await AppContainer.shared.showReading.allShows(limit: 50)) ?? []
            return
        }
        results = (try? await AppContainer.shared.showReading.searchShows(query: query, limit: 30)) ?? []
    }
}
