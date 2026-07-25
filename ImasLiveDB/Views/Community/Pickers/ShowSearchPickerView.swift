import SwiftUI
import GRDB

// MARK: - ShowSearchPickerView

struct ShowSearchPickerView: View {
    @Environment(AppDatabase.self) private var database
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
                        HStack(spacing: 12) {
                            Circle()
                                .fill(DS.fill)
                                .frame(width: 36, height: 36)
                                .overlay {
                                    Image(systemName: "ticket")
                                        .foregroundStyle(DS.sys)
                                        .font(.imasCaption)
                                }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(eventDisplayName(show.eventName))
                                    .font(.imasSubhead)
                                    .fontWeight(.medium)
                                    .foregroundStyle(DS.ink)
                                HStack(spacing: 8) {
                                    Text(show.name)
                                        .font(.imasCaption)
                                        .foregroundStyle(DS.ink2)
                                    Text("·")
                                        .font(.imasCaption)
                                        .foregroundStyle(DS.ink3)
                                    Text(show.date.prefix(10).description)
                                        .font(.imasCaption)
                                        .foregroundStyle(DS.ink2)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.imasCaption)
                                .foregroundStyle(DS.ink3)
                        }
                    }
                    .accessibilityLabel("\(show.eventName) \(show.name)")
                    .listRowBackground(DS.surface)
                    .listRowSeparatorTint(DS.sep)
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
                    Button("キャンセル") { dismiss() }
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
