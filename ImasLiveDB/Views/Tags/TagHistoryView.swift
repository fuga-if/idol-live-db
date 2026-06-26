import SwiftUI

struct TagHistoryView: View {
    let tagId: String

    @State private var history: [TagHistoryEntry] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if history.isEmpty {
                Text("編集履歴はありません")
                    .foregroundStyle(DS.ink2)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(history) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.editedAt, style: .relative)
                                .font(.imasCaption)
                                .foregroundStyle(DS.ink2)
                            Spacer()
                            Text(String(entry.editedBy.prefix(8)) + "...")
                                .font(.imasScaled(11))
                                .foregroundStyle(DS.ink3)
                        }
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
                    .padding(.vertical, 4)
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
        history = (try? await CommunityAPI.shared.tagHistory(id: tagId)) ?? []
    }
}
