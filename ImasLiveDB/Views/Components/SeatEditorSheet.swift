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
                Section {
                    TextField("例: アリーナ A6 12列 34番", text: $draft, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                } footer: {
                    Text("ブロック・列・番号など、自由に記録できます。")
                        .foregroundStyle(DS.ink2)
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)
            }
            .scrollContentBackground(.hidden)
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle("座席")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        draft = markService.seat(entity: entity, id: entityId) ?? ""
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        AppAnalytics.tap("seat_editor.save")
                        try? markService.setSeat(entity: entity, id: entityId, text: draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(220), .medium])
        .onAppear {
            draft = markService.seat(entity: entity, id: entityId) ?? ""
            focused = true
        }
        .trackScreen("seat_editor")
    }
}
