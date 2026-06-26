import SwiftUI
import GRDB

// MARK: - IdolSearchPickerView

struct IdolSearchPickerView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss
    let onSelect: (Idol) -> Void

    @State private var query = ""
    @State private var results: [Idol] = []

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
                Task { await performSearch(query: newValue) }
            }
            .task {
                results = (try? await AppContainer.shared.idolReading.idols(brandId: nil)) ?? []
            }
            .trackScreen("idol_search_picker")
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
