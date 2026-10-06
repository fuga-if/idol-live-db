import os
import SwiftUI

/// 歌詞を投稿するシート。CD の歌詞カードなどの一次ソースを見て入力した歌詞を送る。
///
/// 送った歌詞は確認待ちで預かられ、公開はモデレーターの確認後 (`LyricSubmissionAPI`)。
/// 入力元の選択と「歌詞サイトから写していない」の確認が無いと送れない。
/// 本文の整え方・上限・注意はコア (`lyricSubmissionCheck`) が決める。
struct LyricSubmissionSheet: View {
    let song: Song

    @Environment(\.dismiss) private var dismiss

    @State private var source: LyricSourceKind?
    @State private var sourceNote = ""
    @State private var text = ""
    @State private var attested = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmDiscard = false
    @State private var sent = false

    private var check: LyricSubmissionCheck {
        lyricSubmissionCheck(text: text, source: source, attestedNoCopy: attested)
    }

    private var isDirty: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || source != nil
    }

    var body: some View {
        NavigationStack {
            ImasFormPage {
                ImasFormCard {
                    ImasFormField(label: "曲", imprint: "SONG", systemImage: "music.note") {
                        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                            Text(song.title)
                            if let singer = song.singerLabel, !singer.isEmpty {
                                Text(singer).font(.imasFootnote).foregroundStyle(DS.ink2)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: DS.Space.gap) {
                    ImasSectionHeader("何を見て入力しましたか", style: .small)
                    ImasChoiceCards(choices: sourceChoices, selection: $source, style: .row)
                }

                ImasFormCard {
                    ImasFormTextArea(label: "歌詞", imprint: "LYRICS", systemImage: "text.quote",
                                     text: $text, prompt: "1 行ずつ改行して入力してください")
                    ImasFormTextField(label: "入力元の補足 (任意)", imprint: "SOURCE", text: $sourceNote,
                                      prompt: "例: 初回限定盤のブックレット")
                }
                issueNotes

                ImasFormCard {
                    ImasFormToggle(label: "確認", imprint: "CHECK", title: "歌詞サイトから写していません",
                                   isOn: $attested)
                }

                Text("送った歌詞は運営が確認してから公開します。CD の歌詞カードや、公式に公開されている歌詞を見て入力してください。歌詞サイトから写した歌詞は公開できません。分かった時点で削除します。")
                    .font(.imasFootnote)
                    .foregroundStyle(DS.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .navigationTitle("歌詞を投稿")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.submit(
                canSubmit: check.canSubmit && !isSaving,
                isSubmitting: isSaving,
                onCancel: { isDirty ? (confirmDiscard = true) : dismiss() },
                onSubmit: { AppAnalytics.tap("lyric_submission.submit"); Task { await submit() } }
            ))
            .imasSavingOverlay(isSaving, label: "送信中")
            .imasErrorAlert("送信できませんでした", message: $errorMessage)
            .imasDiscardConfirmation(isPresented: $confirmDiscard) { dismiss() }
            .interactiveDismissDisabled(isDirty)
            .alert("歌詞を送りました", isPresented: $sent) {
                Button("OK") { dismiss() }
            } message: {
                Text("運営が確認してから公開します。ありがとうございました。")
            }
        }
        .trackScreen("lyric_submission")
    }

    private var sourceChoices: [ImasChoiceCards<LyricSourceKind?>.Choice] {
        lyricSourceKinds().map { kind in
            .init(value: kind, title: lyricSourceLabel(kind: kind), systemImage: Self.icon(kind),
                  subtitle: lyricSourceDetail(kind: kind))
        }
    }

    private static func icon(_ kind: LyricSourceKind) -> String {
        switch kind {
        case .booklet: return "opticaldisc"
        case .official: return "globe"
        case .listening: return "headphones"
        }
    }

    /// 行数・文字数と、コアが出した注意。送信を止める注意は朱で出す。
    private var issueNotes: some View {
        let check = check
        return VStack(alignment: .leading, spacing: DS.Space.gapTight) {
            if check.lineCount > 0 {
                Text("\(check.lineCount) 行 · \(check.charCount) / \(lyricSubmissionMaxChars()) 字")
                    .font(.imasFootnote)
                    .foregroundStyle(DS.ink3)
            }
            ForEach(Array(check.issues.enumerated()), id: \.offset) { _, issue in
                if issue != .empty {
                    Text(lyricSubmissionIssueMessage(issue: issue))
                        .font(.imasFootnote.weight(.semibold))
                        .foregroundStyle(lyricSubmissionIssueBlocks(issue: issue) ? DS.danger : DS.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func submit() async {
        let check = check
        guard check.canSubmit, let source else { return }
        isSaving = true
        defer { isSaving = false }
        let note = sourceNote.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await LyricSubmissionAPI.shared.submit(songId: song.id, source: source,
                                                       sourceNote: note.isEmpty ? nil : note,
                                                       text: check.normalized)
            Logger.database.notice("lyric_submitted song=\(song.id, privacy: .public)")
            sent = true
        } catch {
            errorMessage = "時間をおいてもう一度お試しください。(\(error.localizedDescription))"
        }
    }
}
