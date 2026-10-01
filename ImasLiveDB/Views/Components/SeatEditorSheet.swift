import SwiftUI

/// 参加した公演の座席を記録する 1 行入力シート。
/// 会場ごとに表記がバラバラ (アリーナ / スタンド / 整理番号 等) なので自由テキスト。
struct SeatEditorSheet: View {
    let entity: UserMarkEntity
    let entityId: String
    @Binding var draft: String

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    private let markService = UserMarkService.shared

    var body: some View {
        NavigationStack {
            Form {
                ImasListSection(footer: "ブロック・列・番号など、自由に記録できます。") {
                    ImasTextAreaRow(text: $draft, prompt: "例: アリーナ A6 12列 34番", minHeight: 60,
                                   minLines: 1, maxLines: 3)
                        .focused($focused)
                }
            }
            .imasForm()
            .navigationTitle("座席")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.edit(
                onCancel: {
                    draft = markService.seat(entity: entity, id: entityId) ?? ""
                    dismiss()
                },
                onSave: {
                    AppAnalytics.tap("seat_editor.save")
                    do {
                        try markService.setSeat(entity: entity, id: entityId, text: draft)
                        dismiss()
                    } catch {
                        // 書けなかったら閉じない (入れた座席を捨てずに、もう一度押せるように)。
                        LocalWriteFailure.report(error, action: "座席の保存")
                    }
                }
            ))
        }
        .presentationDetents([.height(220), .medium])
        .onAppear {
            draft = markService.seat(entity: entity, id: entityId) ?? ""
            focused = true
        }
        .trackScreen("seat_editor")
    }
}
