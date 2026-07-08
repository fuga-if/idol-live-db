import SwiftUI
import GRDB

// MARK: - IdolSearchPickerView

struct IdolSearchPickerView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss
    let onSelect: (Idol) -> Void

    @State private var query = ""
    @State private var results: [Idol] = []
    /// 検索デバウンス用の世代 ID (SongSearchPickerView.scheduleLoad と同方式)。
    @State private var searchToken = 0

    var body: some View {
        NavigationStack {
            List {
                if results.isEmpty && !query.isEmpty {
                    EmptyStateCard(
                        icon: "magnifyingglass",
                        title: "見つかりません",
                        message: "「\(query)」に一致するアイドルがありません"
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } else if results.isEmpty && query.isEmpty {
                    EmptyStateCard(
                        icon: "person.fill",
                        title: "アイドルを検索",
                        message: "名前を入力して検索してください"
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                ForEach(results) { idol in
                    Button {
                        AppAnalytics.tap("idol_search_picker.select")
                        onSelect(idol)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            IdolAvatarView(idol: idol, size: 36)
                            IdolNameRow(idol: idol, subtitle: idol.nameKana, showsChevron: true)
                        }
                    }
                    .accessibilityLabel(idol.name)
                    .listRowBackground(DS.surface)
                    .listRowSeparatorTint(DS.sep)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DS.bg)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "アイドル名で検索")
            .navigationTitle("アイドルを選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .onChange(of: query) { _, newValue in
                scheduleSearch(query: newValue)
            }
            .task {
                results = (try? await AppContainer.shared.idolReading.idols(brandId: nil)) ?? []
            }
            .trackScreen("idol_search_picker")
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
            results = (try? await AppContainer.shared.idolReading.idols(brandId: nil)) ?? []
            return
        }
        results = (try? await AppContainer.shared.idolReading.searchIdols(query: query, limit: 50)) ?? []
    }
}
