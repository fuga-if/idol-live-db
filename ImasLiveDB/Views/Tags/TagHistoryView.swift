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
                        title: entry.description?.isEmpty == false ? entry.description! : "（説明なし）",
                        subtitle: "\(String(entry.editedBy.prefix(8)))... · \(times[entry.id] ?? "")"
                    )
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
