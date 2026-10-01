import os
import SwiftUI

/// 曲の補足 (`songs.note`) だけを書く・直すシート。
///
/// 補足は利用者からの投稿が主な入口なので、Apple Music ID まで並ぶ楽曲編集フォームを
/// 開かせず、1 文と出典だけで出せるようにする。送り先は楽曲編集と同じオープン編集
/// (`EditService.submitMaster`) で、運営が直接反映できない人の投稿は修正リクエストになる。
/// 出典はマスタに列を持たないので、確認する運営に見えるよう編集の summary に載せる。
struct SongNoteEditSheet: View {
    let song: Song
    /// 直接反映できたときに、確定した補足 (空なら nil) を返す。曲詳細がすぐ書き換えるため。
    let onApplied: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var note: String
    @State private var source = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var requestSent = false

    /// サーバの上限 (`master_validators.ts` の Song.note) と揃える。
    private static let maxLength = 200

    init(song: Song, onApplied: @escaping (String?) -> Void) {
        self.song = song
        self.onApplied = onApplied
        _note = State(initialValue: song.note ?? "")
    }

    private var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedSource: String { source.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isUnchanged: Bool { trimmedNote == (song.note ?? "") }
    private var isTooLong: Bool { trimmedNote.count > Self.maxLength }

    var body: some View {
        NavigationStack {
            Form {
                ImasListSection("補足", footer: "由来や位置づけを 1 文で。曲詳細の曲名の下に表示されます。") {
                    ImasTextAreaRow(text: $note, prompt: "例: ミリシタ 1 周年記念楽曲", minHeight: 80, limit: Self.maxLength)
                }

                ImasListSection("出典", footer: "公式の告知や CD のクレジットなど、確かめられるものを書いてください。確認の目安にします。") {
                    ImasTextAreaRow(text: $source, prompt: "公式サイトの URL など", minHeight: 60)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .imasForm()
            .navigationTitle(song.note == nil ? "補足を書く" : "補足を直す")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.submit(
                canSubmit: !isSaving && !isUnchanged && !isTooLong,
                onCancel: { dismiss() },
                onSubmit: { AppAnalytics.tap("song_note.submit"); Task { await submit() } }
            ))
            .imasSavingOverlay(isSaving, label: "送信中")
            .imasErrorAlert("エラー", message: $errorMessage)
            .editRequestSentAlert(isPresented: $requestSent, onDismiss: { dismiss() })
        }
        .trackScreen("song_note_edit")
    }

    private func submit() async {
        isSaving = true
        defer { isSaving = false }

        let newNote: String? = trimmedNote.isEmpty ? nil : trimmedNote
        let op = EditService.EditOperation(
            op: .update,
            recordType: "Song",
            recordName: song.id,
            // 空にしたら null を送って消す (楽曲編集の clearable と同じ意味)。
            fields: ["note": newNote.map { AnyEncodable($0) } ?? .null]
        )
        let summary = trimmedSource.isEmpty ? "補足を編集" : "補足を編集 (出典: \(trimmedSource))"

        do {
            switch try await EditService.shared.submitMaster(ops: [op], summary: summary) {
            case .applied:
                var saved = song
                saved.note = newNote
                try await AppContainer.shared.songWriting.upsertSongs([saved])
                Logger.database.notice("song_note_edited id=\(song.id, privacy: .public)")
                onApplied(newNote)
                dismiss()
            case .requested:
                requestSent = true
            }
        } catch {
            errorMessage = "送信に失敗しました: \(error.localizedDescription)"
        }
    }
}
