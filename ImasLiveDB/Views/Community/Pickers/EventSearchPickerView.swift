import SwiftUI
import GRDB

// MARK: - EventSearchPickerView

struct EventSearchPickerView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss
    let onSelect: (Event) -> Void

    @State private var query = ""
    @State private var results: [Event] = []

    var body: some View {
        NavigationStack {
            List {
                if results.isEmpty && !query.isEmpty {
                    EmptyStateCard(
                        icon: "magnifyingglass",
                        title: "見つかりません",
                        message: "「\(query)」に一致するイベントがありません"
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } else if results.isEmpty && query.isEmpty {
                    EmptyStateCard(
                        icon: "calendar",
                        title: "イベントを検索",
                        message: "イベント名を入力して検索してください"
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                ForEach(results) { event in
                    Button {
                        AppAnalytics.tap("event_search_picker.select")
                        onSelect(event)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.purple.opacity(0.12))
                                .frame(width: 36, height: 36)
                                .overlay {
                                    Image(systemName: "calendar")
                                        .foregroundStyle(.purple)
                                        .font(.imasCaption)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(eventDisplayName(event.name))
                                    .font(.imasSubhead)
                                    .fontWeight(.medium)
                                    .foregroundStyle(DS.ink)
                                if let brandId = event.brandId {
                                    Text(brandId)
                                        .font(.imasScaled(11))
                                        .foregroundStyle(DS.ink2)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.imasCaption)
                                .foregroundStyle(DS.ink3)
                        }
                    }
                    .accessibilityLabel(event.name)
                    .listRowBackground(DS.surface)
                    .listRowSeparatorTint(DS.sep)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DS.bg)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "イベント名で検索")
            .navigationTitle("イベントを選択")
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
                results = (try? await AppContainer.shared.eventReading.events(brandId: nil)) ?? []
            }
            .trackScreen("event_search_picker")
        }
    }

    private func performSearch(query: String) async {
        if query.isEmpty {
            results = (try? await AppContainer.shared.eventReading.events(brandId: nil)) ?? []
            return
        }
        results = (try? await AppContainer.shared.eventReading.searchEventsByNameOrVenue(query: query, limit: 100)) ?? []
    }
}
