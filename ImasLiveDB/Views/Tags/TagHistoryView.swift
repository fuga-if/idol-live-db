import SwiftUI

struct TagHistoryView: View {
    let tagId: String
    var domain: TagDomain = .song

    @State private var history: [TagHistoryEntry] = []
    /// 直前のページが満杯だった (続きがあるかもしれない)。
    @State private var hasMore = false
    @State private var isLoadingMore = false
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                ImasInlineLoading()
                    .listRowBackground(Color.clear)
            } else if history.isEmpty {
                ImasEmptyState(.empty, title: "編集履歴はありません")
                    .listRowBackground(Color.clear)
            } else {
                let times = EditFeedFormat.relativeTimes(history.map { ($0.id, $0.editedAt) })
                ForEach(history) { entry in
                    ImasRecordRow(
                        systemImage: "pencil",
                        title: "説明を編集",
                        subtitle: "\(times[entry.id] ?? "") · \(String(entry.editedBy.prefix(8)))..."
                    ) {
                        // 説明は行数の制限なしで全文 (最大 300 字)。題 (2 行までの ImasRecordRow
                        // の既定) に乗せると切れるため detail に出す。
                        if let desc = entry.description, !desc.isEmpty {
                            Text(desc)
                                .font(.imasBody)
                                .foregroundStyle(DS.ink)
                        } else {
                            Text("（説明なし）")
                                .font(.imasBody)
                                .foregroundStyle(DS.ink3)
                                .italic()
                        }
                    }
                    .listRowBackground(DS.surface)
                    .listRowSeparatorTint(DS.sep)
                }
                // 末尾まで来たら古い履歴を読み足す (一度に全件は読まない)。
                if hasMore {
                    ImasInlineLoading()
                        .listRowBackground(Color.clear)
                        .onAppear { Task { await loadMore() } }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.bg)
        .navigationTitle("編集履歴")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadHistory() }
        .trackScreen("tag_history")
    }

    private func loadHistory() async {
        isLoading = true
        defer { isLoading = false }
        let page = (try? await fetchPage(before: nil)) ?? []
        history = page
        hasMore = page.count == CommunityAPI.tagHistoryPageSize
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore, let last = history.last else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let page = try? await fetchPage(before: last.id) else { return }
        let known = Set(history.map(\.id))
        history += page.filter { !known.contains($0.id) }
        hasMore = page.count == CommunityAPI.tagHistoryPageSize
    }

    private func fetchPage(before: Int?) async throws -> [TagHistoryEntry] {
        let reading = AppContainer.shared.communityTagReading
        switch domain {
        case .song: return try await reading.tagHistory(id: tagId, before: before)
        case .idol: return try await reading.idolTagHistory(id: tagId, before: before)
        case .unit: return try await reading.unitTagHistory(id: tagId, before: before)
        }
    }
}
