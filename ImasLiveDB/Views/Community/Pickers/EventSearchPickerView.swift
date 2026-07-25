import SwiftUI
import GRDB

// MARK: - EventSearchPickerView

struct EventSearchPickerView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss
    let onSelect: (Event) -> Void

    @State private var query = ""
    @State private var results: [Event] = []
    /// 検索デバウンス用の世代 ID (SongSearchPickerView.scheduleLoad と同方式)。
    @State private var searchToken = 0

    var body: some View {
        NavigationStack {
            List {
                if results.isEmpty && !query.isEmpty {
                    ImasEmptyState(
                        systemImage: "magnifyingglass",
                        title: "見つかりません",
                        message: "「\(query)」に一致するイベントがありません"
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } else if results.isEmpty && query.isEmpty {
                    ImasEmptyState(
                        systemImage: "calendar",
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
                        HStack(spacing: DS.sp4) {
                            Circle()
                                .fill(DS.fill)
                                .frame(width: 36, height: 36)
                                .overlay {
                                    Image(systemName: "calendar")
                                        .foregroundStyle(DS.sys)
                                        .font(.imasCaption)
                                }

                            VStack(alignment: .leading, spacing: DS.sp1) {
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

                            ImasRowChevron()
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
                scheduleSearch(query: newValue)
            }
            .task {
                results = (try? await AppContainer.shared.eventReading.events(brandId: nil)) ?? []
            }
            .trackScreen("event_search_picker")
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
            results = (try? await AppContainer.shared.eventReading.events(brandId: nil)) ?? []
            return
        }
        results = (try? await AppContainer.shared.eventReading.searchEventsByNameOrVenue(query: query, limit: 100)) ?? []
    }
}
