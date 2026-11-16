import SwiftUI

/// これまでの会話の一覧。開く・消す。
///
/// 会話は端末の中にだけある (`ChatSessionStore`)。並びと残す本数はコアが決める。
struct ChatHistorySheet: View {
    /// いま開いている会話 (印を付ける)。
    let currentID: String
    let onOpen: (String) -> Void
    /// 消した会話の id (いま開いている会話を消したら、画面の側で新しい会話にする)。
    let onDelete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [ChatSessionSummary] = []
    @State private var confirmsDeleteAll = false

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    ImasListSection {
                        ImasEmptyState(systemImage: "clock.arrow.circlepath", title: "まだ会話がありません",
                                       message: "送った会話は、この端末の中に残ります")
                    }
                } else {
                    ImasListSection("これまでの会話", count: "\(sessions.count)件",
                                    footer: "会話はこの端末の中にだけ残ります。添えた画像は残しません。行を左にスワイプすると消せます。") {
                        ForEach(sessions, id: \.id) { summary in
                            Button {
                                AppAnalytics.tap("assistant.history_open")
                                onOpen(summary.id)
                                dismiss()
                            } label: {
                                ImasNavRow(title: summary.title, subtitle: subtitle(summary),
                                           systemImage: summary.id == currentID ? "text.bubble.fill" : "text.bubble",
                                           iconTone: .neutral)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                let id = sessions[index].id
                                ChatSessionStore.delete(id)
                                onDelete(id)
                            }
                            sessions.remove(atOffsets: offsets)
                        }
                    }
                    ImasListSection {
                        ImasActionRow(title: "すべて消す", systemImage: "trash", kind: .destructive) {
                            confirmsDeleteAll = true
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .imasForm()
            .navigationTitle("会話の履歴")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.read(onClose: { dismiss() }))
            .confirmationDialog("これまでの会話をすべて消しますか？", isPresented: $confirmsDeleteAll, titleVisibility: .visible) {
                Button("すべて消す", role: .destructive) {
                    AppAnalytics.tap("assistant.history_delete_all")
                    ChatSessionStore.deleteAll()
                    sessions.map(\.id).forEach(onDelete)
                    sessions = []
                }
                Button("やめる", role: .cancel) {}
            }
        }
        .onAppear { sessions = ChatSessionStore.list() }
        .trackScreen("assistant_history")
    }

    private func subtitle(_ summary: ChatSessionSummary) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(summary.updatedAt))
        return "\(date.formatted(date: .abbreviated, time: .shortened))・\(summary.turnCount) 往復"
    }
}
