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
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") {
                            draft = markService.note(entity: entity, id: entityId) ?? ""
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            AppAnalytics.tap("note_editor.save")
                            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            try? markService.setNote(
                                entity: entity,
                                id: entityId,
                                text: trimmed.isEmpty ? nil : trimmed
                            )
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            draft = markService.note(entity: entity, id: entityId) ?? ""
        }
        .trackScreen("note_editor")
    }
}
