import SwiftUI

struct NoteEditorSheet: View {
    let entity: UserMarkEntity
    let entityId: String
    @Binding var draft: String

    @Environment(\.dismiss) private var dismiss
    private let markService = UserMarkService.shared

    var body: some View {
        NavigationStack {
            TextEditor(text: $draft)
                .padding()
                .navigationTitle("メモ")
                .navigationBarTitleDisplayMode(.inline)
                .imasSheetToolbar(.edit(
                    onCancel: {
                        draft = markService.note(entity: entity, id: entityId) ?? ""
                        dismiss()
                    },
                    onSave: {
                        AppAnalytics.tap("note_editor.save")
                        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        do {
                            try markService.setNote(
                                entity: entity,
                                id: entityId,
                                text: trimmed.isEmpty ? nil : trimmed
                            )
                            dismiss()
                        } catch {
                            // 書けなかったら閉じない (打ったメモを捨てずに、もう一度押せるように)。
                            LocalWriteFailure.report(error, action: "メモの保存")
                        }
                    }
                ))
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            draft = markService.note(entity: entity, id: entityId) ?? ""
        }
        .trackScreen("note_editor")
    }
}
