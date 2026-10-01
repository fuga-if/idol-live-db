import SwiftUI

struct TagHistoryView: View {
    let tagId: String
    var domain: TagDomain = .song

    @State private var history: [TagHistoryEntry] = []
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
        let reading = AppContainer.shared.communityTagReading
        switch domain {
        case .song:
            history = (try? await reading.tagHistory(id: tagId)) ?? []
        case .idol:
            history = (try? await reading.idolTagHistory(id: tagId)) ?? []
        case .unit:
            history = (try? await reading.unitTagHistory(id: tagId)) ?? []
        }
    }
}
